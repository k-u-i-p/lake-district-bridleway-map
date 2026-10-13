# Lake District Bridleway Map

`index.html` is a self-contained interactive map and loop planner for mountain biking in the central
Lake District (Ennerdale to Haweswater, Bassenthwaite to Windermere). Open it directly in a browser.
It needs an internet connection only for the base map tiles and the optional elevation lookup.

## Planning a loop
Press **Start planning** and click the map to drop waypoints. After two or more waypoints the planner
draws a loop that visits them in order and returns to the start. It routes on an embedded network of
roughly 52,000 OpenStreetMap ways, preferring public bridleways and byways, falling back to footpaths
and finally roads, and penalising tracks already ridden so the return leg differs from the way out.
Drag a waypoint to move it, right-click to remove it. **Get elevation** fetches a profile and total
climb from the Open-Meteo digital elevation model (online). **Download GPX** saves the loop.

The settings icon adjusts the footpath, road and re-riding penalties. The display icon switches base
maps and shows other rights of way, footpaths, the ten highest fells and labels.

Footpaths are included as a last resort because the request asked for it. Cycling on a public
footpath is not a right of way in England, so treat footpath sections as something to check locally.

## The reference loop
`routes/lakes-loop.gpx` is an approximation of the red loop in the reference image. It was rebuilt by
routing through about 35 waypoints read off the image (Kentmere, Nan Bield, Haweswater, Boredale
Hause, Sticks Pass, Keswick, Skiddaw House, Honister, Black Sail, Wasdale, Eskdale, Walna Scar,
Coniston, the Windermere ferry, Garburn), so the line follows real tracks but is not the original
file. The waypoints are in `tools/wp.json`.

## Data and rebuilding
OpenStreetMap via the Overpass API, fetched 13 Oct 2026. Run `tools/build.sh` to refetch and rebuild,
or `tools/build.sh --offline` to rebuild from the cached data in `tools/data`. Needs `curl`, `python3`
and `node`. Always check the definitive map before relying on a right of way.
