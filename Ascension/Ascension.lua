-- Ascension/Ascension.lua — FACTORY. Auto-ascend cuando level>=levelCap. AscensionController:Ascend() público.
return function(require, SB, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Ascension = {}
    local running = false

    local function AC() return require(LP.PlayerScripts.Controllers.AscensionController) end

    function Ascension.Ready()
        local lvl, cap = SB.Get("level"), SB.Get("levelCap")
        if not (lvl and cap) then return false end
        if (SB.ascendTarget or 0) > 0 and (SB.Get("ascensions") or 0) >= SB.ascendTarget then return false end
        return lvl >= cap
    end

    function Ascension.AscendNow()
        SB.ascending = true
        SB.Move.Stop()
        local ok, err = pcall(function() AC():Ascend() end)
        if not ok then SB.Log(1, "Ascend err:", err) end
        task.wait(2)          -- transición + AscensionChanged
        SB.RefreshState(true)
        SB.ascending = false
        SB.Log(2, "Ascend hecho — ascensions:", SB.Get("ascensions"))
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
