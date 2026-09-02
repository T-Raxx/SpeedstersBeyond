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
