#pragma once
#include <string>

// Forward declaration — full type comes from libgodot headers.
struct GDExtensionInterfaceGetProcAddress;

// Result of a LibGodot initialization attempt.
struct GodotInitResult {
    bool success{false};
    std::string error_message;
};

// Initialize LibGodot and start the main loop.
// Must be called after Julia is initialized (Julia owns the process main thread).
//
// scene_path: path to the Godot project main scene (.tscn)
// Returns GodotInitResult — check success before entering the render loop.
GodotInitResult godot_init(const std::string& project_path);

// Run one iteration of the Godot main loop.
// Returns false when Godot requests shutdown.
bool godot_iterate();

// Tear down LibGodot. Safe to call even if godot_init() failed.
void godot_shutdown();
