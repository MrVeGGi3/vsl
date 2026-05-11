#!/usr/bin/env bash
# VSL — Verificação de Pré-requisitos do Host
# Execute: chmod +x check_env.sh && ./check_env.sh
# Julia, CMake, Ninja, LaTeX e outros são gerenciados pelo Docker — não verificados aqui.

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
DIM='\033[2m'
RESET='\033[0m'

ok()      { echo -e "  ${GREEN}✓${RESET} $1${DIM}$2${RESET}"; }
missing() { echo -e "  ${RED}✗${RESET} $1${DIM}$2${RESET}"; }
warn()    { echo -e "  ${YELLOW}~${RESET} $1${DIM}$2${RESET}"; }
section() { echo -e "\n${BOLD}${CYAN}$1${RESET}"; }

check_version() {
    local name="$1" cmd="$2" min="$3" flag="${4:---version}"
    if command -v "$cmd" &>/dev/null; then
        local ver
        ver=$("$cmd" $flag 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1)
        if [[ -n "$ver" ]]; then
            local cur_maj cur_min min_maj min_min
            cur_maj=$(echo "$ver" | cut -d. -f1)
            cur_min=$(echo "$ver" | cut -d. -f2)
            min_maj=$(echo "$min" | cut -d. -f1)
            min_min=$(echo "$min" | cut -d. -f2)
            if (( cur_maj > min_maj )) || (( cur_maj == min_maj && cur_min >= min_min )); then
                ok "$name" "  ($ver ≥ $min requerido)"
            else
                warn "$name" "  ($ver instalado, requer ≥ $min)"
            fi
        else
            ok "$name" "  (versão não detectada)"
        fi
        return 0
    else
        missing "$name" "  → não encontrado"
        return 1
    fi
}

echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   VSL — Pré-requisitos do Host           ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo -e "${DIM}  Build tools (Julia, CMake, LaTeX…) rodam no Docker.${RESET}"

# ── GPU NVIDIA ────────────────────────────────────────────────────
section "GPU NVIDIA"
if command -v nvidia-smi &>/dev/null; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
    ok "nvidia-smi" "  ($GPU_NAME)"
    ok "Driver NVIDIA" "  (v$DRIVER_VER)"
    ok "VRAM" "  ($VRAM)"
else
    missing "nvidia-smi" "  → driver NVIDIA não encontrado"
fi

if command -v nvcc &>/dev/null; then
    CUDA_VER=$(nvcc --version 2>&1 | grep -oP 'release \K[\d.]+')
    ok "CUDA toolkit (nvcc)" "  ($CUDA_VER)"
else
    warn "CUDA toolkit (nvcc)" "  → nvcc não encontrado (CUDA.jl usa o driver diretamente)"
fi

# ── Docker ────────────────────────────────────────────────────────
section "Docker"
if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version | grep -oP '[\d.]+' | head -1)
    ok "Docker" "  ($DOCKER_VER)"

    if groups | grep -q docker; then
        ok "Grupo docker" "  (usuário no grupo — sem sudo necessário)"
    else
        warn "Grupo docker" "  → sudo usermod -aG docker \$USER && newgrp docker"
    fi

    if docker info &>/dev/null; then
        ok "Docker daemon" "  (rodando)"
    else
        warn "Docker daemon" "  → sudo systemctl start docker"
    fi

    if docker info 2>/dev/null | grep -q "nvidia"; then
        ok "NVIDIA Container Toolkit" "  (configurado)"
    elif command -v nvidia-ctk &>/dev/null; then
        warn "NVIDIA Container Toolkit" "  → instalado mas não configurado no Docker"
        echo -e "     ${DIM}→ sudo nvidia-ctk runtime configure --runtime=docker${RESET}"
        echo -e "     ${DIM}→ sudo systemctl restart docker${RESET}"
    else
        missing "NVIDIA Container Toolkit" "  → necessário para GPU nos containers (CUDA.jl)"
        echo -e "     ${DIM}→ https://docs.nvidia.com/datacenter/cloud-native/container-toolkit${RESET}"
    fi
else
    missing "Docker" "  → não encontrado"
fi

# ── Git ───────────────────────────────────────────────────────────
section "Git"
check_version "Git" "git" "2.30"
if command -v git &>/dev/null; then
    GIT_USER=$(git config --global user.name 2>/dev/null)
    GIT_EMAIL=$(git config --global user.email 2>/dev/null)
    if [[ -n "$GIT_USER" ]]; then
        ok "Git user" "  ($GIT_USER <$GIT_EMAIL>)"
    else
        warn "Git user" "  → git config --global user.name 'Seu Nome'"
    fi
    if [[ -f ~/.ssh/id_ed25519.pub ]] || [[ -f ~/.ssh/id_rsa.pub ]]; then
        ok "SSH key" "  (encontrada)"
    else
        warn "SSH key" "  → ssh-keygen -t ed25519 -C 'email@exemplo.com'"
    fi
fi

# ── Godot editor ─────────────────────────────────────────────────
section "Godot editor (edição local de cenas .tscn)"
GODOT_FOUND=false
for cmd in godot4 godot "godot_editor"; do
    if command -v "$cmd" &>/dev/null; then
        GODOT_VER=$("$cmd" --version 2>/dev/null | head -1)
        ok "Godot" "  ($GODOT_VER) → comando: $cmd"
        MAJ=$(echo "$GODOT_VER" | cut -d. -f1)
        MIN=$(echo "$GODOT_VER" | cut -d. -f2)
        if (( MAJ >= 4 && MIN >= 6 )); then
            ok "Godot versão" "  (≥ 4.6 — LibGodot disponível ✓)"
        else
            warn "Godot versão" "  (< 4.6 — LibGodot requer ≥ 4.6, atualizar)"
        fi
        GODOT_FOUND=true
        break
    fi
done
$GODOT_FOUND || missing "Godot" "  → não encontrado (baixar 4.6.2 em godotengine.org)"

# ── VS Codium ─────────────────────────────────────────────────────
section "VS Codium"
if command -v codium &>/dev/null; then
    CODIUM_VER=$(codium --version 2>/dev/null | head -1)
    ok "VS Codium" "  ($CODIUM_VER)"

    echo -e "  ${DIM}Verificando extensões (Open-VSX)...${RESET}"
    EXTENSIONS=$(codium --list-extensions 2>/dev/null)

    check_ext() {
        local id="$1" name="$2"
        if echo "$EXTENSIONS" | grep -qi "$id"; then
            ok "  ext: $name"
        else
            missing "  ext: $name" "  → codium --install-extension $id"
        fi
    }

    check_ext "julialang.language-julia"               "Julia"
    check_ext "geequlim.godot-tools"                   "Godot Tools"
    check_ext "james-yu.latex-workshop"                "LaTeX Workshop"
    check_ext "llvm-vs-code-extensions.vscode-clangd"  "clangd (C++)"
    check_ext "eamodio.gitlens"                        "GitLens"
    check_ext "usernamehw.errorlens"                   "Error Lens"
else
    missing "VS Codium" "  → não encontrado (vscodium.com)"
fi

# ── Claude Code CLI ───────────────────────────────────────────────
section "Claude Code CLI"
if command -v claude &>/dev/null; then
    CLAUDE_VER=$(claude --version 2>/dev/null | head -1)
    ok "Claude Code" "  ($CLAUDE_VER)"
else
    missing "Claude Code" "  → npm install -g @anthropic-ai/claude-code"
fi

echo -e "\n${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║  Pronto! Use docker compose up para build ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}\n"
