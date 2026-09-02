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
