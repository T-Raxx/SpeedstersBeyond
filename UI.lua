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

        local farm = SB.Tabs.Main:AddLeftGroupbox("Farm")
        farm:AddDropdown("FarmMode", { Values = { "Jobs", "Treadmill" }, Default = "Jobs", Text = "Mode",
            Tooltip = "Jobs y Treadmill son exclusivos por posición.",
            Callback = function(v)
                SB.farmMode = v
                SB.jobsOn = (v == "Jobs")
                SB.treadmillOn = (v == "Treadmill")
            end })
        farm:AddDropdown("JobsTier", { Values = { "auto", "1", "2", "3" }, Default = "auto", Text = "Jobs tier",
            Tooltip = "auto = mejor por ascensión (1=Easy,2=Med,3=Hard).",
            Callback = function(v) SB.jobsTier = v end })
        farm:AddDropdown("JobsType", { Values = { "Simple", "Fragile" }, Default = "Simple", Text = "Jobs type",
            Tooltip = "Fragile = no chocar props (usa modo steady).",
            Callback = function(v) SB.jobsType = v end })
        farm:AddSlider("JobsClaimAt", { Text = "Claim at", Min = 1, Max = 50, Default = 40, Rounding = 0,
            Callback = function(v) SB.jobsClaimAt = v end })
        farm:AddDropdown("TreadmillPad", { Values = { "auto", "x2", "x3", "x4", "x6", "x10" }, Default = "auto",
            Text = "Treadmill pad", Callback = function(v) SB.treadmillPad = v end })
        farm:AddToggle("AscendAuto", { Text = "Auto-Ascend", Default = true,
            Callback = function(v) SB.ascendAuto = v end })
        farm:AddSlider("AscendTarget", { Text = "Ascend target (0=inf)", Min = 0, Max = 200, Default = 0,
            Rounding = 0, Callback = function(v) SB.ascendTarget = v end })
    end

    return UI
end
