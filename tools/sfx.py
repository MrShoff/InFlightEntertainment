import os
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\","/")+"/"
import numpy as np, wave, subprocess, os
SR=44100
rng=np.random.default_rng(7)
def t(d): return np.arange(int(SR*d))/SR
def env(d, decay): return np.exp(-t(d)/decay)
def pad(x, d):
    out=np.zeros(int(SR*d)); out[:min(len(x),len(out))]+=x[:len(out)]; return out
def tap(modes, decays, gains, noise=0.6, nd=0.0025, thump=(170,0.03,0.5), d=0.25):
    x=np.zeros(int(SR*d)); tt=t(d)
    for f,dc,g in zip(modes,decays,gains):
        x+=g*np.sin(2*np.pi*f*tt+rng.uniform(0,6.28))*np.exp(-tt/dc)
    f,dc,g=thump; x+=g*np.sin(2*np.pi*f*tt)*np.exp(-tt/dc)
    n=rng.standard_normal(int(SR*nd))*np.linspace(1,0,int(SR*nd))
    # brighten noise with a simple first difference (high-pass)
    n=np.diff(np.concatenate([[0],n])); x[:len(n)]+=noise*n
    x[:40]*=np.linspace(0,1,40)
    return x
def mix(*parts, d):
    out=np.zeros(int(SR*d))
    for off,x in parts:
        i=int(SR*off); n=min(len(x),len(out)-i); out[i:i+n]+=x[:n]
    return out
def bell(freqs, d, decay=0.35, gains=None):
    tt=t(d); x=np.zeros(len(tt))
    for i,f in enumerate(freqs):
        g=(gains or [1]*len(freqs))[i]
        x+=g*(np.sin(2*np.pi*f*tt)+0.35*np.sin(2*np.pi*f*2.01*tt)*np.exp(-tt/(decay*0.4)))*np.exp(-tt/decay)
    x[:120]*=np.linspace(0,1,120); return x
def save(name, x, peak=0.7):
    x=x/np.max(np.abs(x))*peak
    fade=int(SR*0.01); x[-fade:]*=np.linspace(1,0,fade)
    os.makedirs(os.path.join(os.path.dirname(os.path.abspath(__file__)),".snd"),exist_ok=True); w=os.path.join(os.path.dirname(os.path.abspath(__file__)),".snd",name+".wav")
    with wave.open(w,"wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes((x*32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg","-y","-loglevel","error","-i",w,"-c:a","libvorbis","-q:a","5",
        ROOT+f"Media/Sounds/{name}.ogg"],check=True)
wood=([820,1730,2950],[0.022,0.014,0.008],[1,0.55,0.3])
save("move-self",  tap(*wood, d=0.22), 0.6)
save("move-opponent", tap([700,1520,2600],[0.024,0.015,0.008],[1,0.5,0.25], noise=0.45, thump=(150,0.035,0.55), d=0.22), 0.55)
cap=tap([980,2100,3600],[0.02,0.012,0.007],[1,0.7,0.45], noise=1.1, nd=0.004, thump=(200,0.025,0.6), d=0.25)
save("capture", mix((0,cap),(0.018,0.6*tap(*wood, d=0.2)), d=0.28), 0.75)
save("castle", mix((0,tap(*wood,d=0.2)),(0.11,0.85*tap([760,1650,2800],[0.022,0.014,0.008],[1,0.55,0.3],d=0.2)), d=0.34), 0.62)
chk=mix((0,tap([1050,2250,3900],[0.025,0.015,0.008],[1,0.6,0.4],noise=1.0,d=0.3)),(0.0,0.35*bell([1568],0.3,0.12)), d=0.32)
save("move-check", chk, 0.72)
save("promote", mix((0,tap(*wood,d=0.2)),(0.05,0.4*bell([1047],0.4,0.12)),(0.13,0.4*bell([1568],0.5,0.18)), d=0.6), 0.65)
x=mix((0,bell([392],0.35,0.09)),(0.12,bell([294],0.5,0.13)), d=0.62); save("incorrect", x, 0.5)
save("solved", mix((0,bell([1047],0.5,0.2)),(0.1,bell([1319],0.5,0.2)),(0.2,bell([1568],0.9,0.35)),(0.2,0.5*bell([2093],0.9,0.3)), d=1.1), 0.5)
save("illegal", mix((0,tap([300,640],[0.03,0.015],[1,0.4],noise=0.2,thump=(110,0.04,0.8),d=0.2)), d=0.2), 0.45)
print(sorted(os.listdir(ROOT+"Media/Sounds")))
