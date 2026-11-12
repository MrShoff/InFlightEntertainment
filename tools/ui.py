import os
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\","/")+"/"
from PIL import Image, ImageDraw
out=ROOT+"Media/"
B=256
def save(im,name): im.resize((64,64),Image.LANCZOS).save(out+name+".tga")
im=Image.new("RGBA",(B,B),(0,0,0,0)); d=ImageDraw.Draw(im); d.ellipse((2,2,B-3,B-3),fill=(255,255,255,255)); save(im,"circle")
im=Image.new("RGBA",(B,B),(0,0,0,0)); d=ImageDraw.Draw(im); d.ellipse((2,2,B-3,B-3),outline=(255,255,255,255),width=26); save(im,"ring")
im=Image.new("RGBA",(B,B),(0,0,0,0)); d=ImageDraw.Draw(im); d.ellipse((8,8,B-9,B-9),fill=(129,182,76,255),outline=(255,255,255,255),width=12)
d.line([(70,132),(110,172),(186,88)],fill=(255,255,255,255),width=26,joint="curve"); save(im,"ok")
im=Image.new("RGBA",(B,B),(0,0,0,0)); d=ImageDraw.Draw(im); d.ellipse((8,8,B-9,B-9),fill=(202,52,49,255),outline=(255,255,255,255),width=12)
d.line([(84,84),(172,172)],fill=(255,255,255,255),width=26); d.line([(172,84),(84,172)],fill=(255,255,255,255),width=26); save(im,"bad")
im=Image.new("RGBA",(B,B),(0,0,0,0)); d=ImageDraw.Draw(im); d.ellipse((8,8,B-9,B-9),fill=(240,185,40,255),outline=(255,255,255,255),width=12)
d.rectangle((116,60,140,150),fill=(255,255,255,255)); d.ellipse((114,168,142,196),fill=(255,255,255,255)); save(im,"hint")
print("ok")
