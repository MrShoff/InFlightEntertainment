"""Offline test suite for In-Flight Entertainment.

Setup (once):  pip install --target tests/.deps lupa chess
Run:           python -I tests/run.py

1. Syntax-checks every .lua file with real Lua 5.1 (WoW's Lua version).
2. Chess engine perft on 5 standard positions + replays every puzzle against python-chess.
3. Loads the whole addon (TOC order) against a mocked WoW API (tests/mock.lua) and plays
   all three games end to end (tests/scenario.lua). Ends with "ALL SCENARIOS PASSED".
"""
import sys, glob, os
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE).replace("\\", "/") + "/"
sys.path.insert(0, os.path.join(HERE, ".deps"))
import lupa.lua51 as L
import chess

def runtime():
    return L.LuaRuntime(unpack_returned_tuples=True)

# 1. syntax
lua = runtime()
bad = 0
for f in glob.glob(ROOT + "**/*.lua", recursive=True):
    if "/tests/" in f.replace("\\", "/"):
        continue
    err = lua.eval("function(s,n) local f,e=loadstring(s,n) return e end")(open(f, encoding="utf-8").read(), os.path.basename(f))
    if err:
        print("SYNTAX", err); bad += 1
print("syntax errors:", bad)

# 2. engine
IFE = lua.table()
lua.eval("function(s,ife) assert(loadstring(s))('IFE', ife) end")(open(ROOT + "Chess/ChessEngine.lua").read(), IFE)
lua.execute(open(ROOT + "Data/ChessPuzzles.lua", encoding="utf-8").read())
E = IFE.ChessEngine
perft = lua.eval("""function(E, fen, d)
  local function p(pos, d) if d==0 then return 1 end local n=0
    for _,m in ipairs(E.LegalMoves(pos)) do n=n+p(E.MakeMove(pos,m),d-1) end return n end
  return p(E.FromFEN(fen), d) end""")
tests = [("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 3, 8902),
         ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 3, 97862),
         ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 4, 43238),
         ("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 3, 9467),
         ("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 3, 62379)]
for fen, d, exp in tests:
    got = perft(E, fen, d)
    print("perft", d, got, exp, "OK" if got == exp else "FAIL"); bad += got != exp
check = lua.eval("""function(E, fen, moves)
  local pos=E.FromFEN(fen); local counts={}
  for mv in moves:gmatch('%S+') do
    counts[#counts+1]=#E.LegalMoves(pos)
    local m=E.MoveFromUCI(pos,mv); if not m then return 'missing '..mv end
    pos=E.MakeMove(pos,m)
  end
  counts[#counts+1]=#E.LegalMoves(pos)
  return table.concat(counts,','), E.IsCheckmate(pos) end""")
P = lua.globals().InFlightEntertainment_ChessPuzzles
fails = 0
for i in range(1, len(P) + 1):
    e = P[i]
    res, mate = check(E, e[2], e[3])
    b = chess.Board(e[2]); cnt = []
    for mv in e[3].split():
        cnt.append(b.legal_moves.count()); b.push_uci(mv)
    cnt.append(b.legal_moves.count())
    if res != ",".join(map(str, cnt)) or bool(mate) != b.is_checkmate():
        fails += 1; print("MISMATCH", e[1])
print("puzzles checked:", len(P), "mismatches:", fails); bad += fails

# 3. simulated gameplay
lua = runtime()
lua.execute(open(os.path.join(HERE, "mock.lua")).read())
toc = [l.strip() for l in open(ROOT + "InFlightEntertainment.toc") if l.strip() and not l.startswith("#")]
ns = lua.table()
load = lua.eval("function(s,n,ns) assert(loadstring(s,n))('InFlightEntertainment', ns) end")
for f in toc:
    load(open(ROOT + f.replace("\\", "/"), encoding="utf-8").read(), f, ns)
lua.execute(open(os.path.join(HERE, "scenario.lua")).read())
sys.exit(1 if bad else 0)
