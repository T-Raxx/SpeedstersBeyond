# Speedsters Beyond — Autofarm Suite (Design Spec)

**Fecha:** 2026-09-02
**Juego:** ⚡ Velocistas más allá 👟 (Speedsters Beyond)
**PlaceId:** 98352297590435 · **UniverseId:** 10560640933 · **Creator:** Professional Slop (Group 1057559965) · **PlaceVersion base:** 842
**Cuenta de pruebas:** `663_00` — **BURNER** → defaults agresivos permitidos.
**Ejecución:** script Lua vía executor (roblox-executor-mcp), UI **Obsidian** (fork moderno de Linoria).
**Enfoque aprobado:** C — Híbrido (piggyback lectura + remotes directos para acciones deterministas + movimiento/anti-idle propios).

---

## 1. Modelo de anticheat (verificado en recon)

| Vector | Hallazgo | Implicación de diseño |
|--------|----------|-----------------------|
| AC de exploits en cliente | **No existe.** Cero scripts `anticheat/antiexploit/Kick/Ban` en árbol replicado. `AntiKickController` es anti-AFK, no anti-cheat. | Todo AC real vive server-side (invisible). No hay escaneo de GUI observado. |
| Movimiento | Server **solo rubberbandea** (confirmado por usuario). Umbral ≈ `speedCap + ~20 studs/s`, crece con ascensions. Teleport = yank inmediato. | Travel debe mantenerse bajo umbral (velocity-budget) o usar pulsos/fluctuación (picos ~2× cap toleran yank ocasional; usuario alcanzó 440 sps @ 230 cap). Sin teleport duro. |
| Autoridad de acciones | Todo valor pasa por remote validado server-side: `SetSpeedCap`/`GetSpeedCap` (RF), currency/stats/ascend/orbs/jobs/rewards vía `InvokeServer`/`FireServer`. WalkSpeed lo fija el server tras validar cap solicitado. | No falsear currency/level localmente. Farm = disparar flujos legítimos dentro de límites. |
| Idle heurístico (**único AC agresivo**) | `AntiKickConfig`: `IDLE_SECONDS=960`, `SUSPICIOUS_IDLE=60`, `IDLE_PROOF_MAX_AGE=120`, `IN_FLIGHT_VERIFY=30`, `ATTEMPT_LIMIT=5`, `FLOOD_DELAY=15`, `REPORT_MIN_INTERVAL=30`. Log dev: *"if nobody touched the controls, THIS is the event resetting the anti-kick timer"* → server sospecha de input sintético/ausente. | **AntiIdleService** debe generar input humano-convincente (VirtualInputManager) con jitter, gaps < `SUSPICIOUS_IDLE`. |
| Rate-limit remotes | `ATTEMPT_LIMIT=5`, `FLOOD_DELAY=15`, `REPORT_MIN_INTERVAL=30`, `CLAIM_MIN_INTERVAL=0.4`, `ARRIVAL_MIN_INTERVAL=0.1`, `SERVER_POLL_INTERVAL=0.25`. | **Safety/RateGovernor** central: cada remote tiene min-interval; nunca spamear. |

**Postura de riesgo (burner):** agresivo pero no estúpido. Anti-idle siempre activo; rate governor nunca desactivable; pulso permitido por defecto en tramos largos.

---

## 2. Modelo de mecánicas (reference)

### 2.1 Loop incremental
EXP → nivel. Multiplicador total (`TotalBuffController`):
```
Total = EarlyMult(ascensions) × Treadmill × FriendBoost × Morph × Upgrades(ExpRank) × ExpBuff
```
EXP pasivo acumula parado en pad de treadmill (mult del pad). Money (jobs) compra upgrades/morphs → sube mult → sube EXP/s. Nivel alcanza `levelCap` → **ascend** → sube ascensions → desbloquea speed cap mayor, tiers de jobs, pads, chain slots → repite más rápido. Núcleo prestige clásico.

### 2.2 Jobs (money maker)
`JobsConfig`:
- Tipos: `Simple` (rewardScale 1, maxDist 25000) / `Fragile` (rewardScale 1.2, maxDist 10000, **falla si chocas props**).
- Tiers por ascensions: **Easy** (0 asc, 60s, reward 1000, 2%) / **Medium** (4 asc, 40s, 5000, 3.5%) / **Hard** (10 asc, 35s, 10000, 5%). `rewardPercent` = % del banco → escala con progreso.
- Arrival: `checkArrival()` (JobsController L1131) compara HRP vs drop point (`GetDropPoint`, `u25`) contra `ARRIVAL_RADIUS=50`; dispara `ReportJobArrival`. Server valida con `SERVER_ARRIVAL_SLACK=40` + `SERVER_DEADLINE_GRACE=0.75`.
- Chain multi-leg; `CHAIN_SLOT_ASCENSIONS={0,0,10,25}`; `CHAIN_REDUCTIONS={0,7,10,15}`.
- Banco: `BANK_CAP=50` → `ClaimJob`/`CollectJob` para cobrar.
- Fragile: `ReportFragileBreak` al chocar → run falla.

### 2.3 Treadmill
`TreadmillController`: pad activo por posición (`TreadmillZones:PadUnderPosition`). `IsEligible(padId, ascensions, ownsPass)` gatea pads por ascensions/gamepass. `GetMultiplier()` da mult del pad activo (o `PASSIVE_EXP_MULTIPLIER` sin pad). Estar en pad = EXP pasivo. Parado quieto → dispara idle heurístico → AntiIdleService obligatorio.

### 2.4 Ascension
`AscensionController`: `AscendRequest` (RemoteEvent). Requisito: `StatsController:GetLevel() >= GetLevelCap()` (error "You do not meet the requirements!" si no). `GetAscensions()` estado vivo. `AscensionChanged`/`GetAscensionSnapshot` para sync.

### 2.5 Inventario de remotes relevantes (`ReplicatedStorage.Remotes`, nombres en `Shared.RemoteNames`)
- **Jobs:** `ReportJobArrival` (RE), `ClaimJob` (RE), `CollectJob` (RE), `ReportFragileBreak` (RE), `JobsStateChanged` (RE).
- **Speed:** `SetSpeedCap` (RF), `GetSpeedCap` (RF).
- **Ascend:** `AscendRequest` (RE), `AscensionChanged` (RE), `GetAscensionSnapshot` (RF).
- **Orbs:** `OrbCollect` (RE, `FireServer(index)`), `OrbUpdate` (RE).
- **Economy:** `BuyUpgrade` (RE), `UpgradesChanged` (RE), `GetUpgradesSnapshot` (RF), `BuyMorph` (RE), `MorphChanged` (RE), `CurrencyChanged` (RE).
- **Quests:** `CollectQuest` (RE), `QuestsChanged` (RE), `GetQuestsSnapshot` (RF).
- **Idle:** `ReportIdle` (RE).
- **Extras:** `MultiRaceInvite/Vote/Results` (RE), `ResetRace` (RE), `TrackTeleportRequest` (RE), `TrackChanged` (RE), `ServerEventClaim/Started/Ended` (RE), PlayTime/Free rewards (varios RF, en PlayTimeRewardsController/FreeRewardsController).

> Nombres exactos y firmas de payload de cada remote se confirman en fase de plan vía lectura dirigida + remote-spy antes de escribir cada módulo.

---

## 3. Arquitectura general (Enfoque C)

**Principios:**
- **Un módulo, un propósito**, interfaz explícita, testeable aislado.
- **Lectura piggyback:** `require` de controllers del juego (o snapshots RF) para estado (ascensions, caps, phase, drop point, banco, currency). No reimplementar lo que el juego ya expone.
- **Escritura determinista:** disparar remotes directos para acciones (`ClaimJob`, `AscendRequest`, `BuyUpgrade`, `OrbCollect`, `CollectQuest`). Arrival de jobs = piggyback (dejar que `checkArrival` del juego dispare al entrar al radio).
- **Movimiento y anti-idle 100% propios.**
- **Todo write pasa por RateGovernor.** Todo módulo obedece kill-switch global.

**Data flow (alto nivel):**
```
UI(Obsidian toggles) → Orchestrator(scheduler prioridad) → Tasks(JobsFarm/TreadmillFarm/AscensionMgr/EconomyFarm/Extras)
        ↑                         │                                    │
        │                    StateStore ←── reads (controllers/snapshots RF, character, attributes)
        │                         │                                    │
   Telemetry ←── Logging ←────────┴──── writes → RateGovernor → RemoteHandler:Fire/Invoke
                                                      │
                                   MovementEngine (HRP) · AntiIdleService (VIM)
```

**Loader/entry:** un script único (bundle) o `loadstring` desde repo. Detecta PlaceId, espera `Modules` + `Controllers` listos (`INIT_GRACE=6`), bootstrap Core → UI → Orchestrator. Si PlaceId ≠ 98352297590435 → abort con mensaje.

---

## 4. Diseño por módulo

Cada módulo: **Propósito · Interfaz pública · Dependencias · Estado · Errores**.

### Módulo 0 — Core
- **Propósito:** infraestructura compartida. Bootstrap, config, logging, safe-call, kill-switch, StateStore, integración Obsidian (Library + SaveManager + ThemeManager).
- **Interfaz:** `Core.Config` (tabla tuneable congelable), `Core.Log(level, tag, ...)`, `Core.Safe(fn, ...)` (pcall + log + no-throw), `Core.State` (StateStore: get/set/subscribe), `Core.Stop()` / `Core.IsStopped()` (kill-switch), `Core.Remote(name)` (wrapper cacheado sobre `RemoteHandler` del juego), `Core.Window` (handle Obsidian).
- **Dependencias:** juego `ReplicatedStorage.Modules` (`RemoteHandler`, `Shared.RemoteNames`, `Config.*`), Obsidian lib (fetch a repo o embebida).
- **Estado:** singleton. StateStore = fuente de verdad de lecturas cacheadas (ascensions, caps, currency, phase) refrescadas por listeners de `*Changed` remotes.
- **Errores:** cualquier fallo de bootstrap → abort limpio + notificación. `Safe` envuelve todo callback de UI/loop.

### Módulo 1 — MovementEngine
- **Propósito:** llevar el HRP a un target sin yank. Híbrido.
- **Modos:**
  - **velocity-budget (default corto/medio):** lee `GetSpeedCap` vivo; `vSafe = cap + Config.Move.margin` con `margin = umbral(~20) - Config.Move.epsilon`. Empuja HRP hacia target a `vSafe` (vía `AssemblyLinearVelocity`/`Move` respetando control). Nunca cruza umbral → cero rubberband.
  - **pulse (default tramos largos, burner):** oscila velocidad (duty cycle configurable) para picos ~`Config.Move.pulsePeakMult × cap`, tolerando yank ocasional. Reacelera tras yank detectado (salto de posición hacia atrás > N studs).
- **Interfaz:** `Move:GoTo(pos, opts)` → promise/estado (`arrived`/`stuck`/`cancelled`); `Move:Follow(getPosFn)`; `Move:Stop()`; `Move:GetLiveCap()`.
- **Dependencias:** Core, character/HRP, `GetSpeedCap` RF, `MovementController`/`RunningHandler` (lectura de estado de carrera para no pelear con race mode).
- **Estado:** target actual, modo, último cap, detector de stuck (sin progreso > `stuckSeconds` → nudge/re-path).
- **Errores:** sin HRP → espera respawn. Stuck → intenta desatasco (micro-jump + reorientar); si persiste → reporta a Orchestrator (skip job).

### Módulo 2 — AntiIdleService
- **Propósito:** derrotar `SUSPICIOUS_IDLE` con input humano-convincente. **Siempre activo mientras el suite corre.**
- **Mecánica:** `VirtualInputManager` (o `virtualinput`/`Input` del executor) inyecta pulsos de tecla/mouse a intervalos aleatorios `Config.AntiIdle.gap = rand(25,45)s` (< 60), con jitter y variedad (alterna KeyCode inocuo + micro mouse move). Registra vía `UserInputService` → resetea `os_clock_ret` de AntiKickController legítimamente.
- **Interfaz:** `AntiIdle:Start()` / `AntiIdle:Stop()` / `AntiIdle:Kick()` (pulso inmediato).
- **Dependencias:** Core, VirtualInputManager. Integra con MovementEngine: si ya hubo input/movimiento real reciente, salta el pulso (evita redundancia sospechosa).
- **Estado:** timestamp último input real (observado) + último sintético.
- **Errores:** VIM no disponible en executor → fallback a movimiento real periódico (micro-jump); loguea degradación.

### Módulo 3 — JobsFarm
- **Propósito:** ciclo de deliveries por mejor tier desbloqueado.
- **Flujo:** (1) elegir tier = mejor por `GetAscensions()` (Hard≥10, Medium≥4, else Easy), tipo `Simple` por defecto (Fragile solo si `Config.Jobs.allowFragile`). (2) iniciar job (mecanismo exacto de accept se confirma en plan: método de JobsController o click de tier). (3) leer drop point (`JobsController:GetDropPoint()` / attribute) → `Move:GoTo`. (4) al entrar al radio, `checkArrival` del juego dispara `ReportJobArrival` (piggyback); fallback: fire directo respetando `ARRIVAL_MIN_INTERVAL`. (5) chain: repetir por leg hasta completar. (6) banco: al acercarse a `BANK_CAP=50` (`Config.Jobs.claimAt=48`) → `ClaimJob` (respeta `CLAIM_MIN_INTERVAL`). (7) loop.
- **Interfaz:** `JobsFarm:Start()/Stop()`, `JobsFarm:GetPhase()`, señales `Delivered`, `Claimed`.
- **Dependencias:** Core, MovementEngine, JobsController (lectura phase/drop/banco), remotes `ReportJobArrival`/`ClaimJob`/`CollectJob`, `JobsConfig`, AscensionController (tier gate).
- **Estado:** tier actual, leg, banco estimado, deadline restante.
- **Errores:** deadline por vencer y lejos → abort suave y re-pick (evita fail spam). Fragile break → desactivar fragile. Banco lleno → forzar claim antes de nuevo job.

### Módulo 4 — TreadmillFarm
- **Propósito:** maximizar EXP pasivo en el mejor pad elegible.
- **Flujo:** enumerar pads (`TreadmillConfig.pads`), filtrar por `TreadmillZones:IsEligible(pad, ascensions, ownsPass)`, elegir mayor `multiplier`. `Move:GoTo(padCenter)` → park (mantener dentro de zona). Mantener AntiIdle. Al subir ascensions/comprar pass → re-evaluar mejor pad.
- **Interfaz:** `TreadmillFarm:Start()/Stop()`, `TreadmillFarm:GetActivePad()`, `TreadmillFarm:GetBestEligible()`.
- **Dependencias:** Core, MovementEngine, AntiIdleService, TreadmillController, `TreadmillZones`, `TreadmillConfig`, AscensionController, MonetizationController (pass ownership).
- **Estado:** pad objetivo, en-pad bool.
- **Errores:** empujado fuera del pad → re-park. Ningún pad elegible → idle en pad base + notifica.

### Módulo 5 — AscensionMgr
- **Propósito:** auto-ascend para escalar tiers/caps.
- **Flujo:** watch `StatsController:GetLevel()` vs `AscensionController:GetLevelCap()`. Al alcanzar (y si `Config.Ascend.auto`): pausar farms activos → `AscendRequest:FireServer()` → esperar `AscensionChanged` (confirmación) → refrescar StateStore (ascensions, nuevo cap) → re-scan unlocks (tier jobs, pads) → resume farms. Opcional `Config.Ascend.targetAscensions` (para en N).
- **Interfaz:** `AscensionMgr:Start()/Stop()`, `AscensionMgr:AscendNow()`, señal `Ascended`.
- **Dependencias:** Core, StatsController, AscensionController, remotes `AscendRequest`/`AscensionChanged`, Orchestrator (pausa/resume).
- **Estado:** ascensions actual, level/cap cacheados, flag "ascending".
- **Errores:** requisito no cumplido (server rechaza) → reintento con backoff, no spam. Timeout de confirmación → re-sync snapshot.

### Módulo 6 — EconomyFarm
- **Propósito:** convertir money/orbs en EXP-mult y limpiar recompensas.
- **Sub-tareas:**
  - **Upgrades:** leer `GetUpgradesSnapshot`; priorizar upgrades de EXP-mult asequibles; `BuyUpgrade:FireServer(id)` respetando rate. Prioridad: ExpRank > money-gain > utilidad.
  - **Morphs:** `BuyMorph` para mejor morph EXP-mult desbloqueado y asequible.
  - **Orbs:** al detectar orbs cercanos (`OrbController`/workspace) dentro de `Config.Orbs.radius`, `OrbCollect:FireServer(index)` (piggyback proximidad del juego si existe; si no, validar distancia local antes de fire).
  - **Quests:** `GetQuestsSnapshot`; al completarse, `CollectQuest:FireServer(id)`.
- **Interfaz:** `Economy:Start()/Stop()`, toggles por sub-tarea.
- **Dependencias:** Core, snapshots RF, remotes `BuyUpgrade`/`BuyMorph`/`OrbCollect`/`CollectQuest`, `UpgradesConfig`/`MorphConfig`/`OrbConfig`/`QuestsConfig`, CurrencyController.
- **Estado:** cache de snapshots, cola de compras.
- **Errores:** compra rechazada (fondos) → recalcular. Snapshot stale → refetch.

### Módulo 7 — Extras
- **Propósito:** features secundarios opt-in.
- **Sub-tareas:** Multi-Race (auto join/vote/collect results), Free Rewards (`FreeRewardsController` claims), PlayTime Rewards (`PlayTimeRewardsController` claims temporizados), ServerEvent claim (`ServerEventClaim` al iniciar evento).
- **Interfaz:** `Extras:Start()/Stop()`, toggles por sub-tarea.
- **Dependencias:** Core, controllers/remotes respectivos.
- **Estado:** timers de claim, estado de race.
- **Errores:** feature no presente en server → auto-disable + notifica.

### Módulo 8 — Orchestrator
- **Propósito:** decidir qué tarea corre y cuándo (recursos compartidos: personaje solo puede estar en un sitio).
- **Modelo:** scheduler por prioridad + estado. Prioridad default (burner): `AscensionMgr(interrupt) > JobsFarm > EconomyFarm(oportunista, no bloquea travel) > TreadmillFarm(idle fallback) > Extras`. Reglas: Jobs y Treadmill son mutuamente exclusivos en ubicación → modo seleccionable (`JobsPrimary` / `TreadmillPrimary` / `Auto`: jobs mientras haya tier rentable, treadmill entre cooldowns). Economy y Orbs corren en paralelo (no requieren posición dedicada salvo orbs). Ascend interrumpe todo.
- **Interfaz:** `Orchestrator:SetMode(mode)`, `Orchestrator:Pause()/Resume()`, `Orchestrator:Tick()`.
- **Dependencias:** todos los Task modules, Core, RateGovernor.
- **Estado:** tarea activa, cola, modo.
- **Errores:** deadlock/starvation → watchdog re-evalúa cada `Config.Orchestrator.tick`.

### Módulo 9 — Safety
- **Propósito:** no morir por rate-limit ni parecer bot obvio.
- **Componentes:**
  - **RateGovernor:** min-interval por remote (`ReportIdle≥FLOOD_DELAY=15`, claims `≥CLAIM_MIN_INTERVAL`, arrival `≥ARRIVAL_MIN_INTERVAL`, default global `≥Config.Safety.minGap`). Cola + coalescing; nunca supera `ATTEMPT_LIMIT` en ventana.
  - **Jitter:** aleatoriza timings de todas las acciones repetitivas (±%) para romper periodicidad.
  - **Panic/Stop:** keybind + botón → `Core.Stop()` corta todos los loops, detiene Move, deja AntiIdle opcional.
  - **Rejoin handling:** si server dispara rejoin/`ReportIdle` handoff, detectar y re-bootstrap tras reconexión (o soltar si el executor no persiste).
- **Interfaz:** `Safety.Governor:Allow(remoteName)`, `Safety:Panic()`, `Safety:Jitter(base)`.
- **Dependencias:** Core, RemoteHandler.
- **Estado:** timestamps por remote, ventana de conteo.
- **Errores:** governor nunca desactivable; si se excede presupuesto → drop de acción + log.

---

## 5. UI (Obsidian)

Tabs y grupos (dark pro):
- **Farm:** Master toggle · Mode (JobsPrimary/TreadmillPrimary/Auto) · Jobs (enable, tier auto/force, allowFragile, claimAt) · Treadmill (enable, best-pad auto/force) · Ascend (auto, targetAscensions).
- **Economy:** Upgrades (enable, priority) · Morphs · Orbs (enable, radius) · Quests.
- **Movement:** mode (budget/pulse/hybrid) · margin/epsilon · pulsePeakMult/dutyCycle · stuck settings.
- **Extras:** Multi-Race · Free/PlayTime rewards · ServerEvent.
- **Anti-Idle / Safety:** AntiIdle gap range · jitter % · min gaps · Panic keybind.
- **Config:** Obsidian SaveManager (perfiles) + ThemeManager · telemetry/log level · Unload.

Notificaciones Obsidian para eventos (ascended, claimed x$, job failed, rate-drop, degradaciones).

---

## 6. Config defaults (burner-agresivo, todo tuneable)

```
Move   = { mode="hybrid", margin=18, epsilon=2, pulsePeakMult=1.9, dutyCycle=0.55, stuckSeconds=2.5, longLegStuds=1200 }
AntiIdle = { gapMin=25, gapMax=45, jitter=0.3, preferRealInput=true }
Jobs   = { tier="auto", type="Simple", allowFragile=false, claimAt=48, abortIfDeadlineMargin=1.0 }
Treadmill = { pad="auto" }
Ascend = { auto=true, targetAscensions=0 }        -- 0 = infinito
Economy = { upgrades=true, morphs=true, orbs=true, quests=true, priority={"exp","money","util"}, orbRadius=60 }
Extras = { multiRace=false, freeRewards=true, playTime=true, serverEvent=true }
Orchestrator = { mode="auto", tick=0.5 }
Safety = { minGap=0.35, jitterPct=0.25, panicKey="RightControl", governorHard=true }
```

---

## 7. Estrategia de testing / verificación

No hay harness de unit test en executor. Estrategia por capas, TDD-ish:

1. **Dry-run mode (Core.Config.dryRun):** cada write loguea `[DRY] would fire <remote>(<args>)` en vez de disparar. Primer gate de cada módulo = correr en dry-run y validar decisiones en consola.
2. **Read-probes por módulo (antes de habilitar writes):** vía `get-data-by-code` confirmar que las lecturas piggyback devuelven lo esperado (ascensions, cap vivo, drop point, banco, snapshots). Un probe por módulo = su "test" de contrato.
3. **Remote-spy baseline:** capturar con `ensure-remote-spy` los payloads reales de una acción manual (un job, un claim, un ascend, una compra) → congelar firma esperada → el módulo debe reproducirla byte-compatible.
4. **Habilitación incremental live:** activar un módulo a la vez, verificar efecto con `get-console-output` + probe de estado (currency subió, ascensions subió, en-pad true). Movimiento primero en velocity-budget puro (cero yank) antes de pulso.
5. **Rate governor assertion:** log de cada allow/deny; verificar que ningún remote supera su min-interval bajo carga.
6. **Checkpoints manuales:** el usuario confirma cada hito live (jobs loop, treadmill+antiidle 5min sin kick, auto-ascend, economy) antes de avanzar.

**Regla:** ningún módulo pasa a "write live" sin (a) dry-run limpio, (b) read-probe verde, (c) firma remote-spy validada.

---

## 8. Riesgos y mitigaciones

| Riesgo | Mitigación |
|--------|-----------|
| API interna de controllers cambia en update | Piggyback solo lecturas estables + snapshots RF; writes por remote directo (más estable). Version guard `PlaceVersion`. |
| Métodos de controller privados (upvalues) | Preferir remotes/attributes/GetSnapshot RF; documentar en plan qué es accesible. |
| Pulso gatilla yank frecuente | Default hybrid: budget salvo tramos > `longLegStuds`; detector de yank reacelera. |
| Idle heurístico server más listo de lo visto | AntiIdle con input real variado + jitter + integración con movimiento real; monitor de kicks. |
| Obsidian lib no carga en executor objetivo | Embeber lib en bundle o fallback mínimo; validar en loader. |
| Rejoin/handoff del server rompe sesión | Safety detecta y re-bootstrap; si executor no persiste, soltar limpio. |

---

## 9. Assumptions

- `663_00` = burner → defaults agresivos OK.
- Server AC = solo rubberband + idle heurístico (confirmado recon+usuario); sin GUI scan, sin detección de hooks observada.
- Executor expone `VirtualInputManager` (o equivalente) y `getgenv`/`loadstring`; Obsidian cargable.
- Firmas exactas de remotes/métodos de accept-job se confirman en fase de plan (lectura dirigida + remote-spy) — no bloquean el diseño.

---

## 10. Fuera de alcance (YAGNI)

- Trading/social más allá de FriendBoost pasivo.
- Anti-ban avanzado (spoof HWID, etc.) — burner, no aplica.
- Soporte multi-juego (suite específica a PlaceId 98352297590435).
- Combat/PvP (juego no lo tiene).
