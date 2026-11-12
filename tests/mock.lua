ALL = {}
-- crude WoW API mock
local timers = {}
NOW = 0
function GetTime() return NOW end
C_Timer = { After = function(d, f) timers[#timers+1] = {t = NOW + d, f = f} end,
            NewTicker = function(d, f) return {} end }
function RunTimers(sec)
  local stop = NOW + sec
  while true do
    table.sort(timers, function(a,b) return a.t < b.t end)
    local t = timers[1]
    if not t or t.t > stop then break end
    table.remove(timers, 1); NOW = t.t; t.f()
  end
  NOW = stop
end
local updates = {}
function RunUpdates(n) for i=1,n do NOW = NOW + 0.05; for o, f in pairs(updates) do f(o, 0.05) end end end
date, time = os.date, os.time
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
UISpecialFrames = {}
SlashCmdList = {}
function InCombatLockdown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
CURSOR = {0,0}
function GetCursorPosition() return CURSOR[1], CURSOR[2] end
MOUSEDOWN = false
function IsMouseButtonDown() return MOUSEDOWN end
TAXI = false
function UnitOnTaxi() return TAXI end
function hooksecurefunc(obj, name, fn)
  local orig = obj[name]
  obj[name] = function(...) local r = orig(...); fn(...); return r end
end
local Obj = {}
Obj.__index = function(t, k)
  local v = rawget(Obj, k); if v then return v end
  if type(k) == "string" and k:match("^%u") then return function() return nil end end
end
local function new(parent, kind)
  local o = setmetatable({ shown = true, scripts = {}, parent = parent, kind = kind, w = 0, h = 0, points = {}, children = {}, enabled = true, text = "" }, Obj)
  if parent and parent.children then table.insert(parent.children, o) end
  return o
end
function Obj:Show() if not self.shown then self.shown = true; if self:IsVisible() then self:Fire("OnShow") end end end
function Obj:Hide() if self.shown then local vis = self:IsVisible(); self.shown = false; if vis then self:FireHide() end end end
function Obj:FireHide() self:Fire("OnHide"); for _, c in ipairs(self.children) do if c.shown then c:FireHide() end end end
function Obj:SetShown(s) if s then self:Show() else self:Hide() end end
function Obj:IsShown() return self.shown end
function Obj:IsVisible() local o = self; while o do if not o.shown then return false end o = o.parent end return true end
function Obj:Fire(name, ...) local f = self.scripts[name]; if f then f(self, ...) end end
function Obj:SetScript(n, f) self.scripts[n] = f; if n == "OnUpdate" then updates[self] = f end end
function Obj:GetScript(n) return self.scripts[n] end
function Obj:HookScript(n, f) local o = self.scripts[n]; self.scripts[n] = function(...) if o then o(...) end f(...) end end
function Obj:SetSize(w, h) self.w, self.h = w, h end
function Obj:SetWidth(w) self.w = w end
function Obj:SetHeight(h) self.h = h end
function Obj:GetWidth() return self.w end
function Obj:GetHeight() return self.h end
function Obj:SetPoint(...) self.points[1] = {...} end
function Obj:ClearAllPoints() self.points = {} end
function Obj:GetPoint(i) local p = self.points[i or 1] or {}; local a,b,c,d,e = unpack(p)
  if type(b) == "number" then return a, nil, a, b, c end
  return a, b, c, d or 0, e or 0 end
function Obj:GetLeft() return 0 end
function Obj:GetBottom() return 0 end
function Obj:GetEffectiveScale() return 1 end
function Obj:GetFrameLevel() return 1 end
function Obj:GetName() return self.name end
function Obj:CreateTexture() return new(self, "tex") end
function Obj:CreateFontString() return new(self, "fs") end
function Obj:CreateAnimationGroup() return new(self, "ag") end
function Obj:CreateAnimation() return new(self, "anim") end
function Obj:SetText(t) self.text = t end
function Obj:GetText() return self.text end
function Obj:GetStringWidth() return #(self.text or "") * 9 end
function Obj:SetEnabled(e) self.enabled = e and true or false end
function Obj:IsEnabled() return self.enabled end
function Obj:Click() self:Fire("OnClick", "LeftButton") end
function Obj:Play() if self.kind == "ag" then for _, c in ipairs(self.children) do c:Fire("OnFinished") end self:Fire("OnFinished") end end
function Obj:SetColorTexture(r,g,b,a) assert(type(r)=="number" and type(g)=="number" and type(b)=="number", "bad color") end
function Obj:SetFont(f, s) assert(type(s)=="number") end
function CreateFrame(kind, name, parent, template)
  local o = new(parent, "frame"); o.name = name; ALL[#ALL+1] = o; if name then _G[name] = o end; return o
end
UIParent = new(nil, "frame")
GameTooltip = new(nil, "frame")
SOUNDS = {}
function PlaySoundFile(path, ch) local n = path:match("([%w%-]+)%.ogg$"); SOUNDS[n] = (SOUNDS[n] or 0) + 1; return true end
