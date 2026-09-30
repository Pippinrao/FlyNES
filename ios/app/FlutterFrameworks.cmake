# Called only for the product Flutter host. Resolve by XCFramework metadata,
# never by a hardcoded device/simulator directory name.
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(FLYNES_FLUTTER_FRAMEWORK_DIR "" CACHE PATH "Pinned Flutter XCFramework configuration directory")
if(NOT IS_DIRECTORY "${FLYNES_FLUTTER_FRAMEWORK_DIR}")
    message(FATAL_ERROR "Run tools/flutter/Build-Ios.sh and set FLYNES_FLUTTER_FRAMEWORK_DIR to its Debug or Release directory")
endif()
if(FLYNES_IOS_IS_SIMULATOR)
    set(_flutter_platform simulator)
else()
    set(_flutter_platform device)
endif()
execute_process(
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_LIST_DIR}/../../tools/flutter/ios_frameworks.py"
        "${FLYNES_FLUTTER_FRAMEWORK_DIR}" "${_flutter_platform}" "${CMAKE_OSX_ARCHITECTURES}"
    RESULT_VARIABLE _flutter_result OUTPUT_VARIABLE _flutter_json ERROR_VARIABLE _flutter_error)
if(NOT _flutter_result EQUAL 0)
    message(FATAL_ERROR "Flutter framework selection failed: ${_flutter_error}")
endif()
string(JSON _flutter_runtime GET "${_flutter_json}" runtimeMode)
message(STATUS "Flutter runtime mode: ${_flutter_runtime} (${_flutter_platform})")
foreach(_index RANGE 0 1)
    string(JSON _framework GET "${_flutter_json}" frameworks ${_index})
    target_link_libraries(FlyNES PRIVATE "${_framework}")
    set_property(TARGET FlyNES APPEND PROPERTY XCODE_EMBED_FRAMEWORKS "${_framework}")
endforeach()
set_target_properties(FlyNES PROPERTIES
    XCODE_EMBED_FRAMEWORKS_CODE_SIGN_ON_COPY YES
    XCODE_EMBED_FRAMEWORKS_REMOVE_HEADERS_ON_COPY YES
    XCODE_ATTRIBUTE_LD_RUNPATH_SEARCH_PATHS "$(inherited) @executable_path/Frameworks"
    XCODE_ATTRIBUTE_SWIFT_ACTIVE_COMPILATION_CONDITIONS "$(inherited) FLYNES_FLUTTER $<$<CONFIG:Debug>:DEBUG>")
target_compile_definitions(FlyNES PRIVATE FLYNES_FLUTTER=1)
