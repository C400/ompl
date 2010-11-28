find_package(Boost COMPONENTS python)
# The python version needs to match the one used to build Boost.Python. 
# You can optionally specify the desired version like so:
# 	find_package(Python 2.6)
find_package(Python QUIET)
find_python_module(pyplusplus QUIET)
find_python_module(pygccxml QUIET)
find_package(GCCXML QUIET)

if(APPLE)
	# For some reason gccxml generates 32-bit binaries by default on OS X
	# (maybe because the kernel is still 32-bit?)
	set(PYOMPL_EXTRA_CFLAGS "-m64")
endif(APPLE)

if(PYTHON_FOUND AND Boost_PYTHON_LIBRARY)
	include_directories(${PYTHON_INCLUDE_DIRS})
	# make sure targets are defined only once
	get_target_property(_target generate_headers EXCLUDE_FROM_ALL)
	if(NOT _target)
		# top-level target for updating all-in-one header file for each module
		add_custom_target(generate_headers)
		# top-level target for regenerating code for all python modules
		add_custom_target(update_bindings)
	endif()
	set(PY_OMPL_COMPILE ON CACHE BOOL
		"Whether the OMPL Python modules can be built")
	mark_as_advanced(PY_OMPL_COMPILE)
endif()
if(PYTHON_FOUND AND Boost_PYTHON_LIBRARY AND PY_PYPLUSPLUS
	AND PY_PYGCCXML AND GCCXML)
	# make sure target is defined only once
	get_target_property(_target py_ompl EXCLUDE_FROM_ALL)
	if(NOT _target)
		# top-level target for compiling python modules
		add_custom_target(py_ompl)
	endif()
	set(PY_OMPL_GENERATE ON CACHE BOOL 
		"Whether the C++ code for the OMPL Python module can be generated")
	mark_as_advanced(PY_OMPL_GENERATE)
	set(OMPL_PYTHON_INSTALL_DIR "${PYTHON_SITE_MODULES}" CACHE STRING
	    "Path to directory where OMPL python modules will be installed")
endif()

function(create_module_header_file_target module dir)
	# create list of absolute paths to header files, which we
	# will add as a list of dependencies for the target
	file(READ "headers_${module}.txt" headers_string)
	separate_arguments(rel_headers UNIX_COMMAND "${headers_string}")
	set(headers "")
	foreach(header ${rel_headers})
		list(APPEND headers "${header}")
	endforeach(header)
	# target for all-in-one header for module
	add_custom_target(${module}.h
		COMMAND ${CMAKE_COMMAND} -D module=${module} 
		-P "${OMPL_CMAKE_UTIL_DIR}/generate_header.cmake"
		DEPENDS ${headers} WORKING_DIRECTORY "${dir}"
		COMMENT "Preparing C++ header file for Python binding generation for module ${module}")
	add_dependencies(generate_headers ${module}.h)
endfunction(create_module_header_file_target)

function(create_module_code_generation_target module dir)
	# target for regenerating code. Cmake is run so that the list of 
	# sources for the py_ompl_${module} target (see below) is updated.
	add_custom_target(update_${module}_bindings 
		COMMAND ${PYTHON_EXEC} 
		"${CMAKE_CURRENT_SOURCE_DIR}/generate_bindings.py" "${module}"
		"1>${CMAKE_BINARY_DIR}/pyplusplus_${module}.log" "2>&1"
		COMMAND ${CMAKE_COMMAND} -D "PATH=${dir}/bindings/${module}"
		-P "${OMPL_CMAKE_UTIL_DIR}/abs_to_rel_path.cmake"
		COMMAND ${CMAKE_COMMAND} ${CMAKE_BINARY_DIR}
 		WORKING_DIRECTORY ${dir}
		COMMENT "Creating C++ code for Python module ${module} (see pyplusplus_${module}.log)")
	add_dependencies(update_${module}_bindings ${module}.h)
	add_dependencies(update_bindings update_${module}_bindings)	
endfunction(create_module_code_generation_target)

function(create_module_generation_targets module dir)
	create_module_header_file_target("${module}" "${dir}")
	create_module_code_generation_target("${module}" "${dir}")
endfunction(create_module_generation_targets)

function(create_module_target module dir)
	# target for each python module
	aux_source_directory("${dir}/bindings/${module}" PY${module}BINDINGS)
	list(LENGTH PY${module}BINDINGS NUM_SOURCE_FILES)
	if(NUM_SOURCE_FILES GREATER 0)
		if(ARGC GREATER 2)
			set(_dest_dir "${ARGV2}")
			if(ARGC GREATER 3)
				set(_extra_libs "${ARGV3}")
			endif()
		else()
			set(_dest_dir "${dir}/ompl")
		endif()
		add_library(py_ompl_${module} MODULE ${PY${module}BINDINGS})
		target_link_libraries(py_ompl_${module} 
			ompl
			${_extra_libs}
			${Boost_THREAD_LIBRARY}
			${Boost_DATE_TIME_LIBRARY}
			${Boost_PYTHON_LIBRARY}
			${PYTHON_LIBRARIES})
		add_dependencies(py_ompl py_ompl_${module})
		get_target_property(PY${module}_NAME py_ompl_${module} LOCATION)
		add_custom_command(TARGET py_ompl_${module} POST_BUILD
	        COMMAND ${CMAKE_COMMAND} -E copy "${PY${module}_NAME}" 
	        "${_dest_dir}/${module}/_${module}${CMAKE_SHARED_MODULE_SUFFIX}"
	        WORKING_DIRECTORY ${LIBRARY_OUTPUT_PATH}
	        COMMENT "Copying python module ${module} into place")
		include_directories("${dir}/bindings/${module}" "${dir}")
	else(NUM_SOURCE_FILES GREATER 0)
		if(PY_OMPL_GENERATE)
			message(STATUS "Code for module ${module} not found; type \"make update_bindings\"")
		else()
			message(STATUS "Code for module ${module} not found")
		endif()
	endif(NUM_SOURCE_FILES GREATER 0)
endfunction(create_module_target)
