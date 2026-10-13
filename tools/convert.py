"""Merge Overpass results into one compact dataset for the map + router.
Usage: convert.py out.json bridleways.json paths.json roads.json peaks.json
"""
import json, math, sys
from collections import Counter, defaultdict

out = sys.argv[1]; files = sys.argv[2:5]; peaksfile = sys.argv[5]
CATS = ['bridleway','boat','restricted','permissive','other','footpath','path','cycleway','track','road_minor','road_major','trunk','ferry']
CI = {c:i for i,c in enumerate(CATS)}

def hav(a, b):
    R = 6371000.0
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2-la1)/2)**2 + math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return 2*R*math.asin(math.sqrt(h))

def category(t):
    des = t.get('designation',''); hw = t.get('highway',''); acc = t.get('access','')
    if t.get('route') == 'ferry': return 'ferry'
    if hw == 'steps' or hw == 'motorway' or hw == 'motorway_link': return None
    if des == 'byway_open_to_all_traffic': return 'boat'
    if des == 'restricted_byway': return 'restricted'
    if des == 'public_bridleway': return 'bridleway'
    if des == 'permissive_bridleway' or (hw=='bridleway' and t.get('horse')=='permissive'): return 'permissive'
    if hw == 'bridleway': return 'other'
    if des in ('public_footpath','permissive_footpath'): return 'footpath'
    if hw == 'cycleway' or (hw in ('path','footway') and t.get('bicycle') in ('designated','yes')): return 'cycleway'
    private = acc in ('private','no') and t.get('bicycle') not in ('yes','permissive','designated') and t.get('foot') not in ('yes','permissive','designated')
    if hw in ('path','footway'):
        if t.get('footway') in ('sidewalk','crossing'): return 'road_minor'
        return None if private else 'path'
    if hw == 'track': return None if private else 'track'
    if hw in ('service','living_street','pedestrian','road'): return None if private else 'road_minor'
    if hw in ('unclassified','residential','tertiary','tertiary_link'): return 'road_minor'
    if hw in ('primary','primary_link','secondary','secondary_link'): return 'road_major'
    if hw in ('trunk','trunk_link'): return 'trunk'
    return None

ways = {}
for f in files:
    for e in json.load(open(f))['elements']:
        if e.get('type')!='way' or 'geometry' not in e or e['id'] in ways: continue
        t = e.get('tags',{}); c = category(t)
        if not c: continue
        pts = [(round(p['lat']*1e5), round(p['lon']*1e5)) for p in e['geometry']]
        pts = [p for i,p in enumerate(pts) if i==0 or p!=pts[i-1]]
        if len(pts) < 2: continue
        ways[e['id']] = (c, t, pts)

# junction detection: a vertex used by more than one way, or more than once in a way (loops)
use = Counter()
for c,t,pts in ways.values():
    for p in set(pts): use[p] += 1
    for p,n in Counter(pts).items():
        if n>1: use[p] += 1

def dp(pts, keep, tol):
    """Douglas-Peucker in metres, forced to keep junction vertices."""
    def seg(a, b, lo, hi, out):
        # find max distance
        best, bi = -1, -1
        A = (pts[a][0]/1e5, pts[a][1]/1e5); B = (pts[b][0]/1e5, pts[b][1]/1e5)
        for i in range(a+1, b):
            P = (pts[i][0]/1e5, pts[i][1]/1e5)
            # perpendicular distance via projection in local metres
            kx = 111320*math.cos(math.radians(P[0])); ky = 110540
            ax,ay = (A[1]-P[1])*kx,(A[0]-P[0])*ky; bx,by=(B[1]-P[1])*kx,(B[0]-P[0])*ky
            dx,dy = bx-ax, by-ay; L2 = dx*dx+dy*dy
            if L2==0: d = math.hypot(ax,ay)
            else:
                tt = max(0,min(1,-(ax*dx+ay*dy)/L2)); d = math.hypot(ax+tt*dx, ay+tt*dy)
            if keep[i]: d = float('inf')
            if d>best: best, bi = d, i
        if bi>=0 and best>tol:
            seg(a,bi,lo,hi,out); out.append(bi); seg(bi,b,lo,hi,out)
    idx=[0]; seg(0,len(pts)-1,0,0,idx); idx.append(len(pts)-1)
    idx=sorted(set(idx)); return [pts[i] for i in idx]

def encode(pts):
    # Google polyline encoding, precision 5
    res=[]; plat=plon=0
    for la,lo in pts:
        for v in (la-plat, lo-plon):
            v = ~(v<<1) if v<0 else v<<1
            while v>=0x20:
                res.append(chr((0x20|(v&0x1f))+63)); v>>=5
            res.append(chr(v+63))
        plat,plon=la,lo
    return ''.join(res)

outways=[]; km=Counter(); nv_before=nv_after=0
for wid,(c,t,pts) in ways.items():
    keep=[use[p]>1 for p in pts]
    nv_before+=len(pts)
    sp = dp(pts, keep, 2.0)
    nv_after+=len(sp)
    L = sum(hav((sp[i][0]/1e5,sp[i][1]/1e5),(sp[i+1][0]/1e5,sp[i+1][1]/1e5)) for i in range(len(sp)-1))
    if c=='ferry' and t.get('bicycle')!='yes': continue   # only ferries that carry bikes (Windermere, Ullswater)
    km[c]+=L/1000
    rec=[CI[c], round(L), wid, encode(sp)]
    extra={}
    for k in ('name','prow_ref','surface','tracktype'):
        if k in t: extra[k]=t[k]
    if c in ('bridleway','boat','restricted','permissive','other','footpath','path','track') and t.get('highway'): extra['hw']=t['highway']
    if extra: rec.append(extra)
    outways.append(rec)

peaks=[]
for e in json.load(open(peaksfile))['elements']:
    try: ele=float(str(e['tags']['ele']).replace('m','').strip())
    except: continue
    peaks.append({'n':e['tags']['name'],'e':round(ele),'la':round(e['lat'],5),'lo':round(e['lon'],5)})
# The ten highest Lake District fells (Wainwright summits; subsidiary tops such as Broad Crag excluded)
TOP10=['Scafell Pike','Sca Fell','Helvellyn','Skiddaw','Great End','Bowfell','Great Gable','Pillar','Nethermost Pike','Catstycam']
byname={}
for p in peaks:
    if p['n'] in TOP10 and (p['n'] not in byname or p['e']>byname[p['n']]['e']): byname[p['n']]=p
top=[dict(byname[n], n={'Sca Fell':'Scafell','Catstycam':'Catstye Cam'}.get(n,n)) for n in TOP10 if n in byname]

json.dump({'cats':CATS,'ways':outways,'peaks':top}, open(out,'w'), separators=(',',':'), ensure_ascii=False)
for c in CATS: print(f"{c:11s} {km[c]:8.1f} km")
print(len(outways),'ways; vertices',nv_before,'->',nv_after)
print('peaks:',[(p['n'],p['e']) for p in top])
