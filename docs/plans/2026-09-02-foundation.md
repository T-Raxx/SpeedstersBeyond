# Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Base cargable del suite — global state, capa de red con rate-governor, UI Obsidian con controles globales, y lectura en vivo del estado del juego.

**Architecture:** Enfoque C (híbrido). Módulos factory (`return function(require, SB, Lib)`) ensamblados por `build_bundle.ps1` a `SpeedstersBeyond.lua`. `Core/State.lua` crea `getgenv().SB`. `Net.lua` envuelve remotes (raw instances de `ReplicatedStorage.Remotes`) y pasa todo write por `Safety/Governor`. UI = Obsidian (cargada en runtime). Sin lógica de farm en Foundation.

**Tech Stack:** Luau (executor), Obsidian UI lib (`deividcomsono/Obsidian`), PowerShell bundler.

**Spec:** `docs/specs/2026-09-02-speedsters-beyond-autofarm-design.md`

## Global Constraints

- PlaceId objetivo: `98352297590435`. El loader aborta si no coincide.
- Estado global único en `getgenv().SB`. Guard de doble-carga: al recargar, neutraliza+Unload el build viejo.
- Todo write de remote pasa por `Net` → `Safety.Governor:Allow(name)`. Nunca `FireServer`/`InvokeServer` crudo salteando el governor.
- `dryRun` global: cuando true, los writes loguean `[DRY] <remote>(args)` en vez de disparar.
- Cuenta = burner → defaults agresivos permitidos.
- Rate-limits del server (respetar en Governor): `ReportIdle ≥ 15s` (FLOOD_DELAY), claims `≥ 0.4s` (CLAIM_MIN_INTERVAL), arrival `≥ 0.1s`, default global `≥ 0.35s`, `ATTEMPT_LIMIT=5` por ventana.
- Nombres de remotes = raw children de `ReplicatedStorage.Remotes` (ver spec §2.5). No requerir `RemoteHandler` del juego para writes.

## Ciclo de verificación (executor)

No hay unit-test runner local. El ciclo de cada task (adaptación TDD):
1. **Probe primero (rojo):** ejecutar en el cliente vivo (roblox-executor-mcp `get-data-by-code`) un probe que espera el comportamiento nuevo → debe fallar (nil / módulo ausente).
2. **Build:** `powershell -ExecutionPolicy Bypass -File build_bundle.ps1` → regenera `SpeedstersBeyond.lua`.
3. **Load:** `execute` el bundle en el cliente vivo (o `loadstring(game:HttpGet(raw))()` tras push).
4. **Probe (verde):** re-correr el probe → pasa. Confirmar con `get-console-output` (limit bajo).
5. **Commit.**

> El cliente vivo ya está conectado (place 98352297590435). Preferir `get-data-by-code` devolviendo valores compactos, nunca instancias/tablas grandes.

## File Structure

- `Core/State.lua` — crea `getgenv().SB`: guard doble-carga, `track`/`onCleanup`, `Log`, `dryRun`, StateStore (`Get`/`Set`/`Subscribe`), refs del juego, `Unload`. Responsabilidad única: estado + ciclo de vida.
- `Safety/Governor.lua` — RateGovernor: `Allow(name)` con min-interval por remote + ventana `ATTEMPT_LIMIT`. Puro (testeable por probe con clock inyectable).
- `Net.lua` — resuelve remotes por nombre (`ReplicatedStorage.Remotes`), `Fire(name, ...)` / `Invoke(name, ...)` que pasan por Governor + honran `dryRun`; helper `OnChanged(name, fn)`.
- `UI.lua` — `UI.build(Window, Lib)`: tabs base + groupbox de controles globales (Master, DryRun, LogLevel, Unload, Panic keybind). Flags en `Lib.Toggles`/`Lib.Options`.
- `main.lua` — driver: place guard, bootstrap Obsidian (Library+Save+Theme), crear Window, `UI.build`, init `Net`/`Safety`, wire panic/unload, StateStore listeners, master loop stub.
- `build_bundle.ps1` — ya existe (tooling). Se valida en Task 1.

---

### Task 1: Core/State + main mínimo + bootstrap Obsidian

**Files:**
- Create: `Core/State.lua`
- Create: `main.lua`
- Test: probe en cliente vivo

**Interfaces:**
- Produces: `getgenv().SB` con `SB.version`, `SB.placeId`, `SB.stopped`, `SB.dryRun`, `SB.logLevel`, `SB.track(conn)`, `SB.onCleanup(fn)`, `SB.Log(level,...)`, `SB.Get(k)`, `SB.Set(k,v)`, `SB.Subscribe(k,fn)`, `SB.IsStopped()`, `SB.Unload()`, `SB.Modules`, `SB.Shared`, `SB.Remotes`, `SB.Library`. main expone `SB.Window`.

- [ ] **Step 1: Probe (rojo)**

Ejecutar en cliente vivo:
```lua
return tostring(getgenv().SB and getgenv().SB.version or "nil")
```
Expected: `"nil"` (aún no cargado).

- [ ] **Step 2: Escribir `Core/State.lua`**

```lua
-- Core/State.lua — FACTORY. Crea getgenv().SB (estado global único): guard doble-carga,
-- track de conns, onCleanup, Log (respeta logLevel), StateStore, refs del juego, Unload.
-- Ignora su param SB (ES quien lo crea).
return function(require, _unused, Lib)
    if getgenv().SB then
        local old = getgenv().SB
        old.stopped = true
        if old.Unload then pcall(old.Unload) end
    end
    local RS = game:GetService("ReplicatedStorage")

    local SB = {
        version  = "0.1.0",
        placeId  = 98352297590435,
        stopped  = false,
        dryRun   = false,
        logLevel = 2,            -- 0 silent, 1 warn, 2 info, 3 debug
        conns    = {},
        cleanups = {},
        store    = {},
        _subs    = {},
    }

    function SB.IsStopped() return SB.stopped end
    function SB.track(conn) SB.conns[#SB.conns + 1] = conn; return conn end
    function SB.onCleanup(fn) SB.cleanups[#SB.cleanups + 1] = fn end

    local TAG = { [1] = "[SB-WARN]", [2] = "[SB]", [3] = "[SB-DBG]" }
    function SB.Log(level, ...)
        if level > SB.logLevel or level < 1 then return end
        print(TAG[level] or "[SB]", ...)
    end

    function SB.Get(k) return SB.store[k] end
    function SB.Set(k, v)
        SB.store[k] = v
        local subs = SB._subs[k]
        if subs then for _, fn in ipairs(subs) do task.spawn(fn, v) end end
    end
    function SB.Subscribe(k, fn)
        SB._subs[k] = SB._subs[k] or {}
        table.insert(SB._subs[k], fn)
    end

    SB.Modules = RS:WaitForChild("Modules", 20)
    SB.Shared  = SB.Modules and SB.Modules:WaitForChild("Shared", 20)
    SB.Remotes = RS:WaitForChild("Remotes", 20)

    function SB.Unload()
        SB.stopped = true
        for _, c in ipairs(SB.conns) do pcall(function() c:Disconnect() end) end
        for _, fn in ipairs(SB.cleanups) do pcall(fn) end
        SB.conns, SB.cleanups = {}, {}
        if SB.Library and SB.Library.Unload then pcall(function() SB.Library:Unload() end) end
        if getgenv().SB == SB then getgenv().SB = nil end
    end

    getgenv().SB = SB
    return SB
end
```

- [ ] **Step 3: Escribir `main.lua` (mínimo)**

```lua
-- main.lua — FACTORY driver. Place guard, bootstrap Obsidian, crea Window, init capas, panic/unload.
return function(require, SB, _Lib)
    -- PLACE GUARD
    if game.PlaceId ~= SB.placeId then
        SB.Log(1, "PlaceId", game.PlaceId, "≠", SB.placeId, "— abort")
        SB.Unload()
        return
    end

    -- BOOTSTRAP OBSIDIAN (runtime)
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
    SB.Library = Library
    SB.ThemeManager = ThemeManager
    SB.SaveManager  = SaveManager

    local Window = Library:CreateWindow({
        Title = "SpeedstersBeyond",
        Footer = "v" .. SB.version .. " · burner",
        Center = true, AutoShow = true,
        NotifySide = "Right",
    })
    SB.Window = Window
    SB.Tabs = { Main = Window:AddTab("Main", "home") }

    SB.Log(2, "cargado — window listo")
    Library:Notify("SpeedstersBeyond cargado", 3)
end
```

- [ ] **Step 4: Build**

Run: `powershell -ExecutionPolicy Bypass -File build_bundle.ps1`
Expected: `[build] + Core.State`, `[build] + main`, `[build] OK -> SpeedstersBeyond.lua`.

- [ ] **Step 5: Load + Probe (verde)**

Ejecutar `SpeedstersBeyond.lua` en el cliente vivo, luego:
```lua
return tostring(getgenv().SB and getgenv().SB.version) .. "|" .. tostring(getgenv().SB and getgenv().SB.Window ~= nil)
```
Expected: `"0.1.0|true"`. Window Obsidian visible en pantalla.

- [ ] **Step 6: Commit**

```bash
git add Core/State.lua main.lua
git commit -m "feat(core): global state + main driver + Obsidian bootstrap"
```

---

### Task 2: Safety/Governor

**Files:**
- Create: `Safety/Governor.lua`
- Modify: `main.lua` (require + guardar en SB)
- Test: probe

**Interfaces:**
- Consumes: `SB`.
- Produces: `Governor.Allow(name) -> boolean`, `Governor.SetInterval(name, seconds)`, `Governor.DEFAULT`. Intervals default: `ReportIdle=15`, `ClaimJob=0.4`, `CollectJob=0.4`, `ReportJobArrival=0.1`, `_default=0.35`. Ventana `ATTEMPT_LIMIT=5` por 1s.

- [ ] **Step 1: Probe (rojo)**
```lua
local SB = getgenv().SB
return tostring(SB and SB.Governor ~= nil)
```
Expected: `"false"`.

- [ ] **Step 2: Escribir `Safety/Governor.lua`**

```lua
-- Safety/Governor.lua — FACTORY. RateGovernor: min-interval por remote + ventana ATTEMPT_LIMIT.
-- Allow(name) devuelve true si se puede disparar AHORA (y registra el disparo); false = throttle.
return function(require, SB, Lib)
    local Governor = {}
    local last = {}          -- name -> os.clock del ultimo allow
    local windowTimes = {}   -- lista de os.clock de disparos recientes (ventana 1s)

    local INTERVALS = {
        ReportIdle       = 15,
        ClaimJob         = 0.4,
        CollectJob       = 0.4,
        ReportJobArrival = 0.1,
        _default         = 0.35,
    }
    Governor.DEFAULT = INTERVALS._default
    local ATTEMPT_LIMIT, WINDOW = 5, 1.0

    function Governor.SetInterval(name, seconds) INTERVALS[name] = seconds end

    function Governor.Allow(name)
        local now = os.clock()
        -- ventana global anti-flood
        local n = 0
        for i = #windowTimes, 1, -1 do
            if now - windowTimes[i] > WINDOW then table.remove(windowTimes, i) else n = n + 1 end
        end
        if n >= ATTEMPT_LIMIT then
            SB.Log(3, "Governor: ventana llena (", n, ") — deny", name)
            return false
        end
        local iv = INTERVALS[name] or INTERVALS._default
        if last[name] and (now - last[name]) < iv then
            SB.Log(3, "Governor: min-interval", name, string.format("%.2f", now - last[name]), "<", iv)
            return false
        end
        last[name] = now
        windowTimes[#windowTimes + 1] = now
        return true
    end

    return Governor
end
```

- [ ] **Step 3: Wire en `main.lua`** (tras `SB.Library = Library`, antes del Notify):

```lua
    SB.Governor = require("Safety.Governor")
```

- [ ] **Step 4: Build**
Run: `powershell -ExecutionPolicy Bypass -File build_bundle.ps1`
Expected: incluye `[build] + Safety.Governor`.

- [ ] **Step 5: Load + Probe (verde)**
Ejecutar bundle, luego:
```lua
local G = getgenv().SB.Governor
local a = G.Allow("ClaimJob")          -- true
local b = G.Allow("ClaimJob")          -- false (min-interval 0.4)
return tostring(a) .. "|" .. tostring(b)
```
Expected: `"true|false"`.

- [ ] **Step 6: Commit**
```bash
git add Safety/Governor.lua main.lua
git commit -m "feat(safety): rate governor con min-interval + ventana anti-flood"
```

---

### Task 3: Net (capa de red + read en vivo)

**Files:**
- Create: `Net.lua`
- Modify: `main.lua` (require + guardar en SB)
- Test: probe con read real (`GetSpeedCap`) + dryRun

**Interfaces:**
- Consumes: `SB`, `SB.Governor`, `SB.Remotes`.
- Produces: `Net.Get(name) -> Instance?` (cachea), `Net.Fire(name, ...) -> boolean` (RemoteEvent, pasa por Governor + dryRun), `Net.Invoke(name, ...) -> any` (RemoteFunction, NO gobernado por default — reads; opcional gate), `Net.OnChanged(name, fn) -> conn`.

- [ ] **Step 1: Probe (rojo)**
```lua
return tostring(getgenv().SB and getgenv().SB.Net ~= nil)
```
Expected: `"false"`.

- [ ] **Step 2: Escribir `Net.lua`**

```lua
-- Net.lua — FACTORY. Capa de red: resuelve remotes por nombre (ReplicatedStorage.Remotes),
-- Fire (RemoteEvent, gobernado + dryRun), Invoke (RemoteFunction, reads), OnChanged (listener).
return function(require, SB, Lib)
    local Net = {}
    local cache = {}

    function Net.Get(name)
        if cache[name] and cache[name].Parent then return cache[name] end
        local r = SB.Remotes and SB.Remotes:FindFirstChild(name)
        cache[name] = r
        if not r then SB.Log(1, "Net: remote no encontrado:", name) end
        return r
    end

    function Net.Fire(name, ...)
        if SB.IsStopped() then return false end
        local G = SB.Governor
        if G and not G.Allow(name) then return false end
        if SB.dryRun then
            SB.Log(2, "[DRY] Fire", name, ...)
            return true
        end
        local r = Net.Get(name)
        if not (r and r:IsA("RemoteEvent")) then return false end
        local args = table.pack(...)
        local ok = pcall(function() r:FireServer(table.unpack(args, 1, args.n)) end)
        return ok
    end

    function Net.Invoke(name, ...)
        local r = Net.Get(name)
        if not (r and r:IsA("RemoteFunction")) then return nil end
        local args = table.pack(...)
        local ok, res = pcall(function() return r:InvokeServer(table.unpack(args, 1, args.n)) end)
        if not ok then SB.Log(1, "Net: Invoke fallo", name, res); return nil end
        return res
    end

    function Net.OnChanged(name, fn)
        local r = Net.Get(name)
        if not (r and r:IsA("RemoteEvent")) then return nil end
        return SB.track(r.OnClientEvent:Connect(fn))
    end

    return Net
end
```

- [ ] **Step 3: Wire en `main.lua`** (tras `SB.Governor = ...`):

```lua
    SB.Net = require("Net")
```

- [ ] **Step 4: Build**
Run: `powershell -ExecutionPolicy Bypass -File build_bundle.ps1`
Expected: incluye `[build] + Net`.

- [ ] **Step 5: Load + Probe (verde)**
Ejecutar bundle, luego (read real vía RemoteFunction del juego):
```lua
local Net = getgenv().SB.Net
local cap = Net.Invoke("GetSpeedCap")
return "cap=" .. tostring(cap) .. "|type=" .. typeof(cap)
```
Expected: un número (ej. `"cap=230|type=number"`). Si el juego devuelve tabla, ajustar el probe pero confirmar no-nil.

Probe dryRun (no debe disparar de verdad):
```lua
local SB = getgenv().SB; SB.dryRun = true
local r = SB.Net.Fire("ReportIdle")
SB.dryRun = false
return tostring(r)   -- true, y en consola: [DRY] Fire ReportIdle
```
Expected: `"true"` + línea `[DRY] Fire ReportIdle` en `get-console-output`.

- [ ] **Step 6: Commit**
```bash
git add Net.lua main.lua
git commit -m "feat(net): capa de red gobernada + dryRun + read GetSpeedCap"
```

---

### Task 4: UI shell + controles globales

**Files:**
- Create: `UI.lua`
- Modify: `main.lua` (require + `UI.build` + wire panic/unload/dryRun/logLevel)
- Test: probe flags registrados

**Interfaces:**
- Consumes: `SB`, `SB.Window`, `Library`.
- Produces: `UI.build(Window, Lib)`. Tabs: `Main`. Groupbox "Global": Toggle `MasterEnable`, Toggle `DryRun`, Dropdown `LogLevel` (Silent/Warn/Info/Debug), Button "Unload", KeyPicker `PanicKey` (Default RightControl). Flags: `Lib.Toggles.MasterEnable`, `Lib.Toggles.DryRun`, `Lib.Options.LogLevel`, `Lib.Options.PanicKey`.

- [ ] **Step 1: Probe (rojo)**
```lua
local L = getgenv().SB and getgenv().SB.Library
return tostring(L and L.Toggles and L.Toggles.MasterEnable ~= nil)
```
Expected: `"false"`.

- [ ] **Step 2: Escribir `UI.lua`**

```lua
-- UI.lua — FACTORY. Construye tabs/groupboxes Obsidian + controles globales.
-- Flags en Lib.Toggles / Lib.Options. Sin lógica de farm (solo wiring).
return function(require, SB, Lib)
    local UI = {}

    function UI.build(Window, Library)
        local Toggles, Options = Library.Toggles, Library.Options
        local box = SB.Tabs.Main:AddLeftGroupbox("Global")

        box:AddToggle("MasterEnable", {
            Text = "Master Enable", Default = false,
            Tooltip = "Habilita el suite. Off = todo pausado (kill-switch suave).",
            Callback = function(v) SB.masterOn = v end,
        })
        box:AddToggle("DryRun", {
            Text = "Dry-Run", Default = false,
            Tooltip = "Loguea writes en vez de dispararlos.",
            Callback = function(v) SB.dryRun = v end,
        })
        box:AddDropdown("LogLevel", {
            Values = { "Silent", "Warn", "Info", "Debug" }, Default = "Info",
            Text = "Log Level",
            Callback = function(v)
                SB.logLevel = ({ Silent = 0, Warn = 1, Info = 2, Debug = 3 })[v] or 2
            end,
        })
        box:AddButton("Unload", function() SB.Unload() end)
        box:AddDivider()
        box:AddLabel("Panic Key"):AddKeyPicker("PanicKey", {
            Default = "RightControl", Mode = "Toggle", Text = "Panic (unload)",
            Callback = function() SB.Unload() end,
        })
    end

    return UI
end
```

- [ ] **Step 3: Wire en `main.lua`** (tras `SB.Net = ...`, antes del Notify):

```lua
    SB.UI = require("UI")
    SB.UI.build(Window, Library)
    -- SaveManager / ThemeManager
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetFolder("SpeedstersBeyond")
    ThemeManager:SetFolder("SpeedstersBeyond")
    local cfgTab = Window:AddTab("Config", "settings")
    SB.Tabs.Config = cfgTab
    SaveManager:BuildConfigSection(cfgTab)
    ThemeManager:ApplyToTab(cfgTab)
    SaveManager:LoadAutoloadConfig()
```

- [ ] **Step 4: Build**
Run: `powershell -ExecutionPolicy Bypass -File build_bundle.ps1`
Expected: incluye `[build] + UI`.

- [ ] **Step 5: Load + Probe (verde)**
Ejecutar bundle, luego:
```lua
local L = getgenv().SB.Library
return table.concat({
    tostring(L.Toggles.MasterEnable ~= nil),
    tostring(L.Toggles.DryRun ~= nil),
    tostring(L.Options.LogLevel ~= nil),
    tostring(L.Options.PanicKey ~= nil),
}, "|")
```
Expected: `"true|true|true|true"`. UI muestra tab Main+Config, groupbox Global.

- [ ] **Step 6: Commit**
```bash
git add UI.lua main.lua
git commit -m "feat(ui): shell Obsidian + controles globales + config/theme managers"
```

---

### Task 5: StateStore listeners (lectura viva del juego)

**Files:**
- Modify: `main.lua` (wire listeners + read inicial + loop stub)
- Test: probe valores vivos en SB.store

**Interfaces:**
- Consumes: `SB.Net`, `SB.Subscribe`, remotes `CurrencyChanged`, `AscensionChanged`, RF `GetSpeedCap`, `GetAscensionSnapshot`.
- Produces: `SB.store.currency`, `SB.store.ascensions`, `SB.store.speedCap` poblados y auto-refrescados. `SB.masterOn`. Loop stub en Heartbeat (respeta stopped/masterOn) para futuras tasks.

- [ ] **Step 1: Probe (rojo)**
```lua
local SB = getgenv().SB
return tostring(SB and SB.Get and SB.Get("speedCap"))
```
Expected: `"nil"`.

- [ ] **Step 2: Wire en `main.lua`** (tras el bloque SaveManager, antes del Notify):

```lua
    -- READ INICIAL + LISTENERS (StateStore)
    do
        local Net = SB.Net
        local cap = Net.Invoke("GetSpeedCap")
        if cap ~= nil then SB.Set("speedCap", cap) end
        local snap = Net.Invoke("GetAscensionSnapshot")
        if type(snap) == "table" and snap.ascensions ~= nil then
            SB.Set("ascensions", snap.ascensions)
        end
        Net.OnChanged("CurrencyChanged", function(v) SB.Set("currency", v) end)
        Net.OnChanged("AscensionChanged", function(v)
            if type(v) == "table" and v.ascensions ~= nil then SB.Set("ascensions", v.ascensions)
            else SB.Set("ascensions", v) end
        end)
        -- refresco periódico del speed cap vivo (barato)
        SB.track(game:GetService("RunService").Heartbeat:Connect(function()
            if SB.IsStopped() then return end
        end))
        task.spawn(function()
            while not SB.IsStopped() do
                local c = Net.Invoke("GetSpeedCap")
                if c ~= nil then SB.Set("speedCap", c) end
                task.wait(2)
            end
        end)
    end

    -- MASTER LOOP STUB (las tasks de farm cuelgan de aquí en planes siguientes)
    SB.track(game:GetService("RunService").Heartbeat:Connect(function()
        if SB.IsStopped() or not SB.masterOn then return end
        -- orchestrator tick placeholder (Plan 3)
    end))
```

> Nota: las firmas exactas de `GetAscensionSnapshot`/`AscensionChanged`/`CurrencyChanged` se confirman con remote-spy en el Step 5; ajustar el parseo (`snap.ascensions`) a la forma real.

- [ ] **Step 3: Build**
Run: `powershell -ExecutionPolicy Bypass -File build_bundle.ps1`

- [ ] **Step 4: Remote-spy baseline**
Con `ensure-remote-spy` + `get-remote-spy-logs` (summaryOnly=false, filtros `CurrencyChanged`/`AscensionChanged`/`GetSpeedCap`), capturar la forma real de los payloads. Ajustar el parseo del Step 2 si difiere.

- [ ] **Step 5: Load + Probe (verde)**
Ejecutar bundle, esperar ~3s, luego:
```lua
local SB = getgenv().SB
return table.concat({
    "cap=" .. tostring(SB.Get("speedCap")),
    "asc=" .. tostring(SB.Get("ascensions")),
    "cur=" .. tostring(SB.Get("currency")),
}, "|")
```
Expected: `speedCap` numérico no-nil; `ascensions` numérico; `currency` se puebla tras el primer `CurrencyChanged` (moverse/ganar in-game para gatillarlo).

- [ ] **Step 6: Commit**
```bash
git add main.lua
git commit -m "feat(state): StateStore listeners + read vivo (cap/ascensions/currency) + loop stub"
```

---

## Self-Review

**Spec coverage (Foundation slice):** Core/State ✓ (Módulo 0), Safety/Governor ✓ (Módulo 9 RateGovernor + Panic), Net ✓ (capa write/read gobernada), UI shell + Obsidian + Save/Theme ✓ (Módulo 0 UI base + §5 tab Config), StateStore reads ✓ (piggyback §3). Diferido a planes 2-4: Movement, AntiIdle, Jobs, Treadmill, Ascension, Economy, Extras, Orchestrator (fuera de scope de Foundation — cada uno produce software testeable propio).

**Placeholder scan:** el "orchestrator tick placeholder" es un stub intencional del loop maestro (Plan 3 lo llena), no un requisito sin implementar. El parseo de snapshots está marcado para confirmar con remote-spy (Step 4 de Task 5) — es verificación, no placeholder de código.

**Type consistency:** `SB.Get`/`SB.Set`/`SB.Subscribe`, `Net.Fire`/`Net.Invoke`/`Net.OnChanged`/`Net.Get`, `Governor.Allow`/`SetInterval` — nombres consistentes entre tasks. `SB.Tabs.Main` creado en Task 1, usado en Task 4. `SB.Library` seteado en Task 1, usado en Task 4/5. `SB.Net`/`SB.Governor` seteados antes de su primer uso.

---

## Roadmap (planes siguientes)

- **Plan 2 — Movement + AntiIdle:** `Movement/Movement.lua` (velocity-budget + pulso, lee `SB.Get("speedCap")`), `AntiIdle/AntiIdle.lua` (VirtualInputManager + jitter). Deliverable: viajar a un punto sin yank + mantener idle vivo 5min sin kick.
- **Plan 3 — Core farm:** `Jobs/Jobs.lua`, `Treadmill/Treadmill.lua`, `Ascension/Ascension.lua`, orchestrator en main. Deliverable: loop money+EXP+prestige.
- **Plan 4 — Economy + Extras:** `Economy/{Upgrades,Morphs,Orbs,Quests}.lua`, `Extras/{MultiRace,Rewards,ServerEvent}.lua`. Deliverable: full suite.
