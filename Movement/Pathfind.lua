-- Movement/Pathfind.lua — FACTORY. A* custom sobre grid local para RODEAR árboles (fragile jobs).
-- Los árboles (WorldProps folders T_cx,cz, chunk=1000) rompen por contacto → volar NO sirve; hay que
-- esquivarlos a nivel de piso. Solo consulta los chunks del corredor start→goal (no los 22k árboles).
-- Min-heap para A* eficiente (FPS drops tolerados: uso propio).
return function(require, SB, Lib)
    local Pathfind = {}
    local CHUNK = 1000
    local DEF_CELL = 14           -- grid (tree spacing ~18, hitbox ~7)
    local DEF_OBST_R = 16         -- radio de bloqueo por árbol (hitbox*scale + player + margen)
    local MARGIN = 170            -- ancho del corredor a cada lado de la línea directa
    local MAX_CELLS = 60000
    local ITER_CAP = 40000

    -- ── min-heap (por prioridad f) ─────────────────────────────────────────────
    local function heapNew() return { n = 0 } end
    local function heapPush(h, item, pri)
        h.n = h.n + 1; h[h.n] = { item, pri }
        local i = h.n
        while i > 1 do
            local p = i // 2
            if h[p][2] <= h[i][2] then break end
            h[p], h[i] = h[i], h[p]; i = p
        end
    end
    local function heapPop(h)
        if h.n == 0 then return nil end
        local top = h[1][1]
        h[1] = h[h.n]; h[h.n] = nil; h.n = h.n - 1
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

    -- árboles dentro del corredor (solo chunks tocados por la línea a→b)
    local function corridorObstacles(a, b, margin)
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
                            if pos.X >= minX and pos.X <= maxX and pos.Z >= minZ and pos.Z <= maxZ then
                                obs[#obs + 1] = pos
                            end
                        end
                    end
                end
            end
        end
        return obs
    end

    -- FindPath(a, b) → { Vector3 waypoints } (incluye b real) o {b} si corredor limpio o nil si sin ruta.
    function Pathfind.FindPath(a, b, opts)
        opts = opts or {}
        local obs = corridorObstacles(a, b, MARGIN)
        if #obs == 0 then return { b } end
        local cell, obr = opts.cell or DEF_CELL, opts.obstacleR or DEF_OBST_R
        local minX = math.min(a.X, b.X) - MARGIN
        local minZ = math.min(a.Z, b.Z) - MARGIN
        local maxX = math.max(a.X, b.X) + MARGIN
        local maxZ = math.max(a.Z, b.Z) + MARGIN
        local cols = math.floor((maxX - minX) / cell) + 1
        local rows = math.floor((maxZ - minZ) / cell) + 1
        while cols * rows > MAX_CELLS do
            cell = cell * 1.5
            cols = math.floor((maxX - minX) / cell) + 1
            rows = math.floor((maxZ - minZ) / cell) + 1
        end
        local function idx(c, r) return c * rows + r end
        -- occupancy
        local blocked = {}
        local rad = math.ceil(obr / cell)
        for _, o in ipairs(obs) do
            local c0 = math.floor((o.X - minX) / cell)
            local r0 = math.floor((o.Z - minZ) / cell)
            for c = c0 - rad, c0 + rad do
                for r = r0 - rad, r0 + rad do
                    if c >= 0 and c < cols and r >= 0 and r < rows then
                        local cx = minX + (c + 0.5) * cell
                        local cz = minZ + (r + 0.5) * cell
                        if (cx - o.X) ^ 2 + (cz - o.Z) ^ 2 <= obr * obr then blocked[idx(c, r)] = true end
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
        blocked[idx(sc, sr)] = nil; blocked[idx(gc, gr)] = nil   -- no bloquear extremos
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
            local cur = heapPop(open)
            if not cur then break end
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
        -- reconstruir + reducir a ~waypoints
        local path, k = {}, goalIdx
        while k do
            local c, r = k // rows, k % rows
            path[#path + 1] = Vector3.new(minX + (c + 0.5) * cell, a.Y, minZ + (r + 0.5) * cell)
            k = came[k]
        end
        for i = 1, #path // 2 do path[i], path[#path - i + 1] = path[#path - i + 1], path[i] end
        -- STRING-PULL con line-of-sight sobre el grid: mantener un waypoint solo si el segmento recto
        -- desde el anchor cruzaría una celda bloqueada. Así cada segmento entre waypoints es libre de
        -- árboles (el downsample naive podía cortar por encima de un árbol entre waypoints lejanos).
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
            if not segClear(path[anchor], path[i]) then
                wps[#wps + 1] = path[i - 1]; anchor = i - 1
            end
        end
        wps[#wps + 1] = b   -- goal real (no el centro de celda)
        return wps
    end

    return Pathfind
end
