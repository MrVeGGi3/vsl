# VSL Paper — LaTeX + Overleaf
## Contexto

Documentação acadêmica paralela ao desenvolvimento.
Cada fase técnica do VSL alimenta diretamente uma seção de paper.
Workflow: VSCode local (LaTeX Workshop) → Git → Overleaf (sync automático).

---

## Papers Planejados

| # | Título provisório | Alvo | Fase |
|---|------------------|------|------|
| 1 | "VSL: An Open-Source Mission Analysis Environment with Immersive Visualization" | JOSS | Fase 1–3 |
| 2 | "Immersive VR for Spacecraft Mission Analysis: Usability and Effectiveness" | AIAA SPACE / IAC | Fase 4+ |
| 3 | "Reactive MDO for Early-Stage Spacecraft Conceptual Design" | J. Spacecraft & Rockets | Fase MDO |
| 4 | "Julia-based Astrodynamics Toolchain for Accessible Mission Design" | Advances in Space Research | Paralelo |

---

## O que cada fase técnica alimenta

| Fase | Entrega técnica | Seção do paper |
|------|----------------|----------------|
| 1 | Propagação orbital validada | Paper 1 — Seção 4 (Validation) |
| 2 | Arquitetura LibGodot + libjulia | Paper 1 — Seção 2 (Architecture) |
| 3 | Case study CubeSat completo | Paper 1 — Seção 5 (Case Study) |
| 4 | User study VR vs desktop | Paper 2 — Core |

---

## Stack LaTeX

```
TeX Live (instalado localmente)
├── biblatex + biber     — referências
├── siunitx              — unidades SI
├── booktabs             — tabelas
├── pgfplots             — gráficos (ou importar de Makie.jl)
├── tikz                 — diagramas de arquitetura
├── hyperref             — links
├── cleveref             — referências cruzadas
└── minted               — código com syntax highlight
```

---

## Workflow Overleaf ↔ VSCode

```
1. Editar .tex no VSCode (LaTeX Workshop — preview ao vivo)
2. git commit + push
3. Overleaf sincroniza automaticamente (~30 segundos)
```

### Configuração inicial (uma vez)
```
Overleaf → New Project → Import from GitHub
→ Conectar repositório vsl
→ Root: /paper
```

### Gerar figuras automaticamente pelo solver
```julia
# Ao final de cada notebook Pluto de validação:
using CairoMakie  # backend não-interativo
save("../paper/figures/orbit_ground_track.pdf", fig, pt_per_unit=1)
# Figura vai direto para o paper sem copiar manualmente
```

---

## Estrutura

```
paper/
├── CLAUDE.md
├── main.tex
├── paper.bib
├── sections/
│   ├── 01_summary.tex
│   ├── 02_statement_of_need.tex
│   ├── 03_architecture.tex       ← LibGodot + libjulia (Fase 2)
│   ├── 04_validation.tex         ← SGP4 vs STK/GMAT (Fase 1)
│   ├── 05_case_study.tex         ← CubeSat LEO (Fase 3)
│   └── 06_conclusion.tex
└── figures/                      ← geradas pelo solver
    ├── architecture_diagram.pdf  ← TikZ (vsl_main + libgodot + libjulia)
    ├── orbit_ground_track.pdf
    ├── access_windows.pdf
    └── validation_error.pdf
```

---

## Convenções de Escrita

### Unidades — sempre com siunitx
```latex
\SI{400}{\kilo\meter}                  % altitude
\SI{7.8}{\kilo\meter\per\second}       % velocidade orbital
\SI{98.6}{\degree}                     % inclinação SSO
```

### Arquitetura LibGodot no paper
Descrever como diferencial técnico — processo principal C++ orquestrando
duas bibliotecas (libgodot + libjulia) em igualdade, com double buffer
lock-free para sincronização entre rendering 90Hz e solver numérico.

---

## Status Paper 1

**Submetido ao JOSS em 06 de maio de 2026**
Link: https://joss.theoj.org/papers/0025df1b9f4689d776253ffd37b7cb88
Status: em revisão

## Checklist JOSS (Paper 1)

- [x] Repositório público no GitHub com licença MIT
- [x] Arquivo paper.md no root (formato JOSS específico)
- [x] DOI via Zenodo (release versionado — configurar integração GitHub)
- [x] CI passing (GitHub Actions)
- [x] README com instruções de instalação
- [x] Statement of need claro
- [x] Referências a software relacionado (STK, GMAT, Orekit, Poliastro)

---

## Decision Log

### LibGodot em vez de GDExtension puro
**Data:** início do projeto
**Decisão:** processo principal C++ inicializa libgodot + libjulia como bibliotecas iguais
**Alternativa considerada:** Godot como host com GDExtension carregando libjulia
**Justificativa:** controle total do loop principal, sincronização explícita entre
rendering (90Hz VR) e timestep do solver, ciclo de vida mais previsível,
solver testável de forma isolada sem inicializar o Godot

### Quest Link (cabo) em vez de Air Link
**Decisão:** USB-C 3.2, Quest Link protocol
**Justificativa:** latência ~3–5ms vs ~15–25ms, sem compressão H.265 que degrada
colormaps e gradientes de pressão em visualização científica, carrega bateria

### Julia 1.12.5 em vez de Python/MATLAB
**Decisão:** Julia via Juliaup, PackageCompiler para distribuição
**Justificativa:** Float64 nativo, performance próxima de C++ sem JIT visível
após compilação, SatelliteToolbox.jl do INPE já implementa SGP4/J2,
ModelingToolkit.jl para MDO, CUDA.jl para GPU
