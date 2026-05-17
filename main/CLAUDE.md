# VSL Main — Processo Principal C++
## Contexto

Processo principal do VSL. Inicializa LibGodot e libjulia como bibliotecas
e controla o loop principal — sincronizando rendering com o solver.
Esta é a cola entre o frontend Godot e o núcleo Julia.

---

## Stack

```
C++17 mínimo
CMake 3.28 + Ninja
clangd 18 (LSP)
LibGodot 4.6.2    — godot compilado como .so
libjulia          — Julia compilada com PackageCompiler
```

---

## Arquitetura do Loop Principal

```cpp
int main() {
    // 1. Inicializa Julia
    julia_init();
    vsl_solver_init();          // carrega PackageCompiler sysimage

    // 2. Inicializa LibGodot
    GDExtensionInterfaceGetProcAddress get_proc = godot_init();
    godot_main_loop_start();

    // 3. Loop principal — controle explícito
    while (running) {
        // Solver roda em thread separada (double buffer)
        // Godot consome último estado disponível
        godot_main_loop_iterate();
    }

    // 4. Cleanup ordenado
    godot_main_loop_end();
    julia_atexit_hook(0);
}
```

---

## Patterns de Performance — C++17

### Zero alocação no hot path
```cpp
// PROIBIDO no loop principal
auto* buf = new float[N];          // heap alloc
std::vector<float> v(N);           // heap alloc

// CORRETO — prealoca na inicialização, reutiliza
struct alignas(64) SolverBuffer {  // alinhado à cache line
    std::array<float, MAX_POINTS * 3> positions;
    std::array<float, MAX_POINTS>     timestamps;
    int32_t  point_count{0};
    uint64_t frame_id{0};
};
```

### Double buffer lock-free (solver → render)
```cpp
class DoubleBuffer {
    SolverBuffer buffers_[2];
    std::atomic<int> front_{0};
public:
    SolverBuffer& back()  { return buffers_[1 - front_.load(std::memory_order_acquire)]; }
    SolverBuffer& front() { return buffers_[front_.load(std::memory_order_acquire)]; }
    void swap()           { front_.fetch_xor(1, std::memory_order_acq_rel); }
};

// Solver thread — nunca bloqueia o render
void solver_thread(DoubleBuffer& db, std::atomic<bool>& running) {
    while (running.load()) {
        auto& buf = db.back();
        vsl_propagate_orbit(buf.positions.data(), &buf.point_count);
        buf.frame_id++;
        db.swap();                  // atômico — render vê novo estado no próximo frame
        std::this_thread::sleep_for(std::chrono::milliseconds(16));
    }
}
```

### RAII para recursos Julia e Godot
```cpp
struct JuliaRuntime {
    JuliaRuntime()  { jl_init(); }
    ~JuliaRuntime() { jl_atexit_hook(0); }
    // non-copyable, non-movable
    JuliaRuntime(const JuliaRuntime&) = delete;
    JuliaRuntime& operator=(const JuliaRuntime&) = delete;
};
// Usar como variável local em main() — destrutor garante cleanup
```

### Structs cache-friendly (SoA para dados de pontos)
```cpp
// Para N > 1000 pontos orbitais — SoA é melhor para cache
struct OrbitalTrack {
    std::vector<float> x, y, z;         // lê só posições sem desperdiçar cache
    std::vector<float> timestamps;
    std::vector<float> altitudes;       // separado — só lido quando necessário
};
```

---

## Interface com libjulia

```cpp
// Funções exportadas pelo solver Julia (@ccallable)
// Declaradas em julia_api.h

extern "C" {
    // Retorna 0 = sucesso, negativo = erro
    int vsl_propagate_orbit(
        const char* tle_line1,
        const char* tle_line2,
        double      duration_s,
        float*      out_positions,   // Float32[] x,y,z interleaved (km)
        int*        out_count
    );

    int vsl_compute_access(
        const char* tle_line1,
        const char* tle_line2,
        double      gs_lat_deg,
        double      gs_lon_deg,
        double      gs_min_elevation_deg,
        double      duration_s,
        double*     out_start_times,  // segundos desde epoch
        double*     out_end_times,
        int*        out_count
    );

    int vsl_solver_init(const char* sysimage_path);
    void vsl_solver_shutdown();
}
```

---

## Estrutura de Diretórios

```
main/
├── CLAUDE.md
├── CMakeLists.txt
├── src/
│   ├── main.cpp                    ← entry point, inicializa tudo
│   ├── double_buffer.h             ← double buffer lock-free (solver → render)
│   ├── file_watcher.h              ← hot-reload: inotify watcher não-bloqueante
│   ├── julia_api.h                 ← declarações C das funções Julia
│   ├── godot_bridge.h              ← inicialização LibGodot
│   ├── mission_params.h            ← structs de parâmetros da missão
│   └── mission_params_loader.h/cpp ← parser JSON → VslMissionParams
└── build/                          ← gerado pelo CMake (não commitar)
```

---

## Hot-reload — mission_params.json

O loop principal monitora `mission_params.json` via inotify (Linux).
Qualquer gravação no arquivo — direta ou via rename atômico do editor (vim, VSCode) —
dispara uma recarga completa sem reiniciar o processo.

```cpp
// FileWatcher observa o diretório pai — captura IN_CLOSE_WRITE e IN_MOVED_TO
FileWatcher watcher(params_file);   // inotify_init1(IN_NONBLOCK | IN_CLOEXEC)

// No loop principal — zero overhead quando não há eventos
if (watcher.poll()) {
    // debounce 300 ms — burst writes do editor disparam só uma vez
    if (now - last_reload > 300ms) {
        VslMissionParams mp_new = mp;           // copia defaults atuais
        if (load_mission_params(path, mp_new)) {// falha silenciosa: preserva mp
            mp = mp_new;
            solver_update_orbit(mp);
            solver_update_trajectory(mp);
            write_solver_json(...);             // atualiza solver_results.json
        }
    }
}
```

**Comportamento:**
- `poll()` é O(1) e non-blocking — não atrasa o render quando não há mudanças
- JSON inválido é silencioso: `mp` mantém os valores anteriores
- Render bloqueia ~1-2 s durante o re-solve (aceitável em desenvolvimento)
- Se inotify falhar (ex: sem permissão), log no stderr e continua sem hot-reload

---

## Build

```bash
# Debug (desenvolvimento)
cmake -B build -DCMAKE_BUILD_TYPE=Debug -GNinja
cmake --build build -j$(nproc)

# Release (distribuição)
cmake -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -GNinja
cmake --build build -j$(nproc)
```

---

## Regras de Qualidade

- Nenhuma exceção C++ que cruze a fronteira com Julia ou Godot — capturar internamente
- Valgrind/ASan no Debug build para detectar leaks antes de qualquer release
- Thread sanitizer ativado em CI para detectar race conditions no double buffer
- Todo acesso a libjulia deve acontecer na thread que chamou jl_init()
