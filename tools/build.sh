#!/bin/sh
# Rebuild index.html from fresh OpenStreetMap data.
#   tools/build.sh            fetch data, rebuild route (with elevation), assemble page
#   tools/build.sh --offline  skip the Overpass fetch, reuse tools/data/*.json
set -e
cd "$(dirname "$0")/.."
mkdir -p tools/data
if [ "$1" != "--offline" ]; then
  for q in bridleways paths roads peaks; do
    echo "fetching $q…"
    curl -s -A "LakeDistrictBridlewayMap/1.0" --data-urlencode "data@tools/q-$q.ql" https://overpass-api.de/api/interpreter -o tools/data/$q.json
  done
fi
python3 tools/convert.py tools/data/network.json tools/data/bridleways.json tools/data/paths.json tools/data/roads.json tools/data/peaks.json
node tools/make-route.js tools/data/network.json tools/wp.json routes/lakes-loop.gpx tools/data/route.json
python3 tools/assemble.py tools/template.html tools/router.js tools/data/network.json tools/data/route.json index.html
