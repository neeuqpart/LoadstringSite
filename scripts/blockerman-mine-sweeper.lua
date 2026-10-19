--[[
    Mine ESP + AI Auto-Play — Minesweeper (Solo, place 7871169780)

    Board facts (reverse-engineered):
      • Tiles are 5x5x5 Parts under workspace.Flag.Parts
      • Revealed  = has a "NumberGui" child (TextLabel.Text = adjacent mine count)
      • Flagged   = has a "Metallic" Model child
      • Reveal    = walk the character onto the tile (TouchTransmitter)
      • Flag      = ReplicatedStorage.Events.FlagEvents.PlaceFlag:FireServer(part, token, true)
      • token     = workspace.Salasana.Value, read+destroyed by ReplicatedFirst.MouseControl,
                    still live as upvalue #5 of its Mouse.Button1Down handler.

    Design notes:
      • Solving produces an IMMUTABLE result object that is swapped in atomically.
        Readers grab the reference once, so a solve mid-yield can never corrupt them.
      • Movement is cardinal-only through KNOWN-SAFE cells, with tight arrival at
        turns so the character never clips a diagonal neighbour.
      • There is no "walk direct" fallback. If no safe path exists we pick a
        different target rather than walking blind across the board.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LocalPlayer       = Players.LocalPlayer

local aiEnabled = false
local aiThread  = nil

-- ── Kill any previous instance of this script ──────────────────────────────
-- Loops written as `while true do` never exit, so every re-run used to leave
-- another copy alive: N solve loops all rebuilding the board and fighting over
-- the same SelectionBoxes. That is the "double ESP", and enough of them stacked
-- up will lock the client. Each run now publishes a stop function that the next
-- run calls before doing anything else.
local BOX_NAME = "MineESP_Box"

if _G.__MineESP_stop then pcall(_G.__MineESP_stop) end

local alive = true                 -- every loop in this file checks this
local conns = {}                   -- every connection this run makes

local function track(c) conns[#conns + 1] = c; return c end

local function teardown()
    alive = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    for _, v in ipairs(workspace:GetChildren()) do
        if v:IsA("SelectionBox") and v.Name == BOX_NAME then v:Destroy() end
    end
    local pg  = LocalPlayer:FindFirstChild("PlayerGui")
    local old = pg and pg:FindFirstChild("MineESP_Solo_GUI")
    if old then old:Destroy() end
end

_G.__MineESP_stop = teardown

-- live-reload hands the script a STATE table with a teardown hook. Read it off
-- the environment so this stays valid when pasted into a plain executor tab,
-- where no such global exists.
do
    local env = (getfenv and getfenv(1)) or nil
    local S   = env and rawget(env, "STATE") or nil
    if type(S) == "table" and S.onCleanup then S.onCleanup(teardown) end
end

-- ── Board ──────────────────────────────────────────────────────────────────
local Flag  = workspace:WaitForChild("Flag", 15)
local Parts = Flag and Flag:WaitForChild("Parts", 15)
if not Parts then warn("[MineESP] Could not find workspace.Flag.Parts") return end

local Info     = ReplicatedStorage:WaitForChild("Info", 10)
local MinesVal = Info and Info:FindFirstChild("Mines")
local FlagsVal = Info and Info:FindFirstChild("Flags")

-- ── Challenge / board settings ─────────────────────────────────────────────
-- Active challenges are attributes on Info.ChallengeSettings; board config
-- (tile size, grid, flagless, ...) lives on Info.Settings.
local ChallengeCfg = Info and Info:FindFirstChild("ChallengeSettings")
local SettingsCfg  = Info and Info:FindFirstChild("Settings")

local challengeMode = true    -- adapt to whatever challenge is selected

local function challengeOn(name)
    if not challengeMode or not ChallengeCfg then return false end
    return ChallengeCfg:GetAttribute(name) == true
end

local function boardSetting(name, default)
    if not SettingsCfg then return default end
    local v = SettingsCfg:GetAttribute(name)
    if v == nil then return default end
    return v
end

local function activeChallenges()
    local list = {}
    if ChallengeCfg then
        for k, v in pairs(ChallengeCfg:GetAttributes()) do
            if v == true then list[#list + 1] = k end
        end
    end
    table.sort(list)
    return list
end

-- TileSize is configurable per round, so never assume 5.
local TILE_SIZE = 5

local function refreshTileSize()
    local ts = boardSetting("TileSize", 5)
    if type(ts) == "number" and ts > 0 then TILE_SIZE = ts end
end
refreshTileSize()

local function cellKey(cx, cy)
    return (cx + 5000) * 100000 + (cy + 5000)
end

-- ── Board memory ───────────────────────────────────────────────────────────
-- Disappearance deletes tile numbers after 37.5s. Without remembering what we
-- already saw, the solver goes blind mid-round and starts guessing on a board
-- it had already worked out. Weak keys so recreated tiles do not pile up.
local revealedMemory = setmetatable({}, { __mode = "k" })  -- part -> true
local numberMemory   = setmetatable({}, { __mode = "k" })  -- part -> number
local burnedTiles    = setmetatable({}, { __mode = "k" })  -- part -> true (Scorching)

local function clearBoardMemory()
    revealedMemory = setmetatable({}, { __mode = "k" })
    numberMemory   = setmetatable({}, { __mode = "k" })
    burnedTiles    = setmetatable({}, { __mode = "k" })
end

-- A new round means a new board; remembered numbers would be lies.
if Info and Info:FindFirstChild("GameRunning") then
    track(Info.GameRunning.Changed:Connect(function(running)
        if running then clearBoardMemory() end
    end))
end

-- ═══════════════════════════════════════════════════════════════════════════
--  SNAPSHOT — read the whole board once into plain data
-- ═══════════════════════════════════════════════════════════════════════════
local function buildSnapshot()
    local cells, byKey = {}, {}
    refreshTileSize()

    for _, p in ipairs(Parts:GetChildren()) do
        if p:IsA("BasePart") then
            local cx  = math.round(p.Position.X / TILE_SIZE)
            local cy  = math.round(p.Position.Z / TILE_SIZE)
            local gui = p:FindFirstChild("NumberGui")
            local num = nil
            if gui then
                local tl = gui:FindFirstChild("TextLabel")
                num = tl and tonumber(tl.Text) or nil
            end

            -- Remember what we have seen. A tile never un-reveals, so once it
            -- has shown a number that fact is permanent even after
            -- Disappearance wipes the label.
            if gui then revealedMemory[p] = true end
            if num then numberMemory[p] = num end
            local isRevealed = (gui ~= nil) or (revealedMemory[p] == true)
            if num == nil then num = numberMemory[p] end

            local c = {
                part     = p,
                pos      = p.Position,
                cx       = cx,
                cy       = cy,
                revealed = isRevealed,
                num      = num,                                  -- nil for blank / 'X'
                -- The flag model's NAME follows the player's equipped flag cosmetic
                -- ("Red", "Metallic", ...), so match on the class, not the name.
                flagged  = p:FindFirstChildOfClass("Model") ~= nil,
            }
            cells[#cells + 1] = c
            byKey[cellKey(cx, cy)] = c
        end
    end

    -- Precompute neighbour lists once (big win over re-scanning per query)
    for _, c in ipairs(cells) do
        local n8, n4 = {}, {}
        for dx = -1, 1 do
            for dy = -1, 1 do
                if dx ~= 0 or dy ~= 0 then
                    local o = byKey[cellKey(c.cx + dx, c.cy + dy)]
                    if o then
                        n8[#n8 + 1] = o
                        if dx == 0 or dy == 0 then n4[#n4 + 1] = o end
                    end
                end
            end
        end
        c.n8, c.n4 = n8, n4
    end

    return { cells = cells, byKey = byKey }
end

-- ═══════════════════════════════════════════════════════════════════════════
--  SOLVER — single-constraint rules + subset elimination, to fixpoint
-- ═══════════════════════════════════════════════════════════════════════════
local function solveSnapshot(snap)
    local mine, safe = {}, {}

    -- Unknown (undecided) neighbours of c, plus count of neighbours known to be mines.
    --
    -- NOTE: a flag is deliberately NOT treated as a mine. Anyone on the server
    -- can drop a flag anywhere, and trusting one poisons the arithmetic — a
    -- single misplaced teammate flag can make a real mine deduce as "safe" and
    -- walk the bot straight into it. Only mines this solver proved from the
    -- numbers count. Flags are display, not evidence.
    local function scanNeighbours(c)
        local u, m = {}, 0
        for _, o in ipairs(c.n8) do
            if not o.revealed then
                if mine[o] then
                    m += 1
                elseif not safe[o] then
                    u[#u + 1] = o
                end
            end
        end
        return u, m
    end

    local changed, guard = true, 0
    while changed and guard < 40 do
        changed = false
        guard  += 1

        -- ── Pass 1: trivial rules, and collect the live constraints ────────
        local constraints = {}
        for _, c in ipairs(snap.cells) do
            if c.revealed and c.num then
                local u, m = scanNeighbours(c)
                local need = c.num - m
                if #u > 0 then
                    if need <= 0 then
                        -- all satisfied → every remaining unknown is safe
                        for _, o in ipairs(u) do
                            if not safe[o] then safe[o] = true; changed = true end
                        end
                    elseif need == #u then
                        -- exactly as many mines as unknowns → all are mines
                        for _, o in ipairs(u) do
                            if not mine[o] then mine[o] = true; changed = true end
                        end
                    else
                        local set = {}
                        for _, o in ipairs(u) do set[o] = true end
                        constraints[#constraints + 1] = { cells = u, n = need, set = set }
                    end
                end
            end
        end

        if changed then continue end  -- cheap rules still producing; redo them first

        -- ── Pass 2: subset elimination ─────────────────────────────────────
        -- If A.cells ⊆ B.cells then B\A contains exactly (B.n - A.n) mines.
        for i = 1, #constraints do
            local A = constraints[i]
            for j = 1, #constraints do
                if i ~= j then
                    local B = constraints[j]
                    if #A.cells < #B.cells then
                        local isSubset = true
                        for _, c in ipairs(A.cells) do
                            if not B.set[c] then isSubset = false; break end
                        end
                        if isSubset then
                            local diff = {}
                            for _, c in ipairs(B.cells) do
                                if not A.set[c] then diff[#diff + 1] = c end
                            end
                            local dn = B.n - A.n
                            if dn == 0 then
                                for _, c in ipairs(diff) do
                                    if not safe[c] then safe[c] = true; changed = true end
                                end
                            elseif dn == #diff and dn > 0 then
                                for _, c in ipairs(diff) do
                                    if not mine[c] then mine[c] = true; changed = true end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return mine, safe
end

-- ═══════════════════════════════════════════════════════════════════════════
--  PROBABILITY — for when logic alone is stuck (50/50s and the like)
-- ═══════════════════════════════════════════════════════════════════════════
-- These caps matter: enumeration runs without yielding, so an over-generous
-- budget freezes the client outright rather than merely being slow.
local MAX_COMPONENT   = 16     -- exhaustively enumerate components up to this size
local MAX_ASSIGNMENTS = 20000  -- bail out to the heuristic past this much work

-- Exact per-cell mine probability over one frontier component.
local function enumerateComponent(compCells, comps)
    local n = #compCells
    if n == 0 or n > MAX_COMPONENT then return nil end

    local idx = {}
    for i, c in ipairs(compCells) do idx[c] = i end

    local assign  = table.create(n, false)
    local counts  = table.create(n, 0)
    local total   = 0
    local work    = 0
    local bailed  = false

    -- Constraints restricted to this component
    local cons = {}
    for _, con in ipairs(comps) do
        local inside, outsideKnown = {}, 0
        for _, c in ipairs(con.cells) do
            if idx[c] then inside[#inside + 1] = idx[c] end
        end
        if #inside > 0 then
            cons[#cons + 1] = { idx = inside, n = con.n - outsideKnown }
        end
    end

    -- Check constraints that are fully decided by the first `depth` cells
    local function feasible(depth)
        for _, con in ipairs(cons) do
            local sum, undecided = 0, 0
            for _, i in ipairs(con.idx) do
                if i <= depth then
                    if assign[i] then sum += 1 end
                else
                    undecided += 1
                end
            end
            if sum > con.n then return false end
            if sum + undecided < con.n then return false end
        end
        return true
    end

    local function recurse(i)
        if bailed then return end
        work += 1
        if work > MAX_ASSIGNMENTS then bailed = true; return end

        if i > n then
            total += 1
            for k = 1, n do
                if assign[k] then counts[k] += 1 end
            end
            return
        end
        -- Hoisted: allocating a {false,true} table per node was thousands of
        -- needless allocations per solve.
        assign[i] = false
        if feasible(i) then recurse(i + 1) end
        assign[i] = true
        if feasible(i) then recurse(i + 1) end
        assign[i] = false
    end

    recurse(1)
    if bailed or total == 0 then return nil end

    local probs = {}
    for i, c in ipairs(compCells) do
        probs[c] = counts[i] / total
    end
    return probs
end

-- Returns cell -> probability of being a mine, for every undecided cell.
local function computeProbabilities(snap, mine, safe)
    local probs = {}

    -- Global density for cells with no information at all
    local unknownCount, minesLeft = 0, 0
    if MinesVal then minesLeft = MinesVal.Value end
    for _, c in ipairs(snap.cells) do
        if not c.revealed then
            if mine[c] then                    -- proven, not merely flagged
                minesLeft -= 1
            elseif not safe[c] then
                unknownCount += 1
            end
        end
    end
    minesLeft = math.max(0, minesLeft)
    local globalProb = unknownCount > 0 and (minesLeft / unknownCount) or 0.5

    -- Build the live constraint list over undecided cells
    local constraints = {}
    for _, c in ipairs(snap.cells) do
        if c.revealed and c.num then
            local u, m = {}, 0
            for _, o in ipairs(c.n8) do
                if not o.revealed then
                    if mine[o] then m += 1               -- proven only; see scanNeighbours
                    elseif not safe[o] then u[#u + 1] = o end
                end
            end
            if #u > 0 then
                constraints[#constraints + 1] = { cells = u, n = c.num - m }
            end
        end
    end

    -- Union-find over cells that share a constraint → frontier components
    local parent = {}
    local function find(x)
        while parent[x] and parent[x] ~= x do x = parent[x] end
        return x
    end
    local function union(a, b)
        local ra, rb = find(a), find(b)
        if ra ~= rb then parent[ra] = rb end
    end
    for _, con in ipairs(constraints) do
        for _, c in ipairs(con.cells) do
            if parent[c] == nil then parent[c] = c end
        end
        for i = 2, #con.cells do union(con.cells[1], con.cells[i]) end
    end

    local groups = {}
    for cell in pairs(parent) do
        local r = find(cell)
        groups[r] = groups[r] or {}
        table.insert(groups[r], cell)
    end

    -- Exact probability per component where feasible
    for root, compCells in pairs(groups) do
        local compCons = {}
        for _, con in ipairs(constraints) do
            for _, c in ipairs(con.cells) do
                if find(c) == root then compCons[#compCons + 1] = con; break end
            end
        end
        local exact = enumerateComponent(compCells, compCons)
        if exact then
            for c, p in pairs(exact) do probs[c] = p end
        else
            -- Fallback: worst (highest) local density wins — never average it away
            for _, c in ipairs(compCells) do
                local worst = 0
                for _, con in ipairs(compCons) do
                    for _, cc in ipairs(con.cells) do
                        if cc == c then
                            worst = math.max(worst, con.n / #con.cells)
                            break
                        end
                    end
                end
                probs[c] = worst > 0 and worst or globalProb
            end
        end
    end

    -- Everything else is interior: global density
    for _, c in ipairs(snap.cells) do
        if not c.revealed and not c.flagged and not mine[c] and not safe[c] and probs[c] == nil then
            probs[c] = globalProb
        end
    end

    return probs, globalProb
end

-- ═══════════════════════════════════════════════════════════════════════════
--  SOLUTION STORE — one immutable object, swapped in atomically
-- ═══════════════════════════════════════════════════════════════════════════
local solution = nil   -- { snap, mine, safe, probs }

local function refreshSolution(withProbs)
    local snap       = buildSnapshot()
    local mine, safe = solveSnapshot(snap)
    local probs      = nil
    if withProbs then probs = computeProbabilities(snap, mine, safe) end
    -- single assignment → readers either see the old object or the new one, never a half-built one
    solution = { snap = snap, mine = mine, safe = safe, probs = probs }
    return solution
end

-- ═══════════════════════════════════════════════════════════════════════════
--  ESP
-- ═══════════════════════════════════════════════════════════════════════════
local espEnabled = true
local boxes = {}

local COL_UNKNOWN, SURF_UNKNOWN = Color3.fromRGB(255,200,0),  Color3.fromRGB(200,150,0)
local COL_MINE,    SURF_MINE    = Color3.fromRGB(255, 30,30), Color3.fromRGB(200,  0,0)
local COL_SAFE,    SURF_SAFE    = Color3.fromRGB( 30,255,80), Color3.fromRGB(  0,200,50)

local function getOrMakeBox(part, colour, surf)
    local box = boxes[part]
    if not box then
        box = Instance.new("SelectionBox")
        box.Name          = BOX_NAME
        box.LineThickness = 0.06
        box.Adornee       = part
        box.Parent        = workspace
        boxes[part]       = box
    end
    box.Color3              = colour
    box.SurfaceColor3       = surf
    box.SurfaceTransparency = 0.50
    return box
end

local function removeBox(part)
    local b = boxes[part]; if b then b:Destroy(); boxes[part] = nil end
end

local function removeAllBoxes()
    for part, box in pairs(boxes) do box:Destroy(); boxes[part] = nil end
end

local function renderESP(sol)
    if not espEnabled or not sol then return end
    for _, c in ipairs(sol.snap.cells) do
        if c.revealed then
            removeBox(c.part)
        elseif sol.mine[c] then
            getOrMakeBox(c.part, COL_MINE, SURF_MINE)
        elseif sol.safe[c] then
            -- Green even when flagged: that combination means someone flagged a
            -- tile we proved is safe, and the flagger will clear it.
            getOrMakeBox(c.part, COL_SAFE, SURF_SAFE)
        elseif c.flagged then
            getOrMakeBox(c.part, COL_MINE, SURF_MINE)
        else
            getOrMakeBox(c.part, COL_UNKNOWN, SURF_UNKNOWN)
        end
    end

    -- The game destroys and recreates tile Parts as the board changes, so a box
    -- can outlive its adornee. Those orphans are invisible to the loop above
    -- (the part is gone from the snapshot) and would pile up all round.
    for part, box in pairs(boxes) do
        if not part:IsDescendantOf(Parts) then
            box:Destroy()
            boxes[part] = nil
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  FLAGGING — fire, verify, retry; token re-extracted if it goes stale
-- ═══════════════════════════════════════════════════════════════════════════
local PlaceFlag   = ReplicatedStorage.Events.FlagEvents.PlaceFlag
local FLAG_RADIUS    = 3 * TILE_SIZE  -- only flag mines within 3 tiles of the bot
local FLAGS_PER_BURST = 4             -- flags fired per sweep
local FLAG_SPACING    = 0.07          -- seconds between them (~11 flags/sec)

local cachedToken   = nil
local flagState     = {}   -- part -> { tries = n, last = tick() }  (placing)
local unflagState   = {}   -- part -> { tries = n, last = tick() }  (clearing bad flags)
local consecFails   = 0

local function extractToken()
    local mouse = LocalPlayer:GetMouse()
    local ok, conns = pcall(getconnections, mouse.Button1Down)
    if not ok then return nil end
    for _, conn in ipairs(conns) do
        local ok2, ups = pcall(debug.getupvalues, conn.Function)
        if ok2 then
            for _, v in pairs(ups) do
                if type(v) == "string" and #v > 10 and v:match("^%d+$") then return v end
            end
        end
    end
    return nil
end

local function getToken()
    if not cachedToken then cachedToken = extractToken() end
    return cachedToken
end

-- Fires at most one flag per tick so we never burst, and retries silently
-- dropped ones. Runs alongside movement without ever blocking it.
local function spawnFlagger()
    task.spawn(function()
        while aiEnabled and alive do
            local sol = solution           -- grab the reference once
            -- Flagless rounds reject every flag; do not waste calls on them.
            if sol and boardSetting("Flagless", false) ~= true then
                local hrp = LocalPlayer.Character
                    and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local now   = tick()
                    local cands = {}

                    -- ── Correct provably-wrong flags ───────────────────────
                    -- Anyone can flag anything. If our own deduction proves a
                    -- flagged tile is SAFE, that flag is simply wrong, so clear
                    -- it (firing PlaceFlag again toggles it off) and let the
                    -- sweep reveal the tile normally.
                    for cell in pairs(sol.safe) do
                        local part = cell.part
                        if part:FindFirstChildOfClass("Model")
                            and not part:FindFirstChild("NumberGui")
                            and (part.Position - hrp.Position).Magnitude <= FLAG_RADIUS then
                            local st = unflagState[part]
                            if (not st) or (st.tries < 3 and now - st.last > 1.5) then
                                st = st or { tries = 0 }
                                st.tries += 1
                                st.last   = now
                                unflagState[part] = st
                                local tk = getToken()
                                if tk then
                                    PlaceFlag:FireServer(part, tk, true)
                                    task.wait(FLAG_SPACING)
                                end
                            end
                        end
                    end

                    for cell in pairs(sol.mine) do
                        local part = cell.part
                        -- Live check, not the snapshot: a flag placed since the last
                        -- solve must never be fired at again (that would toggle it OFF).
                        if part:FindFirstChildOfClass("Model") then
                            if flagState[part] then
                                flagState[part] = nil          -- landed; leave it alone for good
                                consecFails = 0                -- proof the token still works
                            end
                        elseif not part:FindFirstChild("NumberGui") then
                            local st = flagState[part]
                            -- Retries are judged on the NEXT sweep, so firing never blocks.
                            if (not st) or (st.tries < 4 and now - st.last > 1.5) then
                                local d = (part.Position - hrp.Position).Magnitude
                                if d <= FLAG_RADIUS then
                                    cands[#cands + 1] = { part = part, d = d, st = st }
                                end
                            end
                        end
                    end

                    table.sort(cands, function(a, b) return a.d < b.d end)

                    local token = getToken()
                    if token then
                        for i = 1, math.min(#cands, FLAGS_PER_BURST) do
                            if not aiEnabled then break end
                            local e  = cands[i]
                            local st = e.st or { tries = 0 }
                            st.tries += 1
                            st.last   = now
                            flagState[e.part] = st
                            PlaceFlag:FireServer(e.part, token, true)
                            consecFails += 1        -- cleared above as soon as one lands
                            task.wait(FLAG_SPACING)
                        end
                        -- Nothing landing at all usually means the token rotated
                        if consecFails >= 12 then
                            cachedToken = extractToken()
                            consecFails = 0
                        end
                    end
                end
            end
            task.wait(0.05)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
--  MOVEMENT — cardinal, known-safe only, tight turns, no blind fallback
-- ═══════════════════════════════════════════════════════════════════════════
local ARRIVE_TIGHT = 1.3   -- studs; must be well inside the 5-stud tile
local SEG_TIMEOUT  = 6

-- Bot walk speed. 16 is the Roblox default; higher clears the board faster but
-- carries more momentum through turns.
local botSpeed = 16

local function applyBotSpeed()
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed ~= botSpeed then hum.WalkSpeed = botSpeed end
end

track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if alive and aiEnabled then applyBotSpeed() end
end))

local function charCell(sol)
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local cx = math.round(hrp.Position.X / TILE_SIZE)
    local cy = math.round(hrp.Position.Z / TILE_SIZE)
    return sol.snap.byKey[cellKey(cx, cy)]
end

-- A cell may be crossed if we know it will not kill us.
-- Flagged tiles count: the flag blocks the reveal, so they act as safe bridges
-- across mine fields and often give a much shorter route than going around.
local function isWalkable(cell, sol)
    -- Scorching sets a tile alight once stepped on, so a route may not reuse it.
    if challengeOn("Scorching") and burnedTiles[cell.part] then return false end
    if cell.flagged then return true end
    if sol.mine[cell] then return false end   -- known mine with no flag on it yet
    return cell.revealed or sol.safe[cell]
end

-- True when standing here puts the character's body within reach of a tile that
-- could still be a mine. The body is ~2 studs wide on a 5-stud tile, so being
-- even a stud off-centre on one of these can clip the neighbour.
local function riskyCell(cell, sol)
    for _, n in ipairs(cell.n8) do
        if not n.revealed and not n.flagged and not sol.safe[n] then return true end
    end
    return false
end

-- BFS over cardinal steps. `goal` may itself be unknown (a deliberate guess);
-- every intermediate cell must be known-safe.
-- avoidRisky routes through the middle of proven-safe ground instead of hugging
-- the frontier. The goal is exempt (it is nearly always on the frontier itself).
local function findPath(sol, startCell, goalCell, avoidRisky)
    if startCell == goalCell then return { goalCell } end

    local queue, head = { startCell }, 1
    local visited     = { [startCell] = true }
    local parent      = {}

    while head <= #queue do
        local cur = queue[head]; head += 1
        for _, n in ipairs(cur.n4) do
            if not visited[n] then
                visited[n] = true
                if n == goalCell then
                    parent[n] = cur
                    local path, node = {}, goalCell
                    while node do table.insert(path, 1, node); node = parent[node] end
                    return path
                end
                if isWalkable(n, sol)
                    and not (avoidRisky and riskyCell(n, sol)) then
                    parent[n] = cur
                    queue[#queue + 1] = n
                end
            end
        end
    end
    return nil
end

-- Interior route if one exists, otherwise accept the frontier one.
local function routeTo(sol, startCell, goalCell)
    return findPath(sol, startCell, goalCell, true)
        or findPath(sol, startCell, goalCell, false)
end

-- One BFS from the character giving the TRUE step distance to every cell at
-- once. Cells we may step onto but not through (an unknown guess target) still
-- get a distance; they just are not expanded from.
local function distanceField(sol, startCell)
    local dist  = { [startCell] = 0 }
    local queue, head = { startCell }, 1
    while head <= #queue do
        local cur = queue[head]; head += 1
        local nd  = dist[cur] + 1
        for _, n in ipairs(cur.n4) do
            if dist[n] == nil then
                dist[n] = nd
                if isWalkable(n, sol) then queue[#queue + 1] = n end
            end
        end
    end
    return dist
end

-- Collapse a cell path into straight runs, so we only stop precisely at turns.
local function compressPath(path)
    if #path <= 2 then return path end
    local out = { path[1] }
    for i = 2, #path - 1 do
        local a, b, c = path[i - 1], path[i], path[i + 1]
        local turning = not ((a.cx == b.cx and b.cx == c.cx) or (a.cy == b.cy and b.cy == c.cy))
        if turning then out[#out + 1] = b end
    end
    out[#out + 1] = path[#path]
    return out
end

-- Follow the whole path in one continuous motion.
--
-- The character is retargeted to the next corner BEFORE it reaches the current
-- one, so it never decelerates to a standstill mid-route. Straight runs are
-- collapsed into single long legs, so on open ground it walks flat out; it only
-- eases through corners, which is what a person actually looks like.
--
-- Rounding is bounded by ADVANCE_AT. At 1.8 studs it stays comfortably inside
-- the 2.5-stud half-width of a tile, so a rounded corner still cannot clip the
-- diagonal neighbour.
local ADVANCE_AT = 1.8   -- retarget this far out; keeps momentum, stays on the line
local FINAL_AT   = 1.2   -- stopping here leaves ~1.3 studs of body clearance

-- ── Teleport mode ──────────────────────────────────────────────────────────
-- Drops the character straight onto a tile centre. Faster than walking, cannot
-- clip a neighbouring tile on the way, and reaches safe tiles that are sealed
-- off from every walking route. The game does run an anti-cheat, so this keeps
-- a deliberate gap between hops rather than blinking instantly across the board.
local teleportMode   = false
local TELEPORT_DELAY = 0.03   -- gap between hops
local REVEAL_FRAMES  = 10     -- give up on a hop after this many frames

-- Resting height of the root above whatever it is standing on. R6 reports
-- HipHeight 0 but stands ~2 studs up on its legs; R15 reports it directly.
local function restHeight()
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return 3.0 end
    local hip = (hum.HipHeight and hum.HipHeight > 0) and hum.HipHeight or 2.0
    return hip + hrp.Size.Y / 2
end

local function teleportTo(cell)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    -- Land ON the tile with a slight overlap rather than dropping in from
    -- above. Waiting for gravity cost a fall every hop; overlapping means the
    -- contact — and therefore the Touched that reveals the tile — is generated
    -- on the very next physics step.
    local top = cell.part.Position.Y + cell.part.Size.Y / 2
    hrp.CFrame = CFrame.new(cell.pos.X, top + restHeight() - 0.4, cell.pos.Z)
    hrp.AssemblyLinearVelocity = Vector3.zero      -- carried momentum would fling us off

    for _ = 1, REVEAL_FRAMES do
        if not aiEnabled then return false end
        RunService.Heartbeat:Wait()
        if cell.part:FindFirstChild("NumberGui") then
            burnedTiles[cell.part] = true
            return true                            -- usually within a frame or two
        end
    end
    return false
end

local function walkPath(path, sol)
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return false end

    -- Deliberately NOT compressed. Aiming at a waypoint several tiles away means
    -- that any nudge off the centre line turns the correction into a diagonal
    -- across tiles that are not on the route — which is how the bot drifted into
    -- unknowns. Cell-by-cell legs are only 5 studs, so every leg is a short
    -- straight hop between adjacent tile centres and can never leave those two
    -- tiles. Handing off 1.8 studs early still keeps it moving continuously.
    local pts = {}
    for _, c in ipairs(path) do
        pts[#pts + 1] = Vector3.new(c.pos.X, 0, c.pos.Z)
    end
    if #pts == 0 then return false end

    -- Conveyors (and Slippery ground) shove the character off course, so the
    -- aim point has to be refreshed constantly instead of once per leg.
    local pushed = challengeOn("Conveyors") or boardSetting("Slippery", false) == true
    local reaim  = pushed and 0.15 or 1.0

    local i = 1
    do
        local p = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
        if #pts > 1 and (pts[1] - p).Magnitude < ADVANCE_AT then i = 2 end
    end

    local aimed, stuck, lastD = -1, 0, math.huge

    while i <= #pts do
        if not aiEnabled then hum.WalkSpeed = botSpeed; return false end

        local p      = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
        local d      = (pts[i] - p).Magnitude
        local isLast = (i == #pts)

        if hum.WalkSpeed ~= botSpeed then hum.WalkSpeed = botSpeed end

        if d <= (isLast and FINAL_AT or ADVANCE_AT) then
            if path[i] then burnedTiles[path[i].part] = true end   -- stepped here
            i += 1
            aimed, stuck, lastD = -1, 0, math.huge
            continue
        end

        if aimed < 0 or tick() - aimed > reaim then
            hum:MoveTo(Vector3.new(pts[i].X, hrp.Position.Y, pts[i].Z))
            aimed = tick()
        end

        if d > lastD - 0.02 then stuck += 1 else stuck = 0 end
        lastD = d
        if stuck > 150 then hum.WalkSpeed = botSpeed; return false end

        RunService.Heartbeat:Wait()
    end

    hum.WalkSpeed = botSpeed
    return true
end

-- Targets that refuse to reveal after repeated visits, so one bad cell cannot
-- stall the sweep. File-scope because buildTour consults it too.
local stubborn = {}

-- Chain several safe tiles into ONE route.
--
-- A tile proven safe stays safe — new deductions only ever ADD safe tiles, they
-- never retract one. So the currently-known safe set can be visited in sequence
-- without re-solving in between, which is what lets the bot walk continuously
-- instead of stopping dead on every reveal to think.
local TOUR_TARGETS = 10
local MAX_LINK     = 7    -- never chain to a target further than this; re-solve instead

local function buildTour(sol, start)
    local route, taken = {}, {}
    local cur = start

    for n = 1, TOUR_TARGETS do
        local dist = distanceField(sol, cur)
        local best, bestD
        for cell in pairs(sol.safe) do
            if not cell.revealed and not cell.flagged
                and not taken[cell] and (stubborn[cell] or 0) < 3 then
                local d = dist[cell]
                if d and (not bestD or d < bestD) then bestD, best = d, cell end
            end
        end
        if not best then break end

        -- Only ever extend the sweep to something close. If the nearest
        -- remaining tile is far, stop and re-solve: revealing what we just
        -- walked over usually opens up something nearer than that jump.
        if n > 1 and bestD > MAX_LINK then break end

        local seg = routeTo(sol, cur, best)
        if not seg then taken[best] = true; continue end

        -- skip seg[1]; it is the cell we are already standing on
        for i = (#route == 0) and 1 or 2, #seg do
            local c = seg[i]
            route[#route + 1] = c
            -- Walking over a safe tile reveals it, so everything on the route
            -- is handled. Without this the bot re-targets a tile it already
            -- crossed and walks back for it.
            taken[c] = true
        end
        cur = best
    end

    return route
end

-- ═══════════════════════════════════════════════════════════════════════════
--  AI
-- ═══════════════════════════════════════════════════════════════════════════
local aiStatusLabel
local function setAIStatus(t) if aiStatusLabel then aiStatusLabel.Text = t end end

local function runAI()
    setAIStatus("AI: starting…")
    flagState   = {}
    consecFails = 0
    cachedToken = extractToken()
    applyBotSpeed()
    spawnFlagger()

    stubborn    = {}
    flagState   = {}
    unflagState = {}

    while aiEnabled and alive do
        -- UNCONDITIONAL yield. Several paths below `continue` without moving
        -- (e.g. the bot is already standing on its target, so walkPath returns
        -- instantly), and a loop that can iterate without ever yielding will
        -- wedge the Luau VM outright.
        task.wait(0.05)

        applyBotSpeed()          -- reassert; respawns and the game can reset it
        local sol = refreshSolution(false)
        local me  = charCell(sol)
        if not me then continue end

        -- One BFS serves every decision below.
        local dist = distanceField(sol, me)

        -- ── Phase 1: clear ALL deduced-safe tiles, truly nearest first ─────
        -- Ordering by real walking distance keeps the bot finishing the cluster
        -- it is standing in instead of hopping to something that only looked
        -- close in a straight line.
        -- ── Teleport sweep ─────────────────────────────────────────────────
        -- No pathing involved, so reachability is irrelevant: it can clear
        -- pockets of safe tiles that are completely walled off by mines.
        if teleportMode then
            local list = {}
            for cell in pairs(sol.safe) do
                if not cell.revealed and not cell.flagged and (stubborn[cell] or 0) < 3 then
                    list[#list + 1] = {
                        cell = cell,
                        d    = dist[cell]
                            or (math.abs(cell.cx - me.cx) + math.abs(cell.cy - me.cy)),
                    }
                end
            end
            table.sort(list, function(a, b) return a.d < b.d end)

            if #list > 0 then
                setAIStatus(("AI: teleport sweep  %d left"):format(#list))
                for n = 1, math.min(#list, 30) do
                    if not aiEnabled then break end
                    local c = list[n].cell
                    if not c.part:FindFirstChild("NumberGui") then
                        if teleportTo(c) then
                            stubborn[c] = nil
                        else
                            stubborn[c] = (stubborn[c] or 0) + 1
                        end
                        task.wait(TELEPORT_DELAY)
                    end
                end
                continue
            end
        end

        local remaining = 0
        for cell in pairs(sol.safe) do
            if not cell.revealed and not cell.flagged and (stubborn[cell] or 0) < 3
                and dist[cell] then
                remaining += 1
            end
        end

        if remaining > 0 then
            -- One route over several safe tiles, walked without stopping.
            local tour = buildTour(sol, me)
            if #tour > 0 then
                local visiting = {}
                for _, c in ipairs(tour) do
                    if sol.safe[c] and not c.revealed then visiting[#visiting + 1] = c end
                end

                setAIStatus(("AI: sweep %d tiles  (%d left)"):format(#visiting, remaining))
                walkPath(tour, sol)

                -- Anything on the route we walked over that still has not
                -- revealed gets a strike, so it cannot trap the sweep.
                for _, c in ipairs(visiting) do
                    if c.part:FindFirstChild("NumberGui") then
                        stubborn[c] = nil
                    else
                        stubborn[c] = (stubborn[c] or 0) + 1
                    end
                end
            end
            continue                              -- re-solve; the board just changed
        end

        -- ── Phase 2: only now, with nothing certain left, gamble ───────────
        sol = refreshSolution(true)
        me  = charCell(sol) or me
        dist = distanceField(sol, me)
        local probs = sol.probs or {}

        local gBest, gP, gD
        for _, cell in ipairs(sol.snap.cells) do
            if not cell.revealed and not cell.flagged
                and not sol.mine[cell] and probs[cell]
                and (teleportMode or dist[cell]) then
                local p = probs[cell]
                local d = dist[cell]
                    or (math.abs(cell.cx - me.cx) + math.abs(cell.cy - me.cy))
                if (not gP) or p < gP - 1e-9
                    or (math.abs(p - gP) < 1e-9 and d < gD) then
                    gBest, gP, gD = cell, p, d
                end
            end
        end

        if gBest then
            setAIStatus(("AI: guess %.0f%% risk (%d steps)"):format(gP * 100, gD))
            if teleportMode then
                teleportTo(gBest)
            else
                local path = routeTo(sol, me, gBest)
                if path then walkPath(path, sol) end
            end
            task.wait(0.1)
        else
            setAIStatus("AI: no reachable move")
            task.wait(0.5)
        end
    end

    setAIStatus("AI: off")
end

-- ═══════════════════════════════════════════════════════════════════════════
--  Background solve for the ESP (independent of the AI)
-- ═══════════════════════════════════════════════════════════════════════════
task.spawn(function()
    while alive do
        if espEnabled then
            local ok, sol = pcall(refreshSolution, false)
            if ok and sol then pcall(renderESP, sol) end
        end
        task.wait(0.25)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  GUI
-- ═══════════════════════════════════════════════════════════════════════════
local screenGui = Instance.new("ScreenGui")
screenGui.Name         = "MineESP_Solo_GUI"
screenGui.ResetOnSpawn = false
screenGui.Parent       = LocalPlayer.PlayerGui

local frame = Instance.new("Frame")
frame.Size             = UDim2.new(0, 195, 0, 228)
frame.Position         = UDim2.new(0, 10, 0.5, -68)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
frame.BorderSizePixel  = 0
frame.Parent           = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(255, 180, 0); stroke.Thickness = 2

local function makeLabel(parent, pos, size, text, col, fs)
    local l = Instance.new("TextLabel", parent)
    l.Size = size; l.Position = pos
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = col or Color3.fromRGB(255,255,255)
    l.Font = Enum.Font.GothamBold
    l.TextXAlignment = Enum.TextXAlignment.Left
    if fs then l.TextSize = fs; l.TextScaled = false else l.TextScaled = true end
    return l
end

makeLabel(frame, UDim2.new(0,8,0,4), UDim2.new(1,-8,0,22), "💣 MINE ESP  (Solo)", Color3.fromRGB(255,180,0))
local mineCountLabel = makeLabel(frame, UDim2.new(0,8,0,28), UDim2.new(1,-8,0,17), "Mines: ? | Flags: ?", Color3.fromRGB(220,220,220), 13)
local deduceLabel    = makeLabel(frame, UDim2.new(0,8,0,47), UDim2.new(1,-8,0,15), "🔴 Confirmed: 0  🟢 Safe: 0", Color3.fromRGB(200,200,200), 12)
makeLabel(frame, UDim2.new(0,8,0,64), UDim2.new(1,-8,0,13), "🟡 Unknown  🔴 Mine  🟢 Safe", Color3.fromRGB(170,170,170), 11)
aiStatusLabel = makeLabel(frame, UDim2.new(0,8,0,79), UDim2.new(1,-8,0,13), "AI: off", Color3.fromRGB(100,200,255), 11)

local function makeBtn(parent, pos, size, text, col)
    local b = Instance.new("TextButton", parent)
    b.Size = size; b.Position = pos
    b.BackgroundColor3 = col
    b.Text = text; b.TextColor3 = Color3.fromRGB(255,255,255)
    b.TextScaled = true; b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,5)
    return b
end

local espToggle = makeBtn(frame, UDim2.new(0,5,0,96),   UDim2.new(0.48,-7,0,24), "ESP: ON",  Color3.fromRGB(200,150,0))
local aiToggle  = makeBtn(frame, UDim2.new(0.5,2,0,96), UDim2.new(0.48,-7,0,24), "AI: OFF",  Color3.fromRGB(70,70,70))

espToggle.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    if espEnabled then
        espToggle.Text = "ESP: ON";  espToggle.BackgroundColor3 = Color3.fromRGB(200,150,0)
    else
        espToggle.Text = "ESP: OFF"; espToggle.BackgroundColor3 = Color3.fromRGB(70,70,70)
        removeAllBoxes()
    end
end)

aiToggle.MouseButton1Click:Connect(function()
    aiEnabled = not aiEnabled
    if aiEnabled then
        aiToggle.Text = "AI: ON"; aiToggle.BackgroundColor3 = Color3.fromRGB(0,170,80)
        aiThread = task.spawn(runAI)
    else
        aiToggle.Text = "AI: OFF"; aiToggle.BackgroundColor3 = Color3.fromRGB(70,70,70)
        if aiThread then task.cancel(aiThread); aiThread = nil end
        local char = LocalPlayer.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum and char:FindFirstChild("HumanoidRootPart") then
            hum.WalkSpeed = 16                       -- hand control back at normal speed
            hum:MoveTo(char.HumanoidRootPart.Position)
        end
        setAIStatus("AI: off")
    end
end)

track(RunService.Heartbeat:Connect(function()
    mineCountLabel.Text = ("Mines: %s | Flags: %s"):format(
        tostring(MinesVal and MinesVal.Value or "?"),
        tostring(FlagsVal and FlagsVal.Value or "?"))
    local sol = solution
    local cM, cS = 0, 0
    if sol then
        for _ in pairs(sol.mine) do cM += 1 end
        for cell in pairs(sol.safe) do if not cell.revealed then cS += 1 end end
    end
    deduceLabel.Text = ("🔴 Confirmed: %d  🟢 Safe: %d"):format(cM, cS)
end))

-- ── Bot speed selector ─────────────────────────────────────────────────────
local speedLabel = makeLabel(frame, UDim2.new(0,8,0,124), UDim2.new(1,-8,0,12),
    "Bot speed: 16 (default)", Color3.fromRGB(160,160,160), 11)

local speedBtns = {}
local SPEED_ON  = Color3.fromRGB(0,120,190)
local SPEED_OFF = Color3.fromRGB(40,40,60)

local function selectSpeed(v, label)
    botSpeed = v
    speedLabel.Text = ("Bot speed: %d%s"):format(v, v == 16 and " (default)" or "")
    for sv, b in pairs(speedBtns) do
        b.BackgroundColor3 = (sv == v) and SPEED_ON or SPEED_OFF
    end
    if aiEnabled then applyBotSpeed() end
end

local function makeSpeedBtn(v, text, xScale, xOff)
    local b = makeBtn(frame, UDim2.new(xScale, xOff, 0, 139),
        UDim2.new(0.32, -5, 0, 19), text, SPEED_OFF)
    b.TextSize = 11; b.TextScaled = false
    speedBtns[v] = b
    b.MouseButton1Click:Connect(function() selectSpeed(v, text) end)
    return b
end

makeSpeedBtn(16, "16",  0,     5)
makeSpeedBtn(30, "30",  0.335, 1)
makeSpeedBtn(60, "60",  0.67, -3)
selectSpeed(16)

-- ── Challenge adaptation ───────────────────────────────────────────────────
local challengeLabel = makeLabel(frame, UDim2.new(0,8,0,162), UDim2.new(1,-10,0,12),
    "Mode: none", Color3.fromRGB(150,200,255), 10)

local challengeBtn = makeBtn(frame, UDim2.new(0,5,0,176), UDim2.new(0.48,-7,0,22),
    "CHALLENGE", Color3.fromRGB(90,60,150))

local teleportBtn = makeBtn(frame, UDim2.new(0.5,2,0,176), UDim2.new(0.48,-7,0,22),
    "TP: OFF", Color3.fromRGB(70,70,70))

teleportBtn.MouseButton1Click:Connect(function()
    teleportMode = not teleportMode
    teleportBtn.Text = teleportMode and "TP: ON" or "TP: OFF"
    teleportBtn.BackgroundColor3 = teleportMode
        and Color3.fromRGB(0,150,170) or Color3.fromRGB(70,70,70)
end)

challengeBtn.MouseButton1Click:Connect(function()
    challengeMode = not challengeMode
    challengeBtn.Text = challengeMode and "CHALLENGE" or "CHLG: OFF"
    challengeBtn.BackgroundColor3 = challengeMode
        and Color3.fromRGB(90,60,150) or Color3.fromRGB(70,70,70)
end)

-- Which adaptations actually exist, so the readout cannot overstate itself.
local HANDLED = {
    Disappearance = true,   -- numbers remembered once seen
    Scorching     = true,   -- never re-cross a burned tile
    Conveyors     = true,   -- constant re-aim against the push
    Confusion     = true,   -- reads text, never colour
    Malfunction   = true,   -- solver already re-reads the board every pass
}

track(RunService.Heartbeat:Connect(function()
    local act = activeChallenges()
    if #act == 0 then
        challengeLabel.Text = "Mode: none"
        challengeLabel.TextColor3 = Color3.fromRGB(150,200,255)
        return
    end
    local parts, anyUnhandled = {}, false
    for _, name in ipairs(act) do
        if HANDLED[name] then
            parts[#parts + 1] = name
        else
            parts[#parts + 1] = name .. "!"
            anyUnhandled = true
        end
    end
    challengeLabel.Text = "Mode: " .. table.concat(parts, ", ")
    challengeLabel.TextColor3 = anyUnhandled
        and Color3.fromRGB(255,190,90) or Color3.fromRGB(150,255,180)
end))

local unloadBtn = makeBtn(frame, UDim2.new(0,5,0,202), UDim2.new(1,-10,0,20), "UNLOAD", Color3.fromRGB(120,30,30))
unloadBtn.MouseButton1Click:Connect(function()
    aiEnabled  = false
    espEnabled = false
    if aiThread then task.cancel(aiThread); aiThread = nil end
    teardown()                     -- stops every loop and disconnects everything
    _G.__MineESP_stop = nil
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum and char:FindFirstChild("HumanoidRootPart") then
        hum.WalkSpeed = 16
        hum:MoveTo(char.HumanoidRootPart.Position)
    end
    print("[MineESP+AI] Unloaded.")
end)

do
    local drag, ds, sp
    frame.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag=true; ds=i.Position; sp=frame.Position end
    end)
    frame.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag=false end
    end)
    track(game:GetService("UserInputService").InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - ds
            frame.Position = UDim2.new(sp.X.Scale, sp.X.Offset+d.X, sp.Y.Scale, sp.Y.Offset+d.Y)
        end
    end))
end

print("[MineESP+AI] Loaded.")