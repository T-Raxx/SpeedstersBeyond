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

    SB.Log(2, "cargado — window listo")
    Library:Notify("SpeedstersBeyond cargado", 3)
end
