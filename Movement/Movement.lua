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
