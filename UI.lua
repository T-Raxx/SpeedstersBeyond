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

        local mv = SB.Tabs.Main:AddRightGroupbox("Movement")
        mv:AddDropdown("MoveMode", { Values = { "fast", "steady" }, Default = "fast", Text = "Mode",
            Tooltip = "fast = fluctúa alto (simple jobs). steady = controlado (fragile, no chocar props).",
            Callback = function(v) SB.moveMode = v end })
        mv:AddSlider("MoveBudgetMult", { Text = "Budget mult", Min = 0.8, Max = 1.35, Default = 1.2,
            Rounding = 2, Suffix = "x",
            Tooltip = "Fracción del speed stat. Techo AC ~1.35x (escala con ascends).",
            Callback = function(v) SB.moveBudgetMult = v end })
        mv:AddSlider("ArriveRadius", { Text = "Arrive radius", Min = 4, Max = 20, Default = 8,
            Rounding = 0, Suffix = " st", Callback = function(v) SB.arriveRadius = v end })

        local ai = SB.Tabs.Main:AddRightGroupbox("Anti-Idle")
        ai:AddToggle("AntiIdleOn", { Text = "Anti-Idle", Default = true,
            Tooltip = "Input sintético (VIM) vs SUSPICIOUS_IDLE (60s).",
            Callback = function(v)
                SB.antiIdleOn = v
                if v then SB.AntiIdle.Start() else SB.AntiIdle.Stop() end
            end })
        ai:AddSlider("IdleGapMin", { Text = "gap min", Min = 15, Max = 40, Default = 25, Rounding = 0,
            Suffix = " s", Callback = function(v) if SB.AntiIdle then SB.AntiIdle.gapMin = v end end })
        ai:AddSlider("IdleGapMax", { Text = "gap max", Min = 30, Max = 55, Default = 45, Rounding = 0,
            Suffix = " s", Callback = function(v) if SB.AntiIdle then SB.AntiIdle.gapMax = v end end })
    end

    return UI
end
