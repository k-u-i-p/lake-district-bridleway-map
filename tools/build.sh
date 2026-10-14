#!/bin/sh
# Rebuild a region's network from fresh OpenStreetMap data.
#   tools/build.sh [--offline] [region]
#   region     lakes (default), nym, dales, pennines, cairngorms or lomond; see tools/regions/*.json
#   --offline  skip the Overpass fetch, reuse tools/data/<region>/*.json
# The Lake District also rebuilds its reference loop and the web page (index.html).
# Every region refreshes the copy bundled in the iOS app.
set -e
cd "$(dirname "$0")/.."
offline=0
region=lakes
for a in "$@"; do
  case "$a" in
    --offline) offline=1 ;;
    *) region="$a" ;;
  esac
done
cfg="tools/regions/$region.json"
[ -f "$cfg" ] || { echo "unknown region '$region' (no $cfg)" >&2; exit 1; }
data="tools/data/$region"
mkdir -p "$data"
bbox=$(python3 -c "import json,sys; print(','.join(str(v) for v in json.load(open(sys.argv[1]))['bbox']))" "$cfg")
# Overpass answers with an HTML page when it is too busy, or sometimes not at all; try each query a few
# times, on two servers, giving up on a request after ten minutes.
fetch() {
  for server in https://overpass-api.de/api/interpreter https://overpass.kumi.systems/api/interpreter https://overpass-api.de/api/interpreter; do
    sed "s/{{bbox}}/$bbox/g" "tools/q-$1.ql" | curl -s -m 600 -A "LakeDistrictBridlewayMap/1.0" --data-urlencode "data@-" "$server" -o "$2"
    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$2" 2>/dev/null; then return 0; fi
    echo "  $server did not return JSON for $1, retrying…" >&2
    sleep 30
  done
  echo "could not fetch $1" >&2; return 1
}
if [ "$offline" = 0 ]; then
  for q in bridleways paths roads peaks; do
    echo "fetching $region $q…"
    fetch "$q" "$data/$q.json"
  done
fi
python3 tools/convert.py "$cfg" "$data/network.json" "$data/bridleways.json" "$data/paths.json" "$data/roads.json" "$data/peaks.json"
# keep the iOS app's bundled copy in step
cp "$data/network.json" "ios/LakeDistrictBridleways/Resources/network-$region.json"
# and its summit cards, from the photos already fetched (run tools/peaks.py <region> for new peaks)
python3 tools/peaks.py --offline "$region"
if [ "$region" = lakes ]; then
  node tools/make-route.js "$data/network.json" tools/wp.json routes/lakes-loop.gpx "$data/route.json"
  cp "$data/route.json" ios/LakeDistrictBridleways/Resources/route-lakes.json
  python3 tools/assemble.py tools/template.html tools/router.js "$data/network.json" "$data/route.json" index.html ios/LakeDistrictBridleways/Resources/peaks-lakes.json
fi
