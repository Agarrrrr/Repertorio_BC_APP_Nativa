# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(flutter_lame_library VERSION 0.0.1 LANGUAGES C)

add_subdirectory(lame)
target_compile_definitions(mp3lame PUBLIC DART_SHARED_LIB)

# Android 15+ devices can use 16 KB memory pages. NDK r27 does not enable
# flexible page-size alignment by default, so align the shared library's ELF
# LOAD segments explicitly as required by Google Play.
if(ANDROID)
  set_target_properties(
    mp3lame
    PROPERTIES LINK_FLAGS
    "-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
  )
endif()
