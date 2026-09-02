-- UI.lua — FACTORY. Construye tabs/groupboxes Obsidian + controles globales.
-- Flags en Lib.Toggles / Lib.Options. Sin lógica de farm (solo wiring).
return function(require, SB, Lib)
    local UI = {}

    function UI.build(Window, Library)
        local box = SB.Tabs.Main:AddLeftGroupbox("Global")

        box:AddToggle("MasterEnable", {
            Text = "Master Enable", Default = false,
            Tooltip = "Habilita el suite. Off = todo pausado (kill-switch suave).",
            Callback = function(v) SB.masterOn = v end,
        })
        box:AddToggle("DryRun", {
            Text = "Dry-Run", Default = false,
            Tooltip = "Loguea writes en vez de dispararlos.",
            Callback = function(v) SB.dryRun = v end,
        })
        box:AddDropdown("LogLevel", {
            Values = { "Silent", "Warn", "Info", "Debug" }, Default = "Info",
            Text = "Log Level",
            Callback = function(v)
                SB.logLevel = ({ Silent = 0, Warn = 1, Info = 2, Debug = 3 })[v] or 2
            end,
        })
        box:AddButton({ Text = "Unload", Func = function() SB.Unload() end })
        box:AddDivider()
        box:AddLabel("Panic Key"):AddKeyPicker("PanicKey", {
            Default = "RightControl", Mode = "Toggle", Text = "Panic (unload)",
            Callback = function() SB.Unload() end,
        })
    end

    return UI
end
