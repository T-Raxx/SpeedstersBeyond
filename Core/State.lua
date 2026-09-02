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
