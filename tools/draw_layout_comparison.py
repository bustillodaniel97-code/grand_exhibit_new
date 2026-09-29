"""Grayscale plan review from venue data, with furniture and room colors removed.

Usage: python3 game/tools/draw_layout_comparison.py BEFORE AFTER OUTPUT VENUE...
Room footprints, physical walls, stairs, desk orientations and queue directions
are shown. Arrows indicate queue fronts, not invented navigation paths.
"""
import argparse,json,math
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
parser=argparse.ArgumentParser();parser.add_argument('before');parser.add_argument('after');parser.add_argument('output');parser.add_argument('venues',nargs='+');args=parser.parse_args()
docs=[{v['id']:v for v in json.loads(Path(p).read_text())['venues']} for p in [args.before,args.after]]
fontfile='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
font=ImageFont.truetype(fontfile,14);small=ImageFont.truetype(fontfile,10);title=ImageFont.truetype(fontfile,21)
width,height=740,670
im=Image.new('RGB',(width*2,height*len(args.venues)), '#f5f5f3');draw=ImageDraw.Draw(im)
for row,vid in enumerate(args.venues):
    for col,doc in enumerate(docs):
        theme=doc[vid]['theme'];rooms={r['id']:r for r in theme['rooms']}
        left=min(r['rect'][0] for r in rooms.values());top=min(r['rect'][1] for r in rooms.values())
        right=max(r['rect'][0]+r['rect'][2] for r in rooms.values());bottom=max(r['rect'][1]+r['rect'][3] for r in rooms.values())
        scale=min(30,(width-85)/(right-left),(height-165)/(bottom-top))
        ox=col*width+(width-(right-left)*scale)/2-left*scale;oy=row*height+75-top*scale
        def xy(p):return (ox+p[0]*scale,oy+p[1]*scale)
        label=('BEFORE' if col==0 else 'REVISED')+' / '+doc[vid]['name']
        draw.text((col*width+30,row*height+20),label,font=title,fill='#222222')
        for rid,r in rooms.items():
            x,y,w,h=r['rect'];a=xy([x,y]);b=xy([x+w,y+h]);level=int(r.get('level',0))
            draw.rectangle([a,b],fill='#d4d4d4' if level else '#e7e7e5',outline='#a2a2a2',width=1)
            text=rid.replace('_',' ').upper()
            if r.get('role')=='queue':text='ADMISSIONS'
            elif rid=='archive':text='CONSERVATION'
            elif rid=='promotions':text='CAFE / MEMBERS'
            elif rid=='lobby':text='ARRIVAL'
            if len(text)*7>w*scale:text=text.replace(' ','\n',1)
            draw.multiline_text((a[0]+7,a[1]+6),text,font=small,fill='#555555',spacing=2)
            rise=int(r.get('rise_to',level))
            if rise!=level:
                for j in range(1,11):
                    tread=([x+w*j/11,y],[x+w*j/11,y+h]) if r.get('stair_axis','y')=='x' else ([x,y+h*j/11],[x+w,y+h*j/11])
                    draw.line([xy(tread[0]),xy(tread[1])],fill='#777777',width=1)
        for w in theme.get('walls',[]):
            a=w['at'];b=[a[0]+(w['len'] if w.get('axis','x')=='x' else 0),a[1]+(w['len'] if w.get('axis','x')=='y' else 0)]
            draw.line([xy(a),xy(b)],fill='#373737',width=3)
        queue_room=next(r for r in rooms.values() if r['role']=='queue');q=queue_room['queue'];count=int(q['windows']);entries=q.get('stations',[])
        for n in range(count):
            entry=entries[n] if entries else dict(at=[q.get('first_gx',2.3)+n*q.get('gx_step',2.5),q.get('counter_gy',1.1)])
            home=rooms[entry.get('room',queue_room['id'])]['rect'];c=[home[0]+entry['at'][0],home[1]+entry['at'][1]];front=entry.get('front',[0,1]);side=[front[1],-front[0]];sz=q.get('counter_size',[1.7,.6]);points=[]
            for u,v in [(-1,-1),(1,-1),(1,1),(-1,1)]:points.append(xy([c[0]+side[0]*u*sz[0]/2+front[0]*v*sz[1]/2,c[1]+side[1]*u*sz[0]/2+front[1]*v*sz[1]/2]))
            draw.polygon(points,fill='#444444')
            for slot in range(int(q.get('slots',4))):
                d=q.get('slot_lead',1)+slot*q.get('slot_gap',.55);p=xy([c[0]+front[0]*d,c[1]+front[1]*d]);draw.ellipse([p[0]-3,p[1]-3,p[0]+3,p[1]+3],fill='#555555')
            p=xy(c);draw.text((p[0]-3,p[1]-6),str(n+1),font=small,fill='white')
        lobby=next(r for r in rooms.values() if r['role']=='lobby');lr=lobby['rect']
        departure=next((r for r in rooms.values() if r['role']=='departure'),lobby)
        for key,label,home in [('door','IN',lobby),('exit','OUT',departure)]:
            if key not in home:continue
            hr=home['rect'];x=hr[0]+home[key][0];p=xy([x,hr[1]+hr[3]]);draw.line([p,(p[0],p[1]+16)],fill='#222222',width=2);draw.text((p[0]-8,p[1]+18),label,font=small,fill='#222222')
        draw.text((col*width+30,(row+1)*height-35),'Desks, queues and walls; furniture omitted. Explicit door data shown.',font=font,fill='#555555')
im.save(args.output)
