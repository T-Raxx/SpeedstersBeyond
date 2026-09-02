-- Movement/Pathfind.lua — FACTORY. A* custom que rodea TODO lo que obstruye (árboles, montañas, muros,
-- edificios) para fragile jobs. Occupancy combinada:
--   • ÁRBOLES: posiciones de tronco (WorldProps chunks T_cx,cz, chunk=1000) con radio → deja huecos para pasar.
--   • TERRENO/MUROS/EDIFICIOS: raycast hacia abajo (EXCLUYE WorldProps para que la copa de árbol no
--     sobre-bloquee) → bloquea celdas cuyo suelo se eleva > baseline+CLIMB_MAX (montaña/muro) o vacío.
-- Min-heap A*, string-pull con LOS de grid. Retry con corredor ancho si no hay ruta. FPS drops tolerados.
return function(require, SB, Lib)
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    local Pathfind = {}
    local CHUNK = 1000
    local DEF_CELL = 15
    local TREE_R = 18           -- radio de bloqueo por tronco de árbol (hitbox 7 * scale + player + margen)
    local CLIMB_MAX = 22        -- altura sobre baseline que cuenta como obstáculo (montaña/muro)
    local PROBE_UP, PROBE_DOWN = 300, 900
    local MAX_CELLS = 8000
    local ITER_CAP = 60000

    -- ── min-heap (por f) ────────────────────────────────────────────────────────
    local function heapNew() return { n = 0 } end
    local function heapPush(h, item, pri)
        h.n = h.n + 1; h[h.n] = { item, pri }
        local i = h.n
        while i > 1 do local p = i // 2; if h[p][2] <= h[i][2] then break end; h[p], h[i] = h[i], h[p]; i = p end
    end
    local function heapPop(h)
        if h.n == 0 then return nil end
        local top = h[1][1]; h[1] = h[h.n]; h[h.n] = nil; h.n = h.n - 1
        local i = 1
        while true do
            local l, r, sm = i * 2, i * 2 + 1, i
            if l <= h.n and h[l][2] < h[sm][2] then sm = l end
            if r <= h.n and h[r][2] < h[sm][2] then sm = r end
            if sm == i then break end
            h[i], h[sm] = h[sm], h[i]; i = sm
        end
        return top
    end

    local function corridorTrees(a, b, margin)
        local wp = workspace:FindFirstChild("WorldProps"); if not wp then return {} end
        local seen, obs = {}, {}
        local steps = math.max(1, math.ceil((b - a).Magnitude / 300))
        local minX, maxX = math.min(a.X, b.X) - margin, math.max(a.X, b.X) + margin
        local minZ, maxZ = math.min(a.Z, b.Z) - margin, math.max(a.Z, b.Z) + margin
        for i = 0, steps do
            local p = a:Lerp(b, i / steps)
            local key = math.floor(p.X / CHUNK) .. "," .. math.floor(p.Z / CHUNK)
            if not seen[key] then
                seen[key] = true
                local f = wp:FindFirstChild("T_" .. key)
                if f then
                    for _, t in ipairs(f:GetChildren()) do
                        local pp = t:IsA("Model") and (t.PrimaryPart or t:FindFirstChildWhichIsA("BasePart"))
                        if pp then
                            local pos = pp.Position
                            if pos.X >= minX and pos.X <= maxX and pos.Z >= minZ and pos.Z <= maxZ then obs[#obs + 1] = pos end
                        end
                    end
                end
            end
        end
        return obs
    end

    local function solve(a, b, margin, cell)
        local minX = math.min(a.X, b.X) - margin
        local minZ = math.min(a.Z, b.Z) - margin
        local maxX = math.max(a.X, b.X) + margin
        local maxZ = math.max(a.Z, b.Z) + margin
        local cols = math.floor((maxX - minX) / cell) + 1
        local rows = math.floor((maxZ - minZ) / cell) + 1
        while cols * rows > MAX_CELLS do
            cell = cell * 1.4
            cols = math.floor((maxX - minX) / cell) + 1
            rows = math.floor((maxZ - minZ) / cell) + 1
        end
        local function idx(c, r) return c * rows + r end
        local blocked = {}

        -- TERRENO/MUROS/EDIFICIOS por raycast (excluye char + WorldProps → copas no sobre-bloquean)
        local baseline = (a.Y + b.Y) * 0.5
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        local exclude = { LP.Character }
        local wp = workspace:FindFirstChild("WorldProps"); if wp then exclude[#exclude + 1] = wp end
        rp.FilterDescendantsInstances = exclude
        rp.IgnoreWater = true
        local DOWN = Vector3.new(0, -PROBE_DOWN, 0)
        for c = 0, cols - 1 do
            local wx = minX + (c + 0.5) * cell
            for r = 0, rows - 1 do
                local wz = minZ + (r + 0.5) * cell
                local hit = workspace:Raycast(Vector3.new(wx, baseline + PROBE_UP, wz), DOWN, rp)
                if (not hit) or (hit.Position.Y > baseline + CLIMB_MAX) then blocked[idx(c, r)] = true end
            end
        end

        -- ÁRBOLES por tronco (radio → deja huecos entre árboles para pasar)
        local rad = math.ceil(TREE_R / cell)
        for _, o in ipairs(corridorTrees(a, b, margin)) do
            local c0 = math.floor((o.X - minX) / cell)
            local r0 = math.floor((o.Z - minZ) / cell)
            for c = c0 - rad, c0 + rad do
                for r = r0 - rad, r0 + rad do
                    if c >= 0 and c < cols and r >= 0 and r < rows then
                        local cx, cz = minX + (c + 0.5) * cell, minZ + (r + 0.5) * cell
                        if (cx - o.X) ^ 2 + (cz - o.Z) ^ 2 <= TREE_R * TREE_R then blocked[idx(c, r)] = true end
                    end
                end
            end
        end

        local function clampCell(p)
            return math.clamp(math.floor((p.X - minX) / cell), 0, cols - 1),
                   math.clamp(math.floor((p.Z - minZ) / cell), 0, rows - 1)
        end
        local sc, sr = clampCell(a)
        local gc, gr = clampCell(b)
        blocked[idx(sc, sr)] = nil; blocked[idx(gc, gr)] = nil
        local goalIdx = idx(gc, gr)
        local function hcost(c, r)
            local dc, dr = math.abs(c - gc), math.abs(r - gr)
            return (dc + dr) + (1.4142 - 2) * math.min(dc, dr)
        end
        local came, gScore = {}, { [idx(sc, sr)] = 0 }
        local open = heapNew()
        heapPush(open, idx(sc, sr), hcost(sc, sr))
        local DIRS = { {1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1} }
        local iters, found = ITER_CAP, false
        while iters > 0 do
            local cur = heapPop(open); if not cur then break end
            if cur == goalIdx then found = true; break end
            iters = iters - 1
            local cc, cr = cur // rows, cur % rows
            local gcur = gScore[cur]
            for _, d in ipairs(DIRS) do
                local nc, nr = cc + d[1], cr + d[2]
                if nc >= 0 and nc < cols and nr >= 0 and nr < rows and not blocked[idx(nc, nr)] then
                    local diag = d[1] ~= 0 and d[2] ~= 0
                    if not (diag and (blocked[idx(cc + d[1], cr)] or blocked[idx(cc, cr + d[2])])) then
                        local ni = idx(nc, nr)
                        local ng = gcur + (diag and 1.4142 or 1)
                        if ng < (gScore[ni] or math.huge) then
                            came[ni] = cur; gScore[ni] = ng
                            heapPush(open, ni, ng + hcost(nc, nr))
                        end
                    end
                end
            end
        end
        if not found then return nil end
        local path, k = {}, goalIdx
        while k do
            local c, r = k // rows, k % rows
            path[#path + 1] = Vector3.new(minX + (c + 0.5) * cell, a.Y, minZ + (r + 0.5) * cell)
            k = came[k]
        end
        for i = 1, #path // 2 do path[i], path[#path - i + 1] = path[#path - i + 1], path[i] end
        -- STRING-PULL con LOS de grid (cada segmento entre waypoints es libre)
        local function segClear(p1, p2)
            local steps = math.max(1, math.ceil((p2 - p1).Magnitude / (cell * 0.5)))
            for i = 0, steps do
                local p = p1:Lerp(p2, i / steps)
                local c = math.floor((p.X - minX) / cell)
                local r = math.floor((p.Z - minZ) / cell)
                if c >= 0 and c < cols and r >= 0 and r < rows and blocked[idx(c, r)] then return false end
            end
            return true
        end
        local wps = { path[1] }
        local anchor = 1
        for i = 3, #path do
            if not segClear(path[anchor], path[i]) then wps[#wps + 1] = path[i - 1]; anchor = i - 1 end
        end
        wps[#wps + 1] = b
        return wps
    end

    -- FindPath: intenta corredor normal, luego ancho si no hay ruta (montaña grande cruzando).
    function Pathfind.FindPath(a, b, opts)
        opts = opts or {}
        return solve(a, b, opts.margin or 260, opts.cell or DEF_CELL)
            or solve(a, b, 700, DEF_CELL)
            or { b }   -- fallback: directo (mejor que nada; raro)
    end

    return Pathfind
end
