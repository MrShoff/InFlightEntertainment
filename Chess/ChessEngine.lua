-- Minimal, complete chess rules: FEN parsing, legal move generation (castling,
-- en passant, promotion), check/checkmate detection, UCI move conversion.
-- Squares are 0..63, index = rank * 8 + file (a1 = 0, h8 = 63).
local _, IFE = ...
local E = {}
IFE.ChessEngine = E

local floor, abs = math.floor, math.abs

local function colorOf(p)
    if not p then return nil end
    return (p == p:upper()) and "w" or "b"
end
E.ColorOf = colorOf

local function at(f, r)
    if f < 0 or f > 7 or r < 0 or r > 7 then return nil end
    return r * 8 + f
end

function E.SquareName(i) return string.char(97 + i % 8) .. (floor(i / 8) + 1) end
function E.ParseSquare(s) return (s:byte(2) - 49) * 8 + (s:byte(1) - 97) end

function E.FromFEN(fen)
    local placement, turn, castle, ep = fen:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
    local pos = { board = {}, turn = turn, castle = {}, ep = nil }
    local r, f = 7, 0
    for c in placement:gmatch(".") do
        if c == "/" then
            r = r - 1; f = 0
        elseif c:find("%d") then
            f = f + tonumber(c)
        else
            pos.board[r * 8 + f] = c; f = f + 1
        end
    end
    for c in castle:gmatch("[KQkq]") do pos.castle[c] = true end
    if ep and ep ~= "-" then pos.ep = E.ParseSquare(ep) end
    return pos
end

function E.Copy(pos)
    local b = {}
    for k, v in pairs(pos.board) do b[k] = v end
    local c = pos.castle
    return { board = b, turn = pos.turn, castle = { K = c.K, Q = c.Q, k = c.k, q = c.q }, ep = pos.ep }
end

local KNIGHT = { { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } }
local KING = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
local ORTHO = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local DIAG = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local PROMOS = { "q", "r", "b", "n" }

local function slideHits(b, f, r, dirs, p1, p2)
    for _, d in ipairs(dirs) do
        local x, y = f + d[1], r + d[2]
        while true do
            local s = at(x, y)
            if not s then break end
            local p = b[s]
            if p then
                if p == p1 or p == p2 then return true end
                break
            end
            x, y = x + d[1], y + d[2]
        end
    end
    return false
end

-- Is square `sq` attacked by side `by` ("w" or "b")?
function E.IsAttacked(pos, sq, by)
    local b = pos.board
    local f, r = sq % 8, floor(sq / 8)
    local w = by == "w"
    local pawn = w and "P" or "p"
    local pr = w and r - 1 or r + 1
    local s = at(f - 1, pr); if s and b[s] == pawn then return true end
    s = at(f + 1, pr); if s and b[s] == pawn then return true end
    local N, K = w and "N" or "n", w and "K" or "k"
    for _, d in ipairs(KNIGHT) do
        s = at(f + d[1], r + d[2]); if s and b[s] == N then return true end
    end
    for _, d in ipairs(KING) do
        s = at(f + d[1], r + d[2]); if s and b[s] == K then return true end
    end
    local Q = w and "Q" or "q"
    if slideHits(b, f, r, ORTHO, w and "R" or "r", Q) then return true end
    if slideHits(b, f, r, DIAG, w and "B" or "b", Q) then return true end
    return false
end

function E.FindKing(pos, side)
    local K = side == "w" and "K" or "k"
    for s = 0, 63 do if pos.board[s] == K then return s end end
end

function E.InCheck(pos, side)
    side = side or pos.turn
    local k = E.FindKing(pos, side)
    return k ~= nil and E.IsAttacked(pos, k, side == "w" and "b" or "w")
end

local function pseudoMoves(pos)
    local moves = {}
    local b, side = pos.board, pos.turn
    local enemy = side == "w" and "b" or "w"
    local function add(from, to, promo) moves[#moves + 1] = { from = from, to = to, promo = promo } end

    for s = 0, 63 do
        local p = b[s]
        if p and colorOf(p) == side then
            local f, r = s % 8, floor(s / 8)
            local t = p:lower()
            if t == "p" then
                local dir = side == "w" and 1 or -1
                local startR, lastR = side == "w" and 1 or 6, side == "w" and 7 or 0
                local function addP(to)
                    if floor(to / 8) == lastR then
                        for _, pp in ipairs(PROMOS) do add(s, to, pp) end
                    else
                        add(s, to)
                    end
                end
                local one = at(f, r + dir)
                if one and not b[one] then
                    addP(one)
                    local two = at(f, r + 2 * dir)
                    if r == startR and two and not b[two] then add(s, two) end
                end
                for df = -1, 1, 2 do
                    local c = at(f + df, r + dir)
                    if c then
                        if b[c] and colorOf(b[c]) == enemy then
                            addP(c)
                        elseif pos.ep == c then
                            add(s, c)
                        end
                    end
                end
            elseif t == "n" or t == "k" then
                for _, d in ipairs(t == "n" and KNIGHT or KING) do
                    local c = at(f + d[1], r + d[2])
                    if c and colorOf(b[c]) ~= side then add(s, c) end
                end
                if t == "k" then
                    local cs = pos.castle
                    if side == "w" and s == 4 then
                        if cs.K and b[7] == "R" and not b[5] and not b[6]
                            and not E.IsAttacked(pos, 4, "b") and not E.IsAttacked(pos, 5, "b") and not E.IsAttacked(pos, 6, "b") then
                            add(4, 6)
                        end
                        if cs.Q and b[0] == "R" and not b[1] and not b[2] and not b[3]
                            and not E.IsAttacked(pos, 4, "b") and not E.IsAttacked(pos, 3, "b") and not E.IsAttacked(pos, 2, "b") then
                            add(4, 2)
                        end
                    elseif side == "b" and s == 60 then
                        if cs.k and b[63] == "r" and not b[61] and not b[62]
                            and not E.IsAttacked(pos, 60, "w") and not E.IsAttacked(pos, 61, "w") and not E.IsAttacked(pos, 62, "w") then
                            add(60, 62)
                        end
                        if cs.q and b[56] == "r" and not b[57] and not b[58] and not b[59]
                            and not E.IsAttacked(pos, 60, "w") and not E.IsAttacked(pos, 59, "w") and not E.IsAttacked(pos, 58, "w") then
                            add(60, 58)
                        end
                    end
                end
            else
                local dirsList = (t == "r" and { ORTHO }) or (t == "b" and { DIAG }) or { ORTHO, DIAG }
                for _, dirs in ipairs(dirsList) do
                    for _, d in ipairs(dirs) do
                        local x, y = f + d[1], r + d[2]
                        while true do
                            local c = at(x, y)
                            if not c then break end
                            local q = b[c]
                            if q then
                                if colorOf(q) == enemy then add(s, c) end
                                break
                            end
                            add(s, c)
                            x, y = x + d[1], y + d[2]
                        end
                    end
                end
            end
        end
    end
    return moves
end

-- Returns a new position with move m applied (m = {from, to, promo}).
function E.MakeMove(pos, m)
    local n = E.Copy(pos)
    local b = n.board
    local p = b[m.from]
    local t = p:lower()
    local side = pos.turn
    local captured = b[m.to]
    b[m.from] = nil
    if t == "p" and m.to == pos.ep and not captured then
        local capSq = m.to + (side == "w" and -8 or 8)
        captured = b[capSq]
        b[capSq] = nil
        n.epCapture = capSq
    end
    if t == "k" and abs(m.to - m.from) == 2 then
        local rf, rt
        if m.to == 6 then rf, rt = 7, 5
        elseif m.to == 2 then rf, rt = 0, 3
        elseif m.to == 62 then rf, rt = 63, 61
        elseif m.to == 58 then rf, rt = 56, 59 end
        b[rt] = b[rf]; b[rf] = nil
        n.rookMove = { from = rf, to = rt }
    end
    if m.promo then p = (side == "w") and m.promo:upper() or m.promo:lower() end
    b[m.to] = p
    n.ep = nil
    if t == "p" and abs(m.to - m.from) == 16 then n.ep = (m.from + m.to) / 2 end
    local c = n.castle
    if t == "k" then
        if side == "w" then c.K, c.Q = false, false else c.k, c.q = false, false end
    end
    for _, sq in ipairs({ m.from, m.to }) do
        if sq == 0 then c.Q = false
        elseif sq == 7 then c.K = false
        elseif sq == 56 then c.q = false
        elseif sq == 63 then c.k = false end
    end
    n.turn = side == "w" and "b" or "w"
    n.captured = captured
    return n
end

function E.LegalMoves(pos)
    local out = {}
    for _, m in ipairs(pseudoMoves(pos)) do
        local n = E.MakeMove(pos, m)
        if not E.InCheck(n, pos.turn) then out[#out + 1] = m end
    end
    return out
end

function E.LegalMovesFrom(pos, sq)
    local out = {}
    for _, m in ipairs(E.LegalMoves(pos)) do
        if m.from == sq then out[#out + 1] = m end
    end
    return out
end

function E.IsCheckmate(pos)
    return E.InCheck(pos) and #E.LegalMoves(pos) == 0
end

function E.ToUCI(m)
    return E.SquareName(m.from) .. E.SquareName(m.to) .. (m.promo or "")
end

function E.MoveFromUCI(pos, uci)
    local from, to, promo = E.ParseSquare(uci:sub(1, 2)), E.ParseSquare(uci:sub(3, 4)), uci:sub(5, 5)
    if promo == "" then promo = nil end
    for _, m in ipairs(E.LegalMoves(pos)) do
        if m.from == from and m.to == to and m.promo == promo then return m end
    end
end
