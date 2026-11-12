-- In-Flight Entertainment: core window, menu, auto-show-in-flight toggle, shared UI helpers.
local addonName, IFE = ...
_G.InFlightEntertainment = IFE

IFE.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
IFE.FONT = "Fonts\\FRIZQT__.TTF"
IFE.FONT_PLAIN = "Fonts\\ARIALN.TTF"

IFE.WIDTH, IFE.HEIGHT = 700, 610
IFE.HEADER = 40

local DEFAULTS = {
    autoShow = true,
    autoHide = true,
    chess = { rating = 1000, played = 0, solved = 0, streak = 0, bestStreak = 0, seen = {} },
    wordle = { hardMode = false, stats = { played = 0, wins = 0, streak = 0, maxStreak = 0, dist = { 0, 0, 0, 0, 0, 0 } } },
    connections = { progress = {}, stats = { played = 0, wins = 0, perfect = 0, streak = 0, maxStreak = 0 } },
}

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ApplyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

---------------------------------------------------------------------------
-- Small UI helpers shared by the games
---------------------------------------------------------------------------
function IFE.Hex(hex)
    hex = hex:gsub("#", "")
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function IFE.Rect(parent, layer, hex, alpha, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    local r, g, b = IFE.Hex(hex or "#000000")
    t:SetColorTexture(r, g, b, alpha or 1)
    return t
end

function IFE.SetColor(tex, hex, alpha)
    local r, g, b = IFE.Hex(hex)
    tex:SetColorTexture(r, g, b, alpha or 1)
end

function IFE.Text(parent, size, hex, font, flags, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(font or IFE.FONT, size or 12, flags or "")
    if hex then fs:SetTextColor(IFE.Hex(hex)) end
    fs:SetWordWrap(true)
    return fs
end

-- 1px border made from four textures; returns a table with :SetColor(hex, a)
function IFE.Border(frame, hex, size, layer)
    size = size or 1
    local edges = {}
    for i = 1, 4 do edges[i] = IFE.Rect(frame, layer or "BORDER", hex) end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(size)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(size)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(size)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(size)
    local border = { edges = edges }
    function border:SetColor(h, a) for _, e in ipairs(self.edges) do IFE.SetColor(e, h, a) end end
    function border:SetShown(s) for _, e in ipairs(self.edges) do e:SetShown(s) end end
    return border
end

-- Flat button. style = { bg, fg, border, hover, disabledBg, disabledFg, font, size }
function IFE.Button(parent, w, h, label, style, onClick)
    style = style or {}
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.style = style
    b.bg = IFE.Rect(b, "BACKGROUND", style.bg or "#3a3a3c")
    b.bg:SetAllPoints()
    if style.border then b.border = IFE.Border(b, style.border, style.borderSize or 1) end
    b.hl = IFE.Rect(b, "HIGHLIGHT", style.hover or "#ffffff", style.hoverAlpha or 0.08)
    b.hl:SetAllPoints()
    b.text = IFE.Text(b, style.size or 13, style.fg or "#ffffff", style.font or IFE.FONT)
    b.text:SetPoint("CENTER")
    b.text:SetText(label or "")
    b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.text:SetPoint("CENTER", 0, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER") end)
    function b:SetLabel(t) self.text:SetText(t) end
    function b:SetStyleColors(bgHex, fgHex, borderHex)
        if bgHex then IFE.SetColor(self.bg, bgHex) end
        if fgHex then self.text:SetTextColor(IFE.Hex(fgHex)) end
        if borderHex and self.border then self.border:SetColor(borderHex) end
    end
    hooksecurefunc(b, "SetEnabled", function(self, enabled)
        local s = self.style
        if enabled then
            IFE.SetColor(self.bg, s.bg or "#3a3a3c"); self.text:SetTextColor(IFE.Hex(s.fg or "#ffffff"))
            if self.border then self.border:SetColor(s.border) end
        else
            IFE.SetColor(self.bg, s.disabledBg or s.bg or "#3a3a3c"); self.text:SetTextColor(IFE.Hex(s.disabledFg or "#888888"))
            if self.border then self.border:SetColor(s.disabledBorder or s.disabledFg or "#888888") end
        end
    end)
    return b
end

function IFE.Tooltip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
        if body then GameTooltip:AddLine(type(body) == "function" and body() or body, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- NYT-style toast: dark rounded-ish box that fades out
function IFE.Toast(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(parent:GetFrameLevel() + 50)
    f:SetSize(10, 36)
    f.bg = IFE.Rect(f, "BACKGROUND", "#ffffff")
    f.bg:SetAllPoints()
    f.text = IFE.Text(f, 14, "#000000", IFE.FONT)
    f.text:SetPoint("CENTER")
    f:Hide()
    local anim = f:CreateAnimationGroup()
    local fade = anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetDuration(0.3)
    anim:SetScript("OnFinished", function() f:Hide(); f:SetAlpha(1) end)
    f.anim, f.fade = anim, fade
    function f:Show_(msg, duration, dark)
        self.anim:Stop(); self:SetAlpha(1)
        IFE.SetColor(self.bg, dark and "#000000" or "#ffffff")
        self.text:SetTextColor(IFE.Hex(dark and "#ffffff" or "#000000"))
        self.text:SetText(msg)
        self:SetWidth(self.text:GetStringWidth() + 32)
        self:Show()
        self.token = (self.token or 0) + 1
        local token = self.token
        if duration and duration > 0 then
            C_Timer.After(duration, function()
                if self.token == token and self:IsShown() then self.anim:Play() end
            end)
        end
    end
    return f
end

function IFE.Shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- Local calendar day number (days since 1970-01-01), used for daily puzzles.
function IFE.DayNumber()
    local d = date("*t")
    return math.floor(time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
end

function IFE.SecondsUntilMidnight()
    local d = date("*t")
    return (23 - d.hour) * 3600 + (59 - d.min) * 60 + (60 - d.sec)
end

function IFE.Print(msg)
    print("|cff4fc3f7In-Flight Entertainment:|r " .. msg)
end

---------------------------------------------------------------------------
-- Game registry
---------------------------------------------------------------------------
IFE.games = {}
function IFE:RegisterGame(def)
    self.games[#self.games + 1] = def
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local frame, content, menu, titleText, backButton, toggle
local activeGame
IFE.instances = {}

local function UpdateToggle()
    if not toggle then return end
    local on = IFE.db.autoShow
    IFE.SetColor(toggle.track, on and "#538d4e" or "#58585a")
    toggle.knob:ClearAllPoints()
    toggle.knob:SetPoint(on and "RIGHT" or "LEFT", toggle.track, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    toggle.state:SetText(on and "ON" or "OFF")
end

local function ShowMenu()
    if activeGame then
        local inst = IFE.instances[activeGame.key]
        if inst then
            if inst.OnHide then inst:OnHide() end
            inst.frame:Hide()
        end
    end
    activeGame = nil
    backButton:Hide()
    titleText:SetText("In-Flight Entertainment")
    menu:Show()
    for _, card in ipairs(menu.cards) do
        local def = card.def
        card.status:SetText(def.status and def.status(IFE.instances[def.key]) or "")
    end
end

local function StartGame(def)
    menu:Hide()
    local inst = IFE.instances[def.key]
    if not inst then
        local f = CreateFrame("Frame", nil, content)
        f:SetAllPoints()
        inst = def.create(f)
        inst.frame = f
        IFE.instances[def.key] = inst
    end
    activeGame = def
    titleText:SetText(def.title)
    backButton:Show()
    inst.frame:Show()
    if inst.OnShow then inst:OnShow() end
end

local function BuildMenu()
    menu = CreateFrame("Frame", nil, content)
    menu:SetAllPoints()
    menu.cards = {}

    local heading = IFE.Text(menu, 22, "#ffffff", IFE.FONT)
    heading:SetPoint("TOP", 0, -26)
    heading:SetText("Pick a game for the trip")
    local sub = IFE.Text(menu, 13, "#a8a8a8", IFE.FONT)
    sub:SetPoint("TOP", heading, "BOTTOM", 0, -8)
    sub:SetText("Your progress is kept until you land, and long after.")

    local cardW, cardH, gap = 612, 118, 18
    for i, def in ipairs(IFE.games) do
        local card = CreateFrame("Button", nil, menu)
        card.def = def
        card:SetSize(cardW, cardH)
        card:SetPoint("TOP", 0, -100 - (i - 1) * (cardH + gap))
        local bg = IFE.Rect(card, "BACKGROUND", "#232325")
        bg:SetAllPoints()
        IFE.Border(card, "#3a3a3c")
        local hl = IFE.Rect(card, "HIGHLIGHT", "#ffffff", 0.06)
        hl:SetAllPoints()
        local stripe = IFE.Rect(card, "ARTWORK", def.accent)
        stripe:SetPoint("TOPLEFT"); stripe:SetPoint("BOTTOMLEFT"); stripe:SetWidth(8)

        local icon = CreateFrame("Frame", nil, card)
        icon:SetSize(84, 84)
        icon:SetPoint("LEFT", 28, 0)
        if def.drawIcon then def.drawIcon(icon) end

        local title = IFE.Text(card, 20, "#ffffff", IFE.FONT)
        title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 24, -6)
        title:SetText(def.title)
        local desc = IFE.Text(card, 13, "#c8c8c8", IFE.FONT)
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        desc:SetWidth(cardW - 160)
        desc:SetJustifyH("LEFT")
        desc:SetText(def.description)
        card.status = IFE.Text(card, 12, def.accent, IFE.FONT)
        card.status:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 24, 4)
        card.status:SetJustifyH("LEFT")

        card:SetScript("OnClick", function() StartGame(def) end)
        menu.cards[#menu.cards + 1] = card
    end
end

local function BuildFrame()
    frame = CreateFrame("Frame", "InFlightEntertainmentFrame", UIParent)
    frame:SetSize(IFE.WIDTH, IFE.HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    local p = IFE.db.point
    if p then
        frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    else
        frame:SetPoint("CENTER", 0, 40)
    end
    table.insert(UISpecialFrames, frame:GetName()) -- Escape closes it

    local bg = IFE.Rect(frame, "BACKGROUND", "#121213", 0.97)
    bg:SetAllPoints()
    IFE.Border(frame, "#3a3a3c", 1)

    -- header (drag to move)
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT")
    header:SetHeight(IFE.HEADER)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local a, _, rp, x, y = frame:GetPoint()
        IFE.db.point = { a, "UIParent", rp, x, y }
    end)
    local hbg = IFE.Rect(header, "BACKGROUND", "#1b1b1d")
    hbg:SetAllPoints()
    local line = IFE.Rect(header, "BORDER", "#3a3a3c")
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)

    titleText = IFE.Text(header, 16, "#ffffff", IFE.FONT)
    titleText:SetPoint("CENTER", 0, 0)
    titleText:SetText("In-Flight Entertainment")

    backButton = IFE.Button(header, 120, 26, "< Back to Menu", { bg = "#1b1b1d", fg = "#e0e0e0", size = 12, border = "#4a4a4c" }, ShowMenu)
    backButton:SetPoint("LEFT", 8, 0)
    backButton:Hide()

    local close = IFE.Button(header, 26, 26, "X", { bg = "#1b1b1d", fg = "#c8c8c8", size = 14 }, function() frame:Hide() end)
    close:SetPoint("RIGHT", -7, 0)

    -- Auto-show toggle switch (top right)
    toggle = CreateFrame("Button", nil, header)
    toggle:SetSize(200, 26)
    toggle:SetPoint("RIGHT", close, "LEFT", -8, 0)
    toggle.track = IFE.Rect(toggle, "ARTWORK", "#538d4e")
    toggle.track:SetSize(36, 18)
    toggle.track:SetPoint("RIGHT", 0, 0)
    toggle.knob = toggle:CreateTexture(nil, "OVERLAY")
    toggle.knob:SetTexture(IFE.MEDIA .. "circle")
    toggle.knob:SetSize(14, 14)
    toggle.state = IFE.Text(toggle, 10, "#ffffff", IFE.FONT)
    toggle.state:SetPoint("RIGHT", toggle.track, "LEFT", -6, 0)
    local label = IFE.Text(toggle, 12, "#c8c8c8", IFE.FONT)
    label:SetPoint("RIGHT", toggle.state, "LEFT", -6, 0)
    label:SetText("Auto-show in flight")
    toggle:SetScript("OnClick", function()
        IFE.db.autoShow = not IFE.db.autoShow
        UpdateToggle()
    end)
    IFE.Tooltip(toggle, "Auto-show in flight", function()
        return "When ON, this window opens automatically when you take a flight path and closes when you land.\nType /ife to open it any time."
    end)
    UpdateToggle()

    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 12, -IFE.HEADER - 10)
    content:SetPoint("BOTTOMRIGHT", -12, 12)
    IFE.content = content

    BuildMenu()
    ShowMenu()

    frame:SetScript("OnShow", function()
        if activeGame then
            local inst = IFE.instances[activeGame.key]
            if inst and inst.OnShow then inst:OnShow() end
        else
            ShowMenu()
        end
    end)
    frame:SetScript("OnHide", function()
        IFE.autoShown = false
        if activeGame then
            local inst = IFE.instances[activeGame.key]
            if inst and inst.OnHide then inst:OnHide() end
        end
    end)
    IFE.frame = frame
end

function IFE:Toggle()
    if frame:IsShown() then frame:Hide() else IFE.autoShown = false; frame:Show() end
end

---------------------------------------------------------------------------
-- Flight detection
---------------------------------------------------------------------------
local onTaxi = false
local function CheckTaxi()
    local now = UnitOnTaxi("player") and true or false
    if now == onTaxi then return end
    onTaxi = now
    if now then
        if IFE.db.autoShow and not frame:IsShown() then
            frame:Show()
            IFE.autoShown = true
        end
    else
        if IFE.autoShown and IFE.db.autoHide and frame:IsShown() then
            frame:Hide()
            IFE.Print("Welcome to your destination! Type |cffffffff/ife|r to keep playing.")
        end
        IFE.autoShown = false
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InFlightEntertainmentDB = InFlightEntertainmentDB or {}
        ApplyDefaults(InFlightEntertainmentDB, DEFAULTS)
        IFE.db = InFlightEntertainmentDB
    elseif event == "PLAYER_LOGIN" then
        BuildFrame()
        self:RegisterEvent("PLAYER_CONTROL_LOST")
        self:RegisterEvent("PLAYER_CONTROL_GAINED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("TAXIMAP_CLOSED")
        C_Timer.NewTicker(1, CheckTaxi) -- cheap safety net; events below make it instant
    else
        -- UnitOnTaxi can lag the event slightly, so check now and shortly after.
        CheckTaxi()
        C_Timer.After(0.5, CheckTaxi)
        C_Timer.After(1.5, CheckTaxi)
    end
end)

SLASH_INFLIGHTENTERTAINMENT1 = "/ife"
SlashCmdList.INFLIGHTENTERTAINMENT = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if not frame then return end
    if msg == "auto" then
        IFE.db.autoShow = not IFE.db.autoShow
        UpdateToggle()
        IFE.Print("Auto-show in flight is now " .. (IFE.db.autoShow and "|cff6aaa64ON|r" or "|cffff5555OFF|r") .. ".")
    elseif msg == "reset" then
        frame:ClearAllPoints(); frame:SetPoint("CENTER", 0, 40); IFE.db.point = nil
        frame:Show()
    else
        IFE:Toggle()
    end
end
