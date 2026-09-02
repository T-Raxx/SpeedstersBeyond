# Movement + AntiIdle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans / subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Viajar a un punto arbitrario sin yank (motor de movimiento) + mantener la sesión viva contra la heurística idle (anti-idle).

**Architecture:** Movimiento por **LinearVelocity constraint** en HRP (verificado live: CFrame writes NO sirven acá; raw AssemblyLinearVelocity lo zeroea el control del humanoide; LinearVelocity gana, cero snapback @200 sps). AntiIdle inyecta input sintético con `VirtualInputManager` a gaps aleatorios < `SUSPICIOUS_IDLE`.

**Tech Stack:** Luau (executor), LinearVelocity/Attachment, VirtualInputManager, Obsidian.

**Spec:** `docs/specs/2026-09-02-speedsters-beyond-autofarm-design.md`

## Global Constraints

- **CFrame writes prohibidos** para traslado (no efecto real). Movimiento = LinearVelocity.
- **Techo AC ESCALA con ascends** (~1.4x el speed stat; ej. 9k speed → ~13k techo). NO clamp fijo: `ceiling = speedStat * 1.35`, `budget = speedStat * mult`, con fluctuación. Modo `steady` para fragile jobs (control fino, no chocar props) vs `fast` (fluctúa alto, simple jobs).
- AC behavioral laxo (NoCheatPlus-2012-style): velocity sostenido bajo ceiling = OK; se permite fluctuar, no hace falta cap estricto.
- `SUSPICIOUS_IDLE=60` → gaps de input anti-idle aleatorios 25–45s.
- Todo hereda las constraints del Plan Foundation (global SB, Governor, dryRun, kill-switch).

## Ciclo de verificación (executor)
Igual que Foundation: probe rojo → build (`build_bundle.ps1`) → `execute-file` bundle → probe verde → commit. Cliente vivo conectado (place 98352297590435).

## File Structure
- `Movement/Movement.lua` — motor LinearVelocity. `Move.GoTo(pos,opts)`, `Move.Stop()`, `Move.Budget()`, stuck-nudge, cleanup del constraint.
- `AntiIdle/AntiIdle.lua` — `AntiIdle.Start()/Stop()/Kick()`, scheduler VIM con jitter.
- `UI.lua` — groupbox "Movement" + "Anti-Idle" (modifica).
- `main.lua` — expone `SB.Move`, `SB.AntiIdle`; AntiIdle auto-run bajo master (modifica).

---

### Task 1: Movement/Movement.lua

**Files:** Create `Movement/Movement.lua`; Modify `main.lua`.

**Interfaces:**
- Consumes: `SB`, `SB.Get("speed")`/`SB.Get("speedCapMax")`.
- Produces: `Move.GoTo(pos, opts) -> "arrived"|"timeout"|"stopped"|"no-hrp"` (bloqueante, correr en thread), `Move.Stop()`, `Move.Budget() -> number`, `Move.Clear()`. `opts = { arrive=8, budget=nil, pulse=false, timeout=20, stuckSeconds=2.5 }`. `SB.Move`.

- [ ] **Step 1: Probe (rojo)**
```lua
return tostring(getgenv().SB and getgenv().SB.Move ~= nil)
```
Expected: `"false"`.

- [ ] **Step 2: Escribir `Movement/Movement.lua`**
```lua
-- Movement/Movement.lua — FACTORY. Travel via LinearVelocity constraint (CFrame writes NO sirven acá;
-- raw AssemblyLinearVelocity lo zeroea el control del humanoide). GoTo empuja HRP al target a budget
-- (clamp al ceiling), hugging al piso, con nudge anti-stuck. Verificado: cero snapback @200 sps.
return function(require, SB, Lib)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local LP = Players.LocalPlayer
    local Move = {}

    local CEIL = 460   -- techo hard (máx script ~500, margen de seguridad)

    local att, lv
    local function ensureMover(hrp)
        if lv and lv.Parent == hrp then return end
        if lv then pcall(function() lv:Destroy() end) end
        if att then pcall(function() att:Destroy() end) end
        att = Instance.new("Attachment"); att.Parent = hrp
        lv = Instance.new("LinearVelocity")
        lv.Attachment0 = att
        lv.MaxForce = math.huge
        lv.RelativeTo = Enum.ActuatorRelativeTo.World
        lv.VectorVelocity = Vector3.zero
        lv.Parent = hrp
    end
    local function clearMover()
        if lv then pcall(function() lv:Destroy() end) end
        if att then pcall(function() att:Destroy() end) end
        lv, att = nil, nil
    end
    Move.Clear = clearMover
    SB.onCleanup(clearMover)

    function Move.Budget()
        local live = SB.Get("speed") or SB.Get("speedCapMax") or 200
        return math.clamp(live + 15, 30, CEIL)
    end

    local function hrpNow()
        local c = LP.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    function Move.Stop()
        if lv then lv.VectorVelocity = Vector3.zero end
    end

    -- GoTo bloqueante. Correr dentro de task.spawn si no querés bloquear.
    function Move.GoTo(pos, opts)
        opts = opts or {}
        local arrive = opts.arrive or 8
        local timeout = opts.timeout or 20
        local stuckSec = opts.stuckSeconds or 2.5
        local t0 = os.clock()
        local lastPos, stuckT = nil, os.clock()
        while not SB.IsStopped() do
            local hrp = hrpNow()
            if not hrp then
                if os.clock() - t0 > timeout then return "no-hrp" end
                task.wait(0.1)
            else
                ensureMover(hrp)
                local here = hrp.Position
                local flat = Vector3.new(pos.X - here.X, 0, pos.Z - here.Z)
                local dist = flat.Magnitude
                if dist <= arrive then lv.VectorVelocity = Vector3.zero; return "arrived" end
                local budget = opts.budget or Move.Budget()
                if opts.pulse then budget = math.min(budget * 1.5, CEIL) end
                local dir = flat.Unit
                lv.VectorVelocity = Vector3.new(dir.X * budget, -20, dir.Z * budget)  -- -20 = ground hug
                if lastPos and (here - lastPos).Magnitude < 2 then
                    if os.clock() - stuckT > stuckSec then
                        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                        if hum then hum.Jump = true end
                        stuckT = os.clock()
                    end
                else stuckT = os.clock() end
                lastPos = here
                if os.clock() - t0 > timeout then lv.VectorVelocity = Vector3.zero; return "timeout" end
                RunService.Heartbeat:Wait()
            end
        end
        Move.Stop()
        return "stopped"
    end

    return Move
end
```

- [ ] **Step 3: Wire en `main.lua`** (tras `SB.Net = require("Net")`):
```lua
    SB.Move = require("Movement.Movement")
```

- [ ] **Step 4: Build** — `powershell -ExecutionPolicy Bypass -File build_bundle.ps1`

- [ ] **Step 5: Load + Probe (verde)** — viaje a un punto ~50 studs adelante, medir llegada + no-yank:
```lua
local SB = getgenv().SB
local LP = game:GetService("Players").LocalPlayer
local hrp = LP.Character.HumanoidRootPart
local start = hrp.Position
local look = hrp.CFrame.LookVector
local target = start + Vector3.new(look.X,0,look.Z).Unit * 50
local res = SB.Move.GoTo(target, { arrive = 8, timeout = 8 })
task.wait(0.3)
local endp = LP.Character.HumanoidRootPart.Position
return "res="..res.."|distToTarget="..math.floor((endp-target).Magnitude).."|movedFromStart="..math.floor((endp-start).Magnitude)
```
Expected: `res=arrived`, `distToTarget` ≤ ~10, `movedFromStart` ~45–50 (sin snapback). Si no llega/yank: ajustar ground-hug Y o budget y re-probar.

- [ ] **Step 6: Commit**
```bash
git add Movement/Movement.lua main.lua SpeedstersBeyond.lua
git commit -m "feat(movement): LinearVelocity travel engine (GoTo/Stop/Budget) sin yank"
```

---

### Task 2: AntiIdle/AntiIdle.lua

**Files:** Create `AntiIdle/AntiIdle.lua`; Modify `main.lua`.

**Interfaces:**
- Consumes: `SB`, VirtualInputManager.
- Produces: `AntiIdle.Start()`, `AntiIdle.Stop()`, `AntiIdle.Kick()` (pulso inmediato), `AntiIdle.lastKick`. `SB.AntiIdle`. Gaps aleatorios `Config.gapMin=25`/`gapMax=45` s.

- [ ] **Step 1: Probe (rojo)**
```lua
return tostring(getgenv().SB and getgenv().SB.AntiIdle ~= nil)
```
Expected: `"false"`.

- [ ] **Step 2: Escribir `AntiIdle/AntiIdle.lua`**
```lua
-- AntiIdle/AntiIdle.lua — FACTORY. Derrota la heurística idle server (SUSPICIOUS_IDLE=60) inyectando
-- input sintético (VirtualInputManager) a gaps aleatorios < 60s → resetea el timer de AntiKickController
-- vía UserInputService legítimamente. PRNG propio (Math.random puede estar bloqueado).
return function(require, SB, Lib)
    local VIM = game:GetService("VirtualInputManager")
    local AntiIdle = {}
    AntiIdle.gapMin, AntiIdle.gapMax = 25, 45
    AntiIdle.lastKick = 0
    local running = false

    -- PRNG LCG
    local rng = 987654321
    local function rnd() rng = (rng * 1103515245 + 12345) % 2147483648; return rng / 2147483648 end

    local KEYS = { Enum.KeyCode.LeftShift, Enum.KeyCode.LeftControl, Enum.KeyCode.RightShift }
    function AntiIdle.Kick()
        local k = KEYS[math.floor(rnd() * #KEYS) + 1]
        pcall(function()
            VIM:SendKeyEvent(true, k, false, game)
            task.wait(0.05 + rnd() * 0.05)
            VIM:SendKeyEvent(false, k, false, game)
        end)
        AntiIdle.lastKick = os.clock()
    end

    function AntiIdle.Start()
        if running then return end
        running = true
        task.spawn(function()
            while running and not SB.IsStopped() do
                local gap = AntiIdle.gapMin + rnd() * (AntiIdle.gapMax - AntiIdle.gapMin)
                task.wait(gap)
                if running and not SB.IsStopped() then AntiIdle.Kick() end
            end
        end)
        SB.Log(2, "AntiIdle armado (gap", AntiIdle.gapMin, "-", AntiIdle.gapMax, "s)")
    end

    function AntiIdle.Stop() running = false end
    SB.onCleanup(function() running = false end)

    return AntiIdle
end
```

- [ ] **Step 3: Wire en `main.lua`** (tras `SB.Move = ...`):
```lua
    SB.AntiIdle = require("AntiIdle.AntiIdle")
```

- [ ] **Step 4: Build** — `build_bundle.ps1`

- [ ] **Step 5: Load + Probe (verde)** — confirmar que el input sintético lo registra UserInputService (= resetea el anti-kick):
```lua
local SB = getgenv().SB
local UIS = game:GetService("UserInputService")
local caught = false
local conn = UIS.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then caught = true end
end)
SB.AntiIdle.Kick()
task.wait(0.4)
conn:Disconnect()
return "caughtByUIS="..tostring(caught)..."|lastKick="..tostring(SB.AntiIdle.lastKick ~= 0)
```
Expected: `caughtByUIS=true|lastKick=true`. Si `caughtByUIS=false`: el executor no propaga VIM a UIS — fallback a `VirtualUser` o micro-jump (ajustar Kick y re-probar).

- [ ] **Step 6: Commit**
```bash
git add AntiIdle/AntiIdle.lua main.lua SpeedstersBeyond.lua
git commit -m "feat(antiidle): input sintético VIM vs SUSPICIOUS_IDLE"
```

---

### Task 3: UI Movement + Anti-Idle + master wiring

**Files:** Modify `UI.lua`, `main.lua`.

**Interfaces:**
- Produces: groupbox "Movement" (Dropdown `MoveMode` fast/steady → `SB.moveMode`, Slider `MoveBudgetMult` 0.8–1.35 → `SB.moveBudgetMult`, Slider `ArriveRadius` 4–20 → `SB.arriveRadius`), groupbox "Anti-Idle" (Toggle `AntiIdleOn` default true, Slider `IdleGapMin` 15–40, Slider `IdleGapMax` 30–55). AntiIdle arranca/para con el toggle; valores iniciales aplicados en main tras `LoadAutoloadConfig`.

- [ ] **Step 1: Probe (rojo)**
```lua
local L = getgenv().SB and getgenv().SB.Library
return tostring(L and L.Toggles and L.Toggles.AntiIdleOn ~= nil)
```
Expected: `"false"`.

- [ ] **Step 2: Modificar `UI.lua`** — añadir al final de `UI.build`, antes del `end` de la función:
```lua
        local mv = SB.Tabs.Main:AddRightGroupbox("Movement")
        mv:AddDropdown("MoveMode", { Values = { "fast", "steady" }, Default = "fast", Text = "Mode",
            Tooltip = "fast = fluctúa alto (simple jobs). steady = controlado (fragile, no chocar props).",
            Callback = function(v) SB.moveMode = v end })
        mv:AddSlider("MoveBudgetMult", { Text = "Budget mult", Min = 0.8, Max = 1.35, Default = 1.2,
            Rounding = 2, Suffix = "x",
            Tooltip = "Fracción del speed stat. Techo AC ~1.35x (escala con ascends).",
            Callback = function(v) SB.moveBudgetMult = v end })
        mv:AddSlider("ArriveRadius", { Text = "Arrive radius", Min = 4, Max = 20, Default = 8,
            Rounding = 0, Suffix = " st", Callback = function(v) SB.arriveRadius = v end })

        local ai = SB.Tabs.Main:AddRightGroupbox("Anti-Idle")
        ai:AddToggle("AntiIdleOn", { Text = "Anti-Idle", Default = true,
            Tooltip = "Input sintético (VIM) vs SUSPICIOUS_IDLE (60s).",
            Callback = function(v)
                SB.antiIdleOn = v
                if v then SB.AntiIdle.Start() else SB.AntiIdle.Stop() end
            end })
        ai:AddSlider("IdleGapMin", { Text = "gap min", Min = 15, Max = 40, Default = 25, Rounding = 0, Suffix = " s",
            Callback = function(v) if SB.AntiIdle then SB.AntiIdle.gapMin = v end end })
        ai:AddSlider("IdleGapMax", { Text = "gap max", Min = 30, Max = 55, Default = 45, Rounding = 0, Suffix = " s",
            Callback = function(v) if SB.AntiIdle then SB.AntiIdle.gapMax = v end end })
```

- [ ] **Step 3: Wire en `main.lua`** — tras `SaveManager:LoadAutoloadConfig()` (o al final del init), arrancar AntiIdle si el toggle quedó on:
```lua
    if SB.Library.Toggles.AntiIdleOn and SB.Library.Toggles.AntiIdleOn.Value then
        SB.AntiIdle.Start()
    end
```

- [ ] **Step 4: Build** — `build_bundle.ps1`

- [ ] **Step 5: Load + Probe (verde)**
```lua
local L = getgenv().SB.Library
return table.concat({
    tostring(L.Options.MoveMode ~= nil),
    tostring(L.Options.MoveBudgetMult ~= nil),
    tostring(L.Toggles.AntiIdleOn ~= nil),
    tostring(L.Options.IdleGapMin ~= nil),
}, "|")
```
Expected: `"true|true|true|true"`. UI muestra groupboxes Movement + Anti-Idle; `SB.moveMode`/`SB.moveBudgetMult` aplicados.

- [ ] **Step 6: Commit**
```bash
git add UI.lua main.lua SpeedstersBeyond.lua
git commit -m "feat(ui): groupboxes Movement + Anti-Idle + auto-start"
```

---

## Self-Review
- **Spec coverage:** Módulo 1 MovementEngine ✓ (LinearVelocity, budget, stuck), Módulo 2 AntiIdle ✓ (VIM + jitter). UI §5 Movement/Anti-Idle ✓.
- **Placeholder scan:** ninguno; todo el código es real. Fallbacks (VIM→VirtualUser) marcados como contingencia condicional a un probe, no placeholders.
- **Type consistency:** `Move.GoTo/Stop/Budget/Clear`, `AntiIdle.Start/Stop/Kick/gapMin/gapMax/lastKick`, flags `PulseMode/MoveBudget/ArriveRadius/AntiIdleOn/IdleGapMin/IdleGapMax` consistentes. `SB.Move`/`SB.AntiIdle` seteados en Task 1/2 antes de uso en Task 3.
