#include "godot_bridge.h"

#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <string>
#include <vector>

// GDExtension types — pulled directly from the Godot source tree,
// which is on the include path via CMake INTERFACE_INCLUDE_DIRECTORIES.
#include "core/extension/gdextension_interface.gen.h"

// VSL has no GDExtension classes to register — these callbacks are no-ops.
static void gdext_noop(void* /*userdata*/, GDExtensionInitializationLevel /*level*/) {}

// LibGodot requires a non-null init function to bootstrap its internal extension.
static GDExtensionBool vsl_gdext_init(
    GDExtensionInterfaceGetProcAddress /*p_get_proc_address*/,
    GDExtensionClassLibraryPtr         /*p_library*/,
    GDExtensionInitialization*         r_initialization)
{
    r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    r_initialization->userdata    = nullptr;
    r_initialization->initialize  = gdext_noop;
    r_initialization->deinitialize = gdext_noop;
    return 1;
}

extern "C" {
    GDExtensionObjectPtr libgodot_create_godot_instance(
        int p_argc, char* p_argv[],
        GDExtensionInitializationFunction p_init_func);
    void libgodot_destroy_godot_instance(GDExtensionObjectPtr p_godot_instance);
}

// ── GodotInstance method pointers ─────────────────────────────────────────────
// Non-virtual C++ methods — exported in libgodot.so with stable mangled names
// for GCC/Clang Linux x86-64, Godot 4.6.2.
// Calling convention: first arg is implicit `this` (rdi on SysV ABI).
using MemberBoolFn = bool (*)(void*);  // bool GodotInstance::method()
using MemberVoidFn = void (*)(void*);  // void GodotInstance::method()

static GDExtensionObjectPtr g_instance      {nullptr};
static MemberBoolFn         g_fn_start      {nullptr};
static MemberBoolFn         g_fn_iteration  {nullptr};
static MemberVoidFn         g_fn_stop       {nullptr};

static bool resolve_godot_symbols() {
    // RTLD_DEFAULT searches all libraries already loaded into the process.
    // libgodot.so is linked at build time, so its symbols are always present.
    g_fn_start     = reinterpret_cast<MemberBoolFn>(
        dlsym(RTLD_DEFAULT, "_ZN13GodotInstance5startEv"));
    g_fn_iteration = reinterpret_cast<MemberBoolFn>(
        dlsym(RTLD_DEFAULT, "_ZN13GodotInstance9iterationEv"));
    g_fn_stop      = reinterpret_cast<MemberVoidFn>(
        dlsym(RTLD_DEFAULT, "_ZN13GodotInstance4stopEv"));

    if (!g_fn_start || !g_fn_iteration || !g_fn_stop) {
        std::fprintf(stderr,
            "[vsl] godot_bridge: symbol resolution failed — "
            "start=%p iteration=%p stop=%p\n",
            (void*)g_fn_start, (void*)g_fn_iteration, (void*)g_fn_stop);
        return false;
    }
    return true;
}

// ── Public API ────────────────────────────────────────────────────────────────

GodotInitResult godot_init(const std::string& project_path) {
    if (!resolve_godot_symbols())
        return {false, "GodotInstance symbol resolution failed"};

    // Pass --path <project> so Godot finds project.godot.
    std::vector<std::string> args_str = {"vsl_main", "--path", project_path};
#ifdef DEBUG
    args_str.push_back("--vulkan-validation");
#endif
    std::vector<char*> argv;
    for (auto& s : args_str)
        argv.push_back(const_cast<char*>(s.c_str()));

    g_instance = libgodot_create_godot_instance(
        static_cast<int>(argv.size()), argv.data(), vsl_gdext_init);

    if (!g_instance)
        return {false, "libgodot_create_godot_instance returned null"};

    if (!g_fn_start(g_instance)) {
        libgodot_destroy_godot_instance(g_instance);
        g_instance = nullptr;
        return {false, "GodotInstance::start() failed"};
    }

    return {true, ""};
}

bool godot_iterate() {
    if (!g_instance || !g_fn_iteration) return false;
    // GodotInstance::iteration() returns true when Godot wants to quit.
    // Our contract: true = still running, false = shutdown requested.
    return !g_fn_iteration(g_instance);
}

void godot_shutdown() {
    if (!g_instance) return;
    g_fn_stop(g_instance);
    libgodot_destroy_godot_instance(g_instance);
    g_instance = nullptr;
}
