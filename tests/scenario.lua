local IFE = InFlightEntertainment
local E = IFE.ChessEngine
local function fire(event, ...) for _, f in ipairs(ALL) do f:Fire("OnEvent", event, ...) end end
local function find(root, pred) if pred(root) then return root end for _, c in ipairs(root.children) do local r = find(c, pred) if r then return r end end end
local function btn(label) return find(IFE.frame, function(o) return o.text and type(o.text) == "table" and o.text.text == label end) end

fire("ADDON_LOADED", "InFlightEntertainment"); fire("PLAYER_LOGIN")
local F = IFE.frame
F.shown = false
TAXI = true; fire("PLAYER_CONTROL_LOST"); RunTimers(2)
assert(F:IsShown(), "should auto-show on taxi"); print("auto-show on taxi OK")
TAXI = false; fire("PLAYER_CONTROL_GAINED"); RunTimers(2)
assert(not F:IsShown(), "should hide on landing"); print("auto-hide on landing OK")
IFE.db.autoShow = false; TAXI = true; fire("PLAYER_CONTROL_LOST"); RunTimers(2)
assert(not F:IsShown(), "toggle off should not show"); print("toggle off respected")
TAXI = false; RunTimers(2); IFE.db.autoShow = true
SlashCmdList.INFLIGHTENTERTAINMENT(""); assert(F:IsShown()); print("/ife opens")

local function startGame(key) find(F, function(o) return o.def and o.def.key == key end):Click(); return IFE.instances[key] end
local function back() btn("< Back to Menu"):Click() end

-------------------------------------------------- chess
local C = startGame("chess")
local SQ = 60
local function clickSq(sq, drag)
  local f, r = sq % 8, math.floor(sq / 8)
  if C.flipped then f, r = 7 - f, 7 - r end
  CURSOR = { f * SQ + 30, r * SQ + 30 }
end
local function userMove(uci, drag)
  local from, to = E.ParseSquare(uci:sub(1,2)), E.ParseSquare(uci:sub(3,4))
  clickSq(from); MOUSEDOWN = true; C.board:Fire("OnMouseDown", "LeftButton")
  if drag then RunUpdates(2); clickSq(to); MOUSEDOWN = false; C.board:Fire("OnMouseUp", "LeftButton")
  else MOUSEDOWN = false; C.board:Fire("OnMouseUp", "LeftButton"); clickSq(to); C.board:Fire("OnMouseDown", "LeftButton"); C.board:Fire("OnMouseUp", "LeftButton") end
  if #uci == 5 then
    assert(C.promo:IsShown(), "promo picker"); for _, b in ipairs(C.promo.buttons) do if b.kind == uci:sub(5,5) then b:Click() end end
  end
  RunUpdates(10)
end
local solvedN, start = 0, IFE.db.chess.rating
for n = 1, 40 do
  RunTimers(1.5); RunUpdates(10)
  assert(C.state == "player", "expected player state, got " .. tostring(C.state))
  while C.state ~= "done" do
    userMove(C.moves[C.ply + 1], n % 2 == 0)
    RunTimers(1.5); RunUpdates(10); RunTimers(1)
    assert(C.state == "player" or C.state == "done", "state " .. tostring(C.state) .. " puzzle " .. C.entry[1])
  end
  assert(C.success and not C.failed); solvedN = solvedN + 1
  C:Next()
end
print("chess: solved 40 puzzles by mouse (click + drag); rating", start, "->", IFE.db.chess.rating)
-- wrong move path
RunTimers(1.5); RunUpdates(10)
local legal = E.LegalMoves(C.pos); local wrong
for _, m in ipairs(legal) do local u = E.ToUCI(m); if u ~= C.moves[C.ply+1] and not E.IsCheckmate(E.MakeMove(C.pos, m)) then wrong = u break end end
local r0 = IFE.db.chess.rating
userMove(wrong); RunTimers(1)
assert(C.state == "wrong" and IFE.db.chess.rating < r0); print("wrong move -> Incorrect, rating", r0, "->", IFE.db.chess.rating)
local rb = btn("Retry"); print("retry btn", rb, rb and rb.scripts.OnClick); rb:Click(); print("state after retry", C.state); assert(C.state == "player")
btn("Solution"):Click(); for i = 1, 400 do RunUpdates(1); RunTimers(0) end
assert(C.state == "done"); print("solution playback ok:", C.statusTitle.text)
C:Next(); RunTimers(1.5); RunUpdates(10)
C:Hint(); assert(C.hintSq); print("hint ok")
back()

-------------------------------------------------- wordle
local W = startGame("wordle")
local function typeWord(w) for c in w:gmatch(".") do W.frame:Fire("OnKeyDown", c) end W.frame:Fire("OnKeyDown", "ENTER") RunTimers(3) end
typeWord("XQZZY"); assert(W.toast.text.text == "Not in word list"); print("wordle: invalid word rejected")
W.frame:Fire("OnKeyDown", "BACKSPACE"); for i = 1, 5 do W.frame:Fire("OnKeyDown", "BACKSPACE") end
assert(W.current == "")
local probe = W.answer == "CRANE" and "SLATE" or "CRANE"
typeWord(probe); assert(#W.guesses == 1)
typeWord(W.answer); RunTimers(5)
assert(W.status == "won" and W.statsPanel:IsShown()); print("wordle: won in", #W.guesses, "toast:", W.toast.text.text, "stats played", IFE.db.wordle.stats.played)
-- hard mode practice
W.statsPanel.play:Click(); assert(W.mode == "practice")
W:ToggleHard(); assert(IFE.db.wordle.hardMode)
typeWord(probe); local res = W.guesses[1]
local nextWord = "FUZZY" ; typeWord(nextWord); print("hard mode guess result:", #W.guesses, W.toast.text.text)
-- dup letter scoring sanity
W.answer = "ABBEY"
back()
-- reopen keeps daily state
local W2 = startGame("wordle"); assert(#W2.guesses >= 1); back()

-------------------------------------------------- connections
local CN = startGame("connections")
local P = CN.puzzle
local function selectWords(list) CN:DeselectAll(); for _, w in ipairs(list) do for _, t in ipairs(CN.tiles) do if t.word == w and t:IsShown() then t:Click() end end end end
selectWords(P[1].words); assert(CN.selectedCount == 4); btn("Submit"):Click(); RunTimers(2)
assert(#CN:State().solved == 1); print("connections: group 1 solved")
local oneAway = { P[2].words[1], P[2].words[2], P[2].words[3], P[3].words[1] }
selectWords(oneAway); btn("Submit"):Click(); print("toast:", CN.toast.text.text); RunTimers(2)
selectWords(oneAway); btn("Submit"):Click(); print("toast:", CN.toast.text.text); RunTimers(2)
assert(CN:State().mistakes == 1)
for i = 1, 3 do
  selectWords({ P[2].words[i], P[3].words[i], P[4].words[i], P[2].words[4] }); btn("Submit"):Click(); RunTimers(2)
end
RunTimers(10)
local st = CN:State()
assert(st.done and not st.won and #st.solved == 4 and CN.results:IsShown()); print("connections: loss reveals all groups, results shown:", CN.results.title.text)
CN:LoadRandomUnplayed(); local P2 = CN.puzzle
for g = 4, 1, -1 do selectWords(P2[g].words); btn("Submit"):Click(); RunTimers(2) end
RunTimers(4); assert(CN:State().won and CN.results:IsShown()); print("connections: win ->", CN.results.title.text)
back()
for _, c in ipairs(find(F, function(o) return o.def end).parent.children) do if c.status then print("menu:", c.status.text) end end
local s = {} for k, v in pairs(SOUNDS) do s[#s+1] = k .. "=" .. v end table.sort(s) print("sound counts:", table.concat(s, " "))
F:Hide(); print("ALL SCENARIOS PASSED")
