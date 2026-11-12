-- Wordle, modelled on the NYT implementation (dark theme):
-- six guesses, tile flip reveal, duplicate-letter scoring, on-screen + physical keyboard,
-- "Not in word list" shake, Hard Mode, daily word, statistics with guess distribution.
-- A Practice mode adds extra words for long flights (it does not touch your daily stats).
local _, IFE = ...

local C = {
    bg = "#121213", empty = "#3a3a3c", filled = "#565758", text = "#ffffff",
    correct = "#538d4e", present = "#b59f3b", absent = "#3a3a3c", key = "#818384",
}
local TILE, GAP = 50, 5
local KEY_W, KEY_H, KEY_GAP, WIDE = 43, 46, 6, 65
local ROWS = { "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" }
local WIN_MSG = { "Genius", "Magnificent", "Impressive", "Splendid", "Great", "Phew" }
local ORD = { "1st", "2nd", "3rd", "4th", "5th" }
local RANK = { absent = 1, present = 2, correct = 3 }

local valid
local function IsValid(w)
    if not valid then
        valid = {}
        for _, a in ipairs(InFlightEntertainment_WordleAnswers) do valid[a] = true end
        for g in InFlightEntertainment_WordleGuesses:gmatch("%a+") do valid[g] = true end
    end
    return valid[w]
end

local function Evaluate(guess, answer)
    local res, counts = {}, {}
    for i = 1, 5 do
        local a = answer:sub(i, i)
        if guess:sub(i, i) == a then res[i] = "correct" else counts[a] = (counts[a] or 0) + 1 end
    end
    for i = 1, 5 do
        if not res[i] then
            local g = guess:sub(i, i)
            if (counts[g] or 0) > 0 then
                res[i] = "present"; counts[g] = counts[g] - 1
            else
                res[i] = "absent"
            end
        end
    end
    return res
end

local W = {}
W.__index = W

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function MakeTile(parent)
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(TILE, TILE)
    t.bg = IFE.Rect(t, "BACKGROUND", C.bg)
    t.bg:SetAllPoints()
    t.border = IFE.Border(t, C.empty, 2)
    t.letter = IFE.Text(t, 28, C.text, IFE.FONT)
    t.letter:SetPoint("CENTER", 0, 0)

    local pop = t:CreateAnimationGroup()
    local s1 = pop:CreateAnimation("Scale"); s1:SetScale(1.12, 1.12); s1:SetDuration(0.05); s1:SetOrder(1)
    local s2 = pop:CreateAnimation("Scale"); s2:SetScale(1 / 1.12, 1 / 1.12); s2:SetDuration(0.05); s2:SetOrder(2)
    t.pop = pop

    local flip = t:CreateAnimationGroup()
    local f1 = flip:CreateAnimation("Scale"); f1:SetScale(1, 0.02); f1:SetDuration(0.22); f1:SetOrder(1)
    local f2 = flip:CreateAnimation("Scale"); f2:SetScale(1, 50); f2:SetDuration(0.22); f2:SetOrder(2)
    f1:SetScript("OnFinished", function() if t.onFlipMid then t.onFlipMid() end end)
    flip:SetScript("OnFinished", function() if t.onFlipDone then t.onFlipDone() end end)
    t.flip = flip

    local bounce = t:CreateAnimationGroup()
    local b1 = bounce:CreateAnimation("Translation"); b1:SetOffset(0, 22); b1:SetDuration(0.12); b1:SetOrder(1)
    local b2 = bounce:CreateAnimation("Translation"); b2:SetOffset(0, -26); b2:SetDuration(0.12); b2:SetOrder(2)
    local b3 = bounce:CreateAnimation("Translation"); b3:SetOffset(0, 4); b3:SetDuration(0.08); b3:SetOrder(3)
    t.bounce = bounce
    return t
end

local function StyleTile(t, state, letter)
    t.letter:SetText(letter or "")
    if state == "empty" then
        IFE.SetColor(t.bg, C.bg); t.border:SetShown(true); t.border:SetColor(C.empty)
    elseif state == "tbd" then
        IFE.SetColor(t.bg, C.bg); t.border:SetShown(true); t.border:SetColor(C.filled)
    else
        IFE.SetColor(t.bg, C[state]); t.border:SetShown(false)
    end
end

function W:Build()
    local f = self.frame
    local bg = IFE.Rect(f, "BACKGROUND", C.bg)
    bg:SetAllPoints()

    -- top bar
    self.modeLabel = IFE.Text(f, 14, "#ffffff", IFE.FONT)
    self.modeLabel:SetPoint("TOP", 0, -6)
    self.hardBtn = IFE.Button(f, 130, 24, "", { bg = C.bg, fg = "#d7dadc", size = 12, border = C.empty }, function() self:ToggleHard() end)
    self.hardBtn:SetPoint("TOPLEFT", 4, -2)
    IFE.Tooltip(self.hardBtn, "Hard Mode", "Any revealed hints must be used in subsequent guesses. Can only be turned on at the start of a round.")
    self.statsBtn = IFE.Button(f, 80, 24, "Statistics", { bg = C.bg, fg = "#d7dadc", size = 12, border = C.empty }, function() self:ShowStats() end)
    self.statsBtn:SetPoint("TOPRIGHT", -4, -2)
    self.practiceBtn = IFE.Button(f, 80, 24, "Practice", { bg = C.bg, fg = "#d7dadc", size = 12, border = C.empty }, function() self:TogglePractice() end)
    self.practiceBtn:SetPoint("RIGHT", self.statsBtn, "LEFT", -6, 0)
    IFE.Tooltip(self.practiceBtn, "Practice / Daily", "Switch between today's daily word and unlimited practice words (practice games don't count toward statistics).")
    local sep = IFE.Rect(f, "BORDER", C.empty)
    sep:SetPoint("TOPLEFT", 0, -30); sep:SetPoint("TOPRIGHT", 0, -30); sep:SetHeight(1)

    -- grid
    local gridW = TILE * 5 + GAP * 4
    local grid = CreateFrame("Frame", nil, f)
    grid:SetSize(gridW, TILE * 6 + GAP * 5)
    grid:SetPoint("TOP", 0, -40)
    self.rows = {}
    for r = 1, 6 do
        local row = CreateFrame("Frame", nil, grid)
        row:SetSize(gridW, TILE)
        row:SetPoint("TOP", 0, -(r - 1) * (TILE + GAP))
        row.tiles = {}
        for c = 1, 5 do
            local t = MakeTile(row)
            t:SetPoint("LEFT", (c - 1) * (TILE + GAP), 0)
            row.tiles[c] = t
        end
        local shake = row:CreateAnimationGroup()
        for i, dx in ipairs({ -6, 12, -12, 12, -12, 6 }) do
            local a = shake:CreateAnimation("Translation"); a:SetOffset(dx, 0); a:SetDuration(0.05); a:SetOrder(i)
        end
        row.shake = shake
        self.rows[r] = row
    end

    -- keyboard
    local kb = CreateFrame("Frame", nil, f)
    kb:SetSize(10 * KEY_W + 9 * KEY_GAP, 3 * KEY_H + 2 * 8)
    kb:SetPoint("TOP", grid, "BOTTOM", 0, -16)
    self.keys = {}
    for r, letters in ipairs(ROWS) do
        local items = {}
        if r == 3 then items[#items + 1] = "ENTER" end
        for ch in letters:gmatch(".") do items[#items + 1] = ch end
        if r == 3 then items[#items + 1] = "BACK" end
        local total = 0
        for _, k in ipairs(items) do total = total + (#k > 1 and WIDE or KEY_W) end
        total = total + KEY_GAP * (#items - 1)
        local x = (kb:GetWidth() - total) / 2
        for _, k in ipairs(items) do
            local w = #k > 1 and WIDE or KEY_W
            local b = IFE.Button(kb, w, KEY_H, k == "BACK" and "" or k, { bg = C.key, fg = "#ffffff", size = #k > 1 and 11 or 16 }, function()
                self:Input(k)
            end)
            b:SetPoint("TOPLEFT", x, -(r - 1) * (KEY_H + 8))
            if k == "BACK" then
                local ic = b:CreateTexture(nil, "ARTWORK")
                ic:SetTexture(IFE.MEDIA .. "backspace")
                ic:SetSize(26, 26)
                ic:SetPoint("CENTER")
            end
            x = x + w + KEY_GAP
            self.keys[k] = b
        end
    end

    self.toast = IFE.Toast(f)
    self.toast:SetPoint("TOP", grid, "TOP", 0, 6)

    self:BuildStats()

    -- physical keyboard
    f:SetScript("OnKeyDown", function(_, key) self:OnKey(key) end)
    local ev = CreateFrame("Frame", nil, f)
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function() self:UpdateKeyboardCapture() end)
end

---------------------------------------------------------------------------
-- Keyboard capture: letters/Enter/Backspace go to the game while it's open.
-- Everything else (Escape, movement, chat) still reaches the game client.
---------------------------------------------------------------------------
function W:UpdateKeyboardCapture()
    local want = self.frame:IsVisible() and not InCombatLockdown()
    pcall(self.frame.EnableKeyboard, self.frame, want and true or false)
    if want then pcall(self.frame.SetPropagateKeyboardInput, self.frame, true) end
end

function W:OnKey(key)
    local handled = false
    if not (IsControlKeyDown() or IsAltKeyDown()) and not self.statsPanel:IsShown() and self.status == "playing" then
        if key == "ENTER" or key == "BACKSPACE" or key:match("^%u$") then handled = true end
    end
    if not InCombatLockdown() then pcall(self.frame.SetPropagateKeyboardInput, self.frame, not handled) end
    if handled then self:Input(key == "BACKSPACE" and "BACK" or key) end
end

---------------------------------------------------------------------------
-- Game flow
---------------------------------------------------------------------------
function W:Input(k)
    if self.status ~= "playing" or self.locked then return end
    local cur = self.current
    if k == "ENTER" then
        self:Submit()
    elseif k == "BACK" then
        if #cur > 0 then
            self.current = cur:sub(1, -2)
            StyleTile(self.rows[#self.guesses + 1].tiles[#cur], "empty", "")
        end
    elseif #k == 1 and #cur < 5 then
        self.current = cur .. k
        local t = self.rows[#self.guesses + 1].tiles[#cur + 1]
        StyleTile(t, "tbd", k)
        t.pop:Play()
    end
end

function W:HardModeError(guess)
    for _, g in ipairs(self.guesses) do
        local res = Evaluate(g, self.answer)
        for i = 1, 5 do
            if res[i] == "correct" and guess:sub(i, i) ~= g:sub(i, i) then
                return ORD[i] .. " letter must be " .. g:sub(i, i)
            end
        end
        local need = {}
        for i = 1, 5 do
            if res[i] == "present" or res[i] == "correct" then
                local ch = g:sub(i, i); need[ch] = (need[ch] or 0) + 1
            end
        end
        for i = 1, 5 do
            local ch = g:sub(i, i)
            if res[i] == "present" and need[ch] then
                local have = select(2, guess:gsub(ch, ""))
                if have < need[ch] then return "Guess must contain " .. ch end
            end
        end
    end
end

function W:Submit()
    local row = self.rows[#self.guesses + 1]
    if #self.current < 5 then
        row.shake:Play(); self.toast:Show_("Not enough letters", 1.2); return
    end
    if not IsValid(self.current) then
        row.shake:Play(); self.toast:Show_("Not in word list", 1.2); return
    end
    if self:IsHard() then
        local err = self:HardModeError(self.current)
        if err then row.shake:Play(); self.toast:Show_(err, 1.5); return end
    end
    local guess = self.current
    self.guesses[#self.guesses + 1] = guess
    self.current = ""
    self:Save()
    self.locked = true
    self:Reveal(#self.guesses, true, function()
        self.locked = false
        self:CheckEnd(true)
    end)
end

function W:Reveal(r, animate, done)
    local guess = self.guesses[r]
    local res = Evaluate(guess, self.answer)
    local row = self.rows[r]
    if not animate then
        for i = 1, 5 do StyleTile(row.tiles[i], res[i], guess:sub(i, i)) end
        self:ColorKeys(guess, res)
        if done then done() end
        return
    end
    for i = 1, 5 do
        local t = row.tiles[i]
        t.onFlipMid = function() StyleTile(t, res[i], guess:sub(i, i)) end
        t.onFlipDone = (i == 5) and function()
            self:ColorKeys(guess, res)
            if done then done() end
        end or nil
        C_Timer.After((i - 1) * 0.3, function() t.flip:Play() end)
    end
end

function W:ColorKeys(guess, res)
    for i = 1, 5 do
        local ch = guess:sub(i, i)
        local old = self.keyState[ch]
        if not old or RANK[res[i]] > RANK[old] then self.keyState[ch] = res[i] end
    end
    for ch, b in pairs(self.keys) do
        if #ch == 1 then
            local s = self.keyState[ch]
            IFE.SetColor(b.bg, s and C[s] or C.key)
        end
    end
end

function W:CheckEnd(fresh)
    local last = self.guesses[#self.guesses]
    local won = last == self.answer
    if not won and #self.guesses < 6 then
        self.status = "playing"
        return
    end
    self.status = won and "won" or "lost"
    if fresh then
        self:RecordResult(won)
        local row = self.rows[#self.guesses]
        if won then
            self.toast:Show_(WIN_MSG[#self.guesses], 2)
            for i = 1, 5 do C_Timer.After((i - 1) * 0.1, function() row.tiles[i].bounce:Play() end) end
        else
            self.toast:Show_(self.answer, 0)
        end
        C_Timer.After(2.2, function() if self.frame:IsVisible() then self:ShowStats() end end)
    elseif not won then
        self.toast:Show_(self.answer, 0)
    end
    self:Save()
    self:UpdateBar()
end

function W:RecordResult(won)
    if self.mode ~= "daily" then return end
    local s = IFE.db.wordle.stats
    if s.lastDay == self.day then return end
    s.lastDay = self.day
    s.played = s.played + 1
    if won then
        s.wins = s.wins + 1
        s.streak = (s.lastWinDay == self.day - 1) and s.streak + 1 or 1
        s.lastWinDay = self.day
        s.maxStreak = math.max(s.maxStreak, s.streak)
        s.dist[#self.guesses] = s.dist[#self.guesses] + 1
    else
        s.streak = 0
    end
end

function W:IsHard() return IFE.db.wordle.hardMode end

function W:ToggleHard()
    if not self:IsHard() and #self.guesses > 0 and self.status == "playing" then
        self.toast:Show_("Hard mode can only be enabled at the start of a round", 2)
        return
    end
    IFE.db.wordle.hardMode = not IFE.db.wordle.hardMode
    self:UpdateBar()
end

function W:UpdateBar()
    self.hardBtn:SetLabel("Hard Mode: " .. (self:IsHard() and "ON" or "OFF"))
    self.hardBtn.text:SetTextColor(IFE.Hex(self:IsHard() and "#6aaa64" or "#d7dadc"))
    if self.mode == "daily" then
        self.modeLabel:SetText(string.format("Daily Wordle  #%d", self.puzzleNumber))
        self.practiceBtn:SetLabel("Practice")
    else
        self.modeLabel:SetText("Practice Word")
        self.practiceBtn:SetLabel("Daily")
    end
end

function W:Save()
    if self.mode ~= "daily" then return end
    local g = {}
    for i, v in ipairs(self.guesses) do g[i] = v end
    IFE.db.wordle.daily = { day = self.day, guesses = g }
end

function W:Reset(answer)
    self.answer = answer
    self.guesses, self.current, self.keyState = {}, "", {}
    self.status, self.locked = "playing", false
    self.toast:Hide()
    for r = 1, 6 do
        for c = 1, 5 do StyleTile(self.rows[r].tiles[c], "empty", "") end
    end
    self:ColorKeys("", {})
end

function W:LoadDaily()
    local list = InFlightEntertainment_WordleAnswers
    self.mode = "daily"
    self.day = IFE.DayNumber()
    self.puzzleNumber = self.day - 20000
    self:Reset(list[(self.day % #list) + 1])
    local saved = IFE.db.wordle.daily
    if saved and saved.day == self.day then
        for i, g in ipairs(saved.guesses) do
            self.guesses[i] = g
            self:Reveal(i, false)
        end
        if #self.guesses > 0 then self:CheckEnd(false) end
    end
    self:UpdateBar()
end

function W:LoadPractice()
    local list = InFlightEntertainment_WordleAnswers
    self.mode = "practice"
    local pick
    repeat pick = list[math.random(#list)] until pick ~= self.answer
    self:Reset(pick)
    self:UpdateBar()
end

function W:TogglePractice()
    if self.locked then return end
    self.statsPanel:Hide()
    if self.mode == "daily" then self:LoadPractice() else self:LoadDaily() end
end

---------------------------------------------------------------------------
-- Statistics panel
---------------------------------------------------------------------------
function W:BuildStats()
    local p = CreateFrame("Frame", nil, self.frame)
    p:SetSize(440, 420)
    p:SetPoint("CENTER", 0, 10)
    p:SetFrameLevel(self.frame:GetFrameLevel() + 30)
    p:EnableMouse(true)
    local bg = IFE.Rect(p, "BACKGROUND", "#121213")
    bg:SetAllPoints()
    IFE.Border(p, "#1a1a1b", 1)
    local sh = IFE.Rect(p, "BACKGROUND", "#000000", 0.6, -1)
    sh:SetPoint("TOPLEFT", -4, 4); sh:SetPoint("BOTTOMRIGHT", 4, -4)
    local close = IFE.Button(p, 24, 24, "X", { bg = "#121213", fg = "#d7dadc", size = 14 }, function() p:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    local title = IFE.Text(p, 14, "#ffffff", IFE.FONT)
    title:SetPoint("TOP", 0, -24)
    title:SetText("STATISTICS")
    p.nums = {}
    local labels = { "Played", "Win %", "Current\nStreak", "Max\nStreak" }
    for i, l in ipairs(labels) do
        local n = IFE.Text(p, 30, "#ffffff", IFE.FONT)
        n:SetPoint("TOP", p, "TOPLEFT", 85 + (i - 1) * 90, -50)
        local lt = IFE.Text(p, 11, "#ffffff", IFE.FONT)
        lt:SetPoint("TOP", n, "BOTTOM", 0, -4)
        lt:SetText(l)
        p.nums[i] = n
    end
    local dt = IFE.Text(p, 14, "#ffffff", IFE.FONT)
    dt:SetPoint("TOP", 0, -145)
    dt:SetText("GUESS DISTRIBUTION")
    p.bars = {}
    for i = 1, 6 do
        local y = -172 - (i - 1) * 26
        local num = IFE.Text(p, 13, "#ffffff", IFE.FONT)
        num:SetPoint("TOPLEFT", 60, y - 3)
        num:SetText(tostring(i))
        local bar = IFE.Rect(p, "ARTWORK", C.absent)
        bar:SetPoint("TOPLEFT", 76, y)
        bar:SetHeight(20)
        local v = IFE.Text(p, 12, "#ffffff", IFE.FONT)
        v:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
        p.bars[i] = { bar = bar, value = v }
    end
    local nt = IFE.Text(p, 12, "#ffffff", IFE.FONT)
    nt:SetPoint("BOTTOMLEFT", 40, 52)
    nt:SetText("NEXT WORDLE")
    p.countdown = IFE.Text(p, 26, "#ffffff", IFE.FONT)
    p.countdown:SetPoint("TOPLEFT", nt, "BOTTOMLEFT", 0, -6)
    p.play = IFE.Button(p, 170, 40, "Play Practice Word", { bg = C.correct, fg = "#ffffff", size = 13 }, function()
        p:Hide(); self:LoadPractice()
    end)
    p.play:SetPoint("BOTTOMRIGHT", -36, 30)
    p.elapsed = 0
    p:SetScript("OnUpdate", function(_, e)
        p.elapsed = p.elapsed + e
        if p.elapsed < 0.25 then return end
        p.elapsed = 0
        local s = IFE.SecondsUntilMidnight()
        p.countdown:SetText(string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60))
        if self.mode == "daily" and self.day ~= IFE.DayNumber() and self.status ~= "playing" then
            p:Hide(); self:LoadDaily()
        end
    end)
    p:Hide()
    self.statsPanel = p
end

function W:ShowStats()
    local p, s = self.statsPanel, IFE.db.wordle.stats
    p.nums[1]:SetText(tostring(s.played))
    p.nums[2]:SetText(tostring(s.played > 0 and math.floor(s.wins / s.played * 100 + 0.5) or 0))
    local streak = s.streak
    if s.lastWinDay and s.lastWinDay < IFE.DayNumber() - 1 then streak = 0 end
    p.nums[3]:SetText(tostring(streak))
    p.nums[4]:SetText(tostring(s.maxStreak))
    local most = 1
    for i = 1, 6 do most = math.max(most, s.dist[i]) end
    local highlight = self.mode == "daily" and self.status == "won" and #self.guesses or nil
    for i = 1, 6 do
        local b = p.bars[i]
        b.bar:SetWidth(math.max(22, 300 * s.dist[i] / most))
        IFE.SetColor(b.bar, i == highlight and C.correct or C.absent)
        b.value:SetText(tostring(s.dist[i]))
    end
    p.play:SetLabel(self.mode == "practice" and "New Practice Word" or "Play Practice Word")
    p:Show()
end

function W:OnShow()
    if not self.mode or (self.mode == "daily" and self.day ~= IFE.DayNumber() and not self.locked) then
        self:LoadDaily()
    end
    self:UpdateKeyboardCapture()
end

function W:OnHide()
    pcall(self.frame.EnableKeyboard, self.frame, false)
end

---------------------------------------------------------------------------
IFE:RegisterGame({
    key = "wordle",
    title = "Wordle",
    accent = "#6aaa64",
    description = "Guess the hidden five-letter word in six tries. A new word every day, plus practice words for long hauls.",
    create = function(f)
        local self = setmetatable({ frame = f }, W)
        self:Build()
        f:HookScript("OnHide", function() self:OnHide() end)
        return self
    end,
    status = function()
        local d = IFE.db.wordle.daily
        if d and d.day == IFE.DayNumber() and #d.guesses > 0 then
            local list = InFlightEntertainment_WordleAnswers
            local answer = list[(d.day % #list) + 1]
            if d.guesses[#d.guesses] == answer then return "Today's word solved in " .. #d.guesses .. "/6" end
            if #d.guesses >= 6 then return "Today's word: better luck tomorrow" end
            return "Today's word in progress (" .. #d.guesses .. "/6)"
        end
        return "Today's word is waiting"
    end,
    drawIcon = function(icon)
        local cols = { C.correct, C.present, C.absent, C.correct, C.correct, C.correct, C.present, C.absent, C.correct }
        for i = 0, 8 do
            local t = IFE.Rect(icon, "ARTWORK", cols[i + 1])
            t:SetSize(25, 25)
            t:SetPoint("TOPLEFT", (i % 3) * 29.5, -math.floor(i / 3) * 29.5)
        end
    end,
})
