#!/usr/bin/env bash
# VSL — Verificação de Dependências do Ambiente
# Execute: chmod +x check_env.sh && ./check_env.sh

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

check_cmd() {
    local name="$1" cmd="$2" version_flag="${3:---version}"
    if command -v "$cmd" &>/dev/null; then
        local ver
        ver=$("$cmd" $version_flag 2>&1 | head -1 | sed 's/[^0-9.]//g' | head -c 20)
        ok "$name" "  ($ver)"
        return 0
    else
        missing "$name" "  → não encontrado"
        return 1
    fi
}

check_version() {
    # check_version "Nome" "cmd" "versão mínima" "flag"
    local name="$1" cmd="$2" min="$3" flag="${4:---version}"
    if command -v "$cmd" &>/dev/null; then
        local ver
        ver=$("$cmd" $flag 2>&1 | grep -oP '\d+\.\d+[\.\d]*' | head -1)
        if [[ -n "$ver" ]]; then
            # Comparação simples de versão (major.minor)
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
echo -e "${BOLD}║   VSL — Verificação de Dependências      ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"

# ── Sistema ──────────────────────────────────────────────────────
section "Sistema"
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    ok "Linux" "  ($PRETTY_NAME)"
else
    warn "Linux" "  (distro não detectada)"
fi

ARCH=$(uname -m)
ok "Arquitetura" "  ($ARCH)"

CPU_CORES=$(nproc)
ok "CPU cores" "  ($CPU_CORES cores disponíveis)"

RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
if (( RAM_GB >= 16 )); then
    ok "RAM" "  (${RAM_GB}GB)"
else
    warn "RAM" "  (${RAM_GB}GB — recomendado ≥ 16GB para Julia + Godot)"
fi

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
    warn "CUDA toolkit (nvcc)" "  → nvcc não encontrado (CUDA.jl pode ainda funcionar sem ele)"
fi

# ── Terminal & Shell ──────────────────────────────────────────────
section "Terminal & Shell"
check_cmd "WezTerm"  "wezterm"
check_cmd "Fish"     "fish"
check_cmd "Zsh"      "zsh"
check_cmd "Starship" "starship"
check_cmd "tmux"     "tmux"     # alternativa ao multiplexer do WezTerm

# ── Linguagens & Runtimes ─────────────────────────────────────────
section "Linguagens & Runtimes"
check_version "Julia"   "julia"  "1.10"
check_cmd     "Juliaup" "juliaup"

check_version "Node.js" "node"   "18.0"
check_cmd     "npm"     "npm"
check_version "Python"  "python3" "3.10"

# ── Editor ────────────────────────────────────────────────────────
section "Editor"
if command -v code &>/dev/null; then
    CODE_VER=$(code --version 2>/dev/null | head -1)
    ok "VSCode" "  ($CODE_VER)"

    echo -e "  ${DIM}Verificando extensões instaladas...${RESET}"
    EXTENSIONS=$(code --list-extensions 2>/dev/null)

    check_ext() {
        local id="$1" name="$2"
        if echo "$EXTENSIONS" | grep -qi "$id"; then
            ok "  ext: $name"
        else
            missing "  ext: $name" "  → code --install-extension $id"
        fi
    }

    check_ext "julialang.language-julia"              "Julia"
    check_ext "geequlim.godot-tools"                  "Godot Tools"
    check_ext "james-yu.latex-workshop"               "LaTeX Workshop"
    check_ext "llvm-vs-code-extensions.vscode-clangd" "clangd (C++)"
    check_ext "ms-azuretools.vscode-docker"           "Docker"
    check_ext "eamodio.gitlens"                       "GitLens"
    check_ext "usernamehw.errorlens"                  "Error Lens"
else
    missing "VSCode" "  → não encontrado"
fi

# ── Godot ─────────────────────────────────────────────────────────
section "Godot"
GODOT_FOUND=false
for cmd in godot4 godot "godot_editor"; do
    if command -v "$cmd" &>/dev/null; then
        GODOT_VER=$("$cmd" --version 2>/dev/null | head -1)
        ok "Godot" "  ($GODOT_VER) → comando: $cmd"
        # Verifica se é 4.6+
        MAJ=$(echo "$GODOT_VER" | cut -d. -f1)
        MIN=$(echo "$GODOT_VER" | cut -d. -f2)
        if (( MAJ >= 4 && MIN >= 6 )); then
            ok "Godot versão" "  (≥ 4.6 — LibGodot disponível ✓)"
        else
            warn "Godot versão" "  (< 4.6 — LibGodot não disponível, atualizar recomendado)"
        fi
        GODOT_FOUND=true
        break
    fi
done
$GODOT_FOUND || missing "Godot" "  → não encontrado (baixar 4.6.2)"

# ── Build tools C++ ───────────────────────────────────────────────
section "Build Tools C++"
check_cmd     "CMake"   "cmake"   "--version"
check_version "CMake"   "cmake"   "3.25"        "--version"
check_cmd     "Ninja"   "ninja"   "--version"
check_cmd     "clangd"  "clangd"  "--version"
check_cmd     "clang++" "clang++" "--version"
check_cmd     "g++"     "g++"     "--version"
check_cmd     "pkg-config" "pkg-config"

# Vulkan
if command -v vulkaninfo &>/dev/null; then
    ok "Vulkan tools" "  (vulkaninfo disponível)"
else
    warn "Vulkan tools" "  → instalar: vulkan-tools"
fi

# ── Docker ────────────────────────────────────────────────────────
section "Docker"
if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version | grep -oP '[\d.]+' | head -1)
    ok "Docker" "  ($DOCKER_VER)"

    # Verifica se usuário está no grupo docker
    if groups | grep -q docker; then
        ok "Grupo docker" "  (usuário no grupo — sem sudo necessário)"
    else
        warn "Grupo docker" "  → adicionar: sudo usermod -aG docker \$USER"
    fi

    # Verifica se daemon está rodando
    if docker info &>/dev/null; then
        ok "Docker daemon" "  (rodando)"
    else
        warn "Docker daemon" "  → iniciar: sudo systemctl start docker"
    fi

    # NVIDIA Container Toolkit
    if docker info 2>/dev/null | grep -q "nvidia"; then
        ok "NVIDIA Container Toolkit" "  (configurado)"
    elif command -v nvidia-ctk &>/dev/null; then
        warn "NVIDIA Container Toolkit" "  → instalado mas não configurado no Docker"
        echo -e "     ${DIM}→ sudo nvidia-ctk runtime configure --runtime=docker${RESET}"
        echo -e "     ${DIM}→ sudo systemctl restart docker${RESET}"
    else
        missing "NVIDIA Container Toolkit" "  → necessário para CUDA.jl no Docker"
    fi
else
    missing "Docker" "  → não encontrado"
fi

# ── Claude Code CLI ───────────────────────────────────────────────
section "Claude Code CLI"
check_cmd "Claude Code" "claude"

# ── LaTeX ─────────────────────────────────────────────────────────
section "LaTeX"
if command -v latexmk &>/dev/null; then
    ok "latexmk" ""
    # Verifica instalação TeX Live
    if command -v tlmgr &>/dev/null; then
        TEXLIVE_VER=$(tlmgr --version 2>/dev/null | grep -oP '\d{4}' | head -1)
        ok "TeX Live" "  ($TEXLIVE_VER)"
    fi
else
    warn "LaTeX local" "  → não encontrado (OK se usar só via Docker)"
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
    # Verifica se há chave SSH configurada
    if [[ -f ~/.ssh/id_ed25519.pub ]] || [[ -f ~/.ssh/id_rsa.pub ]]; then
        ok "SSH key" "  (encontrada)"
    else
        warn "SSH key" "  → ssh-keygen -t ed25519 (para GitHub)"
    fi
fi

# ── Resumo ────────────────────────────────────────────────────────
echo -e "\n${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   Próximos passos sugeridos               ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo -e "${DIM}Execute este script e compartilhe o output"
echo -e "para receber instruções personalizadas de instalação.${RESET}\n"
