// Reconstructs the loop from the reference image by routing through traced waypoints.
// Usage: node make-route.js data.json out.gpx out.json
const fs=require('fs'); const Router=require('./router.js');
const [,, dataFile, wpFile, gpxOut, jsonOut] = process.argv;
const data=JSON.parse(fs.readFileSync(dataFile,'utf8'));
console.time('graph'); const g=Router.build(data); console.timeEnd('graph'); console.log(g.n,'nodes',g.m,'edges');

// Waypoints traced from the image (clockwise from Kentmere)
const WP = JSON.parse(fs.readFileSync(wpFile,'utf8'));
const nodes=[];
for(const [name,la,lo] of WP){ const s=Router.nearest(g,la,lo,600); if(!s){console.error('no node near',name); process.exit(1);} nodes.push(s.node); console.log(name.padEnd(16), s.dist.toFixed(0)+' m snap'); }
console.time('route');
const res=Router.loop(g,nodes,{factors:Router.defaultFactors(3,5), usedPenalty:4});
console.timeEnd('route');
if(!res){console.error('routing failed'); process.exit(1);}
console.log('length', (res.len/1000).toFixed(1),'km');
for(const c in res.byCat) console.log('  ',c.padEnd(11),(res.byCat[c]/1000).toFixed(1),'km');

function writeOut(samp, eles, asc){
  fs.writeFileSync(gpxOut, Router.gpx('Lake District loop (reconstructed from image)', samp, eles));
  fs.writeFileSync(jsonOut, JSON.stringify({name:'Loop from the image', len:Math.round(res.len), asc, byCat:Object.fromEntries(Object.entries(res.byCat).map(([k,v])=>[k,Math.round(v)])),
    coords:res.coords.map(c=>[+c[0].toFixed(5),+c[1].toFixed(5)]), profile:eles?eles.map(e=>Math.round(e)):null, profileStep:60, waypoints:WP}));
}
writeOut(res.coords, null, null); console.log('written without elevation');
if(process.argv.includes('--no-elevation')) process.exit(0);
(async()=>{
  const samp=Router.resample(res.coords,60);
  const eles=await Router.fetchElevation(samp, p=>process.stdout.write('.'));
  if(!eles){ console.error('elevation: all sources failed'); process.exit(1); }
  const asc=Router.ascent(eles);
  console.log('ascent',asc,'m from',samp.length,'samples');
  writeOut(samp, eles, asc); console.log('written with elevation', gpxOut, jsonOut);
})();
