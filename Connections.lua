-- Connections, modelled on the NYT implementation:
-- 16 words, find four groups of four. Select up to four, Submit; Shuffle; Deselect All.
-- Four mistakes allowed, "One away..." and "Already guessed!" hints, solved groups
-- collapse into coloured bars (yellow < green < blue < purple), results grid at the end.
local _, IFE = ...

local GROUP_COLORS = { "#f9df6d", "#a0c35a", "#b0c4ef", "#ba81c5" }
local TILE_BG, TILE_SEL, INK = "#efefe6", "#5a594e", "#000000"
local TW, TH, GAP = 150, 76, 8
local GRID_W = TW * 4 + GAP * 3
local WIN_MSG = { [0] = "Perfect!", "Great!", "Solid!", "Phew!" }

local CN = {}
CN.__index = CN

local function Puzzles() return InFlightEntertainment_ConnectionsPuzzles or {} end

local function FitText(fs, text, width, sizes)
    for _, size in ipairs(sizes) do
        fs:SetFont(IFE.FONT, size, "")
        fs:SetText(text)
        if fs:GetStringWidth() <= width then return end
    end
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local PILL = { bg = "#ffffff", fg = INK, border = INK, size = 14, hover = "#000000", hoverAlpha = 0.05,
    disabledBg = "#ffffff", disabledFg = "#a5a5a5", disabledBorder = "#a5a5a5" }

function CN:Build()
    local f = self.frame
    local bg = IFE.Rect(f, "BACKGROUND", "#ffffff")
    bg:SetAllPoints()

    self.title = IFE.Text(f, 16, INK, IFE.FONT)
    self.title:SetPoint("TOP", 0, -14)
    self.title:SetText("Create four groups of four!")

    local grid = CreateFrame("Frame", nil, f)
    grid:SetSize(GRID_W, TH * 4 + GAP * 3)
    grid:SetPoint("TOP", 0, -44)
    self.grid = grid

    self.tiles = {}
    for i = 1, 16 do
        local t = CreateFrame("Button", nil, grid)
        t:SetSize(TW, TH)
        t.bg = IFE.Rect(t, "BACKGROUND", TILE_BG)
        t.bg:SetAllPoints()
        t.text = IFE.Text(t, 18, INK, IFE.FONT)
        t.text:SetPoint("CENTER")
        t.text:SetWordWrap(false)
        local hop = t:CreateAnimationGroup()
        local h1 = hop:CreateAnimation("Translation"); h1:SetOffset(0, 8); h1:SetDuration(0.1); h1:SetOrder(1)
        local h2 = hop:CreateAnimation("Translation"); h2:SetOffset(0, -8); h2:SetDuration(0.1); h2:SetOrder(2)
        t.hop = hop
        local shake = t:CreateAnimationGroup()
        for k, dx in ipairs({ -5, 10, -10, 10, -10, 5 }) do
            local a = shake:CreateAnimation("Translation"); a:SetOffset(dx, 0); a:SetDuration(0.05); a:SetOrder(k)
        end
        t.shake = shake
        t:SetScript("OnClick", function() self:ToggleWord(t.word) end)
        self.tiles[i] = t
    end

    self.bars = {}
    for i = 1, 4 do
        local b = CreateFrame("Frame", nil, grid)
        b:SetSize(GRID_W, TH)
        b.bg = IFE.Rect(b, "BACKGROUND", GROUP_COLORS[i])
        b.bg:SetAllPoints()
        b.name = IFE.Text(b, 17, INK, IFE.FONT)
        b.name:SetPoint("CENTER", 0, 11)
        b.words = IFE.Text(b, 15, INK, IFE.FONT_PLAIN)
        b.words:SetPoint("CENTER", 0, -12)
        local fade = b:CreateAnimationGroup()
        local a = fade:CreateAnimation("Alpha"); a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.35)
        local s = fade:CreateAnimation("Scale"); s:SetScale(1.04, 1.04); s:SetDuration(0.15); s:SetOrder(1)
        b.fade = fade
        b:Hide()
        self.bars[i] = b
    end

    -- mistakes
    local mist = CreateFrame("Frame", nil, f)
    mist:SetSize(260, 20)
    mist:SetPoint("TOP", grid, "BOTTOM", 0, -18)
    local ml = IFE.Text(mist, 14, INK, IFE.FONT_PLAIN)
    ml:SetPoint("LEFT", 0, 0)
    ml:SetText("Mistakes Remaining:")
    self.mistakeLabel = ml
    self.dots = {}
    for i = 1, 4 do
        local d = mist:CreateTexture(nil, "ARTWORK")
        d:SetTexture(IFE.MEDIA .. "circle")
        d:SetVertexColor(IFE.Hex(TILE_SEL))
        d:SetSize(15, 15)
        d:SetPoint("LEFT", ml, "RIGHT", 10 + (i - 1) * 22, 0)
        self.dots[i] = d
    end
    self.mistakesRow = mist

    -- buttons
    local row = CreateFrame("Frame", nil, f)
    row:SetSize(3 * 120 + 2 * 12, 44)
    row:SetPoint("TOP", mist, "BOTTOM", 0, -16)
    self.shuffleBtn = IFE.Button(row, 120, 44, "Shuffle", PILL, function() self:Shuffle() end)
    self.shuffleBtn:SetPoint("LEFT")
    self.deselectBtn = IFE.Button(row, 120, 44, "Deselect All", PILL, function() self:DeselectAll() end)
    self.deselectBtn:SetPoint("LEFT", self.shuffleBtn, "RIGHT", 12, 0)
    self.submitBtn = IFE.Button(row, 120, 44, "Submit", PILL, function() self:Submit() end)
    self.submitBtn:SetPoint("LEFT", self.deselectBtn, "RIGHT", 12, 0)
    self.resultsBtn = IFE.Button(f, 180, 44, "View Results", PILL, function() self:ShowResults() end)
    self.resultsBtn:SetPoint("TOP", mist, "BOTTOM", 0, -16)
    self.resultsBtn:Hide()
    self.buttonRow = row

    -- puzzle navigation
    local nav = CreateFrame("Frame", nil, f)
    nav:SetSize(GRID_W, 30)
    nav:SetPoint("BOTTOM", 0, 6)
    local NAV = { bg = "#ffffff", fg = "#5a594e", border = "#c7c7bf", size = 12 }
    self.prevBtn = IFE.Button(nav, 34, 26, "<", NAV, function() self:Load(self.index - 1) end)
    self.prevBtn:SetPoint("LEFT", 0, 0)
    self.nextBtn = IFE.Button(nav, 34, 26, ">", NAV, function() self:Load(self.index + 1) end)
    self.nextBtn:SetPoint("LEFT", self.prevBtn, "RIGHT", 6, 0)
    self.navLabel = IFE.Text(nav, 13, "#5a594e", IFE.FONT)
    self.navLabel:SetPoint("LEFT", self.nextBtn, "RIGHT", 12, 0)
    self.todayBtn = IFE.Button(nav, 110, 26, "Today's Puzzle", NAV, function() self:Load(self:TodayIndex()) end)
    self.todayBtn:SetPoint("RIGHT", 0, 0)
    self.randomBtn = IFE.Button(nav, 120, 26, "Random Unplayed", NAV, function() self:LoadRandomUnplayed() end)
    self.randomBtn:SetPoint("RIGHT", self.todayBtn, "LEFT", -8, 0)

    self.toast = IFE.Toast(f)
    self.toast:SetPoint("TOP", grid, "TOP", 0, 20)
    self.toast:SetFrameLevel(grid:GetFrameLevel() + 40)

    self:BuildResults()
end

function CN:BuildResults()
    local p = CreateFrame("Frame", nil, self.frame)
    p:SetSize(360, 360)
    p:SetPoint("CENTER", 0, 10)
    p:SetFrameLevel(self.frame:GetFrameLevel() + 30)
    p:EnableMouse(true)
    local bg = IFE.Rect(p, "BACKGROUND", "#ffffff")
    bg:SetAllPoints()
    IFE.Border(p, "#c7c7bf", 1)
    local sh = IFE.Rect(p, "BACKGROUND", "#000000", 0.25, -1)
    sh:SetPoint("TOPLEFT", -5, 5); sh:SetPoint("BOTTOMRIGHT", 5, -5)
    local close = IFE.Button(p, 24, 24, "X", { bg = "#ffffff", fg = INK, size = 14 }, function() p:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    p.title = IFE.Text(p, 24, INK, IFE.FONT)
    p.title:SetPoint("TOP", 0, -28)
    p.sub = IFE.Text(p, 13, "#5a594e", IFE.FONT_PLAIN)
    p.sub:SetPoint("TOP", p.title, "BOTTOM", 0, -8)
    p.squares = {}
    for r = 1, 7 do
        p.squares[r] = {}
        for c = 1, 4 do
            local t = IFE.Rect(p, "ARTWORK", "#ffffff")
            t:SetSize(30, 30)
            t:SetPoint("TOPLEFT", p, "TOP", -68 + (c - 1) * 35, -90 - (r - 1) * 35)
            p.squares[r][c] = t
        end
    end
    p.stats = IFE.Text(p, 12, "#5a594e", IFE.FONT_PLAIN)
    p.stats:SetPoint("BOTTOM", 0, 18)
    p:Hide()
    self.results = p
end

---------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------
function CN:TodayIndex()
    return (IFE.DayNumber() % #Puzzles()) + 1
end

function CN:GroupOf(word)
    for gi, g in ipairs(self.puzzle) do
        for _, w in ipairs(g.words) do if w == word then return gi end end
    end
end

function CN:State()
    local prog = IFE.db.connections.progress
    local st = prog[self.index]
    if not st then
        local words = {}
        for _, g in ipairs(self.puzzle) do
            for _, w in ipairs(g.words) do words[#words + 1] = w end
        end
        st = { order = IFE.Shuffle(words), solved = {}, mistakes = 0, guesses = {}, done = false }
        prog[self.index] = st
    end
    return st
end

local function GuessKey(words)
    local t = {}
    for i, w in ipairs(words) do t[i] = w end
    table.sort(t)
    return table.concat(t, "|")
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
function CN:Render()
    local st = self:State()
    local solvedCount = #st.solved
    for i, gi in ipairs(st.solved) do
        local b = self.bars[i]
        local g = self.puzzle[gi]
        IFE.SetColor(b.bg, GROUP_COLORS[gi])
        b.name:SetText(g.name)
        b.words:SetText(table.concat(g.words, ", "))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -(i - 1) * (TH + GAP))
        b:Show()
    end
    for i = solvedCount + 1, 4 do self.bars[i]:Hide() end

    local remaining = {}
    local solvedSet = {}
    for _, gi in ipairs(st.solved) do solvedSet[gi] = true end
    for _, w in ipairs(st.order) do
        if not solvedSet[self:GroupOf(w)] then remaining[#remaining + 1] = w end
    end
    for i, t in ipairs(self.tiles) do
        local w = remaining[i]
        if w then
            local slot = solvedCount * 4 + (i - 1)
            local r, c = math.floor(slot / 4), slot % 4
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", c * (TW + GAP), -r * (TH + GAP))
            t.word = w
            FitText(t.text, w, TW - 12, { 18, 16, 14, 12 })
            local sel = self.selected[w]
            IFE.SetColor(t.bg, sel and TILE_SEL or TILE_BG)
            t.text:SetTextColor(IFE.Hex(sel and "#ffffff" or INK))
            t:Show()
        else
            t:Hide()
        end
    end

    for i, d in ipairs(self.dots) do d:SetShown(i <= 4 - st.mistakes) end
    local n = 0
    for _ in pairs(self.selected) do n = n + 1 end
    self.selectedCount = n
    local busy = self.busy or st.done
    self.submitBtn:SetEnabled(n == 4 and not busy)
    if n == 4 and not busy then self.submitBtn:SetStyleColors(INK, "#ffffff", INK) end
    self.deselectBtn:SetEnabled(n > 0 and not busy)
    self.shuffleBtn:SetEnabled(not busy)
    self.buttonRow:SetShown(not st.done)
    self.mistakesRow:SetShown(not st.done)
    self.resultsBtn:SetShown(st.done and not self.busy)

    local today = self.index == self:TodayIndex()
    local status = st.done and (st.won and "  -  Solved" or "  -  Finished") or ""
    self.navLabel:SetText(string.format("Puzzle %d of %d%s%s", self.index, #Puzzles(), today and "  (Today)" or "", status))
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function CN:ToggleWord(w)
    if self.busy or self:State().done or not w then return end
    if self.selected[w] then
        self.selected[w] = nil
    elseif (self.selectedCount or 0) < 4 then
        self.selected[w] = true
    end
    self:Render()
end

function CN:DeselectAll()
    wipe(self.selected)
    self:Render()
end

function CN:Shuffle()
    local st = self:State()
    IFE.Shuffle(st.order)
    self:Render()
end

function CN:SelectedTiles()
    local out = {}
    for _, t in ipairs(self.tiles) do
        if t:IsShown() and self.selected[t.word] then out[#out + 1] = t end
    end
    -- NYT hops tiles in grid order
    table.sort(out, function(a, b)
        local _, _, _, ax, ay = a:GetPoint(1)
        local _, _, _, bx, by = b:GetPoint(1)
        if ay ~= by then return ay > by end
        return ax < bx
    end)
    return out
end

function CN:Submit()
    local st = self:State()
    if self.busy or st.done or self.selectedCount ~= 4 then return end
    local words = {}
    for w in pairs(self.selected) do words[#words + 1] = w end
    local key = GuessKey(words)
    for _, g in ipairs(st.guesses) do
        if g.key == key then self.toast:Show_("Already guessed!", 1.5, true) return end
    end

    local counts, groups = {}, {}
    for i, w in ipairs(words) do
        local gi = self:GroupOf(w)
        groups[i] = gi
        counts[gi] = (counts[gi] or 0) + 1
    end
    local best, bestGroup = 0, nil
    for gi, n in pairs(counts) do if n > best then best, bestGroup = n, gi end end
    st.guesses[#st.guesses + 1] = { key = key, groups = groups }

    self.busy = true
    self:Render()
    local tiles = self:SelectedTiles()
    for i, t in ipairs(tiles) do C_Timer.After((i - 1) * 0.1, function() t.hop:Play() end) end

    local idx = self.index
    C_Timer.After(0.65, function()
        if self.index ~= idx then return end
        if best == 4 then
            st.solved[#st.solved + 1] = bestGroup
            wipe(self.selected)
            self.busy = false
            self:Render()
            self.bars[#st.solved].fade:Play()
            if #st.solved == 4 then self:Finish(true) end
        else
            for _, t in ipairs(tiles) do t.shake:Play() end
            st.mistakes = st.mistakes + 1
            if best == 3 then self.toast:Show_("One away...", 1.5, true) end
            C_Timer.After(0.35, function()
                if self.index ~= idx then return end
                self.busy = false
                self:Render()
                if st.mistakes >= 4 then self:Finish(false) end
            end)
        end
    end)
end

function CN:Finish(won)
    local st = self:State()
    local idx = self.index
    st.done, st.won = true, won
    wipe(self.selected)
    local s = IFE.db.connections.stats
    if not st.counted then
        st.counted = true
        s.played = s.played + 1
        if won then
            s.wins = s.wins + 1
            s.streak = s.streak + 1
            s.maxStreak = math.max(s.maxStreak, s.streak)
            if st.mistakes == 0 then s.perfect = s.perfect + 1 end
        else
            s.streak = 0
        end
    end
    if won then
        self.toast:Show_(WIN_MSG[st.mistakes] or "Phew!", 2, true)
        C_Timer.After(1.6, function() if self.index == idx then self:ShowResults() end end)
        self:Render()
        return
    end
    -- reveal the remaining groups one at a time, easiest first
    self.toast:Show_("Next Time!", 2, true)
    self.busy = true
    local missing = {}
    local solvedSet = {}
    for _, gi in ipairs(st.solved) do solvedSet[gi] = true end
    for gi = 1, 4 do if not solvedSet[gi] then missing[#missing + 1] = gi end end
    for i, gi in ipairs(missing) do
        C_Timer.After(0.6 + (i - 1) * 0.8, function()
            if self.index ~= idx then return end
            st.solved[#st.solved + 1] = gi
            if i == #missing then self.busy = false end
            self:Render()
            self.bars[#st.solved].fade:Play()
            if i == #missing then
                C_Timer.After(1.2, function() if self.index == idx then self:ShowResults() end end)
            end
        end)
    end
    self:Render()
end

function CN:ShowResults()
    local st = self:State()
    local p = self.results
    p.title:SetText(st.won and (WIN_MSG[st.mistakes] or "Phew!") or "Next Time!")
    p.sub:SetText(string.format("Connections  -  Puzzle #%d", self.index))
    for r = 1, 7 do
        local g = st.guesses[r]
        for c = 1, 4 do
            local sq = p.squares[r][c]
            if g then
                IFE.SetColor(sq, GROUP_COLORS[g.groups[c]])
                sq:Show()
            else
                sq:Hide()
            end
        end
    end
    local s = IFE.db.connections.stats
    p.stats:SetText(string.format("Completed %d   -   Win %% %d   -   Perfect %d   -   Streak %d   -   Max %d",
        s.played, s.played > 0 and math.floor(s.wins / s.played * 100 + 0.5) or 0, s.perfect, s.streak, s.maxStreak))
    p:Show()
end

function CN:Load(index)
    local n = #Puzzles()
    if n == 0 then return end
    if index < 1 then index = n elseif index > n then index = 1 end
    self.index = index
    self.puzzle = Puzzles()[index]
    self.selected = {}
    self.busy = false
    self.toast:Hide()
    self.results:Hide()
    self:Render()
end

function CN:LoadRandomUnplayed()
    local prog, cands = IFE.db.connections.progress, {}
    for i = 1, #Puzzles() do
        if not (prog[i] and prog[i].done) and i ~= self.index then cands[#cands + 1] = i end
    end
    if #cands == 0 then self.toast:Show_("You've played every puzzle!", 2, true) return end
    self:Load(cands[math.random(#cands)])
end

function CN:OnShow()
    if not self.index then self:Load(self:TodayIndex()) end
end

---------------------------------------------------------------------------
IFE:RegisterGame({
    key = "connections",
    title = "Connections",
    accent = "#ba81c5",
    description = "Find four groups of four words that share something in common. Four mistakes and you're out.",
    create = function(f)
        local self = setmetatable({ frame = f, selected = {} }, CN)
        self:Build()
        return self
    end,
    status = function()
        local n = #Puzzles()
        if n == 0 then return "" end
        local prog = IFE.db.connections.progress
        local today = prog[(IFE.DayNumber() % n) + 1]
        local done = 0
        for _, st in pairs(prog) do if st.done then done = done + 1 end end
        local t = (today and today.done) and (today.won and "Today's puzzle solved" or "Today's puzzle finished") or "Today's puzzle is waiting"
        return string.format("%s   -   %d of %d completed", t, done, n)
    end,
    drawIcon = function(icon)
        for i = 0, 3 do
            local t = IFE.Rect(icon, "ARTWORK", GROUP_COLORS[i + 1])
            t:SetSize(84, 17)
            t:SetPoint("TOPLEFT", 0, -i * 22.3)
        end
    end,
})
