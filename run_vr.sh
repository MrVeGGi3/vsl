#!/usr/bin/env bash
# Launch VSL in VR mode via WiVRn.
# Requires: WiVRn server running (flatpak run io.github.wivrn.wivrn) + Quest connected.
#
# Problem solved: active_runtime.json is a symlink; the OpenXR loader doesn't follow
# it when resolving the relative .so path, causing "failed to load a runtime".
# Fix: XR_RUNTIME_JSON points to the real JSON inside the Flatpak (no symlink).

WIVRN_JSON=$(find ~/.local/share/flatpak/app/io.github.wivrn.wivrn \
    -name "openxr_wivrn.json" 2>/dev/null | head -1)

if [[ -z "$WIVRN_JSON" ]]; then
    echo "ERROR: WiVRn Flatpak not found. Install with:"
    echo "  flatpak install flathub io.github.wivrn.wivrn"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/main/build_release"

# JULIA_NUM_THREADS=1: prevents Julia 1.12 parallel GC/task-scheduler threads
# from conflicting with Godot's libuv event loop (jl_threadfun crash).
exec env XR_RUNTIME_JSON="$WIVRN_JSON" \
    JULIA_NUM_THREADS=1 \
    "$BUILD_DIR/vsl_main" "" "$SCRIPT_DIR/godot/project" "$@"
