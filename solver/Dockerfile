# VSL Julia Solver
# Base: CUDA 12.0 + Ubuntu 22.04 (compatível com driver 580 / CUDA 13.0)
# Usado por: julia-solver, pluto, julia-compile

FROM nvidia/cuda:12.0.0-devel-ubuntu22.04

# ── Evitar prompts interativos no apt ────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# ── Dependências do sistema ───────────────────────────────────────
RUN apt-get update && apt-get install -y \
    curl wget git \
    ca-certificates \
    build-essential \
    libssl-dev \
    # Necessário para GLMakie (display virtual em CI)
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    xvfb \
    # Necessário para SPICE.jl
    libcspice-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Juliaup + Julia 1.12.5 ───────────────────────────────────────
RUN curl -fsSL https://install.julialang.org | sh -s -- \
    --yes \
    --default-channel 1.12

ENV PATH="/root/.juliaup/bin:$PATH"

# ── Variáveis de ambiente Julia ───────────────────────────────────
ENV JULIA_NUM_THREADS=auto
ENV JULIA_DEPOT_PATH=/root/.julia
ENV JULIA_CUDA_SOFT_MEMORY_LIMIT=6GiB
# Garante que CUDA.jl usa o toolkit do container, não o host
ENV JULIA_CUDA_USE_BINARYBUILDER=false

# ── Pré-instalar pacotes Julia (camada cacheável) ─────────────────
WORKDIR /workspace/solver

# Copia só os arquivos de dependência primeiro (melhor cache)
COPY Project.toml Manifest.toml ./

RUN julia --project=. -e ' \
    using Pkg; \
    Pkg.instantiate(); \
    Pkg.precompile(); \
    println("✓ Pacotes Julia instalados e compilados") \
    '

# ── Copia o código fonte ──────────────────────────────────────────
COPY . .

# ── Verificação final ─────────────────────────────────────────────
RUN julia --project=. -e ' \
    using CUDA; \
    @info "CUDA functional: $(CUDA.functional())"; \
    using SatelliteToolboxTle, SatelliteToolboxPropagation; \
    @info "SatelliteToolbox OK"; \
    using DifferentialEquations; \
    @info "DifferentialEquations OK" \
    '

CMD ["julia", "--project=.", "--threads=auto"]
