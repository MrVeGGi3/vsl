# VSL Godot — Cenas, Scripts e Shaders
## Contexto

Módulo de frontend do VSL. Contém cenas GDScript, shaders e assets.
Não é mais o processo host — é inicializado como LibGodot pelo processo
principal C++ em main/. O Godot 4.6.2 é usado como biblioteca.

---

## Mudança arquitetural — LibGodot vs GDExtension puro

```
ANTES (arquitetura anterior):
  Godot (processo host)
    └── GDExtension C++ carregava libjulia

AGORA (arquitetura VSL):
  vsl_main (C++ — processo principal)
    ├── libgodot.so   ← Godot como biblioteca
    └── libjulia.so   ← Julia como biblioteca
```

O código GDScript e as cenas continuam os mesmos — a diferença está
em como o Godot é inicializado (pelo main C++, não como executável).

---

## Stack

```
Godot 4.6.2 (LibGodot)
├── GDScript       — lógica de UI, cenas, orquestração
├── OpenXR         — VR via Quest Link (USB-C 3.2)
└── Shaders GLSL   — colormaps, streamlines, órbitas
```

---

## Patterns de Performance — VR CRÍTICO

Budget por frame: **~8ms total** a 90Hz (Quest Link).
Render deve usar no máximo 6ms — 2ms de margem para o OS.

### Zero alocação em _process() e _physics_process()
```gdscript
# PROIBIDO em _process()
var data = []          # cria Array — alocação
var s = "frame: " + str(n)  # concatenação aloca

# CORRETO — prealoca em _ready(), reutiliza
var _positions: PackedVector3Array  # preallocado em _ready()
var _point_count: int = 0

func _ready():
    _positions = PackedVector3Array()
    _positions.resize(MAX_ORBITAL_POINTS)

func _process(delta):
    # só atualiza valores existentes, sem resize
    _update_orbit_line(_positions, _point_count)
```

### Atualização da órbita via double buffer (recebe do C++)
```gdscript
# SolverBridge é um Node registrado pelo main C++
# Expõe o último estado do double buffer de forma thread-safe

func _process(_delta):
    var bridge = get_node("/root/SolverBridge")
    if bridge.has_new_data():
        # copia apenas os pontos válidos
        var count = bridge.get_point_count()
        bridge.copy_positions_to(_positions, count)
        _point_count = count
        _orbit_line.clear_points()
        for i in count:
            _orbit_line.add_point(_positions[i])
```

### Shader budget VR — colormaps sem branching
```glsl
// Fragment shader — máximo 100 instruções
// Usar mix() e step() em vez de if/else

vec3 colormap_viridis(float t) {
    t = clamp(t, 0.0, 1.0);
    // Aproximação polinomial — sem lookup texture, sem branching
    vec3 c0 = vec3(0.267, 0.005, 0.329);
    vec3 c1 = vec3(0.230, 0.322, 0.546);
    vec3 c2 = vec3(0.128, 0.566, 0.551);
    vec3 c3 = vec3(0.369, 0.789, 0.383);
    vec3 c4 = vec3(0.993, 0.906, 0.144);
    return c0 + t*(c1 + t*(c2 + t*(c3 + t*c4)));
}
```

---

## Fallback Desktop / VR — decisão arquitetural

**Regra:** uma única cena funciona nos dois modos. A lógica de cena
(órbita, Terra, UI) não sabe e não precisa saber se está em VR ou desktop.
Só `main_scene.gd` decide qual câmera fica ativa.

### Estrutura de cena que suporta ambos os modos

```
main.tscn
└── Node3D
    ├── Camera3D          ← desktop — current=true por padrão no editor
    ├── XROrigin3D        ← sempre presente; inerte sem OpenXR
    │   ├── XRCamera3D    ← ativa automaticamente quando use_xr=true
    │   ├── XRController3D (left)
    │   └── XRController3D (right)
    ├── orbit_viewer      ← instância de orbit_viewer.tscn — igual nos 2 modos
    ├── earth             ← instância de earth.tscn        — igual nos 2 modos
    └── ui/               ← painéis — reposicionados em _ready() se VR ativo
```

`XROrigin3D` é inerte quando `use_xr = false` — não há custo em mantê-lo na
cena. Adicionar/remover nós por modo seria duplicação; não fazer isso.

### Inicialização em main_scene.gd

```gdscript
var _vr_active := false

func _ready():
    _vr_active = _try_init_openxr()
    if not _vr_active:
        _setup_desktop_camera()

func _try_init_openxr() -> bool:
    var xr = XRServer.find_interface("OpenXR")
    if xr == null or not xr.initialize():
        return false
    get_viewport().use_xr = true
    get_viewport().scaling_3d_scale = 1.0  # Quest 3S: 2064x2208/olho, qualidade máxima
    $Camera3D.current = false              # XRCamera3D assume automaticamente
    return true

func _setup_desktop_camera():
    # Camera3D já está current=true pelo editor — apenas posiciona
    $Camera3D.position = Vector3(0.0, 2.0, 8.0)
    $Camera3D.look_at(Vector3.ZERO, Vector3.UP)
```

### Por que não duplicar cenas (uma para VR, outra para desktop)

Manter `orbit_viewer.tscn`, `earth.tscn` e `ui/` como arquivos separados
por modo causaria divergência inevitável — qualquer mudança precisaria ser
aplicada em dois lugares. A câmera é o único elemento que difere; o restante
da cena é idêntico e deve permanecer assim.

### Guard em vr_controller.gd

Scripts que dependem de input do Quest devem verificar `_vr_active` antes
de processar — sem isso um erro em `XRController3D` quebraria o modo desktop:

```gdscript
# vr_controller.gd
func _process(_delta):
    if not get_node("/root/MainScene")._vr_active:
        return
    # lógica de controllers Quest aqui
```

### UI em modo VR

Painéis 2D (`control_panel.tscn`, `data_panel.tscn`) devem ser filhos de
`SubViewport` ancorado ao mundo 3D quando em VR. Em modo desktop ficam no
`CanvasLayer` padrão. `main_scene.gd` faz a troca em `_ready()`:

```gdscript
func _ready():
    _vr_active = _try_init_openxr()
    if not _vr_active:
        _setup_desktop_camera()
    else:
        _attach_ui_to_world()  # move painéis para SubViewport 3D

func _attach_ui_to_world():
    # implementar na Fase 4 — placeholder até Quest Link estar ativo
    pass
```

---

## Estrutura de Diretórios

```
godot/
├── CLAUDE.md
└── project/
    ├── project.godot
    ├── scenes/
    │   ├── main.tscn              ← cena raiz
    │   ├── orbit_viewer.tscn      ← visualização 3D orbital
    │   ├── earth.tscn             ← Terra com atmosfera
    │   ├── vr_origin.tscn         ← XROrigin3D + XRCamera3D
    │   └── ui/
    │       ├── control_panel.tscn ← parâmetros de missão
    │       └── data_panel.tscn    ← gráficos e resultados
    ├── scripts/
    │   ├── main_scene.gd          ← orquestração + OpenXR
    │   ├── orbit_renderer.gd      ← atualiza linha orbital
    │   ├── earth_renderer.gd      ← textura + atmosfera
    │   └── vr_controller.gd       ← input Quest controllers
    └── shaders/
        ├── colormap.gdshader      ← colormaps científicos
        ├── orbit_line.gdshader    ← linha orbital com glow
        ├── earth_atmosphere.gdshader
        └── ground_track.gdshader  ← projeção no globo
```

---

## Regras de Qualidade

- Nenhuma alocação heap em _process() — verificar com Godot Profiler
- Todo shader deve ter fallback para modo desktop (sem VR)
- Testar sempre em modo desktop antes de testar com Quest
- GDScript para UI e orquestração — lógica pesada fica no solver Julia
- Manter cenas pequenas — composição de cenas em vez de cenas monolíticas
