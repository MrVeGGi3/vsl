---
title: 'VSL: An Open-Source Mission Analysis Environment with Interactive 3D and Immersive Visualization'
tags:
  - astrodynamics
  - mission analysis
  - orbital mechanics
  - Julia
  - C++
  - spacecraft
  - CubeSat
authors:
  - name: Matheus Veras Soares
    orcid: 0000-0000-0000-0000
    affiliation: 1
affiliations:
  - name: Instituto Tecnológico de Aeronáutica, São José dos Campos, SP, Brazil
    index: 1
date: 06 May 2026
bibliography: paper.bib
---

# Summary

VSL (Virtual Simulation Lab) is an open-source mission analysis environment for early-stage spacecraft design. It provides orbital propagation, eclipse analysis, ground station access window computation, and maneuver planning within an interactive real-time 3D environment. The system couples a Julia numerical solver (`VSLSolver.jl`) with a LibGodot rendering layer and an optional OpenXR immersive visualization mode, targeting sounding rockets, CubeSats, and smallsats. VSL follows the Space Mission Analysis and Design (SMAD) methodology [@smad] and is designed to lower the entry barrier for mission analysis without sacrificing physical fidelity.

# Statement of Need

Professional astrodynamics tools such as AGI Systems Tool Kit (STK) [@stk] and NASA's General Mission Analysis Tool (GMAT) [@gmat] offer comprehensive mission analysis capabilities, but present significant barriers: STK requires a commercial license, and GMAT, although open-source, has a steep learning curve and no integrated visualization during analysis. Open-source libraries such as Orekit [@orekit] and poliastro [@poliastro] are well-validated but script-only, requiring separate visualization pipelines for interactive exploration.

VSL fills this gap by integrating mission analysis and real-time 3D visualization in a single interactive tool. The intended users are small-satellite engineers, university students, and researchers who need rapid mission feasibility assessment—contact times, eclipse fractions, ΔV budgets—without the overhead of commercial tools or the fragmentation of assembling separate solver and visualization stacks. All analysis results can be exported as structured JSON for downstream use in reports and Jupyter/Pluto notebooks.

# Architecture

VSL employs a process-level architecture in which a C++17 main process initializes LibGodot [@godot] and libjulia [@julia] as peer libraries (Figure 1). This differs from the conventional GDExtension plugin approach where Godot acts as host: the C++ process owns the main loop, controls synchronization between the render timestep and the numerical solver, and manages the lifecycle of both libraries explicitly.

![Architecture diagram: vsl\_main (C++17) initializes libgodot.so for rendering and libjulia.so for the orbital solver. A lock-free double buffer decouples the 90 Hz render thread from the propagation timestep.\label{fig:arch}](figures/architecture_diagram.pdf)

The numerical solver (`VSLSolver.jl`, Julia 1.12) provides:

- **Orbital propagation** via `SatelliteToolboxPropagators.jl` (SGP4/J2) [@satellitetoolbox]
- **Eclipse detection** using cylindrical shadow geometry (SMAD Ch. 11)
- **Ground station access windows** with GMST-corrected ECI→ECEF transformation
- **Hohmann transfer ΔV** using universal variables and Stumpff functions [@curtis]
- **Mission report** serialization to JSON via `MissionReport` struct

The visualization layer (LibGodot 4.6) renders an 8K Earth with albedo, night-side illumination, and cloud compositing. The orbital trajectory is vertex-colored by segment type (sunlit, eclipse, access window). A thin C API (`julia_solver.cpp`) bridges the Julia functions to Godot via `jl_eval_string`, avoiding the global-binding restrictions introduced in Julia 1.12 [@julia].

For VR, VSL initializes OpenXR directly through LibGodot, targeting Meta Quest 3S via Quest Link (USB-C 3.2, ≈3–5 ms latency). A lock-free double buffer (`std::atomic` swap) decouples the 90 Hz render thread from the propagation thread, eliminating frame stalls.

# Validation

VSL's solver was validated against SMAD reference values using a publicly known ISS TLE epoch (2024-01-01 12:00:00 UTC, NORAD ID 25544):

| Quantity | VSL | SMAD Reference | Error |
|---|---|---|---|
| Altitude | 408.3 km | 408 km | < 0.1 % |
| Orbital period | 92.7 min | 92.7 min | < 0.1 % |
| Eclipse fraction | 35.4 % | 28–45 % (β ≈ −23°) | within range |
| GMST at J2000.0 | 280.46° | 280.461° (IAU 1982) | < 0.01° |

Ground station access windows for Brasília (φ = −15.78°, λ = −47.93°, elevation mask 5°) over 24 hours yielded 4 passes with mean contact duration 6.6 minutes, consistent with SMAD Ch. 9 predictions for ISS inclination (51.6°). The full test suite (34 unit tests + 31 integration tests) passes on Julia 1.12.5 and GCC 13.

# Case Study

A 24-hour mission analysis for the ISS orbit was performed with a single ground station at Brasília. Orbital propagation at 30-second steps produced 2,880 state vectors. Eclipse and access analysis completed in under 2 seconds on an RTX 4060 laptop (28 cores, 8 GB VRAM).

![Ground track of the ISS over 24 hours. Green segments indicate contact windows with the Brasília ground station (yellow marker). Eclipse periods are shown in purple.\label{fig:groundtrack}](figures/ground_track_iss.pdf)

The interactive environment displayed contact-time countdown, eclipse fraction, and orbit parameters in real time. A JSON report exported by `vsl_generate_report_json()` contained the full propagation epoch, per-period eclipse flags, access window timestamps with maximum elevation angles, and a Hohmann transfer ΔV budget to a 600 km circular target orbit. The same data fed the Pluto validation notebook used to produce Figure \ref{fig:groundtrack}, ensuring reproducibility of all paper figures directly from the source code.

# Acknowledgements

The author thanks Ronan Arraes Jardim Chagas and contributors to `SatelliteToolbox.jl` at INPE for the Julia astrodynamics library that underpins VSL's orbital propagation.

# References
