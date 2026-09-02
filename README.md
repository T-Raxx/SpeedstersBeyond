# SpeedstersBeyond

Autofarm suite autónomo para **⚡ Velocistas más allá 👟** (Speedsters Beyond) — PlaceId `98352297590435`.
UI **Obsidian**. Farm ascend-aware: Jobs + Treadmill + Auto-Ascend + Economy + Extras.

> Cuenta de pruebas: burner. Suite específico a este PlaceId.

## Estado

Scaffold + spec. Implementación por-fases vía plan (ver `docs/plans/`). No hay features aún.

## Carga (cuando exista el bundle)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/T-Raxx/SpeedstersBeyond/main/SpeedstersBeyond.lua"))()
```

El bundle carga la lib **Obsidian** en runtime (no inline). Build local con `build_bundle.ps1`.

## Arquitectura

Enfoque híbrido (ver spec): lectura piggyback de los controllers del juego + snapshots RF; escritura por remotes directos para acciones deterministas; movimiento y anti-idle propios; todo write pasa por RateGovernor. Modelo AC verificado: server **solo rubberbandea** + heurística de idle (`SUSPICIOUS_IDLE`). Sin AC de exploits en cliente.

## Patrón de desarrollo — feature por carpeta y archivo

Idéntico a `LifeInPrisonPrimordial`. Ver `docs/pattern.md`. Resumen:

- Cada feature = **un archivo** bajo su **carpeta de categoría** (`Jobs/`, `Treadmill/`, `Economy/Orbs.lua`, …).
- Cada archivo es un **factory**: `return function(require, SB, Lib) local M = {}; ... function M.init() end; return M end`.
- Capas raíz: `Core/State.lua` (crea `getgenv().SB`), `Net.lua`, `UI.lua`, `main.lua` (driver).
- `build_bundle.ps1` concatena todo a `SpeedstersBeyond.lua` (require lazy shim; `Core.State` primero, `main` último).
- Specs en `docs/specs/`, planes en `docs/plans/` (fechados).

## Layout

```
Core/         State.lua (global SB, tracking conns/cleanup, RemoteHandler wrapper, opcodes/remote refs)
Net.lua       capa de red (wrappers Fire/Invoke sobre RemoteHandler del juego, listeners *Changed)
UI.lua        construcción de tabs/grupos Obsidian, flags en Lib.Toggles/Options
main.lua      driver: require features, crear Window Obsidian, init cada módulo, orchestrator loop
Movement/     MovementEngine (travel híbrido velocity-budget + pulso)
AntiIdle/     AntiIdleService (VirtualInputManager, derrota SUSPICIOUS_IDLE)
Jobs/         JobsFarm (deliveries por tier, arrival piggyback, chain, claim)
Treadmill/    TreadmillFarm (mejor pad elegible, park, anti-idle)
Ascension/    AscensionMgr (auto-ascend en level cap, re-scan unlocks)
Economy/      Upgrades / Morphs / Orbs / Quests
Extras/       MultiRace / Rewards / ServerEvent
Safety/       RateGovernor / Panic / jitter
docs/specs/   diseño
docs/plans/   planes de implementación
```
