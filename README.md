# VSL — Virtual Simulation Lab

[![CI](https://github.com/MrVeGGi3/vsl/actions/workflows/ci.yml/badge.svg)](https://github.com/MrVeGGi3/vsl/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![DOI](https://zenodo.org/badge/1230281538.svg)](https://doi.org/10.5281/zenodo.20059111)

An open-source mission analysis environment for early-stage spacecraft design. VSL combines a Julia numerical solver with real-time 3D visualization (LibGodot) and optional immersive VR (OpenXR / Meta Quest via Quest Link), targeting sounding rockets, CubeSats, and smallsats.

The analysis methodology follows the [Space Mission Analysis and Design (SMAD)](https://doi.org/10.1007/978-94-011-2692-2) framework. Results can be exported as structured JSON for use in reports and Pluto notebooks.

---

## Features

- **Orbital propagation** — SGP4 / J2 via [SatelliteToolbox.jl](https://github.com/JuliaSpace/SatelliteToolbox.jl)
- **Eclipse analysis** — cylindrical shadow geometry, fraction per orbit
- **Ground station access** — contact windows with max elevation, GMST-corrected ECI→ECEF
- **Maneuver planning** — Hohmann transfer ΔV and time of flight
- **Mission report** — JSON export with epoch, access windows, eclipse flags, ΔV budget
- **Interactive 3D** — real-time Earth (8K textures), orbital trajectory colored by segment type, ground station marker
- **VR mode** — immersive visualization via OpenXR (Meta Quest 3S over Quest Link)

---

## Requirements

| Component | Version | Notes |
|-----------|---------|-------|
| Julia | ≥ 1.12 | via [Juliaup](https://github.com/JuliaLang/juliaup) |
| Godot | 4.6.2 | required for 3D visualization |
| C++ compiler | GCC ≥ 13 or Clang ≥ 17 | C++17 required |
| CMake | ≥ 3.22 | |
| Docker + NVIDIA Container Toolkit | 29+ | optional, for containerized workflow |

For VR visualization only: Meta Quest 2/3/3S connected via Quest Link (USB-C 3.2) or WiVRn.

---

## Installation

### Option A — Docker (recommended)

Requires Docker ≥ 29 and NVIDIA Container Toolkit.

```bash
git clone https://github.com/MrVeGGi3/vsl.git
cd vsl

# Run the Julia solver REPL
docker compose run --rm julia-solver

# Start Pluto notebooks (validation + paper figures)
docker compose up pluto
# Open http://localhost:1234 in your browser

# Compile the C++ main process
docker compose run --rm vsl-build
```

### Option B — Manual installation

**1. Clone the repository**

```bash
git clone https://github.com/MrVeGGi3/vsl.git
cd vsl
```

**2. Install Julia via Juliaup**

```bash
curl -fsSL https://install.julialang.org | sh
juliaup add 1.12
juliaup default 1.12
```

**3. Instantiate the solver**

```bash
cd solver
julia --project=. -e "using Pkg; Pkg.instantiate()"
cd ..
```

**4. Build the C++ main process** *(requires LibGodot 4.6 compiled as shared library)*

```bash
cd main
cmake -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -GNinja
cmake --build build -j$(nproc)
```

> **Note:** LibGodot must be compiled from source (`scons platform=linuxbsd target=template_release library_type=shared_library`). See [SETUP.md](SETUP.md) for the full environment setup guide.

---

## Running Tests

```bash
cd solver
julia --project=. -e "using Pkg; Pkg.test()"
```

Expected output: **34 tests passing** across four test sets:
- `orbital/test_propagation.jl` — SGP4 accuracy vs. SMAD reference (ISS, 408 km)
- `orbital/test_maneuvers.jl` — Hohmann transfer ΔV (universal variables)
- `mission/test_eclipse.jl` — eclipse geometry and fraction (ISS: 35.4%)
- `mission/test_access.jl` — ground station access windows (Brasília, 4 passes/24 h)

---

## Usage

### Solver (Julia)

```julia
cd("solver")
using VSLSolver, SatelliteToolboxTle, Dates

tle_l1 = "1 25544U 98067A   24001.50000000  .00006000  00000-0  10000-3 0  9992"
tle_l2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49507896 12343"
jd     = datetime2julian(DateTime(2024, 1, 1, 12, 0, 0))

tle            = read_tle(tle_l1, tle_l2)
times, pos, v  = propagate_orbit(tle, 86400.0; step_s=30.0)

# Eclipse fraction
frac = eclipse_fraction(pos, times, jd)
println("Eclipse fraction: $(round(frac * 100; digits=1))%")

# Ground station access windows (Brasília)
windows = access_windows(pos, times, -15.78, -47.93, jd; min_elev_deg=5.0)
println("Passes: $(length(windows)), mean duration: $(round(mean(te-ts for (ts,te,_) in windows)/60; digits=1)) min")

# Export mission report
report = mission_report(tle_l1, tle_l2, jd, 86400.0; gs_lat=-15.78, gs_lon=-47.93)
open("report.json", "w") do f; write(f, to_json(report)); end
```

### Validation notebook

```bash
docker compose up pluto
# Open http://localhost:1234 → solver/notebooks/phase3_validation.jl
```

The notebook reproduces all paper figures and SMAD validation checks.

### Interactive 3D / VR

```bash
# Desktop mode
./main/build/vsl_main --path godot/project

# VR mode (WiVRn / Quest Link)
./run_vr.sh
```

---

## Project Structure

```
vsl/
├── solver/          Julia numerical solver (VSLSolver.jl)
│   ├── src/         Orbital propagation, eclipse, access, maneuvers, MDO
│   ├── test/        34 unit tests
│   └── notebooks/   Pluto validation notebooks → paper figures
├── main/            C++17 main process (LibGodot + libjulia orchestration)
│   └── src/         julia_solver.cpp C API bridge, main.cpp
├── godot/           Godot scenes, GDScript, shaders
│   └── project/     orbit_viewer, analysis_panel, VR controllers
├── paper/           JOSS paper (paper.md, paper.bib, figures/)
└── docker-compose.yml
```

---

## How to Cite

If you use VSL in your research, please cite:

**Software archive (Zenodo):**

```bibtex
@software{vsl2026_zenodo,
  author  = {Soares, Matheus Veras},
  title   = {{VSL}: Virtual Simulation Lab},
  year    = {2026},
  doi     = {10.5281/zenodo.20059111},
  url     = {https://doi.org/10.5281/zenodo.20059111}
}
```

**JOSS paper** *(under review — DOI assigned upon acceptance):*

Submission: https://joss.theoj.org/papers/0025df1b9f4689d776253ffd37b7cb88

```bibtex
@article{vsl2026,
  author  = {Soares, Matheus Veras},
  title   = {{VSL}: An Open-Source Mission Analysis Environment with Interactive 3D and Immersive Visualization},
  journal = {Journal of Open Source Software},
  year    = {2026},
  doi     = {10.21105/joss.XXXXX}
}
```

---

## License

MIT © 2026 Matheus Veras Soares — Instituto Tecnológico de Aeronáutica
