# VSL — Design Decisions Report
## Pipeline A: Sounding Rocket Mission

**Branch:** `feature/mission-pipeline-a`  
**Data:** 2026-05-12  
**Autor:** Matheus Veras  
**Assistência:** Claude (Sonnet 4.6)

---

## 1. Contexto e Motivação

O VSL é um laboratório de simulação virtual aeroespacial com objetivo de substituir
ferramentas como STK/AGI e ANSYS para análise de missão e pré-validação de projetos.
O presente documento registra as decisões tomadas para o **Pipeline A** — o fluxo
completo de design de uma missão de foguete de sondagem, desde os requisitos SMAD
até a simulação 6-DOF.

### Problema que a versão anterior tinha

Os parâmetros do foguete e da missão estavam **hardcoded** em `main/src/main.cpp`
(constantes estáticas): TLE, curva de empuxo, tabela aerodinâmica, estação terrena.
Isso impedia qualquer experimentação pelo usuário sem recompilar o binário.

---

## 2. Fluxo SMAD Adotado (Pipeline A)

O pipeline segue a sequência do SMAD (Wertz & Larson, 2nd ed.) para sistemas
de foguete de sondagem:

```
1. Definição de Missão      → objetivo, altitude-alvo, tipo de payload
2. Carga Útil               → massa, volume, carga-G máxima, ambiente térmico
3. Design de Trajetória     → sítio de lançamento, azimute, elevação, atmosfera
4. Propulsão                → Isp, impulso total, curva de empuxo, massas
5. Aerodinâmica / Estrutura → diâmetro, nariz, CD/CN, CP, CG, inércia
6. Controle                 → margem de estabilidade estática (CP − CG > 1 calibre)
7. OBDH                     → massa, potência (versão mínima)
8. TT&C                     → frequência, potência TX, ganho de antena
9. Potência                 → bateria, consumo médio
10. Térmico                 → revestimento, faixa de temperatura
11. Budget                  → massa total, potência total, custo estimado
```

**Decisão:** Implementar os subsistemas 1–5 e 6 (margem de estabilidade calculada)
na primeira iteração. OBDH, TT&C, Potência e Térmico entram como campos no JSON
mas sem solver acoplado ainda.

### Critérios críticos SMAD identificados

| Critério | Por que crítico | Propaga para |
|---|---|---|
| Altitude-alvo H* | Requisito primário → determina ΔV | Motor (classe, impulso) |
| Massa da payload | Budget de massa | Massa seca, seleção de motor |
| Carga-G máxima | Limita empuxo máximo | Perfil de queima |
| Isp | Equação de Tsiolkovsky | Massa de propelente |
| Impulso total I_total | Energia cinética entregue | Apogeu alcançável |
| Margem de estabilidade | (CP−CG)/d ≥ 1 calibre | Geometria das aletas |
| Max-Q | ½ρv² → cargas estruturais | Fator de segurança |
| Sítio de lançamento | Latitude, altitude, atmosfera | Trajetória, range |

---

## 3. Arquitetura de Dados: JSON como Contrato UI ↔ Solver

### Decisão: `mission_params.json` como único ponto de entrada

**Alternativas consideradas:**

| Opção | Prós | Contras | Decisão |
|---|---|---|---|
| Parâmetros hardcoded em C++ | Zero dependência, rápido | Requere recompilação; não testável | ❌ Abandonado |
| Protocolo RPC (sockets) | Real-time, bidirecional | Complexidade, latência, sincronização | ❌ Futuro (Phase 5+) |
| JSON em disco lido no startup | Simples, editável, testável, versionável | One-shot (sem live update) | ✅ Adotado agora |
| Variáveis de ambiente | Trivial de passar | Não suporta arrays (curvas de empuxo) | ❌ Insuficiente |

**Fluxo de dados:**
```
Godot UI (GDScript)
  └── escreve godot/project/mission_params.json

C++ main (startup)
  └── load_mission_params() → VslMissionParams
  └── make_thrust_curve() → VslThrustCurveData
  └── make_aero_table()   → VslAeroTableData

Julia solver (vsl_trajectory_sixdof_points)
  └── escreve godot/project/solver_results.json

Godot UI (SolverBridge.gd)
  └── lê solver_results.json → atualiza painéis
```

**Por que JSON e não TOML/INI/binary?**
- GDScript tem suporte nativo a JSON (`JSON.parse_string()`)
- Editável por humano sem ferramenta — facilita debugging e testes manuais
- Versionável no git — permite rastrear experimentos
- Extensível: adicionar campos sem quebrar leitores existentes (campos opcionais com defaults)

### Schema do arquivo

Arquivo: `godot/project/mission_params.json`

```
mission_params.json
├── orbital         → TLE, duração, step de propagação
├── launch_site     → lat, lon, alt, azimute, elevação
├── ground_station  → lat, lon, elevação mínima
├── atmosphere      → modelo (nrlmsise00 | isa), F10.7, Ap
├── payload         → massa, dimensões, G_max, temperatura
├── propulsion      → Isp, massas, thrust_curve{times, thrusts, mass_flows}
├── rocket          → geometria, nariz, CP, CG, inércia, aero_table{mach, aoa, CD, CN}
└── simulation      → t_end, condições iniciais (posição, velocidade, quaternion, ω)
```

---

## 4. Acoplamento MDO (Grafo de Dependências Reativo)

### Decisão: propagação forward reativa no frontend

O MDO Engine (previsto na arquitetura com ModelingToolkit.jl) será implementado
em etapas. Na fase atual (Pipeline A v1), a propagação é feita no frontend Godot:

```
H* alterado
  → sugere I_total_min = f(H*, m_total, g, atm) via modelo 1-DOF simplificado
  → sugere classe de motor (NAR A–O) baseado em I_total_min

m_payload alterado
  → atualiza m_wet = m_dry + m_propelente + m_payload
  → recalcula razão de massa
  → verifica constraint: F_max ≤ G_max · m_wet · g₀

Propulsion(Isp, I_total) alterado
  → m_propelente = I_total / (Isp · 9.81) kg
  → m_wet atualizado
  → CG estimado recalculado (distribuição de massa)
  → margem de estabilidade = (xcp − xcg) / d

Geometria das aletas alterada (futuro: Barrowman)
  → CN_α recalculado
  → xcp recalculado via método de Barrowman simplificado
```

**Decisão de adiamento:** O grafo completo com ModelingToolkit.jl (Julia) fica para
depois que o pipeline de parâmetros estiver funcional e validado. O frontend faz
a propagação com fórmulas simples enquanto isso.

---

## 5. Dois Painéis de Input: Mission Design vs. Rocket Design

### Rationale da separação

O SMAD distingue explicitamente entre **análise de missão** (o que se quer
alcançar) e **design do sistema** (como alcançar). Misturar os dois em um único
painel cria confusão de responsabilidade:

- **Mission Design** = especificações externas ao veículo (o cliente/cientista define)
- **Rocket Design** = parâmetros internos ao veículo (o engenheiro define)

Essa separação também facilita cenários de MDO: fixar requisitos de missão e
otimizar o design do foguete automaticamente.

### Inputs do Mission Design Panel

| Campo | Tipo | Unidade | Faixa |
|---|---|---|---|
| Altitude-alvo (apogeu) | float | km | 10–300 |
| Tipo de missão | enum | — | atm. / microgravidez / demo |
| Duração de coleta no apogeu | float | s | 0–300 |
| Massa da payload | float | kg | 0.1–50 |
| Diâmetro da payload | float | m | 0.04–0.30 |
| Comprimento da payload | float | m | 0.05–1.0 |
| Carga-G máxima | float | g | 5–200 |
| Faixa de temperatura | float×2 | °C | -40/+85 |
| Sítio de lançamento | preset+custom | lat/lon | — |
| Azimute de lançamento | float | deg | 0–360 |
| Ângulo de elevação | float | deg | 60–90 |
| Modelo atmosférico | toggle | — | NRLMSISE-00 / ISA |
| F10.7 / Ap | float | SFU / nT | 70–300 / 0–400 |

### Inputs do Rocket Design Panel

**Propulsão:**

| Campo | Tipo | Unidade | Observação |
|---|---|---|---|
| Modo de entrada | enum | — | manual / RASP .eng / preset |
| Impulso total I_total | float | N·s | design driver |
| Empuxo máximo F_max | float | N | constraint: ≤ G_max·m_wet·g |
| Tempo de queima | float | s | F_avg = I_total/t_b |
| Isp (vácuo) | float | s | para Tsiolkovsky |
| Massa seca (estrutura) | float | kg | excl. payload |
| Massa úmida | float | kg | calculada automaticamente |
| Curva de empuxo | tabela | (s, N, kg/s) | editável ponto a ponto |

**Aerodinâmica:**

| Campo | Tipo | Unidade | Observação |
|---|---|---|---|
| Diâmetro do corpo | float | m | → S_ref = π(d/2)² |
| Comprimento total | float | m | — |
| Formato do nariz | enum | — | ogiva / Von Kármán / cônico |
| CD subsônico | float | — | M < 0.8 |
| CD transsônico | float | — | 0.8–1.2 |
| CD supersônico | float | — | M > 1.2 |
| CN_α | float | 1/rad | linear ou tabela |
| Posição CP (da ponta) | float | m | — |

**Estrutura / Inércia:**

| Campo | Tipo | Unidade | Observação |
|---|---|---|---|
| Posição CG (da ponta) | float | m | CG < CP para estabilidade |
| Inércia lateral I_xx | float | kg·m² | = I_yy (simetria) |
| Inércia axial I_zz | float | kg·m² | rolagem |

---

## 6. Integração CAD / Modelo 3D para Impressão

### Decisão: OpenSCAD como gerador paramétrico

**Motivação:** O usuário precisa poder validar fisicamente o design com um
protótipo impresso em 3D (PLA/PETG) antes de fabricar o foguete real.

**Abordagem:**
```
Rocket Design params → template .scad populado → openscad --export stl
  → rocket_body.stl + fins.stl + motor_mount.stl
  → preview no Godot (MeshInstance3D via ArrayMesh)
  → botão "Exportar para impressão"
```

**Por que OpenSCAD e não FreeCAD/Blender?**
- CLI headless nativa (`openscad --export out.stl model.scad`)
- Parâmetros via `-D var=val` ou arquivo `.json` companion
- Sintaxe simples: cilindros, revoluções de perfil (nariz Von Kármán), extrusões
- Sem dependência de UI para geração programática

**Parâmetros geométricos adicionais para CAD:**

| Campo | Unidade | Observação |
|---|---|---|
| Comprimento do nariz | m | L_nose/d ≈ 3–5 |
| Número de aletas | int | 3 ou 4 |
| Raiz da aleta (c_root) | m | — |
| Ponta da aleta (c_tip) | m | — |
| Altura da aleta (span) | m | — |
| Espessura da aleta | m | ≥ 2 mm para impressão |
| Diâmetro do tubo do motor | m | padrões NAR: 24/29/38/54 mm |
| Material (densidade) | kg/m³ | PLA 1240 / PETG 1270 / ABS 1050 |

**Retroalimentação para a simulação:**
- Volume calculado do corpo → estima CG automaticamente
- Área das aletas → contribui para CN_α via Barrowman simplificado
- Massa estimada = Volume × densidade do material

---

## 7. Biblioteca JSON em C++: nlohmann/json

### Decisão: FetchContent com fallback para sistema

**Avaliação de opções:**

| Biblioteca | Tamanho | Facilidade | Licença | Decisão |
|---|---|---|---|---|
| nlohmann/json | ~17k LOC (header) | Excelente API | MIT | ✅ Adotado |
| RapidJSON | ~7k LOC | API verbose | MIT | ❌ API inferior |
| cJSON | 800 LOC, C | Mínimo | MIT | ❌ Sem suporte a C++ nativo |
| Manual (sscanf) | 0 deps | Frágil | — | ❌ Não escala com schema complexo |

**Integração no CMake:**
```cmake
find_package(nlohmann_json 3.11 QUIET)   # usa sistema se disponível
if(NOT nlohmann_json_FOUND)
    FetchContent_Declare(...)             # baixa do GitHub na primeira build
    FetchContent_MakeAvailable(...)
endif()
```

O pacote `nlohmann-json3-dev` (v3.11.3) está disponível via apt para instalação
manual se preferir evitar FetchContent:
```bash
sudo apt install nlohmann-json3-dev
```

---

## 8. Parâmetros do Arquivo e Defaults

Todos os campos são **opcionais** no JSON. O loader aplica defaults seguros se
um campo está ausente, permitindo que o arquivo JSON seja editado incrementalmente
sem quebrar a aplicação.

**Defaults refletem o demo atual** (N-class motor, 80 mm, Alcântara, ISS TLE)
para garantir que o comportamento não mude ao fazer upgrade sem fornecer novo JSON.

---

## 9. Extensibilidade Futura

| Funcionalidade | Como integrar |
|---|---|
| Painel Godot editável em runtime | GDScript escreve novo JSON → sinal `solver_params_changed` → C++ relê e recalcula |
| Live update sem restart | IPC socket entre Godot e C++ (Phase 5) |
| MDO completo | Julia solver expõe `vsl_mdo_optimize()` via C API |
| Base de dados de motores | JSON array de motores conhecidos (RASP format) lido no startup |
| Barrowman automático | Julia function `vsl_barrowman(geometry) → (xcp, cn_alpha)` |
| CAD paramétrico | Godot chama `openscad --export` via `OS.execute()` ou C++ subprocess |
| FEM/CFD (futuro) | Plugin separado com interface JSON idêntica |

---

## 10. Arquivos Criados / Modificados

| Arquivo | Tipo | Descrição |
|---|---|---|
| `main/src/mission_params.h` | novo | Structs C++ para todos os inputs |
| `main/src/mission_params_loader.h` | novo | Interface do loader JSON |
| `main/src/mission_params_loader.cpp` | novo | Implementação com nlohmann/json |
| `main/src/main.cpp` | modificado | Usa loader; sem hardcodes |
| `main/CMakeLists.txt` | modificado | FetchContent nlohmann_json |
| `godot/project/mission_params.json` | novo | Parâmetros default (schema v1.0) |
| `docs/design_decisions.md` | novo | Este documento |
