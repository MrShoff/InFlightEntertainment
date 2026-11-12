-- Chess Puzzles, modelled on chess.com's rated puzzles:
--  * the opponent's move is played first, then you find the best continuation
--  * click-click or drag-and-drop, legal-move dots, last-move highlights
--  * green check / red X badges, Retry / Hint / Solution / Next
--  * an Elo-style puzzle rating that rises and falls with each puzzle
local _, IFE = ...
local E = IFE.ChessEngine

local SQ = 60
local BOARD = SQ * 8
local LIGHT, DARK = "#eeeed2", "#769656"
local LIGHT_HL, DARK_HL = "#f6f669", "#baca2b"
local HINT_HL = "#f0b928"
local GREEN, RED = "#81b64c", "#ca3431"
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local function PieceTex(p)
    if not p then return nil end
    local color = (p == p:upper()) and "w" or "b"
    return IFE.MEDIA .. color .. p:lower()
end

local Chess = {}
Chess.__index = Chess

-- Original synthesized sounds in the style of chess.com's board sounds.
local function Sound(name)
    if IFE.db.chess.sound == false then return end
    PlaySoundFile(IFE.MEDIA .. "Sounds\\" .. name .. ".ogg", "SFX")
end

-- Pick the sound for a move that has just been made (before -> after).
local function MoveSound(before, after, m, isPlayer)
    if E.InCheck(after) then return "move-check" end
    if m.promo then return "promote" end
    if after.rookMove then return "castle" end
    if after.captured then return "capture" end
    return isPlayer and "move-self" or "move-opponent"
end

---------------------------------------------------------------------------
-- Board construction
---------------------------------------------------------------------------
function Chess:BuildBoard()
    local board = CreateFrame("Frame", nil, self.frame)
    board:SetSize(BOARD, BOARD)
    board:SetPoint("LEFT", 0, 0)
    board:EnableMouse(true)
    self.board = board

    self.cells = {}
    for row = 0, 7 do
        for col = 0, 7 do
            local cell = {}
            local x, y = col * SQ, row * SQ
            local isDark = (col + row) % 2 == 0
            cell.dark = isDark
            cell.bg = IFE.Rect(board, "BACKGROUND", isDark and DARK or LIGHT)
            cell.bg:SetSize(SQ, SQ)
            cell.bg:SetPoint("BOTTOMLEFT", x, y)
            cell.hl = board:CreateTexture(nil, "BORDER")
            cell.hl:SetSize(SQ, SQ)
            cell.hl:SetPoint("BOTTOMLEFT", x, y)
            cell.hl:Hide()
            cell.piece = board:CreateTexture(nil, "ARTWORK")
            cell.piece:SetSize(SQ, SQ)
            cell.piece:SetPoint("BOTTOMLEFT", x, y)
            cell.dot = board:CreateTexture(nil, "OVERLAY", nil, 1)
            cell.dot:SetPoint("CENTER", cell.bg, "CENTER")
            cell.dot:Hide()
            cell.badge = board:CreateTexture(nil, "OVERLAY", nil, 3)
            cell.badge:SetSize(26, 26)
            cell.badge:SetPoint("CENTER", cell.bg, "TOPRIGHT", -4, -4)
            cell.badge:Hide()
            local labelColor = isDark and LIGHT or DARK
            if col == 0 then
                cell.rankLabel = IFE.Text(board, 12, labelColor, IFE.FONT, nil, "OVERLAY")
                cell.rankLabel:SetPoint("TOPLEFT", cell.bg, "TOPLEFT", 3, -3)
            end
            if row == 0 then
                cell.fileLabel = IFE.Text(board, 12, labelColor, IFE.FONT, nil, "OVERLAY")
                cell.fileLabel:SetPoint("BOTTOMRIGHT", cell.bg, "BOTTOMRIGHT", -3, 3)
            end
            self.cells[row * 8 + col] = cell
        end
    end

    -- floating layer for drag and move animation
    local layer = CreateFrame("Frame", nil, board)
    layer:SetAllPoints()
    layer:SetFrameLevel(board:GetFrameLevel() + 5)
    self.layer = layer
    self.floatTex = layer:CreateTexture(nil, "OVERLAY", nil, 7)
    self.floatTex:SetSize(SQ, SQ)
    self.floatTex:Hide()
    self.hover = CreateFrame("Frame", nil, layer)
    self.hover:SetSize(SQ, SQ)
    local hb = IFE.Border(self.hover, "#ffffff", 3, "OVERLAY")
    hb:SetColor("#ffffff", 0.75)
    self.hover:Hide()
    self.animDriver = CreateFrame("Frame", nil, board)

    board:SetScript("OnMouseDown", function(_, button) self:OnBoardMouseDown(button) end)
    board:SetScript("OnMouseUp", function(_, button) self:OnBoardMouseUp(button) end)

    self:BuildPromotion()
end

function Chess:BuildPromotion()
    local p = CreateFrame("Frame", nil, self.board)
    p:SetSize(SQ, SQ * 4 + 24)
    p:SetFrameLevel(self.board:GetFrameLevel() + 20)
    p:EnableMouse(true)
    local bg = IFE.Rect(p, "BACKGROUND", "#ffffff")
    bg:SetAllPoints()
    local shadow = IFE.Rect(p, "BACKGROUND", "#000000", 0.35, -1)
    shadow:SetPoint("TOPLEFT", -3, 3); shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    p.buttons = {}
    for i, kind in ipairs({ "q", "n", "r", "b" }) do
        local b = CreateFrame("Button", nil, p)
        b:SetSize(SQ, SQ)
        b:SetPoint("TOP", 0, -(i - 1) * SQ)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        local hl = IFE.Rect(b, "HIGHLIGHT", "#000000", 0.12)
        hl:SetAllPoints()
        b.kind = kind
        b:SetScript("OnClick", function()
            p:Hide()
            if p.callback then p.callback(kind) end
        end)
        p.buttons[i] = b
    end
    local cancel = CreateFrame("Button", nil, p)
    cancel:SetSize(SQ, 24)
    cancel:SetPoint("BOTTOM")
    local cbg = IFE.Rect(cancel, "ARTWORK", "#f1f1f1")
    cbg:SetAllPoints()
    local ct = IFE.Text(cancel, 14, "#8b8987", IFE.FONT)
    ct:SetPoint("CENTER")
    ct:SetText("x")
    cancel:SetScript("OnClick", function() p:Hide(); self:Render() end)
    p:Hide()
    self.promo = p
end

---------------------------------------------------------------------------
-- Side panel
---------------------------------------------------------------------------
local BTN = { bg = "#3c3a37", fg = "#ffffff", size = 13, disabledBg = "#2b2a28", disabledFg = "#6b6a68" }
local BTN_GREEN = { bg = "#81b64c", fg = "#ffffff", size = 16, hover = "#ffffff", hoverAlpha = 0.12 }

function Chess:BuildPanel()
    local panel = CreateFrame("Frame", nil, self.frame)
    panel:SetPoint("TOPLEFT", self.board, "TOPRIGHT", 16, 0)
    panel:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, (548 - BOARD) / 2)
    local bg = IFE.Rect(panel, "BACKGROUND", "#262522")
    bg:SetAllPoints()
    self.panel = panel
    local W = 180 - 24

    local turn = CreateFrame("Frame", nil, panel)
    turn:SetPoint("TOPLEFT", 12, -12); turn:SetPoint("TOPRIGHT", -12, -12)
    turn:SetHeight(46)
    turn.bg = IFE.Rect(turn, "BACKGROUND", "#ffffff")
    turn.bg:SetAllPoints()
    turn.icon = turn:CreateTexture(nil, "ARTWORK")
    turn.icon:SetSize(34, 34)
    turn.icon:SetPoint("LEFT", 6, 0)
    turn.text = IFE.Text(turn, 14, "#312e2b", IFE.FONT)
    turn.text:SetPoint("LEFT", turn.icon, "RIGHT", 6, 0)
    self.turnBox = turn

    self.statusTitle = IFE.Text(panel, 20, "#ffffff", IFE.FONT)
    self.statusTitle:SetPoint("TOPLEFT", turn, "BOTTOMLEFT", 0, -18)
    self.statusTitle:SetWidth(W); self.statusTitle:SetJustifyH("LEFT")
    self.statusBody = IFE.Text(panel, 12, "#bababa", IFE.FONT)
    self.statusBody:SetPoint("TOPLEFT", self.statusTitle, "BOTTOMLEFT", 0, -6)
    self.statusBody:SetWidth(W); self.statusBody:SetJustifyH("LEFT")

    local function stat(label, anchor, yOff)
        local l = IFE.Text(panel, 11, "#8b8987", IFE.FONT)
        l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff)
        l:SetText(label)
        local v = IFE.Text(panel, 18, "#ffffff", IFE.FONT)
        v:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -3)
        return l, v
    end
    local l1
    l1, self.ratingValue = stat("YOUR RATING", self.statusBody, -22)
    self.ratingDelta = IFE.Text(panel, 14, GREEN, IFE.FONT)
    self.ratingDelta:SetPoint("LEFT", self.ratingValue, "RIGHT", 8, 0)
    local l2
    l2, self.puzzleRating = stat("PUZZLE RATING", self.ratingValue, -12)
    self.themes = IFE.Text(panel, 11, "#8b8987", IFE.FONT)
    self.themes:SetPoint("TOPLEFT", self.puzzleRating, "BOTTOMLEFT", 0, -10)
    self.themes:SetWidth(W); self.themes:SetJustifyH("LEFT")

    self.stats = IFE.Text(panel, 11, "#8b8987", IFE.FONT)
    self.stats:SetPoint("BOTTOM", 0, 166)
    self.stats:SetWidth(W)

    local function StyleSound(b)
        local on = IFE.db.chess.sound ~= false
        b:SetLabel(on and "Sound: On" or "Sound: Off")
        if on then
            b:SetStyleColors(GREEN, "#ffffff", GREEN)
        else
            b:SetStyleColors("#262522", "#8b8987", "#3c3a37")
        end
    end
    local soundBtn = IFE.Button(panel, 74, 20, "", { bg = "#262522", fg = "#8b8987", size = 10, border = "#3c3a37" }, function(b)
        IFE.db.chess.sound = not (IFE.db.chess.sound ~= false)
        StyleSound(b)
        if IFE.db.chess.sound then Sound("move-self") end
    end)
    soundBtn:SetPoint("BOTTOM", 0, 186)
    StyleSound(soundBtn)

    self.nextBtn = IFE.Button(panel, W, 44, "Next", BTN_GREEN, function() self:Next() end)
    self.nextBtn:SetPoint("BOTTOM", 0, 12)
    self.solutionBtn = IFE.Button(panel, W, 30, "Solution", BTN, function() self:ShowSolution() end)
    self.solutionBtn:SetPoint("BOTTOM", self.nextBtn, "TOP", 0, 8)
    self.hintBtn = IFE.Button(panel, W, 30, "Hint", BTN, function() self:Hint() end)
    self.hintBtn:SetPoint("BOTTOM", self.solutionBtn, "TOP", 0, 6)
    self.retryBtn = IFE.Button(panel, W, 30, "Retry", BTN, function() self:Retry() end)
    self.retryBtn:SetPoint("BOTTOM", self.hintBtn, "TOP", 0, 6)
    IFE.Tooltip(self.hintBtn, "Hint", "Highlights the piece to move. Using a hint counts as a failed attempt.")
    IFE.Tooltip(self.solutionBtn, "Solution", "Plays out the rest of the solution. Counts as a failed attempt.")
end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
function Chess:CellOf(sq)
    local f, r = sq % 8, floor(sq / 8)
    if self.flipped then f, r = 7 - f, 7 - r end
    return self.cells[r * 8 + f], f * SQ, r * SQ
end

function Chess:CursorSquare()
    local x, y = GetCursorPosition()
    local s = self.board:GetEffectiveScale()
    x, y = x / s - self.board:GetLeft(), y / s - self.board:GetBottom()
    local col, row = floor(x / SQ), floor(y / SQ)
    if col < 0 or col > 7 or row < 0 or row > 7 then return nil, x, y end
    if self.flipped then col, row = 7 - col, 7 - row end
    return row * 8 + col, x, y
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
function Chess:Render()
    local pos = self.pos
    for row = 0, 7 do
        for col = 0, 7 do
            local cell = self.cells[row * 8 + col]
            local f, r = col, row
            if self.flipped then f, r = 7 - col, 7 - row end
            local sq = r * 8 + f
            local p = pos and pos.board[sq]
            if p and sq ~= self.hiddenSq then
                cell.piece:SetTexture(PieceTex(p)); cell.piece:Show()
            else
                cell.piece:Hide()
            end
            cell.hl:Hide(); cell.dot:Hide(); cell.badge:Hide()
            if cell.rankLabel then cell.rankLabel:SetText(tostring(r + 1)) end
            if cell.fileLabel then cell.fileLabel:SetText(string.char(97 + f)) end
        end
    end
    local function hl(sq, hex, a)
        if not sq then return end
        local cell = self:CellOf(sq)
        IFE.SetColor(cell.hl, hex or (cell.dark and DARK_HL or LIGHT_HL), a or 1)
        cell.hl:Show()
    end
    if self.lastMove then hl(self.lastMove.from); hl(self.lastMove.to) end
    if self.selected then hl(self.selected) end
    if self.hintSq then hl(self.hintSq, HINT_HL, 0.85) end
    if self.selected and self.selectedMoves then
        for _, m in ipairs(self.selectedMoves) do
            local cell = self:CellOf(m.to)
            if pos.board[m.to] or (pos.ep == m.to and pos.board[m.from] and pos.board[m.from]:lower() == "p") then
                cell.dot:SetTexture(IFE.MEDIA .. "ring"); cell.dot:SetSize(SQ, SQ)
            else
                cell.dot:SetTexture(IFE.MEDIA .. "circle"); cell.dot:SetSize(SQ * 0.33, SQ * 0.33)
            end
            cell.dot:SetVertexColor(0, 0, 0, 0.14)
            cell.dot:Show()
        end
    end
    if self.badge then
        local cell = self:CellOf(self.badge.sq)
        cell.badge:SetTexture(IFE.MEDIA .. self.badge.kind)
        cell.badge:Show()
    end
end

function Chess:UpdatePanel()
    local db = IFE.db.chess
    local player = self.player or "w"
    self.turnBox.icon:SetTexture(PieceTex(player == "w" and "K" or "k"))
    IFE.SetColor(self.turnBox.bg, player == "w" and "#ffffff" or "#1f1e1c")
    self.turnBox.text:SetTextColor(IFE.Hex(player == "w" and "#312e2b" or "#ffffff"))
    self.turnBox.text:SetText(player == "w" and "White to Move" or "Black to Move")

    local s = self.state
    local title, body, color = "", "", "#ffffff"
    if s == "intro" then
        title, body = "Get Ready", "Watch your opponent's move."
    elseif s == "player" then
        if self.failed then
            title, body = "Keep Trying", "This puzzle no longer affects your rating."
        else
            title, body = "Your Turn", "Find the best move for " .. (player == "w" and "White" or "Black") .. "."
        end
    elseif s == "correct" or (s == "busy" and self.lastWasCorrect) then
        title, body, color = "Correct!", "Keep going...", GREEN
    elseif s == "wrong" then
        title, body, color = "Incorrect", "That's not the move. Retry, or view the solution.", RED
    elseif s == "solution" then
        title, body = "Solution", "Here's how it goes."
    elseif s == "done" then
        if self.success and not self.failed then
            title, body, color = "Solved!", "Nice work. On to the next one.", GREEN
        elseif self.success then
            title, body, color = "Solved", "Completed after a miss - unrated.", GREEN
        else
            title, body = "Solution Shown", "Study the line, then try the next puzzle."
        end
    elseif s == "busy" then
        title = self.statusTitle:GetText() or ""
        body = self.statusBody:GetText() or ""
        color = nil
    end
    self.statusTitle:SetText(title)
    if color then self.statusTitle:SetTextColor(IFE.Hex(color)) end
    self.statusBody:SetText(body)

    self.ratingValue:SetText(tostring(db.rating))
    if self.ratingChange then
        local d = self.ratingChange
        self.ratingDelta:SetText((d >= 0 and "+" or "") .. d)
        self.ratingDelta:SetTextColor(IFE.Hex(d >= 0 and GREEN or RED))
    else
        self.ratingDelta:SetText("")
    end
    local resolved = s == "done" or self.ratingApplied
    if self.entry then
        self.puzzleRating:SetText(resolved and tostring(self.entry[4]) or "?")
        local themes = ""
        if s == "done" then
            local names = {}
            local skip = { short = 1, long = 1, veryLong = 1, oneMove = 1, advantage = 1, crushing = 1, equality = 1,
                master = 1, masterVsMaster = 1, superGM = 1 }
            for t in self.entry[5]:gmatch("%S+") do
                if not skip[t] then
                    local name = t:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):gsub("^%l", string.upper)
                    names[#names + 1] = name
                end
            end
            themes = table.concat(names, ", ")
        end
        self.themes:SetText(themes)
    end
    self.stats:SetText(string.format("Solved %d of %d   |   Streak %d", db.solved, db.played, db.streak))

    local canAct = s == "player"
    self.hintBtn:SetEnabled(canAct and not self.hintSq)
    self.solutionBtn:SetEnabled(s == "player" or s == "wrong")
    self.retryBtn:SetEnabled(s == "wrong" or s == "done")
    self.retryBtn:SetLabel(s == "done" and "Retry Puzzle" or "Retry")
    self.nextBtn:SetLabel((s == "done" or self.ratingApplied) and "Next Puzzle" or "Skip")
end

---------------------------------------------------------------------------
-- Timers that are cancelled when a new puzzle loads
---------------------------------------------------------------------------
function Chess:After(delay, fn)
    local gen = self.gen
    C_Timer.After(delay, function()
        if self.gen == gen then fn() end
    end)
end

---------------------------------------------------------------------------
-- Moving pieces
---------------------------------------------------------------------------
function Chess:PlayMove(m, animate, done)
    local before = self.pos
    local after = E.MakeMove(before, m)
    local function finish()
        self.hiddenSq = nil
        self.pos = after
        self.lastMove = { from = m.from, to = m.to }
        Sound(MoveSound(before, after, m, E.ColorOf(before.board[m.from]) == self.player))
        self:Render()
        if done then done() end
    end
    if not animate then return finish() end

    local piece = before.board[m.from]
    local _, x1, y1 = self:CellOf(m.from)
    local _, x2, y2 = self:CellOf(m.to)
    self.hiddenSq = m.from
    self:Render()
    local tex = self.floatTex
    tex:SetTexture(PieceTex(piece))
    tex:ClearAllPoints()
    tex:SetPoint("BOTTOMLEFT", self.board, "BOTTOMLEFT", x1, y1)
    tex:Show()
    local t0, dur = GetTime(), 0.2
    self.animDriver:SetScript("OnUpdate", function(driver)
        local t = min(1, (GetTime() - t0) / dur)
        local e = 1 - (1 - t) * (1 - t)
        tex:ClearAllPoints()
        tex:SetPoint("BOTTOMLEFT", self.board, "BOTTOMLEFT", x1 + (x2 - x1) * e, y1 + (y2 - y1) * e)
        if t >= 1 then
            driver:SetScript("OnUpdate", nil)
            tex:Hide()
            finish()
        end
    end)
end

function Chess:Select(sq)
    self.selected = sq
    self.selectedMoves = E.LegalMovesFrom(self.pos, sq)
    self:Render()
end

function Chess:ClearSelection()
    self.selected, self.selectedMoves = nil, nil
    self:Render()
end

function Chess:MovesTo(to)
    local out = {}
    for _, m in ipairs(self.selectedMoves or {}) do
        if m.to == to then out[#out + 1] = m end
    end
    return out
end

function Chess:OwnPiece(sq)
    local p = sq and self.pos.board[sq]
    return p and E.ColorOf(p) == self.player
end

function Chess:OnBoardMouseDown(button)
    if self.promo:IsShown() then self.promo:Hide(); self:ClearSelection(); return end
    if button ~= "LeftButton" then self:ClearSelection(); return end
    if self.state ~= "player" then return end
    local sq = self:CursorSquare()
    if not sq then return end
    if self.selected and sq ~= self.selected and #self:MovesTo(sq) > 0 then
        self:AttemptMove(self.selected, sq, false)
        return
    end
    if self:OwnPiece(sq) then
        self.wasSelected = (self.selected == sq)
        self:Select(sq)
        self:StartDrag(sq)
    else
        self:ClearSelection()
    end
end

function Chess:OnBoardMouseUp(button)
    if not self.dragging then return end
    local from = self.dragging
    self:StopDrag()
    local sq = self:CursorSquare()
    if sq and sq ~= from and self.state == "player" and #self:MovesTo(sq) > 0 then
        self:AttemptMove(from, sq, true)
    elseif sq == from and self.wasSelected then
        self:ClearSelection()
    else
        if sq and sq ~= from then Sound("illegal") end
        self:Render()
    end
end

function Chess:StartDrag(sq)
    self.dragging = sq
    self.hiddenSq = sq
    self:Render()
    local tex = self.floatTex
    tex:SetTexture(PieceTex(self.pos.board[sq]))
    tex:Show()
    local board = self.board
    self.animDriver:SetScript("OnUpdate", function()
        local over, x, y = self:CursorSquare()
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", board, "BOTTOMLEFT", max(0, min(BOARD, x)), max(0, min(BOARD, y)))
        if over then
            local _, cx, cy = self:CellOf(over)
            self.hover:ClearAllPoints()
            self.hover:SetPoint("BOTTOMLEFT", board, "BOTTOMLEFT", cx, cy)
            self.hover:Show()
        else
            self.hover:Hide()
        end
        if not IsMouseButtonDown("LeftButton") then self:OnBoardMouseUp("LeftButton") end
    end)
end

function Chess:StopDrag()
    self.dragging = nil
    self.hiddenSq = nil
    self.animDriver:SetScript("OnUpdate", nil)
    self.floatTex:Hide()
    self.hover:Hide()
end

function Chess:AttemptMove(from, to, dropped)
    local cands = self:MovesTo(to)
    if #cands == 0 then return end
    if #cands > 1 then
        -- promotion: show chess.com-style picker over the target file
        local p = self.promo
        local _, x, y = self:CellOf(to)
        local color = self.player
        for _, b in ipairs(p.buttons) do
            b.tex:SetTexture(PieceTex(color == "w" and b.kind:upper() or b.kind))
        end
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", self.board, "BOTTOMLEFT", x, y + SQ)
        p.callback = function(kind)
            for _, m in ipairs(cands) do
                if m.promo == kind then self:CommitPlayerMove(m, true) return end
            end
        end
        self.hiddenSq = nil
        self:Render()
        p:Show()
        return
    end
    self:CommitPlayerMove(cands[1], dropped)
end

---------------------------------------------------------------------------
-- Puzzle flow
---------------------------------------------------------------------------
function Chess:ApplyResult(win)
    if self.ratingApplied then return end
    self.ratingApplied = true
    local db = IFE.db.chess
    local pr = self.entry[4]
    local expected = 1 / (1 + 10 ^ ((pr - db.rating) / 400))
    local k = db.played < 20 and 40 or 24
    local delta = floor(k * ((win and 1 or 0) - expected) + 0.5)
    if win and delta < 1 then delta = 1 end
    if not win and delta > -1 then delta = -1 end
    db.rating = max(100, db.rating + delta)
    db.played = db.played + 1
    if win then
        db.solved = db.solved + 1
        db.streak = db.streak + 1
        db.bestStreak = max(db.bestStreak, db.streak)
    else
        db.streak = 0
    end
    db.seen[self.entry[1]] = true
    self.ratingChange = delta
end

function Chess:Fail()
    self.failed = true
    self:ApplyResult(false)
end

function Chess:CommitPlayerMove(m, dropped)
    self.selected, self.selectedMoves = nil, nil
    self.hintSq = nil
    local uci = E.ToUCI(m)
    local after = E.MakeMove(self.pos, m)
    local correct = (uci == self.moves[self.ply + 1]) or E.IsCheckmate(after)
    self.undo = { pos = self.pos, lastMove = self.lastMove }
    self.state = "busy"
    self.lastWasCorrect = correct
    self:PlayMove(m, not dropped, function()
        if correct then
            self.ply = self.ply + 1
            self.badge = { sq = m.to, kind = "ok" }
            self:Render()
            if self.ply >= #self.moves or E.IsCheckmate(self.pos) then
                self:Finish(true)
            else
                self.state = "correct"
                self:UpdatePanel()
                self:After(0.45, function() self:PlayOpponent() end)
            end
        else
            self.badge = { sq = m.to, kind = "bad" }
            self.state = "wrong"
            C_Timer.After(0.12, function() Sound("incorrect") end)
            self:Fail()
            self:Render()
            self:UpdatePanel()
        end
    end)
    self:UpdatePanel()
end

function Chess:PlayOpponent()
    local uci = self.moves[self.ply + 1]
    if not uci then return end
    local m = E.MoveFromUCI(self.pos, uci)
    if not m then return end
    self.state = "busy"
    self:PlayMove(m, true, function()
        self.ply = self.ply + 1
        self.badge = nil
        self:Render()
        if self.solutionMode then
            self:After(0.6, function() self:StepSolution() end)
        else
            self.state = "player"
            self:UpdatePanel()
        end
    end)
end

function Chess:Finish(success)
    self.state = "done"
    self.success = success
    self.solutionMode = false
    if success and not self.failed then self:ApplyResult(true) end
    if success then C_Timer.After(0.15, function() Sound("solved") end) end
    self:UpdatePanel()
end

function Chess:StepSolution()
    local uci = self.moves[self.ply + 1]
    if not uci then return self:Finish(false) end
    local m = E.MoveFromUCI(self.pos, uci)
    self.state = "solution"
    self:UpdatePanel()
    self:PlayMove(m, true, function()
        self.ply = self.ply + 1
        self.badge = nil
        self:Render()
        if self.ply >= #self.moves then
            self:Finish(false)
        else
            self:After(0.6, function() self:StepSolution() end)
        end
    end)
end

function Chess:ShowSolution()
    if self.state == "wrong" then self:TakeBack() end
    self:Fail()
    self.solutionMode = true
    self.hintSq = nil
    self.selected, self.selectedMoves = nil, nil
    self.state = "solution"
    self:UpdatePanel()
    self:StepSolution()
end

function Chess:Hint()
    if self.state ~= "player" then return end
    local uci = self.moves[self.ply + 1]
    self.hintSq = E.ParseSquare(uci:sub(1, 2))
    self:Fail()
    self:Render()
    self:UpdatePanel()
end

function Chess:TakeBack()
    if self.undo then
        self.pos, self.lastMove = self.undo.pos, self.undo.lastMove
        self.undo = nil
    end
    self.badge = nil
end

function Chess:Retry()
    if self.state == "wrong" then
        self:TakeBack()
        self.state = "player"
        self:Render()
        self:UpdatePanel()
    elseif self.state == "done" then
        local keep = self.ratingChange
        self:Load(self.entry, true)
        self.ratingChange = keep
        self:UpdatePanel()
    end
end

function Chess:Next()
    if self.entry and not self.ratingApplied then self:ApplyResult(false) end
    self:Load(self:PickPuzzle())
end

function Chess:PickPuzzle()
    local list = InFlightEntertainment_ChessPuzzles
    local db = IFE.db.chess
    local cur = self.entry and self.entry[1]
    for _, window in ipairs({ 100, 200, 400, 800, 5000 }) do
        local cands = {}
        for _, e in ipairs(list) do
            if not db.seen[e[1]] and e[1] ~= cur and abs(e[4] - db.rating) <= window then
                cands[#cands + 1] = e
            end
        end
        if #cands > 0 then return cands[math.random(#cands)] end
    end
    wipe(db.seen) -- played them all; start over
    return list[math.random(#list)]
end

function Chess:Load(entry, isRetry)
    self.gen = (self.gen or 0) + 1
    self:StopDrag()
    self.promo:Hide()
    self.entry = entry
    self.moves = {}
    for mv in entry[3]:gmatch("%S+") do self.moves[#self.moves + 1] = mv end
    self.pos = E.FromFEN(entry[2])
    self.player = self.pos.turn == "w" and "b" or "w"
    self.flipped = self.player == "b"
    self.ply = 0
    self.lastMove, self.selected, self.selectedMoves, self.hintSq, self.badge, self.undo = nil, nil, nil, nil, nil, nil
    self.solutionMode, self.success, self.lastWasCorrect = false, false, false
    if not isRetry then
        self.failed, self.ratingApplied, self.ratingChange = false, false, nil
    end
    self.state = "intro"
    self:Render()
    self:UpdatePanel()
    self:After(0.7, function() self:PlayOpponent() end)
end

function Chess:OnShow()
    if not self.entry then self:Load(self:PickPuzzle()) end
end

function Chess:OnHide()
    if self.dragging then self:StopDrag(); self:Render() end
end

---------------------------------------------------------------------------
IFE:RegisterGame({
    key = "chess",
    title = "Chess Puzzles",
    accent = "#81b64c",
    description = "Find the winning move. Puzzles adapt to your rating as you solve them.",
    create = function(f)
        local self = setmetatable({ frame = f }, Chess)
        self:BuildBoard()
        self:BuildPanel()
        return self
    end,
    status = function()
        local db = IFE.db.chess
        return string.format("Rating %d   -   %d solved", db.rating, db.solved)
    end,
    drawIcon = function(icon)
        for r = 0, 1 do
            for c = 0, 1 do
                local t = IFE.Rect(icon, "BACKGROUND", (r + c) % 2 == 0 and DARK or LIGHT)
                t:SetSize(42, 42)
                t:SetPoint("BOTTOMLEFT", c * 42, r * 42)
            end
        end
        local k = icon:CreateTexture(nil, "ARTWORK")
        k:SetTexture(IFE.MEDIA .. "wn")
        k:SetSize(64, 64)
        k:SetPoint("CENTER")
    end,
})
