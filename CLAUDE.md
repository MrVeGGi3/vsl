# VSL — Virtual Simulation Lab
## Contexto do Produto

Laboratório de simulação virtual aeroespacial para dimensionar, testar e pré-validar
projetos antes de manufaturar. Substituto acessível de ferramentas como STK/AGI,
ANSYS e RPA — voltado inicialmente para análise de missão orbital.

**Veículos alvo:** foguete de sondagem · CubeSat / SmallSat · Spacecraft / Satélite
**Referência metodológica:** SMAD (Space Mission Analysis and Design)
**Público:** uso pessoal agora → produto comercial no futuro

---

## Ambiente de Desenvolvimento

| Item | Versão | Status |
|------|--------|--------|
| OS | Pop!_OS 24.04 LTS | ✓ |
| CPU | x86_64 · 28 cores | ✓ |
| GPU | RTX 4060 Laptop · 8GB VRAM | ✓ |
| CUDA (host) | 12.0 (nvcc) / 13.0 (driver) | ✓ |
| Julia | 1.12.5 via Juliaup | ✓ |
| Godot | 4.6.2 stable | ✓ |
| Docker | 29.4.2 + NVIDIA Container Toolkit | ✓ |
| VS Codium | latest stable | ✓ |
| Claude Code | 2.1.128 | ✓ |
| Shell | bash + Starship 1.25.1 | ✓ |

---

## Stack Técnica

| Camada | Tecnologia | Papel |
|--------|-----------|-------|
| Processo principal | C++17 | Orquestra LibGodot + libjulia |
| Solver | Julia 1.12+ via libjulia | Núcleo numérico — propagação orbital, MDO |
| Frontend | LibGodot 4.6.2 | Rendering 3D, UI, VR — como biblioteca |
| VR | Quest 3S via Quest Link (USB-C 3.2) | Visualização imersiva |
| Paper | LaTeX + Overleaf (sync Git) | Publicação acadêmica paralela |
| CI | Docker + GitHub Actions | Build reprodutível |

---

## Arquitetura — Decisões Tomadas

### 1. LibGodot como biblioteca (não Godot como host)
Godot 4.6+ pode ser compilado como biblioteca standalone.
O VSL tem seu próprio processo principal em C++ que inicializa
tanto libgodot (rendering/UI/VR) quanto libjulia (solver) como
bibliotecas iguais — nenhuma é hóspede da outra.

```
vsl_main  (C++17 — processo principal)
├── libgodot.so   → rendering 3D, UI, OpenXR
└── libjulia.so   → solver orbital, MDO, CFD
```

Vantagens sobre GDExtension puro:
- Controle total do loop principal — sincroniza render com timestep do solver
- Ciclo de vida explícito de ambas as bibliotecas
- Solver testável de forma completamente isolada
- Sem dependência do sistema de plugins do Godot para o solver

### 2. Double buffer lock-free para VR
Render thread (LibGodot, 90Hz) nunca bloqueia esperando o solver.
Solver Julia escreve buffer B enquanto LibGodot lê buffer A.
Swap via std::atomic — zero contention.

### 3. Quest Link (cabo USB-C 3.2) — não Air Link
Latência ~3–5ms, sem compressão H.265, carrega bateria durante uso.
LibGodot inicializa OpenXR diretamente. Zero código Android necessário.

### 4. MDO Engine no núcleo
Propagação reativa de parâmetros entre disciplinas via grafo de dependências.
Implementado com ModelingToolkit.jl. Cada plugin registra suas variáveis.
Metodologia SMAD — a cada mudança de parâmetro, disciplinas dependentes
recalculam automaticamente.

### 5. CUDA 13.0 disponível
Driver suporta CUDA 13.0, nvcc instalado como 12.0.
Usar CUDA.jl em vez de nvcc direto — detecta versão do driver automaticamente.

### 6. Monorepo com CLAUDE.md por módulo
Abrir Claude Code a partir do subdiretório correto para contexto específico.

---

## Estrutura do Repositório

```
vsl/
├── CLAUDE.md                  ← este arquivo (contexto global)
├── SETUP.md                   ← guia de instalação do ambiente
├── check_env.sh               ← verificação de pré-requisitos do host
├── docker-compose.yml
├── .github/workflows/
├── main/                      ← processo principal C++ (LibGodot + libjulia)
│   ├── CLAUDE.md
│   ├── src/main.cpp
│   └── CMakeLists.txt
├── solver/                    ← Julia (núcleo numérico)
│   ├── CLAUDE.md
│   ├── src/
│   ├── test/
│   └── notebooks/
├── godot/                     ← cenas GDScript, shaders, assets
│   ├── CLAUDE.md
│   └── project/
└── paper/                     ← LaTeX + Overleaf
    ├── CLAUDE.md
    ├── main.tex
    ├── sections/
    └── figures/
```

---

## Glossário Aeroespacial

- **TLE** — Two-Line Element: formato padrão de elementos orbitais
- **SGP4** — propagador orbital padrão para LEO
- **ΔV** — variação de velocidade para manobras orbitais
- **Isp** — Impulso específico: eficiência do propulsor (segundos)
- **RAAN** — Right Ascension of Ascending Node: elemento orbital
- **SSO** — Sun-Synchronous Orbit: órbita heliosíncrona (~98° inclinação)
- **LEO** — Low Earth Orbit: 200–2000 km altitude
- **MDO** — Multidisciplinary Design Optimization
- **SMAD** — Space Mission Analysis and Design (Wertz & Larson)
- **LibGodot** — Godot 4.6+ compilado como biblioteca standalone
- **SUS** — System Usability Scale: métrica para estudos de usabilidade

---

## Roadmap de Desenvolvimento

| Fase | Semanas | Entrega | Paper |
|------|---------|---------|-------|
| 1 ✓ | 1–4 | Julia standalone: propagação orbital + plots | Dados validação Paper 1 |
| 2 ✓ | 5–10 | Processo principal C++ + LibGodot + Terra 3D | Arquitetura Paper 1 |
| 3 ✓ | 11–16 | Análise completa: acesso, eclipse, ΔV, relatório | Case study Paper 1 |
| 4 ✓ | 17+ | VR ativo: Quest Link + exploração imersiva | Core Paper 2 (AIAA) |

**Paper 1 submetido ao JOSS em 06/05/2026 — em revisão**
https://joss.theoj.org/papers/0025df1b9f4689d776253ffd37b7cb88

---

## Regras Globais para o Claude Code

- Sempre perguntar antes de criar arquivos ou fazer edições destrutivas
- Decisões de arquitetura registradas neste arquivo
- Todo código novo deve ter teste correspondente
- Benchmarks obrigatórios antes de merge em módulos de performance crítica
- Comentários em inglês no código, comunicação em português
- Nunca instalar dependências sem verificar se já estão presentes
