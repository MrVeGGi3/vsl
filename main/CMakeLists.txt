cmake_minimum_required(VERSION 3.28)
project(vsl_main CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ── Compiler flags ────────────────────────────────────────────────────────────
# ASan and TSan are mutually exclusive — Debug uses ASan for memory safety.
# To build with TSan: cmake -DCMAKE_BUILD_TYPE=Debug -DVSL_TSAN=ON
option(VSL_TSAN "Enable ThreadSanitizer instead of AddressSanitizer" OFF)

add_compile_options(-Wall -Wextra -Wpedantic)
add_compile_options($<$<CONFIG:Debug>:-g3>)
add_compile_options($<$<CONFIG:RelWithDebInfo>:-O2>)
add_compile_options($<$<CONFIG:RelWithDebInfo>:-g>)
add_compile_options($<$<CONFIG:Release>:-O3>)

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    if(VSL_TSAN)
        add_compile_options(-fsanitize=thread)
        add_link_options(-fsanitize=thread)
    else()
        add_compile_options(-fsanitize=address -fno-omit-frame-pointer)
        add_link_options(-fsanitize=address)
    endif()
endif()

# ── LibGodot ──────────────────────────────────────────────────────────────────
# Path to compiled libgodot.so and headers.
# Override with: cmake -DGODOT_SRC=<path>
set(GODOT_SRC "${CMAKE_SOURCE_DIR}/../../../godot-src"
    CACHE PATH "Path to Godot source tree (after compilation)")

set(GODOT_LIB_DIR "${GODOT_SRC}/bin"
    CACHE PATH "Directory containing libgodot*.so")

# The .so filename changes with build config — glob for it.
file(GLOB GODOT_SO "${GODOT_LIB_DIR}/libgodot.linuxbsd.*.x86_64.so")
if(NOT GODOT_SO)
    message(WARNING
        "libgodot.so not found in ${GODOT_LIB_DIR}. "
        "Run: cd ${GODOT_SRC} && scons platform=linuxbsd target=template_debug library_type=shared_library")
endif()

add_library(libgodot SHARED IMPORTED)
set_target_properties(libgodot PROPERTIES
    IMPORTED_LOCATION             "${GODOT_SO}"
    INTERFACE_INCLUDE_DIRECTORIES "${GODOT_SRC}"
)

# ── libjulia ─────────────────────────────────────────────────────────────────
# Locate via JULIA_DIR env or juliaup default path.
if(NOT JULIA_DIR)
    execute_process(
        COMMAND julia --startup-file=no -e "print(dirname(Sys.BINDIR))"
        OUTPUT_VARIABLE JULIA_DIR
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
endif()

find_library(JULIA_LIB julia
    HINTS "${JULIA_DIR}/lib" "${JULIA_DIR}/lib/julia"
    REQUIRED
)
find_path(JULIA_INCLUDE julia.h
    HINTS "${JULIA_DIR}/include/julia"
    REQUIRED
)

add_library(libjulia SHARED IMPORTED)
set_target_properties(libjulia PROPERTIES
    IMPORTED_LOCATION             "${JULIA_LIB}"
    INTERFACE_INCLUDE_DIRECTORIES "${JULIA_INCLUDE}"
)

# ── vsl_main executable ───────────────────────────────────────────────────────
add_executable(vsl_main
    src/main.cpp
    src/godot_bridge.cpp
    src/julia_solver.cpp
)

target_include_directories(vsl_main PRIVATE src/)

target_link_libraries(vsl_main PRIVATE
    libgodot
    libjulia
    dl          # dlsym for GodotInstance C++ symbol resolution
)

# ── Install ───────────────────────────────────────────────────────────────────
install(TARGETS vsl_main DESTINATION bin)
