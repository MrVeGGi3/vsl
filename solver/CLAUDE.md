# VSL Solver — Módulo Julia
## Contexto

Núcleo numérico do VSL. Responsável por toda computação científica:
propagação orbital, análise de missão, MDO, dinâmica de voo.
Compilado com PackageCompiler.jl → libjulia para embed no processo principal C++.

---

## Stack Julia

```
Julia 1.12.5 (via Juliaup)
├── SatelliteToolboxTle.jl            — parsing de TLEs
├── SatelliteToolboxPropagators.jl    — SGP4, J2, Cowell
├── SatelliteToolboxCelestialBodies.jl — Sol, Lua, planetas
├── SPICE.jl                          — ephemeris NASA
├── DifferentialEquations.jl          — ODEs (dinâmica de voo)
├── ModelingToolkit.jl                — MDO Engine (equações acopladas)
├── StaticArrays.jl                   — arrays de tamanho fixo (zero alloc)
├── CUDA.jl                           — GPU RTX 4060 (CUDA 13.0 via driver)
├── KernelAbstractions.jl             — kernels GPU agnósticos
├── CairoMakie.jl                     — figuras para o paper (não-interativo)
├── GLMakie.jl                        — visualização interativa standalone
├── BenchmarkTools.jl                 — benchmarks obrigatórios
├── Pluto.jl                          — notebooks reprodutíveis
└── PackageCompiler.jl                — compila → libjulia para C++
```

---

## Patterns de Performance — OBRIGATÓRIOS

### 1. Tipos numéricos
```julia
# SEMPRE Float64 para cálculos orbitais — precisão necessária para SGP4
# Float32 apenas em arrays de saída para LibGodot (rendering)
using StaticArrays

const Vec3  = SVector{3, Float64}  # posição / velocidade (km, km/s)
const Vec6  = SVector{6, Float64}  # estado orbital [r; v]
const Quat  = SVector{4, Float64}  # quaternion de atitude
```

### 2. Zero alocação no hot path
```julia
# RUIM — aloca a cada chamada
function propagate_step(state, dt)
    new_state = similar(state)   # alocação!
    # ...
end

# BOM — prealoca fora do loop, modifica in-place
function propagate_step!(state_out::Vec6, state_in::Vec6, dt::Float64, cache)
    # zero alloc — usa cache preallocado
end
# Convenção: funções mutantes terminam com !
```

### 3. @views em slices
```julia
r = @view state[1:3]   # sem cópia
v = @view state[4:6]   # sem cópia
```

### 4. @inbounds em loops críticos
```julia
@inbounds for i in eachindex(out)
    out[i] = a[i] + b[i]
end
# Usar apenas quando índices são garantidamente válidos
```

### 5. Type stability — verificar com @code_warntype
```julia
# Detectar instabilidade:
@code_warntype propagate_orbit(tle, 3600.0)
# Qualquer Any vermelho no output = problema de performance
```

### 6. GC desabilitado no hot path (chamado pelo C++)
```julia
Base.@ccallable function vsl_propagate_orbit(
    tle1::Cstring, tle2::Cstring,
    duration::Cdouble,
    out_pos::Ptr{Cfloat}, out_count::Ptr{Cint}
)::Cint
    GC.enable(false)
    try
        # computação crítica — sem alocações aqui
        return Cint(0)
    catch e
        @error "vsl_propagate_orbit" exception=e
        return Cint(-1)
    finally
        GC.enable(true)
    end
end
```

### 7. CUDA.jl — RTX 4060 (CUDA 13.0 via driver)
```julia
# Verificar disponibilidade
using CUDA
CUDA.functional()        # deve retornar true
CUDA.versioninfo()       # mostra RTX 4060 + CUDA 13.0

# Kernels GPU para operações pesadas (LBM, campos CFD)
using KernelAbstractions
@kernel function orbital_kernel!(out, states)
    i = @index(Global)
    # ...
end
# KernelAbstractions roda em CPU ou GPU sem mudar o código
```

---

## Interface C Exportada (para processo principal C++)

```julia
# Toda função chamável do C++ deve:
# - usar Base.@ccallable
# - retornar Cint (0 = ok, negativo = erro)
# - nunca lançar exceções (capturar com try/catch)
# - aceitar apenas tipos C primitivos ou Ptr{}

Base.@ccallable function vsl_propagate_orbit(
    tle_line1::Cstring,
    tle_line2::Cstring,
    duration_s::Cdouble,
    out_positions::Ptr{Cfloat},  # Float32[] x,y,z interleaved (km)
    out_count::Ptr{Cint}
)::Cint
    try
        tle = read_tle(unsafe_string(tle_line1), unsafe_string(tle_line2))
        orbp = Propagators.init(Val(:SGP4), tle)
        # propaga e preenche out_positions...
        return Cint(0)
    catch e
        @error "vsl_propagate_orbit failed" exception=e
        return Cint(-1)
    end
end
```

---

## Estrutura de Diretórios

```
solver/
├── CLAUDE.md
├── Project.toml
├── Manifest.toml
├── src/
│   ├── VSLSolver.jl           ← módulo principal
│   ├── orbital/
│   │   ├── propagation.jl     ← SGP4, J2
│   │   ├── maneuvers.jl       ← Hohmann, Lambert
│   │   └── access.jl          ← janelas de acesso, ground track
│   ├── mission/
│   │   ├── eclipse.jl
│   │   ├── power_budget.jl
│   │   └── link_budget.jl
│   ├── mdo/
│   │   └── engine.jl          ← ModelingToolkit MDO
│   └── export/
│       └── c_api.jl           ← funções @ccallable para C++
├── test/
│   ├── runtests.jl
│   └── orbital/               ← validação vs STK/GMAT/Vallado
└── notebooks/
    ├── 01_orbit_validation.jl ← Pluto — Paper 1 Seção 4
    ├── 02_mission_analysis.jl ← Pluto — Paper 1 Seção 5
    └── 03_mdo_demo.jl         ← Pluto — Paper 3
```

---

## Regras de Qualidade

- @code_warntype em toda função do hot path antes de merge
- BenchmarkTools antes/depois de qualquer otimização
- Notebooks Pluto reprodutíveis — sem estado oculto entre células
- Figuras salvas em ../paper/figures/ via CairoMakie (não GLMakie)
- Testes de validação comparam com referência conhecida (Vallado, GMAT)

---

## Referências Técnicas

- Vallado — *Fundamentals of Astrodynamics and Applications* (SGP4 reference)
- Wertz & Larson — *SMAD* (metodologia de missão)
- SatelliteToolbox.jl docs: https://juliaspace.github.io/SatelliteToolbox.jl
- CUDA.jl docs: https://cuda.juliagpu.org
