import os
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\","/")+"/"
import sys, csv, random
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", ".deps"))
import chess
random.seed(42)
buckets = {}
with open(sys.argv[1], newline="", encoding="utf-8") as f:
    rd = csv.reader(f); next(rd)
    for row in rd:
        if len(row) < 10: continue
        pid,fen,moves,rating,rd_,pop,plays,themes = row[:8]
        try: rating=int(rating); rd_=int(rd_); pop=int(pop); plays=int(plays)
        except: continue
        if rd_>80 or pop<88 or plays<800 or rating<500 or rating>2600: continue
        mv = moves.split()
        if len(mv) > 10: continue
        b = (rating//100)*100
        buckets.setdefault(b, []).append((pid,fen,moves,rating,themes))
out=[]
for b in sorted(buckets):
    lst=buckets[b]; random.shuffle(lst); out += lst[:50]
# verify
for pid,fen,moves,rating,themes in out:
    bd = chess.Board(fen)
    for m in moves.split():
        mv = chess.Move.from_uci(m); assert mv in bd.legal_moves, pid; bd.push(mv)
out.sort(key=lambda r:r[3])
p = ROOT+"Data/ChessPuzzles.lua"
with open(p,"w",encoding="utf-8",newline="\n") as w:
    w.write("-- Chess puzzles from the Lichess puzzle database (CC0 public domain): https://database.lichess.org/#puzzles\n")
    w.write("-- Fields: id, FEN (position before the opponent's setup move), moves (UCI; first move is the opponent's), rating, themes\n")
    w.write("InFlightEntertainment_ChessPuzzles = {\n")
    for pid,fen,moves,rating,themes in out:
        w.write('{"%s","%s","%s",%d,"%s"},\n'%(pid,fen,moves,rating,themes))
    w.write("}\n")
print(len(out), {b:min(50,len(v)) for b,v in sorted(buckets.items())})
