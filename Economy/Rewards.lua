-- Economy/Rewards.lua — FACTORY. Auto-claim PlayTime rewards (time-gated: unlockAt<=now, no claimed)
-- vía Presents.{i}.ButtonClaim del panel Uis.PlayTimeRewards. FreeRewards NO (task-gated: like/group = social).
return function(require, SB, Lib)
    local LP = game:GetService("Players").LocalPlayer
    local Rewards = {}
    local running = false

    local function fire(btn)
        if not btn then return end
        for _, c in ipairs(getconnections(btn.Activated)) do pcall(function() c:Fire() end) end
    end
    local function ptPanel()
        local u = LP.PlayerGui:FindFirstChild("Uis")
        return u and u:FindFirstChild("PlayTimeRewards")
    end

    function Rewards.ClaimPlayTime()
        local snap = SB.Net.Invoke("GetPlayTimeRewardsSnapshot")
        if type(snap) ~= "table" then return 0 end
        local pnl = ptPanel(); if not pnl then return 0 end
        local presents = pnl:FindFirstChild("Presents", true)
        if not presents then return 0 end
        local now = os.time()
        local n = 0
        for i, tier in pairs(snap) do
            if type(tier) == "table" and not tier.claimed and tier.unlockAt and now >= tier.unlockAt then
                local frame = presents:FindFirstChild(tostring(i))
                local btn = frame and frame:FindFirstChild("ButtonClaim")
                if btn then fire(btn); n = n + 1; task.wait(0.3) end
            end
        end
        if n > 0 then SB.Log(2, "PlayTime rewards claimed:", n) end
        return n
    end

    function Rewards.Start()
        if running then return end
        running = true
        task.spawn(function()
            while running and not SB.IsStopped() do
                if SB.masterOn and SB.rewardsOn then pcall(Rewards.ClaimPlayTime) end
                task.wait(SB.rewardsInterval or 30)
            end
        end)
        SB.Log(2, "Rewards auto-claim armado")
    end
    function Rewards.Stop() running = false end
    SB.onCleanup(function() running = false end)

    return Rewards
end
