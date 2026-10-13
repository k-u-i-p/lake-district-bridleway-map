import sys, json, os
tpl, router, data, route, out = sys.argv[1:6]
s=open(tpl).read()
s=s.replace('/*__ROUTER__*/', open(router).read())
s=s.replace('/*__DATA__*/', open(data).read())
s=s.replace('/*__ROUTE__*/', open(route).read() if os.path.exists(route) else 'null')
open(out,'w').write(s); print(len(s)//1024,'KB ->',out)
