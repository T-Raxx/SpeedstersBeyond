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
    SB.Net = require("Net")
    SB.Move = require("Movement.Movement")
    SB.AntiIdle = require("AntiIdle.AntiIdle")
    SB.Jobs = require("Jobs.Jobs")
    SB.Treadmill = require("Treadmill.Treadmill")

    local Window = Library:CreateWindow({
        Title = "SpeedstersBeyond",
        Footer = "v" .. SB.version .. " · burner",
        Center = true, AutoShow = true,
        NotifySide = "Right",
    })
    SB.Window = Window
    SB.Tabs = { Main = Window:AddTab("Main", "home") }

    SB.UI = require("UI")
    SB.UI.build(Window, Library)
    -- SaveManager / ThemeManager
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetFolder("SpeedstersBeyond")
    ThemeManager:SetFolder("SpeedstersBeyond")
    local cfgTab = Window:AddTab("Config", "settings")
    SB.Tabs.Config = cfgTab
    SaveManager:BuildConfigSection(cfgTab)
    ThemeManager:ApplyToTab(cfgTab)
    SaveManager:LoadAutoloadConfig()

    -- aplicar valores iniciales de flags de movimiento + arrancar AntiIdle si quedó on
    do
        local T, O = Library.Toggles, Library.Options
        if O.MoveMode then SB.moveMode = O.MoveMode.Value end
        if O.MoveBudgetMult then SB.moveBudgetMult = O.MoveBudgetMult.Value end
        if O.ArriveRadius then SB.arriveRadius = O.ArriveRadius.Value end
        if O.IdleGapMin then SB.AntiIdle.gapMin = O.IdleGapMin.Value end
        if O.IdleGapMax then SB.AntiIdle.gapMax = O.IdleGapMax.Value end
        if T.AntiIdleOn and T.AntiIdleOn.Value then SB.AntiIdle.Start() end
    end

    -- READ INICIAL + REFRESH (StateStore). Fuentes reales confirmadas live:
    --   GetCurrencySnapshot { points(money), speed(stat velocidad = techo budget), safeMode }
    --   GetStatsSnapshot     { level, goal, exp }
    --   GetAscensionSnapshot { ascensions, levelCap, nextLevelCap, speedCap, nextSpeedCap }
    --   GetSpeedCap          { max, cap } (cap seleccionable vivo)
    do
        local Net = SB.Net
        local RunService = game:GetService("RunService")
        local lastRefresh = 0
        local function refreshState(force)
            local now = os.clock()
            if not force and (now - lastRefresh) < 0.5 then return end   -- throttle anti-spam (CurrencyChanged)
            lastRefresh = now
            local cur = Net.Invoke("GetCurrencySnapshot")
            if type(cur) == "table" then
                if cur.points ~= nil then SB.Set("points", cur.points) end
                if cur.speed  ~= nil then SB.Set("speed",  cur.speed)  end
            end
            local st = Net.Invoke("GetStatsSnapshot")
            if type(st) == "table" then
                if st.level ~= nil then SB.Set("level", st.level) end
                if st.goal  ~= nil then SB.Set("expGoal", st.goal) end
            end
            local asc = Net.Invoke("GetAscensionSnapshot")
            if type(asc) == "table" then
                if asc.ascensions   ~= nil then SB.Set("ascensions", asc.ascensions) end
                if asc.levelCap     ~= nil then SB.Set("levelCap", asc.levelCap) end
                if asc.speedCap     ~= nil then SB.Set("speedCapTier", asc.speedCap) end
                if asc.nextSpeedCap ~= nil then SB.Set("nextSpeedCap", asc.nextSpeedCap) end
            end
            local sc = Net.Invoke("GetSpeedCap")
            if type(sc) == "table" and sc.max ~= nil then SB.Set("speedCapMax", sc.max) end
        end
        SB.RefreshState = refreshState
        refreshState(true)
        Net.OnChanged("CurrencyChanged", function() refreshState() end)
        Net.OnChanged("AscensionChanged", function() refreshState() end)
        task.spawn(function()
            while not SB.IsStopped() do
                refreshState()
                task.wait(2)
            end
        end)
    end

    -- MASTER LOOP STUB (las tasks de farm cuelgan de aquí en planes siguientes)
    SB.track(game:GetService("RunService").Heartbeat:Connect(function()
        if SB.IsStopped() or not SB.masterOn then return end
        -- orchestrator tick placeholder (Plan 3)
    end))

    SB.Log(2, "cargado — window listo")
    Library:Notify("SpeedstersBeyond cargado", 3)
end
