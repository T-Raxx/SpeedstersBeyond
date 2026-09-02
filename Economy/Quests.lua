-- Economy/Quests.lua — FACTORY. Auto-collect quests completadas (progress>=amount, no collected)
-- vía botón QuestFrame{i}.TextButton del panel Uis.Quests. Sin zona; corre en paralelo al farm.
return function(require, SB, Lib)
    local LP = game:GetService("Players").LocalPlayer
    local Quests = {}
    local running = false

    local function panel()
        local uis = LP.PlayerGui:FindFirstChild("Uis")
        return uis and uis:FindFirstChild("Quests")
    end
    local function fire(btn)
        if not btn then return end
        for _, c in ipairs(getconnections(btn.Activated)) do pcall(function() c:Fire() end) end
    end

    function Quests.CollectAll()
        local snap = SB.Net.Invoke("GetQuestsSnapshot")
        if not (snap and snap.quests) then return 0 end
        local pnl = panel(); if not pnl then return 0 end
        local n = 0
        for i, q in pairs(snap.quests) do
            if q.progress and q.amount and q.progress >= q.amount and not q.collected then
                local qf = pnl:FindFirstChild("QuestFrame" .. tostring(i), true)
                local btn = qf and qf:FindFirstChild("TextButton")
                if btn then fire(btn); n = n + 1; task.wait(0.3) end
            end
        end
        if n > 0 then SB.Log(2, "Quests: colectadas", n) end
        return n
    end

    function Quests.Start()
        if running then return end
        running = true
        task.spawn(function()
            while running and not SB.IsStopped() do
                if SB.masterOn and SB.questsOn then pcall(Quests.CollectAll) end
                task.wait(SB.questsInterval or 20)
            end
        end)
        SB.Log(2, "Quests auto-collect armado")
    end
    function Quests.Stop() running = false end
    SB.onCleanup(function() running = false end)

    return Quests
end
