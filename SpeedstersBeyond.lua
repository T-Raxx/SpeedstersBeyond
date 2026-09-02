-- SpeedstersBeyond bundle self-contained. No editar a mano (generado por build_bundle.ps1).
local __rawRequire = require
local _MODS = {}
_MODS["Core.State"] = (function()
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

end)()
_MODS["Safety.Governor"] = (function()
-- Safety/Governor.lua — FACTORY. RateGovernor: min-interval por remote + ventana ATTEMPT_LIMIT.
-- Allow(name) devuelve true si se puede disparar AHORA (y registra el disparo); false = throttle.
return function(require, SB, Lib)
    local Governor = {}
    local last = {}          -- name -> os.clock del ultimo allow
    local windowTimes = {}   -- lista de os.clock de disparos recientes (ventana 1s)

    local INTERVALS = {
        ReportIdle       = 15,
        ClaimJob         = 0.4,
        CollectJob       = 0.4,
        ReportJobArrival = 0.1,
        _default         = 0.35,
    }
    Governor.DEFAULT = INTERVALS._default
    local ATTEMPT_LIMIT, WINDOW = 5, 1.0

    function Governor.SetInterval(name, seconds) INTERVALS[name] = seconds end

    function Governor.Allow(name)
        local now = os.clock()
        -- ventana global anti-flood
        local n = 0
        for i = #windowTimes, 1, -1 do
            if now - windowTimes[i] > WINDOW then table.remove(windowTimes, i) else n = n + 1 end
        end
        if n >= ATTEMPT_LIMIT then
            SB.Log(3, "Governor: ventana llena (", n, ") — deny", name)
            return false
        end
        local iv = INTERVALS[name] or INTERVALS._default
        if last[name] and (now - last[name]) < iv then
            SB.Log(3, "Governor: min-interval", name, string.format("%.2f", now - last[name]), "<", iv)
            return false
        end
        last[name] = now
        windowTimes[#windowTimes + 1] = now
        return true
    end

    return Governor
end

end)()
_MODS["main"] = (function()
-- main.lua — FACTORY driver. Place guard, bootstrap Obsidian, crea Window, init capas, panic/unload.
return function(require, SB, _Lib)
    -- PLACE GUARD
    if game.PlaceId ~= SB.placeId then
        SB.Log(1, "PlaceId", game.PlaceId, "≠", SB.placeId, "— abort")
        SB.Unload()
        return
    end

    -- BOOTSTRAP OBSIDIAN (runtime)
    local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
    local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
    SB.Library = Library
    SB.ThemeManager = ThemeManager
    SB.SaveManager  = SaveManager

    SB.Governor = require("Safety.Governor")

    local Window = Library:CreateWindow({
        Title = "SpeedstersBeyond",
        Footer = "v" .. SB.version .. " · burner",
        Center = true, AutoShow = true,
        NotifySide = "Right",
    })
    SB.Window = Window
    SB.Tabs = { Main = Window:AddTab("Main", "home") }

    SB.Log(2, "cargado — window listo")
    Library:Notify("SpeedstersBeyond cargado", 3)
end

end)()
local _cache = {}
local SB
local function require(name)
    -- Instance â†’ ModuleScript del juego (piggyback): delega al require real de Roblox (devuelve
    -- la tabla CACHEADA que el juego ya usa). String â†’ uno de nuestros factories.
    if typeof(name) == "Instance" then return __rawRequire(name) end
    if _cache[name] then return _cache[name] end
    local factory = _MODS[name]
    if not factory then error("[SB] modulo no encontrado: " .. tostring(name)) end
    local m = factory(require, SB, nil)
    _cache[name] = m
    return m
end
-- Core.State crea el global SB (ignora su param). Lib (Obsidian) la carga main en runtime.
SB = _MODS["Core.State"](require, nil, nil)
_cache["Core.State"] = SB
SB.require = require
_MODS["main"](require, SB, nil)
return SB