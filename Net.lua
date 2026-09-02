-- Net.lua — FACTORY. Capa de red: resuelve remotes por nombre (ReplicatedStorage.Remotes),
-- Fire (RemoteEvent, gobernado + dryRun), Invoke (RemoteFunction, reads), OnChanged (listener).
return function(require, SB, Lib)
    local Net = {}
    local cache = {}

    function Net.Get(name)
        if cache[name] and cache[name].Parent then return cache[name] end
        local r = SB.Remotes and SB.Remotes:FindFirstChild(name)
        cache[name] = r
        if not r then SB.Log(1, "Net: remote no encontrado:", name) end
        return r
    end

    function Net.Fire(name, ...)
        if SB.IsStopped() then return false end
        local G = SB.Governor
        if G and not G.Allow(name) then return false end
        if SB.dryRun then
            SB.Log(2, "[DRY] Fire", name, ...)
            return true
        end
        local r = Net.Get(name)
        if not (r and r:IsA("RemoteEvent")) then return false end
        local args = table.pack(...)
        local ok = pcall(function() r:FireServer(table.unpack(args, 1, args.n)) end)
        return ok
    end

    function Net.Invoke(name, ...)
        local r = Net.Get(name)
        if not (r and r:IsA("RemoteFunction")) then return nil end
        local args = table.pack(...)
        local ok, res = pcall(function() return r:InvokeServer(table.unpack(args, 1, args.n)) end)
        if not ok then SB.Log(1, "Net: Invoke fallo", name, res); return nil end
        return res
    end

    function Net.OnChanged(name, fn)
        local r = Net.Get(name)
        if not (r and r:IsA("RemoteEvent")) then return nil end
        return SB.track(r.OnClientEvent:Connect(fn))
    end

    return Net
end
