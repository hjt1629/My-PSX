#!/usr/bin/env python3
# 앱 아이콘(Resources/AppIcon.png, 1024×1024)을 다시 그립니다. 필요: pip install pillow
# 사용법: python3 scripts/make-icon.py Resources/AppIcon.png
from PIL import Image, ImageDraw, ImageFilter
import sys
S=4; N=1024*S
def L(v): return int(v*S)
img=Image.new('RGBA',(N,N),(0,0,0,0))
# macOS 아이콘 격자: 824x824 본체, 모서리 반경 185
x0,y0,x1,y1=L(100),L(100),L(924),L(924); R=L(185)
# 그림자
sh=Image.new('RGBA',(N,N),(0,0,0,0)); d=ImageDraw.Draw(sh)
d.rounded_rectangle((x0,y0+L(12),x1,y1+L(12)),R,fill=(0,0,0,110))
sh=sh.filter(ImageFilter.GaussianBlur(L(14))); img.alpha_composite(sh)
# 배경 그라데이션 (위: 남색 → 아래: 보라빛 파랑)
grad=Image.new('RGBA',(N,N))
top=(35,48,92); bot=(18,22,44)
gd=ImageDraw.Draw(grad)
for y in range(N):
    t=y/N; gd.line([(0,y),(N,y)],fill=tuple(int(top[i]*(1-t)+bot[i]*t) for i in range(3))+(255,))
mask=Image.new('L',(N,N),0); ImageDraw.Draw(mask).rounded_rectangle((x0,y0,x1,y1),R,fill=255)
img.paste(grad,(0,0),mask)
# 사진 카드 (뒤 장 살짝 기울임)
def card(angle, offset, fill, alpha):
    c=Image.new('RGBA',(N,N),(0,0,0,0)); cd=ImageDraw.Draw(c)
    cx,cy=N//2+L(offset[0]),N//2+L(offset[1]); w,h=L(500),L(400)
    cd.rounded_rectangle((cx-w//2,cy-h//2,cx+w//2,cy+h//2),L(36),fill=fill+(alpha,))
    return c.rotate(angle,resample=Image.BICUBIC,center=(cx,cy))
img.alpha_composite(card(-12,(-30,10),(120,140,200),150))
img.alpha_composite(card(0,(20,0),(255,255,255),255))
# 사진 안쪽: 하늘 + 산 + 해
cx,cy=N//2+L(20),N//2; w,h=L(500),L(400); m=L(26)
ix0,iy0,ix1,iy1=cx-w//2+m,cy-h//2+m,cx+w//2-m,cy+h//2-m
inner=Image.new('RGBA',(N,N),(0,0,0,0)); idr=ImageDraw.Draw(inner)
for y in range(iy0,iy1):
    t=(y-iy0)/(iy1-iy0); a=(64,156,255); b=(140,210,255)
    idr.line([(ix0,y),(ix1,y)],fill=tuple(int(a[i]*(1-t)+b[i]*t) for i in range(3))+(255,))
idr.ellipse((ix1-L(150),iy0+L(40),ix1-L(70),iy0+L(120)),fill=(255,206,64,255))
idr.polygon([(ix0,iy1),(ix0+L(140),iy0+L(150),),(ix0+L(270),iy1)],fill=(40,170,110,255))
idr.polygon([(ix0+L(150),iy1),(ix0+L(300),iy0+L(110)),(ix1,iy1)],fill=(24,128,86,255))
im=Image.new('L',(N,N),0); ImageDraw.Draw(im).rounded_rectangle((ix0,iy0,ix1,iy1),L(16),fill=255)
img.paste(inner,(0,0),im)
# 반짝이 (AI 편집)
def sparkle(cx,cy,r,col):
    s=Image.new('RGBA',(N,N),(0,0,0,0)); sd=ImageDraw.Draw(s)
    k=r*0.22
    sd.polygon([(cx,cy-r),(cx+k,cy-k),(cx+r,cy),(cx+k,cy+k),(cx,cy+r),(cx-k,cy+k),(cx-r,cy),(cx-k,cy-k)],fill=col)
    return s
img.alpha_composite(sparkle(L(745),L(300),L(95),(255,214,90,255)))
img.alpha_composite(sparkle(L(820),L(420),L(42),(255,240,190,255)))
out=img.resize((1024,1024),Image.LANCZOS)
out.save(sys.argv[1])
