#pragma once
#include "mission_params.h"
#include "julia_api.h"
#include <string>

// Load mission_params.json into VslMissionParams.
// Returns true on success; on failure prints to stderr and leaves params at defaults.
bool load_mission_params(const std::string& json_path, VslMissionParams& out);

// Build C API structs from loaded params.
// The returned structs hold raw pointers into params.propulsion and params.rocket.aero,
// so params must remain alive for the lifetime of the returned structs.
VslThrustCurveData make_thrust_curve(const VslMissionParams& params);
VslAeroTableData   make_aero_table(const VslMissionParams& params);
