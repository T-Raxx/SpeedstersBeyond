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
