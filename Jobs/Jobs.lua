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
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local dist = hrp and (Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)).Magnitude or 1e9
        -- YA en zona (ej. recién claimeamos acá) → sin re-viaje ni dwell (el server ya nos cuenta dentro).
        -- Esto hace la re-selección tras claim instantánea.
        if dist <= 20 then SB.Move.Stop(); return true end
        -- lejos (fin de delivery a miles de studs) → ReturnToSpawn (teleport server, ~53 studs de JobsPart).
        if dist > 150 then SB.Net.Fire("ReturnToSpawn"); task.wait(1) end
        SB.Move.GoTo(pos, { arrive = 12, timeout = 15, mode = "fast" })
        SB.Move.Stop()
        task.wait(SB.jobsZoneDwell or 3.5)   -- dwell SOLO al entrar fresco: server zone confirm (STRIKES 3x1s)
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
            if SB.collectJobPoints and jc:GetBankedCount() >= (SB.jobsClaimAt or 40) then fire(claimButton()); task.wait(1) end
            Jobs.SetType(SB.jobsType or "Simple")
            local btn = tierButton(Jobs.BestTier())
            if not btn then return "tier-locked" end
            local want = math.min(Jobs.AvailableSlots(), SB.jobsBatch or 99)
            -- El botón se puede spammear sin problema; lo crítico es DETECTAR rápido que los slots están
            -- llenos. Spam + poll GetLegCount cada tick (rápido) hasta llenar; guard por TIEMPO, no por
            -- # de fires. jobsSelectDelay chico = spam rápido + detección inmediata.
            local t0 = os.clock()
            while jc:GetLegCount() < want and os.clock() - t0 < 3 and not SB.IsStopped() do
                fire(btn); task.wait(SB.jobsSelectDelay or 0.05)
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
        if SB.collectJobPoints and jc:GetBankedCount() >= (SB.jobsClaimAt or 40) then gotoZone(); fire(claimButton()); task.wait(1) end
        return "cycle-done"
    end

    function Jobs.Start()
        if running then return end
        running = true
        task.spawn(function()
            while running and not SB.IsStopped() do
                if SB.masterOn and SB.jobsOn and not SB.ascending then
                    SB.jobsActive = true                    -- exclusión: Treadmill no se mueve mientras hay job en curso
                    local ok, err = pcall(Jobs.RunCycle)
                    SB.jobsActive = false                   -- limpia siempre (aun si RunCycle erroró)
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
