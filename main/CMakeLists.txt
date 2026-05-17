cmake_minimum_required(VERSION 3.28)
project(vsl_main CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ── nlohmann/json ─────────────────────────────────────────────────────────────
# Header-only JSON library for reading mission_params.json.
# Uses system package if available, otherwise fetches from GitHub.
find_package(nlohmann_json 3.11 QUIET)
if(NOT nlohmann_json_FOUND)
    include(FetchContent)
    FetchContent_Declare(
        nlohmann_json
        URL      https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
        URL_HASH SHA256=d6c65aca6b1ed68e7a182f4757257b107ae403032760ed6ef121c9d55e81757d
    )
    FetchContent_MakeAvailable(nlohmann_json)
endif()

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

if(GODOT_SO)
    add_library(libgodot SHARED IMPORTED)
    set_target_properties(libgodot PROPERTIES
        IMPORTED_LOCATION             "${GODOT_SO}"
        INTERFACE_INCLUDE_DIRECTORIES "${GODOT_SRC}"
    )
endif()

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

# ── Julia sysimage ────────────────────────────────────────────────────────────
# Builds a PackageCompiler sysimage (~400 MB) for fast Julia startup.
#   Manual:    cmake --build build --target sysimage
#   Automatic: cmake -DVSL_BUILD_SYSIMAGE=ON ... (rebuilds when .jl sources change)
option(VSL_BUILD_SYSIMAGE "Rebuild Julia sysimage when Julia sources change" OFF)

set(VSL_SOLVER_DIR   "${CMAKE_SOURCE_DIR}/../solver")
set(VSL_SYSIMAGE_OUT "${VSL_SOLVER_DIR}/build/vsl_solver.so")

file(GLOB_RECURSE _julia_sources
    "${VSL_SOLVER_DIR}/src/*.jl"
    "${VSL_SOLVER_DIR}/Project.toml"
    "${VSL_SOLVER_DIR}/test/precompile_hints.jl"
    "${VSL_SOLVER_DIR}/scripts/build_sysimage.jl"
)

add_custom_command(
    OUTPUT  "${VSL_SYSIMAGE_OUT}"
    COMMAND "${JULIA_DIR}/bin/julia" --project=. scripts/build_sysimage.jl
    DEPENDS ${_julia_sources}
    WORKING_DIRECTORY "${VSL_SOLVER_DIR}"
    COMMENT "Building Julia sysimage (may take several minutes)..."
    VERBATIM
)

add_custom_target(sysimage DEPENDS "${VSL_SYSIMAGE_OUT}")

# ── vsl_main executable ───────────────────────────────────────────────────────
if(GODOT_SO)
    add_executable(vsl_main
        src/main.cpp
        src/godot_bridge.cpp
        src/julia_solver.cpp
        src/mission_params_loader.cpp
    )

    target_include_directories(vsl_main PRIVATE src/)

    target_link_libraries(vsl_main PRIVATE
        libgodot
        libjulia
        nlohmann_json::nlohmann_json
        dl          # dlsym for GodotInstance C++ symbol resolution
    )

    target_compile_definitions(vsl_main PRIVATE
        VSL_JULIA_BINDIR="${JULIA_DIR}/bin"
    )

    if(VSL_BUILD_SYSIMAGE)
        add_dependencies(vsl_main sysimage)
    endif()
else()
    message(STATUS "Skipping vsl_main — libgodot.so not found in ${GODOT_LIB_DIR}")
endif()

# ── Integration test ─────────────────────────────────────────────────────────
# Standalone binary — links libjulia only (no libgodot needed for solver tests).
# Run from build/ so solver_abs_path() in julia_solver.cpp resolves correctly.
add_executable(vsl_integration_test
    tests/integration_test.cpp
    src/julia_solver.cpp
    src/mission_params_loader.cpp
)

target_include_directories(vsl_integration_test PRIVATE src/)

target_link_libraries(vsl_integration_test PRIVATE libjulia nlohmann_json::nlohmann_json dl)

# Julia dlopen(RTLD_DEEPBIND) is incompatible with AddressSanitizer
# (https://github.com/google/sanitizers/issues/611). Override global ASan flags
# for this target. TSan is unaffected and remains enabled when VSL_TSAN=ON.
if(CMAKE_BUILD_TYPE STREQUAL "Debug" AND NOT VSL_TSAN)
    target_compile_options(vsl_integration_test PRIVATE -fno-sanitize=all)
    target_link_options(vsl_integration_test PRIVATE -fno-sanitize=all)
endif()

enable_testing()
add_test(NAME phase3_integration
    COMMAND vsl_integration_test
    WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
)

# ── Install ───────────────────────────────────────────────────────────────────
if(GODOT_SO)
    install(TARGETS vsl_main DESTINATION bin)
endif()
