// Minimal static file server for previewing index.html
const http=require('http'),fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..');
const types={'.html':'text/html','.geojson':'application/geo+json','.json':'application/json','.js':'text/javascript','.css':'text/css'};
http.createServer((req,res)=>{
  let p=decodeURIComponent(req.url.split('?')[0]); if(p==='/') p='/index.html';
  const f=path.join(root,p);
  if(!f.startsWith(root)) {res.writeHead(403);return res.end();}
  fs.readFile(f,(e,d)=>{ if(e){res.writeHead(404);return res.end('not found');}
    res.writeHead(200,{'Content-Type':types[path.extname(f)]||'application/octet-stream'}); res.end(d); });
}).listen(8765,()=>console.log('serving '+root+' on 8765'));
