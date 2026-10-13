# Lake District Bridleway Map

`index.html` is a self-contained interactive map and loop planner for mountain biking in the central
Lake District (Ennerdale to Haweswater, Bassenthwaite to Windermere). Open it directly in a browser.
It needs an internet connection only for the base map tiles and the optional elevation lookup. The
iOS app below covers the North York Moors, the Yorkshire Dales, the Cairngorms and Loch Lomond & The
Trossachs as well; the web page is Lake District only.

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

## iOS app
`ios/LakeDistrictBridleways.xcodeproj` is a native SwiftUI port of the page for iPhone and iPad
(iOS 17 or later). Open it in Xcode 16 or newer, pick a simulator or set your signing team, and run.
The app bundles a network file per region (`Resources/network-lakes.json`, `network-nym.json`,
`network-dales.json`, `network-cairngorms.json`, `network-lomond.json`) plus the Lake District's `route-lakes.json`, builds the routing graph on launch and runs the A* loop
planner on-device, so planning works offline; only the base-map tiles and the elevation lookup need
a connection.

The first screen picks the region: the **Lake District**, the **North York Moors** (Osmotherley to
the coast, Guisborough to Helmsley), the **Yorkshire Dales** (the Howgills to Nidderdale, Kirkby
Stephen to Malham), the **Cairngorms** (Newtonmore to Glen Tanar, Grantown to Blair Atholl) or
**Loch Lomond & The Trossachs** (Loch Eck to Loch Earn, Balloch to Tyndrum). Each region has its own
map framing, labels and ten highest tops (Munros in the Scottish parks), and its own
Core Data store, so only that region's saved routes are loaded. The card shows how many routes are
saved in each and which was open last. The region pill at the top left of the map goes back to the
picker; the draft being planned is kept per region.

Each region card shows a photo of the National Park, credited on the card. They come from Wikimedia
Commons, resized to 1280 px wide in `Assets.xcassets/region-<id>.imageset`:

- Lake District: [Derwent Water, Lake District, Cumbria - June 2009](https://commons.wikimedia.org/wiki/File:Derwent_Water,_Lake_District,_Cumbria_-_June_2009.jpg) by Diliff, CC BY-SA 3.0
- North York Moors: [The sea of purple in North York Moors 03](https://commons.wikimedia.org/wiki/File:The_sea_of_purple_in_North_York_Moors_03.jpg) by Thelight00702, CC BY-SA 4.0
- Yorkshire Dales: [2015 Swaledale from Kisdon Hill](https://commons.wikimedia.org/wiki/File:2015_Swaledale_from_Kisdon_Hill.jpg) by Kreuzschnabel, CC BY-SA 3.0
- Cairngorms: [Cairngorms National Park, Scotland](https://commons.wikimedia.org/wiki/File:Cairngorms_National_Park,_Scotland.jpg) by Thomas Andy Branson, CC BY-SA 4.0
- Loch Lomond & The Trossachs: [Loch Lomond from Conic Hill](https://commons.wikimedia.org/wiki/File:Loch_Lomond_from_Conic_Hill.jpg) by Craigmacl, CC BY-SA 4.0

Scotland has no public bridleways: the Land Reform (Scotland) Act gives cyclists access to most
tracks and paths, so the Scottish networks are tracks, paths and roads, the bridleway layers are
empty there, and the map opens on the **Track** layer instead. Routing there trades tracks against
paths and roads using the same penalties.

The map fills the screen. Floating buttons at the top right open the map layers, the routing
penalties and fit the view to the route. The planner is a card at the bottom (a sidebar on iPad)
that shows the route's name, distance, climb and waypoint count even when collapsed. Press
**Add waypoints** and tap the map; drag a marker to move it, tap it and press the bin to remove it.
Elevation is fetched automatically from Open-Meteo once routing settles, and the card shows the
profile and a surface breakdown. **Save route** stores the loop under a suggested name (the nearest
labelled place). **Share** exports GPX.

A saved route opens for viewing, with just its line on the map. Press the pencil in the card to edit
it: the waypoint markers, planning buttons, **Save changes** button and the rename / save-as-new menu
appear, and an unsaved-changes dot shows next to the name. Press the tick to finish; if there are
unsaved changes you are asked whether to save or discard them.

**Routes** lists the saved routes with distance, climb, waypoint count and date: tap one to open it,
swipe to rename or delete, long-press to edit, duplicate or share. The built-in reference loop
("Loop from the image") is listed last, marked with a padlock: it opens and shares like any other
route but cannot be edited.

Core Data (`Persistence/LakeDistrictBridleways.xcdatamodeld`) stores the loop being planned so it
survives relaunches and the saved routes (waypoints, route, elevation and the penalties used). The
model is shared; each region opens its own store file (`LakeDistrictBridleways.sqlite`,
`NorthYorkMoors.sqlite`, `YorkshireDales.sqlite`, `Cairngorms.sqlite`, `LochLomond.sqlite`). Display and routing preferences live in
UserDefaults; the layers shown are one choice for the English regions and a separate one for the
Scottish regions. The routing engine in `Routing/` is a line-for-line port of `tools/router.js`.

## Data and rebuilding
OpenStreetMap via the Overpass API, fetched 13 Oct 2026. Regions are described in
`tools/regions/<id>.json` (bounding box, which peaks to show, and `scottishAccess` for Scottish
regions, where tracks and paths tagged private are kept unless bikes are excluded too). Run
`tools/build.sh` to refetch and rebuild the Lake District, `tools/build.sh nym` for the North York
Moors, `tools/build.sh dales` for the Yorkshire Dales, `tools/build.sh cairngorms` for the
Cairngorms, `tools/build.sh lomond` for Loch Lomond & The Trossachs, or add `--offline` to rebuild from the cached data in `tools/data/<id>`.
Each refreshes the copy bundled in the iOS app; the Lake District build also rebuilds the reference
loop and `index.html`. Needs `curl`, `python3` and `node`. Always check the definitive map before
relying on a right of way.