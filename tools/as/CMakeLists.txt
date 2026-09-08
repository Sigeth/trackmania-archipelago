cmake_minimum_required(VERSION 3.16)
project(op_asrun CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

include(FetchContent)

# codecat/angelscript-mirror -- the tree Openplanet itself tracks. Pinned; bump
# deliberately and re-run `asrun --compile src` after.
FetchContent_Declare(angelscript
  GIT_REPOSITORY https://github.com/codecat/angelscript-mirror.git
  GIT_TAG        c81df254037524b18cd41a57805cfec76acd05bf   # 2.38.0, 2025-08-14
  GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(angelscript)

set(AS_SDK "${angelscript_SOURCE_DIR}/sdk")
add_subdirectory("${AS_SDK}/angelscript/projects/cmake" angelscript_lib)

set(AS_ADDON "${AS_SDK}/add_on")
add_library(as_addons STATIC
  "${AS_ADDON}/scriptbuilder/scriptbuilder.cpp"
  "${AS_ADDON}/scriptarray/scriptarray.cpp"
  "${AS_ADDON}/scriptdictionary/scriptdictionary.cpp"
  "${AS_ADDON}/scripthandle/scripthandle.cpp"
  "${AS_ADDON}/scripthelper/scripthelper.cpp"
)
target_include_directories(as_addons PUBLIC
  "${AS_SDK}/angelscript/include" "${AS_ADDON}")
target_link_libraries(as_addons PUBLIC angelscript)

add_executable(asrun
  host/main.cpp
  host/op_bindings.cpp
  host/op_string.cpp
  host/json_value.cpp
)
target_include_directories(asrun PRIVATE
  "${AS_SDK}/angelscript/include" "${AS_ADDON}" host)
target_link_libraries(asrun PRIVATE as_addons angelscript)

if(MSVC)
  target_compile_options(asrun PRIVATE /EHsc /W3)
  target_compile_definitions(asrun PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()
