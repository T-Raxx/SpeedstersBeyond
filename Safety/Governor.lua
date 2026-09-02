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
