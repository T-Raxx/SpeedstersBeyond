-- SpeedstersBeyond bundle self-contained. No editar a mano (generado por build_bundle.ps1).
local __rawRequire = require
local _MODS = {}
_MODS["Core.State"] = (function()
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

end)()
_MODS["Net"] = (function()
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

end)()
_MODS["Movement.Movement"] = (function()
-- Movement/Movement.lua — FACTORY. Travel via LinearVelocity constraint (CFrame writes NO sirven acá;
-- raw AssemblyLinearVelocity lo zeroea el control del humanoide). Verificado: cero snapback @200 sps.
--
-- BUDGET DINÁMICO: el techo del AC serverside ESCALA con ascends (~1.4x el speed stat; usuario: 9k→13k),
-- así que NO clampeamos a un número fijo. techo = speedStat * HEADROOM, budget = speedStat * mult, con
-- FLUCTUACIÓN (señal no-plana, y empuja alto en simple jobs). Modo "steady" (fragile jobs: velocidad
-- controlada, desaceleración fuerte cerca del target para no chocar props) vs "fast" (default, fluctúa alto).
return function(require, SB, Lib)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local LP = Players.LocalPlayer
    local Move = {}

    local HEADROOM = 1.35   -- techo relativo al speed stat (escala con ascends; ~9k→13k≈1.44 → 1.35 margen)
    local FLOOR = 30

    -- PRNG para fluctuación (Math.random puede estar bloqueado)
    local rng = 20260902
    local function rnd() rng = (rng * 1103515245 + 12345) % 2147483648; return rng / 2147483648 end

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

    local function base() return SB.Get("speed") or SB.Get("speedCapMax") or 200 end
    function Move.Ceiling() return base() * HEADROOM end
    function Move.Budget()
        if SB.moveMode == "steady" then return math.clamp(base() * 0.92, FLOOR, Move.Ceiling()) end
        return math.clamp(base() * (SB.moveBudgetMult or 1.2), FLOOR, Move.Ceiling())
    end

    local function hrpNow()
        local c = LP.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    -- Stop DESTRUYE el constraint (no solo zeroea): un LinearVelocity con MaxForce=huge y
    -- VectorVelocity=0 PINEA la velocidad a 0 → el char queda atascado (ni el juego lo mueve).
    function Move.Stop()
        clearMover()
    end

    -- GoTo bloqueante. Correr dentro de task.spawn si no querés bloquear.
    -- opts: { arrive=8, budget=nil, mode=nil("fast"|"steady"), timeout=20, stuckSeconds=2.5 }
    function Move.GoTo(pos, opts)
        opts = opts or {}
        local arrive = opts.arrive or 8
        local timeout = opts.timeout or 20
        local stuckSec = opts.stuckSeconds or 2.5
        local mode = opts.mode or SB.moveMode or "fast"
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
                if dist <= arrive then clearMover(); return "arrived" end
                local budget = opts.budget or Move.Budget()
                local ceil = Move.Ceiling()
                if mode ~= "steady" then
                    budget = math.min(budget * (0.9 + rnd() * 0.25), ceil)   -- fluctuación (no-plana, empuja alto)
                end
                local slow = (mode == "steady") and 40 or 22                 -- desaceleración cerca del target
                if dist < slow then budget = math.max(FLOOR, budget * math.clamp(dist / slow, 0.35, 1)) end
                local dir = flat.Unit
                -- VUELO sobre terreno: sube a altitud crucero mientras viaja (limpia colinas/paredes que
                -- atascaban el horizontal puro), desciende al target al acercarse. El AC rubberbandea horizontal,
                -- no vertical → volar es seguro. Y proporcional (control suave), clamp.
                local cruise = math.max(here.Y, pos.Y) + 28
                local desiredY = (dist > (arrive + 15)) and cruise or pos.Y
                local yVel = math.clamp((desiredY - here.Y) * 3, -90, 90)
                lv.VectorVelocity = Vector3.new(dir.X * budget, yVel, dir.Z * budget)
                if lastPos and (here - lastPos).Magnitude < 2 then
                    if os.clock() - stuckT > stuckSec then
                        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                        if hum then hum.Jump = true end
                        stuckT = os.clock()
                    end
                else stuckT = os.clock() end
                lastPos = here
                if os.clock() - t0 > timeout then clearMover(); return "timeout" end
                RunService.Heartbeat:Wait()
            end
        end
        Move.Stop()
        return "stopped"
    end

    return Move
end

end)()
_MODS["AntiIdle.AntiIdle"] = (function()
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

end)()
_MODS["Jobs.Jobs"] = (function()
-- Jobs/Jobs.lua — FACTORY. Deliveries autofarm (mecánica confirmada live).
-- GoTo JobsPart → fire tier button → phase claimed+drop → GoTo drop (→running→banca) → chain → claim.
return function(require, SB, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Jobs = {}
    local running = false

    local JobsConfig = require(game:GetService("ReplicatedStorage").Modules.Config.JobsConfig)
    local function JC() return require(LP.PlayerScripts.Controllers.JobsController) end

    -- Slots de chain disponibles por ascensión (CHAIN_SLOT_ASCENSIONS = {0,0,10,25}):
    -- 2 slots (<asc10), 3 (asc10-24), 4 (asc25+).
    function Jobs.AvailableSlots()
        local asc = SB.Get("ascensions") or 0
        local n = 0
        for _, th in ipairs(JobsConfig.CHAIN_SLOT_ASCENSIONS or { 0, 0, 10, 25 }) do
            if asc >= th then n = n + 1 end
        end
        return math.max(1, n)
    end
    local function jobsPartPos()
        local p = workspace:FindFirstChild("JobsPart", true)
        return p and p.Position
    end
    local function panel()
        local pg = LP:FindFirstChild("PlayerGui")
        local uis = pg and pg:FindFirstChild("Uis")
        return uis and uis:FindFirstChild("Jobs")
    end
    local function fire(btn)
        if not btn then return false end
        local n = 0
        for _, c in ipairs(getconnections(btn.Activated)) do pcall(function() c:Fire() end); n = n + 1 end
        return n > 0
    end

    -- Easy=JobFrame, Med=JobFrame1, Hard=JobFrame2
    local TIER_FRAME = { [1] = "JobFrame", [2] = "JobFrame1", [3] = "JobFrame2" }
    function Jobs.BestTier()
        if SB.jobsTier and SB.jobsTier ~= "auto" then return tonumber(SB.jobsTier) or 1 end
        local asc = SB.Get("ascensions") or 0
        if asc >= 10 then return 3 elseif asc >= 4 then return 2 else return 1 end
    end

    local function tierButton(idx)
        local pnl = panel(); if not pnl then return nil end
        local frame = pnl:FindFirstChild(TIER_FRAME[idx]); if not frame then return nil end
        local locked = frame:FindFirstChild("Locked")
        if locked and locked.Visible then return nil end
        return frame:FindFirstChild("Button")
    end
    local function claimButton()
        local pnl = panel(); if not pnl then return nil end
        local pf = pnl:FindFirstChild("ProgressFrame")
        return pf and pf:FindFirstChild("TextButton")
    end

    -- Tipo de entrega: "Simple" (directo, puede romper props) | "Fragile" (NO chocar props → steady).
    -- El label CurrentJob muestra "Simple Delivery"/"Fragile Delivery"; ButtonNext cicla el tipo.
    function Jobs.SetType(desired)
        desired = desired or "Simple"
        local pnl = panel(); if not pnl then return end
        local label = pnl:FindFirstChild("CurrentJob", true)
        local nf = pnl:FindFirstChild("ButtonNext", true)
        local nextB = nf and (nf:IsA("TextButton") and nf or nf:FindFirstChildWhichIsA("TextButton"))
        if not (label and nextB) then return end
        for _ = 1, 3 do
            if label.Text:find(desired) then return end
            fire(nextB)
            task.wait(0.3)
        end
    end

    local function gotoZone()
        local pos = jobsPartPos(); if not pos then return false end
        -- si estamos lejos (fin de delivery a miles de studs) → ReturnToSpawn (teleport server-side
        -- a spawn, ~53 studs de JobsPart) en vez del viaje largo de vuelta.
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp and (Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)).Magnitude > 150 then
            SB.Net.Fire("ReturnToSpawn")
            task.wait(1)
        end
        SB.Move.GoTo(pos, { arrive = 12, timeout = 15, mode = "fast" })
        SB.Move.Stop()
        task.wait(3.5)   -- dwell: server zone confirm = SERVER_STRIKES(3) x SERVER_INTERVAL(1s) ≈ 3s
        return true
    end

    -- Una vuelta: si banked>=claimAt claim; aceptar tier; correr chain hasta phase idle.
    function Jobs.RunCycle()
        local jc = JC()
        local fragile = (SB.jobsType == "Fragile")
        -- Si NO hay chain activo → ir a zona, claim si toca, y SELECCIONAR X jobs (llenar slots).
        -- Si YA hay legs (chain en progreso, tiers "In Progress" locked) → saltar accept y correrlos.
        if jc:GetLegCount() == 0 then
            if not gotoZone() then return "no-zone" end
            if jc:GetBankedCount() >= (SB.jobsClaimAt or 40) then fire(claimButton()); task.wait(1) end
            Jobs.SetType(SB.jobsType or "Simple")
            local btn = tierButton(Jobs.BestTier())
            if not btn then return "tier-locked" end
            local want = math.min(Jobs.AvailableSlots(), SB.jobsBatch or 99)
            local fills = 0
            -- Selección a ~1.7/s (máx confiable con lag; más rápido dropea fires → slots sin llenar).
            -- Tunable por SB.jobsSelectDelay (slider). Confirma por GetLegCount, no por # de fires.
            while jc:GetLegCount() < want and fills < want + 5 do
                fire(btn); task.wait(SB.jobsSelectDelay or 0.58); fills = fills + 1
            end
        end
        -- correr el batch: GoTo cada drop hasta idle (arranca al salir de zona → phase running)
        local guard = 0
        while not SB.IsStopped() and jc:GetPhase() ~= "idle" and guard < 16 do
            local dp = jc:GetDropPoint()
            if typeof(dp) ~= "Vector3" then break end
            SB.Move.GoTo(dp, { arrive = 15, timeout = 30, mode = fragile and "steady" or (SB.moveMode or "fast") })
            task.wait(0.15)   -- banca + próximo leg (snappy; FPS drops OK)
            guard = guard + 1
        end
        if jc:GetBankedCount() >= (SB.jobsClaimAt or 40) then gotoZone(); fire(claimButton()); task.wait(1) end
        return "cycle-done"
    end

    function Jobs.Start()
        if running then return end
        running = true
        task.spawn(function()
            while running and not SB.IsStopped() do
                if SB.masterOn and SB.jobsOn and not SB.ascending then
                    local ok, err = pcall(Jobs.RunCycle)
                    if not ok then SB.Log(1, "Jobs cycle err:", err) end
                else
                    task.wait(0.2)
                end
                task.wait(0.05)
            end
        end)
        SB.Log(2, "JobsFarm armado")
    end
    function Jobs.Stop() running = false; SB.Move.Stop() end
    SB.onCleanup(function() running = false end)

    return Jobs
end

end)()
_MODS["Treadmill.Treadmill"] = (function()
-- Treadmill/Treadmill.lua — FACTORY. Park en el mejor pad elegible (por ascensión) → EXP pasivo.
-- Pads en workspace folder "Treadmills" (x2..x10). Elegibilidad: minAscensions de TreadmillConfig.
return function(require, SB, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Treadmill = {}
    local running = false

    local TC = require(game:GetService("ReplicatedStorage").Modules.Config.TreadmillConfig)

    local function padsFolder()
        return workspace:FindFirstChild("Treadmills", true)
    end

    -- mejor pad elegible por multiplier (asc-gated; ignora gamepass salvo override)
    function Treadmill.BestPad()
        local folder = padsFolder(); if not folder then return nil end
        if SB.treadmillPad and SB.treadmillPad ~= "auto" then
            local p = folder:FindFirstChild(SB.treadmillPad)
            return SB.treadmillPad, (p and p:IsA("BasePart") and p.Position or nil)
        end
        local asc = SB.Get("ascensions") or 0
        local best, bestMult, bestPos
        for name, cfg in pairs(TC.pads) do
            local eligible = (not cfg.gamepass) and asc >= (cfg.minAscensions or 0)
            local part = folder:FindFirstChild(name)
            local pos = part and part:IsA("BasePart") and part.Position
            if eligible and pos and cfg.multiplier > (bestMult or -1) then
                best, bestMult, bestPos = name, cfg.multiplier, pos
            end
        end
        return best, bestPos
    end

    function Treadmill.Start()
        if running then return end
        running = true
        task.spawn(function()
            while running and not SB.IsStopped() do
                if SB.masterOn and SB.treadmillOn and not SB.ascending then
                    local name, pos = Treadmill.BestPad()
                    if pos then
                        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                        local tol = TC.STAND_TOLERANCE or 6
                        if hrp and (Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)).Magnitude > tol then
                            SB.Move.GoTo(pos, { arrive = 4, timeout = 15, mode = "steady" })
                        else
                            SB.Move.Stop()   -- ya en el pad → quieto (AntiIdle mantiene vivo)
                        end
                    end
                end
                task.wait(0.5)
            end
        end)
        SB.Log(2, "TreadmillFarm armado")
    end
    function Treadmill.Stop() running = false; SB.Move.Stop() end
    SB.onCleanup(function() running = false end)

    return Treadmill
end

end)()
_MODS["Ascension.Ascension"] = (function()
-- Ascension/Ascension.lua — FACTORY. Auto-ascend cuando level>=levelCap. AscensionController:Ascend() público.
return function(require, SB, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Ascension = {}
    local running = false

    local function AC() return require(LP.PlayerScripts.Controllers.AscensionController) end
    local function UIC() return require(LP.PlayerScripts.Controllers.UIController) end
    local function ascendHoldButton()
        local panel = LP.PlayerGui:FindFirstChild("Uis") and LP.PlayerGui.Uis:FindFirstChild("Ascend")
        if not panel then return nil end
        for _, d in ipairs(panel:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Name == "Ascend" then return d end
        end
    end

    function Ascension.Ready()
        local lvl, cap = SB.Get("level"), SB.Get("levelCap")
        if not (lvl and cap) then return false end
        if (SB.ascendTarget or 0) > 0 and (SB.Get("ascensions") or 0) >= SB.ascendTarget then return false end
        return lvl >= cap
    end

    -- Ascend LEGIT: abrir panel + HOLDear el botón (beginHold en MouseButton1Down → llena barra →
    -- al completar dispara Ascend() = AscendRequest). Un fire pelado a veces no basta (el server puede
    -- gatear por el hold). Fallback: Ascend() directo. Duración de hold generosa (2.6s > barra).
    function Ascension.AscendNow()
        SB.ascending = true
        SB.Move.Stop()
        local before = SB.Get("ascensions") or 0
        local ok, err = pcall(function()
            UIC():Open("Ascend")
            task.wait(0.4)
            local btn = ascendHoldButton()
            if btn then
                for _, c in ipairs(getconnections(btn.MouseButton1Down)) do pcall(function() c:Fire() end) end
                task.wait(2.6)   -- hold hasta que la barra llene → beginHold completa → Ascend()
                for _, c in ipairs(getconnections(btn.MouseButton1Up)) do pcall(function() c:Fire() end) end
            end
            task.wait(0.5)
            pcall(function() AC():Ascend() end)   -- fallback fire directo
            pcall(function() UIC():Close("Ascend") end)
        end)
        if not ok then SB.Log(1, "Ascend err:", err) end
        task.wait(2)          -- transición + AscensionChanged
        SB.RefreshState(true)
        SB.ascending = false
        local now = SB.Get("ascensions") or 0
        SB.Log(2, "Ascend intento — ascensions", before, "->", now, now > before and "(OK)" or "(sin cambio)")
    end

    function Ascension.Start()
        if running then return end
        running = true
        task.spawn(function()
            while running and not SB.IsStopped() do
                if SB.masterOn and SB.ascendAuto and Ascension.Ready() and not SB.ascending then
                    Ascension.AscendNow()
                end
                task.wait(1)
            end
        end)
        SB.Log(2, "AscensionMgr armado")
    end
    function Ascension.Stop() running = false end
    SB.onCleanup(function() running = false end)

    return Ascension
end

end)()
_MODS["Economy.Quests"] = (function()
-- Economy/Quests.lua — FACTORY. Auto-collect quests completadas (progress>=amount, no collected)
-- vía botón QuestFrame{i}.TextButton del panel Uis.Quests. Sin zona; corre en paralelo al farm.
return function(require, SB, Lib)
    local LP = game:GetService("Players").LocalPlayer
    local Quests = {}
    local running = false

    local function panel()
        local uis = LP.PlayerGui:FindFirstChild("Uis")
        return uis and uis:FindFirstChild("Quests")
    end
    local function fire(btn)
        if not btn then return end
        for _, c in ipairs(getconnections(btn.Activated)) do pcall(function() c:Fire() end) end
    end

    function Quests.CollectAll()
        local snap = SB.Net.Invoke("GetQuestsSnapshot")
        if not (snap and snap.quests) then return 0 end
        local pnl = panel(); if not pnl then return 0 end
        local n = 0
        for i, q in pairs(snap.quests) do
            if q.progress and q.amount and q.progress >= q.amount and not q.collected then
                local qf = pnl:FindFirstChild("QuestFrame" .. tostring(i), true)
                local btn = qf and qf:FindFirstChild("TextButton")
                if btn then fire(btn); n = n + 1; task.wait(0.3) end
            end
        end
        if n > 0 then SB.Log(2, "Quests: colectadas", n) end
        return n
    end

    function Quests.Start()
        if running then return end
        running = true
        task.spawn(function()
            while running and not SB.IsStopped() do
                if SB.masterOn and SB.questsOn then pcall(Quests.CollectAll) end
                task.wait(SB.questsInterval or 20)
            end
        end)
        SB.Log(2, "Quests auto-collect armado")
    end
    function Quests.Stop() running = false end
    SB.onCleanup(function() running = false end)

    return Quests
end

end)()
_MODS["Economy.Rewards"] = (function()
-- Economy/Rewards.lua — FACTORY. Auto-claim PlayTime rewards (time-gated: unlockAt<=now, no claimed)
-- vía Presents.{i}.ButtonClaim del panel Uis.PlayTimeRewards. FreeRewards NO (task-gated: like/group = social).
return function(require, SB, Lib)
    local LP = game:GetService("Players").LocalPlayer
    local Rewards = {}
    local running = false

    local function fire(btn)
        if not btn then return end
        for _, c in ipairs(getconnections(btn.Activated)) do pcall(function() c:Fire() end) end
    end
    local function ptPanel()
        local u = LP.PlayerGui:FindFirstChild("Uis")
        return u and u:FindFirstChild("PlayTimeRewards")
    end

    function Rewards.ClaimPlayTime()
        local snap = SB.Net.Invoke("GetPlayTimeRewardsSnapshot")
        if type(snap) ~= "table" then return 0 end
        local pnl = ptPanel(); if not pnl then return 0 end
        local presents = pnl:FindFirstChild("Presents", true)
        if not presents then return 0 end
        local now = os.time()
        local n = 0
        for i, tier in pairs(snap) do
            if type(tier) == "table" and not tier.claimed and tier.unlockAt and now >= tier.unlockAt then
                local frame = presents:FindFirstChild(tostring(i))
                local btn = frame and frame:FindFirstChild("ButtonClaim")
                if btn then fire(btn); n = n + 1; task.wait(0.3) end
            end
        end
        if n > 0 then SB.Log(2, "PlayTime rewards claimed:", n) end
        return n
    end

    function Rewards.Start()
        if running then return end
        running = true
        task.spawn(function()
            while running and not SB.IsStopped() do
                if SB.masterOn and SB.rewardsOn then pcall(Rewards.ClaimPlayTime) end
                task.wait(SB.rewardsInterval or 30)
            end
        end)
        SB.Log(2, "Rewards auto-claim armado")
    end
    function Rewards.Stop() running = false end
    SB.onCleanup(function() running = false end)

    return Rewards
end

end)()
_MODS["Economy.Upgrades"] = (function()
-- Economy/Upgrades.lua — FACTORY. Auto-buy upgrades (SpeedN/SpeedT/PointsB) — sube ranks si asequible.
-- Sin zona (verificado: compra desde cualquier lado). El botón no-op si no alcanza → seguro spamear.
-- Corre en paralelo al farm (no requiere posición). Drena points en upgrades (sinergia EXP/speed).
return function(require, SB, Lib)
    local LP = game:GetService("Players").LocalPlayer
    local Upgrades = {}
    local running = false
    local TRACKS = { "MainFrameSpeedN", "MainFrameSpeedT", "MainFramePointsB" }

    local function panel()
        local u = LP.PlayerGui:FindFirstChild("Uis")
        return u and u:FindFirstChild("Upgrades")
    end
    local function fire(btn)
        if not btn then return end
        for _, c in ipairs(getconnections(btn.Activated)) do pcall(function() c:Fire() end) end
    end

    function Upgrades.BuyAffordable(rounds)
        local pnl = panel(); if not pnl then return end
        for _ = 1, (rounds or 3) do
            for _, name in ipairs(TRACKS) do
                local f = pnl:FindFirstChild(name, true)
                local ub = f and f:FindFirstChild("UpgradeButton")
                local btn = ub and ub:FindFirstChild("Button")
                fire(btn); task.wait(0.15)
            end
        end
    end

    function Upgrades.Start()
        if running then return end
        running = true
        task.spawn(function()
            while running and not SB.IsStopped() do
                if SB.masterOn and SB.upgradesOn then pcall(function() Upgrades.BuyAffordable(3) end) end
                task.wait(SB.upgradesInterval or 15)
            end
        end)
        SB.Log(2, "Upgrades auto-buy armado")
    end
    function Upgrades.Stop() running = false end
    SB.onCleanup(function() running = false end)

    return Upgrades
end

end)()
_MODS["Safety.Governor"] = (function()
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

end)()
_MODS["UI"] = (function()
-- UI.lua — FACTORY. Construye tabs/groupboxes Obsidian + controles globales.
-- Flags en Lib.Toggles / Lib.Options. Sin lógica de farm (solo wiring).
return function(require, SB, Lib)
    local UI = {}

    function UI.build(Window, Library)
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
        box:AddButton({ Text = "Unload", Func = function() SB.Unload() end })
        box:AddDivider()
        -- Panic key = End (NO RightControl: ese es el toggle de menú de Obsidian → colisiona y
        -- ocultar el menú unloadearía todo). El menú se oculta con RightControl (Obsidian) sin unload.
        box:AddLabel("Panic Key"):AddKeyPicker("PanicKey", {
            Default = "End", Mode = "Toggle", Text = "Panic (unload)",
            Callback = function() SB.Unload() end,
        })

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
        ai:AddSlider("IdleGapMin", { Text = "gap min", Min = 15, Max = 40, Default = 25, Rounding = 0,
            Suffix = " s", Callback = function(v) if SB.AntiIdle then SB.AntiIdle.gapMin = v end end })
        ai:AddSlider("IdleGapMax", { Text = "gap max", Min = 30, Max = 55, Default = 45, Rounding = 0,
            Suffix = " s", Callback = function(v) if SB.AntiIdle then SB.AntiIdle.gapMax = v end end })

        local farm = SB.Tabs.Main:AddLeftGroupbox("Farm")
        farm:AddDropdown("FarmMode", { Values = { "Jobs", "Treadmill" }, Default = "Jobs", Text = "Mode",
            Tooltip = "Jobs y Treadmill son exclusivos por posición.",
            Callback = function(v)
                SB.farmMode = v
                SB.jobsOn = (v == "Jobs")
                SB.treadmillOn = (v == "Treadmill")
            end })
        farm:AddDropdown("JobsTier", { Values = { "auto", "1", "2", "3" }, Default = "auto", Text = "Jobs tier",
            Tooltip = "auto = mejor por ascensión (1=Easy,2=Med,3=Hard).",
            Callback = function(v) SB.jobsTier = v end })
        farm:AddDropdown("JobsType", { Values = { "Simple", "Fragile" }, Default = "Simple", Text = "Jobs type",
            Tooltip = "Fragile = no chocar props (usa modo steady).",
            Callback = function(v) SB.jobsType = v end })
        farm:AddSlider("JobsClaimAt", { Text = "Claim at", Min = 1, Max = 50, Default = 40, Rounding = 0,
            Callback = function(v) SB.jobsClaimAt = v end })
        farm:AddSlider("JobsSelectDelay", { Text = "Select delay", Min = 0.1, Max = 1, Default = 0.58,
            Rounding = 2, Suffix = "s",
            Tooltip = "Delay entre selección de jobs. 0.58s ≈ 1.7/s (máx confiable con lag). Menor = más rápido pero puede dropear fires.",
            Callback = function(v) SB.jobsSelectDelay = v end })
        farm:AddDropdown("TreadmillPad", { Values = { "auto", "x2", "x3", "x4", "x6", "x10" }, Default = "auto",
            Text = "Treadmill pad", Callback = function(v) SB.treadmillPad = v end })
        farm:AddToggle("AscendAuto", { Text = "Auto-Ascend", Default = true,
            Callback = function(v) SB.ascendAuto = v end })
        farm:AddSlider("AscendTarget", { Text = "Ascend target (0=inf)", Min = 0, Max = 200, Default = 0,
            Rounding = 0, Callback = function(v) SB.ascendTarget = v end })
        farm:AddButton({ Text = "Ascend Now (test)", Func = function()
            if SB.Ascension then task.spawn(SB.Ascension.AscendNow) end
        end })

        local econ = SB.Tabs.Main:AddRightGroupbox("Economy")
        econ:AddToggle("QuestsOn", { Text = "Auto-Quests", Default = true,
            Tooltip = "Colecta quests completadas (sin zona, en paralelo al farm).",
            Callback = function(v) SB.questsOn = v end })
        econ:AddToggle("RewardsOn", { Text = "Auto-Rewards (PlayTime)", Default = true,
            Tooltip = "Claim PlayTime rewards al desbloquearse. FreeRewards NO (requiere like/group).",
            Callback = function(v) SB.rewardsOn = v end })
        econ:AddToggle("UpgradesOn", { Text = "Auto-Upgrades", Default = true,
            Tooltip = "Compra upgrades asequibles (Speed/Points) — drena points en boosts. Sin zona.",
            Callback = function(v) SB.upgradesOn = v end })
    end

    return UI
end

end)()
_MODS["main"] = (function()
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

    SB.Governor = require("Safety.Governor")
    SB.Net = require("Net")
    SB.Move = require("Movement.Movement")
    SB.AntiIdle = require("AntiIdle.AntiIdle")
    SB.Jobs = require("Jobs.Jobs")
    SB.Treadmill = require("Treadmill.Treadmill")
    SB.Ascension = require("Ascension.Ascension")
    SB.Quests = require("Economy.Quests")
    SB.Rewards = require("Economy.Rewards")
    SB.Upgrades = require("Economy.Upgrades")

    local Window = Library:CreateWindow({
        Title = "SpeedstersBeyond",
        Footer = "v" .. SB.version .. " · burner",
        Center = true, AutoShow = true,
        NotifySide = "Right",
    })
    SB.Window = Window
    SB.Tabs = { Main = Window:AddTab("Main", "home") }

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

    -- aplicar valores iniciales de flags de movimiento + arrancar AntiIdle si quedó on
    do
        local T, O = Library.Toggles, Library.Options
        if O.MoveMode then SB.moveMode = O.MoveMode.Value end
        if O.MoveBudgetMult then SB.moveBudgetMult = O.MoveBudgetMult.Value end
        if O.ArriveRadius then SB.arriveRadius = O.ArriveRadius.Value end
        if O.IdleGapMin then SB.AntiIdle.gapMin = O.IdleGapMin.Value end
        if O.IdleGapMax then SB.AntiIdle.gapMax = O.IdleGapMax.Value end
        if T.AntiIdleOn and T.AntiIdleOn.Value then SB.AntiIdle.Start() end
    end

    -- FARM: defaults desde flags + arrancar loops (guardados por masterOn/<x>On/ascending)
    do
        local T, O = Library.Toggles, Library.Options
        SB.farmMode = O.FarmMode and O.FarmMode.Value or "Jobs"
        SB.jobsOn = (SB.farmMode == "Jobs")
        SB.treadmillOn = (SB.farmMode == "Treadmill")
        SB.jobsTier = O.JobsTier and O.JobsTier.Value or "auto"
        SB.jobsType = O.JobsType and O.JobsType.Value or "Simple"
        SB.jobsClaimAt = O.JobsClaimAt and O.JobsClaimAt.Value or 40
        SB.jobsSelectDelay = O.JobsSelectDelay and O.JobsSelectDelay.Value or 0.58
        SB.treadmillPad = O.TreadmillPad and O.TreadmillPad.Value or "auto"
        SB.ascendAuto = T.AscendAuto and T.AscendAuto.Value
        SB.ascendTarget = O.AscendTarget and O.AscendTarget.Value or 0
        SB.questsOn = (T.QuestsOn == nil) and true or T.QuestsOn.Value
        SB.rewardsOn = (T.RewardsOn == nil) and true or T.RewardsOn.Value
        SB.upgradesOn = (T.UpgradesOn == nil) and true or T.UpgradesOn.Value
    end
    SB.Jobs.Start(); SB.Treadmill.Start(); SB.Ascension.Start(); SB.Quests.Start(); SB.Rewards.Start(); SB.Upgrades.Start()

    -- READ INICIAL + REFRESH (StateStore). Fuentes reales confirmadas live:
    --   GetCurrencySnapshot { points(money), speed(stat velocidad = techo budget), safeMode }
    --   GetStatsSnapshot     { level, goal, exp }
    --   GetAscensionSnapshot { ascensions, levelCap, nextLevelCap, speedCap, nextSpeedCap }
    --   GetSpeedCap          { max, cap } (cap seleccionable vivo)
    do
        local Net = SB.Net
        local RunService = game:GetService("RunService")
        local lastRefresh = 0
        local function refreshState(force)
            local now = os.clock()
            if not force and (now - lastRefresh) < 0.5 then return end   -- throttle anti-spam (CurrencyChanged)
            lastRefresh = now
            local cur = Net.Invoke("GetCurrencySnapshot")
            if type(cur) == "table" then
                if cur.points ~= nil then SB.Set("points", cur.points) end
                if cur.speed  ~= nil then SB.Set("speed",  cur.speed)  end
            end
            local st = Net.Invoke("GetStatsSnapshot")
            if type(st) == "table" then
                if st.level ~= nil then SB.Set("level", st.level) end
                if st.goal  ~= nil then SB.Set("expGoal", st.goal) end
            end
            local asc = Net.Invoke("GetAscensionSnapshot")
            if type(asc) == "table" then
                if asc.ascensions   ~= nil then SB.Set("ascensions", asc.ascensions) end
                if asc.levelCap     ~= nil then SB.Set("levelCap", asc.levelCap) end
                if asc.speedCap     ~= nil then SB.Set("speedCapTier", asc.speedCap) end
                if asc.nextSpeedCap ~= nil then SB.Set("nextSpeedCap", asc.nextSpeedCap) end
            end
            local sc = Net.Invoke("GetSpeedCap")
            if type(sc) == "table" and sc.max ~= nil then SB.Set("speedCapMax", sc.max) end
        end
        SB.RefreshState = refreshState
        refreshState(true)
        Net.OnChanged("CurrencyChanged", function() refreshState() end)
        Net.OnChanged("AscensionChanged", function() refreshState() end)
        task.spawn(function()
            while not SB.IsStopped() do
                refreshState()
                task.wait(2)
            end
        end)
    end

    -- MASTER LOOP STUB (las tasks de farm cuelgan de aquí en planes siguientes)
    SB.track(game:GetService("RunService").Heartbeat:Connect(function()
        if SB.IsStopped() or not SB.masterOn then return end
        -- orchestrator tick placeholder (Plan 3)
    end))

    SB.Log(2, "cargado — window listo")
    Library:Notify("SpeedstersBeyond cargado", 3)
end

end)()
local _cache = {}
local SB
local function require(name)
    -- Instance â†’ ModuleScript del juego (piggyback): delega al require real de Roblox (devuelve
    -- la tabla CACHEADA que el juego ya usa). String â†’ uno de nuestros factories.
    if typeof(name) == "Instance" then return __rawRequire(name) end
    if _cache[name] then return _cache[name] end
    local factory = _MODS[name]
    if not factory then error("[SB] modulo no encontrado: " .. tostring(name)) end
    local m = factory(require, SB, nil)
    _cache[name] = m
    return m
end
-- Core.State crea el global SB (ignora su param). Lib (Obsidian) la carga main en runtime.
SB = _MODS["Core.State"](require, nil, nil)
_cache["Core.State"] = SB
SB.require = require
_MODS["main"](require, SB, nil)
return SB