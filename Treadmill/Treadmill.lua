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
