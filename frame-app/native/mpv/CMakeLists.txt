# Native extension embedding libmpv: video decoded in-app and drawn into a
# texture, so it can play on the 3D screen. Build with native/build.sh.
cmake_minimum_required(VERSION 3.22)
project(streamframe_mpv LANGUAGES CXX)

include(FetchContent)
# Extensions built against the 4.5 API load in later 4.x versions.
set(GODOTCPP_DIR "" CACHE PATH "An existing godot-cpp checkout (otherwise it is downloaded)")
if(GODOTCPP_DIR)
    add_subdirectory(${GODOTCPP_DIR} godot-cpp)
else()
    FetchContent_Declare(godot-cpp
        GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
        GIT_TAG godot-4.5-stable
        GIT_SHALLOW TRUE)
    FetchContent_MakeAvailable(godot-cpp)
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv)

add_library(streamframe_mpv SHARED src/mpv_player.cpp src/register_types.cpp)
target_link_libraries(streamframe_mpv PRIVATE godot-cpp PkgConfig::MPV)
get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set_target_properties(streamframe_mpv PROPERTIES
    CXX_STANDARD 17
    CXX_VISIBILITY_PRESET hidden
    POSITION_INDEPENDENT_CODE ON
    PREFIX "lib"
    OUTPUT_NAME "streamframe_mpv${GODOTCPP_SUFFIX}"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../addons/mpv/bin")
