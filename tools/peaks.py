"""Build the summit cards for the iOS app from tools/peaks.json.
Usage: peaks.py [--offline] [region ...]   (default: every region in tools/peaks.json)

tools/peaks.json holds, per region and peak (named as in the network's ten peaks), the Wikimedia
Commons photo to show and the hand-written notes: "about" (a line on the summit) and "routes" (the
usual ways up). For each photo this fetches the author and licence from Commons into
tools/data/<region>/photos.json and saves a 1024 px copy as the asset peak-<region>-<slug>; --offline
skips both and reuses what is there. It then writes the bundled Resources/peaks-<region>.json.
"""
import json, os, re, subprocess, sys, time, unicodedata, urllib.parse, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
APP = os.path.join(ROOT, 'ios', 'LakeDistrictBridleways')
UA = {'User-Agent': 'BensMapper/1.0 (peak photos for a bridleway map app)'}
WIDTH = 1024
FETCH = 1280  # Commons only serves thumbnails in its standard widths (https://w.wiki/GHai)

def get(url, tries=8):
    for i in range(tries):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
        except Exception as e:
            if i == tries - 1: raise
            print(f'  retrying ({e})', file=sys.stderr)
            time.sleep(30 * (i + 1))

def slug(name):
    s = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')

def plain(html):
    """Commons artist fields are HTML, often a link to a user page."""
    t = re.sub(r'<[^>]+>', '', html or '')
    t = re.sub(r'\s+', ' ', t).strip()
    t = re.sub(r'^(Photo|Photograph)\s*by\s*', '', t, flags=re.I)
    t = re.sub(r'^The original uploader was (.*?)\.?$', r'\1', t)  # Wikipedia transfer boilerplate
    t = re.sub(r'\s*\(--.*\(UTC\)\)', '', t)                      # a wiki signature after the name
    return t or 'Unknown'

def fetch_photos(region, peaks):
    """Author, licence and a resized copy of each peak's photo."""
    cache_path = os.path.join(ROOT, 'tools', 'data', region, 'photos.json')
    cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    titles = ['File:' + p['photo'] for p in peaks.values()]
    info = {}
    for i in range(0, len(titles), 40):
        q = urllib.parse.urlencode({'action': 'query', 'titles': '|'.join(titles[i:i+40]), 'prop': 'imageinfo',
                                    'iiprop': 'url|extmetadata|size', 'iiurlwidth': FETCH, 'format': 'json'})
        d = json.loads(get('https://commons.wikimedia.org/w/api.php?' + q))
        norm = {n['to']: n['from'] for n in d['query'].get('normalized', [])}
        for page in d['query']['pages'].values():
            if 'imageinfo' not in page:
                sys.exit(f'{region}: no Commons file {page["title"]}')
            info[norm.get(page['title'], page['title'])] = page['imageinfo'][0]
    for name, p in peaks.items():
        ii = info['File:' + p['photo']]
        meta = ii['extmetadata']
        asset = f'peak-{region}-{slug(name)}'
        folder = os.path.join(APP, 'Assets.xcassets', asset + '.imageset')
        os.makedirs(folder, exist_ok=True)
        jpg = os.path.join(folder, asset + '.jpg')
        if cache.get(name, {}).get('file') != p['photo'] or not os.path.exists(jpg):
            print(f'  {name}: {p["photo"]}')
            src = ii.get('thumburl') if ii['width'] > FETCH else ii['url']
            src = src.split('?')[0]  # Commons appends tracking parameters that upload.wikimedia.org then rate-limits
            # upload.wikimedia.org throttles bulk downloads, so photos Commons mirrors from Geograph fall back to
            # Geograph's own copy (the same 640 px image), found through its oEmbed API.
            g = re.search(r'geograph[^0-9]*(\d+)\)?\.jpe?g$', p['photo'])
            try:
                image = get(src, tries=3 if g else 8)
            except Exception:
                if not g: raise
                o = json.loads(get(f'https://api.geograph.org.uk/api/oembed?url=https://www.geograph.org.uk/photo/{g.group(1)}&format=json'))
                image = get(o['url'])
            open(jpg, 'wb').write(image)
            width = int(re.search(r'pixelWidth: (\d+)', subprocess.run(['sips', '-g', 'pixelWidth', jpg], check=True,
                                                                       capture_output=True, text=True).stdout).group(1))
            subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '75'] +
                           (['--resampleWidth', str(WIDTH)] if width > WIDTH else []) + [jpg, '--out', jpg],
                           check=True, capture_output=True)
            time.sleep(3)
        json.dump({'images': [{'filename': asset + '.jpg', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}},
                  open(os.path.join(folder, 'Contents.json'), 'w'), indent=2)
        cache[name] = {'file': p['photo'], 'asset': asset, 'author': p.get('author') or plain(meta.get('Artist', {}).get('value')),
                       'license': meta.get('LicenseShortName', {}).get('value', ''),
                       'page': ii['descriptionurl']}
        json.dump(cache, open(cache_path, 'w'), indent=1, ensure_ascii=False)
    for name in list(cache):
        if name not in peaks: del cache[name]
    json.dump(cache, open(cache_path, 'w'), indent=1, ensure_ascii=False)
    return cache

def main():
    args = sys.argv[1:]
    offline = '--offline' in args
    data = json.load(open(os.path.join(ROOT, 'tools', 'peaks.json')))
    regions = [a for a in args if a != '--offline'] or list(data)
    for region in regions:
        peaks = data[region]
        shown = json.load(open(os.path.join(ROOT, 'tools', 'data', region, 'network.json')))['peaks']
        osm = json.load(open(os.path.join(ROOT, 'tools', 'data', region, 'peaks.json')))['elements']
        missing = [s['n'] for s in shown if s['n'] not in peaks]
        if missing: sys.exit(f'{region}: tools/peaks.json has nothing for {missing}')
        print(f'{region}…')
        photos = json.load(open(os.path.join(ROOT, 'tools', 'data', region, 'photos.json'))) if offline else fetch_photos(region, peaks)
        out = {}
        for s in shown:
            name = s['n']
            if name not in photos: sys.exit(f'{region}: no photo fetched for {name}; run tools/peaks.py {region}')
            p, ph = peaks[name], photos[name]
            out[name] = {'photo': ph['asset'], 'credit': f'{ph["author"]}, {ph["license"]}', 'source': ph['page'],
                         'about': p.get('about', ''), 'routes': p.get('routes', [])}
            # The Wikipedia article: the OSM node's wikipedia tag unless peaks.json overrides it (null for none).
            node = min(osm, key=lambda e: (e['lat'] - s['la']) ** 2 + (e['lon'] - s['lo']) ** 2)
            wiki = p['wiki'] if 'wiki' in p else node['tags'].get('wikipedia')
            if wiki:
                lang, title = wiki.split(':', 1)
                out[name]['wiki'] = f'https://{lang}.wikipedia.org/wiki/' + urllib.parse.quote(title.replace(' ', '_'), safe="_(),'")
        json.dump(out, open(os.path.join(APP, 'Resources', f'peaks-{region}.json'), 'w'), indent=1, ensure_ascii=False)

main()
