-- Jobs/Jobs.lua — FACTORY. Deliveries autofarm (mecánica confirmada live).
-- GoTo JobsPart → fire tier button → phase claimed+drop → GoTo drop (→running→banca) → chain → claim.
return function(require, SB, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Jobs = {}
    local running = false

    local function JC() return require(LP.PlayerScripts.Controllers.JobsController) end
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
        SB.Move.GoTo(pos, { arrive = 12, timeout = 15, mode = "fast" })
        SB.Move.Stop()
        task.wait(3.5)   -- dwell: server zone confirm = SERVER_STRIKES(3) x SERVER_INTERVAL(1s) ≈ 3s
        return true
    end

    -- Una vuelta: si banked>=claimAt claim; aceptar tier; correr chain hasta phase idle.
    function Jobs.RunCycle()
        local jc = JC()
        if not gotoZone() then return "no-zone" end
        if jc:GetBankedCount() >= (SB.jobsClaimAt or 40) then
            fire(claimButton()); task.wait(1)
        end
        Jobs.SetType(SB.jobsType or "Simple")
        local fragile = (SB.jobsType == "Fragile")
        local btn = tierButton(Jobs.BestTier())
        if not btn then return "tier-locked" end
        fire(btn)
        local t0 = os.clock()
        while jc:GetPhase() == "idle" and os.clock() - t0 < 4 do task.wait(0.2) end
        local guard = 0
        while not SB.IsStopped() and jc:GetPhase() ~= "idle" and guard < 12 do
            local dp = jc:GetDropPoint()
            if typeof(dp) ~= "Vector3" then break end
            -- Fragile = steady (control, no chocar props); Simple = modo elegido (fast por defecto)
            SB.Move.GoTo(dp, { arrive = 15, timeout = 25, mode = fragile and "steady" or (SB.moveMode or "fast") })
            task.wait(0.6)   -- banca + próximo leg
            guard = guard + 1
        end
        if jc:GetBankedCount() >= (SB.jobsClaimAt or 40) then
            gotoZone(); fire(claimButton()); task.wait(1)
        end
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
                    task.wait(0.5)
                end
                task.wait(0.3)
            end
        end)
        SB.Log(2, "JobsFarm armado")
    end
    function Jobs.Stop() running = false; SB.Move.Stop() end
    SB.onCleanup(function() running = false end)

    return Jobs
end
