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
