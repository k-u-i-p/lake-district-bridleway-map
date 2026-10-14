/* Lake District bridleway router: graph build, A* routing, loop planning.
   Used from Node (module.exports) by make-route.js; the iOS app's Routing/ is a port of it. */
(function(root){
'use strict';
const Router = {};

// ---- geometry helpers
const R = 6371000;
function hav(la1, lo1, la2, lo2){ // degrees -> metres
  const p = Math.PI/180, dLa=(la2-la1)*p, dLo=(lo2-lo1)*p;
  const a = Math.sin(dLa/2)**2 + Math.cos(la1*p)*Math.cos(la2*p)*Math.sin(dLo/2)**2;
  return 2*R*Math.asin(Math.sqrt(a));
}
Router.hav = hav;

Router.decode = function(str){ // Google polyline (precision 5) -> flat int array [lat,lon,...] (1e-5 deg units)
  let i=0, lat=0, lon=0; const out=[];
  while(i<str.length){
    let shift=0, result=0, b;
    do{ b=str.charCodeAt(i++)-63; result|=(b&0x1f)<<shift; shift+=5; }while(b>=0x20);
    lat += (result&1)?~(result>>1):(result>>1);
    shift=0; result=0;
    do{ b=str.charCodeAt(i++)-63; result|=(b&0x1f)<<shift; shift+=5; }while(b>=0x20);
    lon += (result&1)?~(result>>1):(result>>1);
    out.push(lat,lon);
  }
  return out;
};

// ---- graph
Router.build = function(data){
  const ways = data.ways, nWays = ways.length;
  const key2id = new Map(); const nlat=[], nlon=[];
  function nodeId(la, lo){
    const k = la*100000000 + (lo+50000000);
    let id = key2id.get(k);
    if(id===undefined){ id=nlat.length; key2id.set(k,id); nlat.push(la); nlon.push(lo); }
    return id;
  }
  const eFrom=[], eTo=[], eLen=[], eWay=[];
  const wayNodes = new Array(nWays), wayCat = new Int8Array(nWays), wayLen = new Float32Array(nWays);
  for(let w=0; w<nWays; w++){
    const rec = ways[w]; const pts = Router.decode(rec[3]);
    const ids = new Int32Array(pts.length/2);
    for(let i=0;i<pts.length;i+=2) ids[i>>1] = nodeId(pts[i], pts[i+1]);
    wayNodes[w]=ids; wayCat[w]=rec[0]; wayLen[w]=rec[1];
    for(let i=0;i<ids.length-1;i++){
      const a=ids[i], b=ids[i+1]; if(a===b) continue;
      const len = hav(nlat[a]/1e5, nlon[a]/1e5, nlat[b]/1e5, nlon[b]/1e5);
      eFrom.push(a,b); eTo.push(b,a); eLen.push(len,len); eWay.push(w,w);
    }
  }
  const n = nlat.length, m = eFrom.length;
  const off = new Int32Array(n+1);
  for(let e=0;e<m;e++) off[eFrom[e]+1]++;
  for(let i=0;i<n;i++) off[i+1]+=off[i];
  const adj = new Int32Array(m); const fill = off.slice(0,n);
  for(let e=0;e<m;e++) adj[fill[eFrom[e]]++] = e;
  // spatial grid (0.005 deg cells) for snapping
  const grid = new Map(); const CELL=500; // in 1e-5 deg units
  for(let i=0;i<n;i++){
    const k = Math.floor(nlat[i]/CELL)*100000 + Math.floor(nlon[i]/CELL);
    let arr = grid.get(k); if(!arr){arr=[]; grid.set(k,arr);} arr.push(i);
  }
  return { cats:data.cats, ways, nlat:Int32Array.from(nlat), nlon:Int32Array.from(nlon),
           eTo:Int32Array.from(eTo), eLen:Float32Array.from(eLen), eWay:Int32Array.from(eWay),
           off, adj, wayNodes, wayCat, wayLen, grid, CELL, n, m };
};

Router.nearest = function(g, lat, lon, maxM){
  maxM = maxM || 300;
  const la=Math.round(lat*1e5), lo=Math.round(lon*1e5);
  const cla=Math.floor(la/g.CELL), clo=Math.floor(lo/g.CELL);
  const r = Math.ceil(maxM/400)+1; // cells to search
  // prefer snapping to rideable ways: a footpath node must be much closer than a bridleway/road node to win
  const pref = g.snapPref || (g.snapPref = g.cats.map(c => ({footpath:2.2, path:2.2, ferry:3, trunk:2, track:1.2, cycleway:1.1}[c] || 1)));
  let best=-1, bd=Infinity, bs=Infinity;
  for(let dy=-r;dy<=r;dy++) for(let dx=-r;dx<=r;dx++){
    const arr = g.grid.get((cla+dy)*100000 + (clo+dx)); if(!arr) continue;
    for(const i of arr){
      const d = hav(lat,lon,g.nlat[i]/1e5,g.nlon[i]/1e5); if(d>maxM) continue;
      let pf=Infinity; for(let k=g.off[i];k<g.off[i+1];k++){ const f=pref[g.wayCat[g.eWay[g.adj[k]]]]; if(f<pf) pf=f; }
      const sc=d*pf; if(sc<bs){bs=sc;bd=d;best=i;}
    }
  }
  return best>=0 ? {node:best, dist:bd, lat:g.nlat[best]/1e5, lon:g.nlon[best]/1e5} : null;
};

// default cost multipliers per category index (see data.cats order)
Router.defaultFactors = function(fp, rd){
  fp = fp||3; rd = rd||5;
  return { bridleway:1, boat:1, restricted:1, permissive:1.1, other:1.2, footpath:fp, path:fp*1.3,
           cycleway:1, track:2, road_minor:rd, road_major:rd*1.6, trunk:rd*4, ferry:3 };
};

// binary min-heap over (key, value) pairs
function Heap(){ this.k=[]; this.v=[]; }
Heap.prototype.push=function(k,v){ const K=this.k,V=this.v; let i=K.length; K.push(k); V.push(v);
  while(i>0){ const p=(i-1)>>1; if(K[p]<=K[i]) break; [K[p],K[i]]=[K[i],K[p]]; [V[p],V[i]]=[V[i],V[p]]; i=p; } };
Heap.prototype.pop=function(){ const K=this.k,V=this.v; const k=K[0], v=V[0]; const lk=K.pop(), lv=V.pop();
  if(K.length){ K[0]=lk; V[0]=lv; let i=0; for(;;){ const l=2*i+1, r=l+1; let s=i;
    if(l<K.length&&K[l]<K[s]) s=l; if(r<K.length&&K[r]<K[s]) s=r; if(s===i) break;
    [K[s],K[i]]=[K[i],K[s]]; [V[s],V[i]]=[V[i],V[s]]; i=s; } }
  return [k,v]; };
Heap.prototype.size=function(){ return this.k.length; };

/* A* from node s to node t.
   opts.factors: {catName: multiplier}; opts.used: Set of way indices already ridden; opts.usedPenalty: multiplier */
Router.route = function(g, s, t, opts){
  opts = opts||{};
  const fac = opts.factors || Router.defaultFactors();
  const catF = new Float64Array(g.cats.length);
  let minF = Infinity;
  g.cats.forEach((c,i)=>{ catF[i] = fac[c]!=null ? fac[c] : 1; if(catF[i]<minF) minF=catF[i]; });
  const used = opts.used || null, up = opts.usedPenalty || 4;
  const n=g.n, dist=new Float64Array(n).fill(Infinity), prev=new Int32Array(n).fill(-1), done=new Uint8Array(n);
  const tla=g.nlat[t]/1e5, tlo=g.nlon[t]/1e5;
  const h = i => hav(g.nlat[i]/1e5, g.nlon[i]/1e5, tla, tlo)*minF;
  const heap=new Heap(); dist[s]=0; heap.push(h(s), s);
  while(heap.size()){
    const [,u]=heap.pop(); if(done[u]) continue; done[u]=1;
    if(u===t) break;
    const du=dist[u];
    for(let k=g.off[u];k<g.off[u+1];k++){
      const e=g.adj[k], v=g.eTo[e], w=g.eWay[e];
      let c = g.eLen[e]*catF[g.wayCat[w]];
      if(used && used.has(w)) c*=up;
      const nd=du+c;
      if(nd<dist[v]){ dist[v]=nd; prev[v]=e; heap.push(nd+h(v), v); }
    }
  }
  if(dist[t]===Infinity) return null;
  const edges=[]; for(let v=t; v!==s; ){ const e=prev[v]; edges.push(e); v=g.eTo[e^1]; } // e^1 is reverse edge -> its "to" is our from
  edges.reverse();
  const coords=[[g.nlat[s]/1e5,g.nlon[s]/1e5]]; const byCat={}; let len=0; const waysUsed=new Set();
  for(const e of edges){ const v=g.eTo[e], w=g.eWay[e]; coords.push([g.nlat[v]/1e5,g.nlon[v]/1e5]);
    const c=g.cats[g.wayCat[w]]; byCat[c]=(byCat[c]||0)+g.eLen[e]; len+=g.eLen[e]; waysUsed.add(w); }
  return { coords, len, byCat, ways:waysUsed, cost:dist[t] };
};

/* Loop through waypoint node ids, returning to the first. Ways ridden in earlier legs are penalised so the
   return uses different tracks where possible. */
Router.loop = function(g, nodes, opts){
  opts=opts||{};
  const seq = nodes.length>1 ? nodes.concat([nodes[0]]) : nodes.slice();
  const used=new Set(); const legs=[];
  for(let i=0;i<seq.length-1;i++){
    const leg = Router.route(g, seq[i], seq[i+1], Object.assign({}, opts, {used}));
    if(!leg) return null;
    legs.push(leg); leg.ways.forEach(w=>used.add(w));
  }
  const coords=[], byCat={}; let len=0;
  legs.forEach((l,i)=>{ coords.push(...(i?l.coords.slice(1):l.coords)); len+=l.len; for(const c in l.byCat) byCat[c]=(byCat[c]||0)+l.byCat[c]; });
  return { coords, len, byCat, legs };
};

// resample a lat/lon path at ~step metres (for elevation lookups)
Router.resample = function(coords, step){
  const out=[coords[0]]; let acc=0;
  for(let i=1;i<coords.length;i++){
    const a=coords[i-1], b=coords[i]; const d=hav(a[0],a[1],b[0],b[1]); if(!d) continue;
    let pos=step-acc;
    while(pos<d){ const f=pos/d; out.push([a[0]+(b[0]-a[0])*f, a[1]+(b[1]-a[1])*f]); pos+=step; }
    acc=(acc+d)%step;
  }
  out.push(coords[coords.length-1]); return out;
};
/* Elevation for a list of [lat,lon] points. Tries Open-Meteo, then OpenTopoData (SRTM 30 m).
   Both are free public APIs with rate limits, so requests are spaced out. Returns null if both fail. */
Router.fetchElevation = async function(pts, onProgress){
  const sleep=ms=>new Promise(r=>setTimeout(r,ms));
  const sources=[
    {name:'Open-Meteo', chunk:100, gap:1500, url:c=>'https://api.open-meteo.com/v1/elevation?latitude='+c.map(p=>p[0].toFixed(5)).join(',')+'&longitude='+c.map(p=>p[1].toFixed(5)).join(','), parse:j=>j.elevation},
    {name:'OpenTopoData', chunk:100, gap:1100, nodeOnly:true, url:c=>'https://api.opentopodata.org/v1/srtm30m?locations='+c.map(p=>p[0].toFixed(5)+','+p[1].toFixed(5)).join('|'), parse:j=>j.results.map(r=>r.elevation)},
  ];
  for(const src of sources){
    if(src.nodeOnly && typeof window!=='undefined') continue; // no CORS headers, so only usable from the build script
    const out=[]; let ok=true;
    for(let i=0;i<pts.length && ok;i+=src.chunk){
      const c=pts.slice(i,i+src.chunk); let got=null;
      for(let attempt=0; attempt<3 && !got; attempt++){
        try{ const r=await fetch(src.url(c)); if(r.ok){ const j=await r.json(); got=src.parse(j); break; }
          if(r.status!==429){ break; } await sleep(4000*(attempt+1)); }
        catch(e){ break; }
      }
      if(!got || got.some(v=>v==null)){ ok=false; break; }
      out.push(...got); if(onProgress) onProgress(Math.min(1,(i+src.chunk)/pts.length), src.name);
      if(i+src.chunk<pts.length) await sleep(src.gap);
    }
    if(ok) return out;
  }
  return null;
};
Router.ascent = function(eles){ // total climb with 5 m hysteresis to ignore DEM noise
  let asc=0, base=eles[0];
  for(let i=1;i<eles.length;i++){ const e=eles[i]; if(e>base+5){asc+=e-base; base=e;} else if(e<base-5){ base=e; } }
  return Math.round(asc);
};
Router.gpx = function(name, coords, eles){
  const esc=s=>String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
  let s=`<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1" creator="Lake District Bridleway Map" xmlns="http://www.topografix.com/GPX/1/1">\n<trk><name>${esc(name)}</name><trkseg>\n`;
  coords.forEach((c,i)=>{ s+=`<trkpt lat="${c[0].toFixed(6)}" lon="${c[1].toFixed(6)}">`+(eles&&eles[i]!=null?`<ele>${Math.round(eles[i])}</ele>`:'')+`</trkpt>\n`; });
  return s+`</trkseg></trk>\n</gpx>\n`;
};

if(typeof module!=='undefined' && module.exports) module.exports=Router; else root.Router=Router;
})(typeof window!=='undefined'?window:globalThis);
