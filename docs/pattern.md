# Patrón de desarrollo — feature por carpeta y archivo

Portado de `LifeInPrisonPrimordial`. Regla: **una feature = un archivo bajo su carpeta de categoría**, escrito como *factory*. El bundler los ensambla; el `require` es lazy.

## Contrato de módulo (factory)

Todo archivo `.lua` de módulo devuelve una función factory:

```lua
-- Categoria/Feature.lua — FACTORY. <una línea de qué hace + gotcha si aplica>
return function(require, SB, Lib)
    local Feature = {}

    -- deps por require lazy (resueltas al primer uso, cacheadas)
    local Net  = require("Net")
    local Move = require("Movement.Movement")

    -- estado local del módulo aquí

    function Feature.init()
        -- registrar loops/conns vía SB.track(...), instancias vía SB.onCleanup(...)
    end

    return Feature
end
```

- **`require(name)`**: resuelve `"Categoria.Feature"` (punto, no slash), corre el factory una vez, cachea. Lazy → el orden en el bundle no importa mientras el módulo exista.
- **`SB`**: estado global único (`getgenv().SB`), creado por `Core/State.lua`. Tracking de conexiones (`SB.track`), cleanups (`SB.onCleanup`), refs de remotes, flags de runtime, kill-switch (`SB.Stop`/`SB.IsStopped`).
- **`Lib`**: la librería Obsidian (Window/Toggles/Options). Flags viven en `Lib.Toggles[name]` / `Lib.Options[name]`.

## Capas raíz

| Archivo | Rol |
|---------|-----|
| `Core/State.lua` | **Crea** `getgenv().SB`. Ignora su param `SB` (es quien lo crea). Guard de doble-carga (neutraliza build viejo). Tracking conns/cleanup, StateStore, wrapper sobre `RemoteHandler`/`RemoteNames` del juego. |
| `Net.lua` | Capa de red: wrappers `Fire(remote, ...)` / `Invoke(remote, ...)` que pasan por el RateGovernor (Safety); listeners de `*Changed` que refrescan el StateStore. |
| `UI.lua` | `UI.build(Window)`: arma tabs/grupos Obsidian, define flags. Sin lógica de farm (solo wiring UI→toggles). |
| `main.lua` | Driver factory. `require` de todas las features, crea el Window Obsidian, `UI.build`, `init()` de cada módulo, arranca el orchestrator loop y el kill-switch/panic. |

## Bundler

`build_bundle.ps1`:
1. `ORDER = Core/State.lua, Net.lua, <cada carpeta de categoría *.lua ordenado>, UI.lua, main.lua`.
2. Cada archivo → `_MODS["Categoria.Feature"] = (function() <src> end)()` (devuelve el factory).
3. Emite el require lazy shim, crea `SB = _MODS["Core.State"](require, nil, Lib)`, luego `_MODS["main"](require, SB, Lib)`.
4. Salida: `SpeedstersBeyond.lua` (LF, UTF-8 sin BOM) en root, para loadstring-raw.

**Obsidian** se carga en runtime dentro de `main.lua` (loadstring de su raw), no se inlinea. Bump: si Obsidian cambia API, ajustar solo el adapter/UI.

## Convenciones

- Comentario de cabecera en cada archivo: qué hace + gotcha/decisión no obvia (denso, como LiP).
- PRNG propio si el executor bloquea `math.random`/`Math.random`.
- Nada de `os.time`/`tick` para lógica determinista si rompe resume; timestamps por `os.clock`.
- Un solo hook por metamétodo (si se necesita hook): shell delgado persistente + lógica redefinible (patrón reload-safe de LiP).
- Todo write de remote pasa por `Net` → `Safety.Governor`. Nunca `FireServer` crudo salteando el governor.
