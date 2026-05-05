#include "godot_bridge.h"

#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <string>
#include <vector>

// ── Minimal GDExtension types (from gdextension_interface.gen.h) ─────────────
using GDExtensionObjectPtr              = void*;
using GDExtensionInitializationFunction = void*;

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
    std::vector<char*> argv;
    for (auto& s : args_str)
        argv.push_back(const_cast<char*>(s.c_str()));

    g_instance = libgodot_create_godot_instance(
        static_cast<int>(argv.size()), argv.data(), nullptr);

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
    return g_fn_iteration(g_instance);
}

void godot_shutdown() {
    if (!g_instance) return;
    g_fn_stop(g_instance);
    libgodot_destroy_godot_instance(g_instance);
    g_instance = nullptr;
}
