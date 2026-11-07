cmake_minimum_required(VERSION 3.20)
project(lba1_godot LANGUAGES C)

set(LBA_BUILD_SDL OFF CACHE BOOL "Standalone SDL frontend" FORCE)
set(LBA_BUILD_TESTS OFF CACHE BOOL "Native tests" FORCE)
set(LBA_BUILD_GODOT ON CACHE BOOL "Native simulation" FORCE)
add_subdirectory(native/lba1-native)

add_library(lba1_gdextension SHARED native/gdextension/lba1_gdextension.c)
set_target_properties(lba1_gdextension PROPERTIES
  C_STANDARD 11 C_STANDARD_REQUIRED YES
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/addons/lba1/bin"
  BUILD_RPATH "$ORIGIN")
target_include_directories(lba1_gdextension PRIVATE
  native/gdextension/generated native/lba1-native/include)
target_link_libraries(lba1_gdextension PRIVATE lba_simulation)
set_target_properties(lba_simulation PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/addons/lba1/bin")
