[out:json][timeout:180];
(
  way["highway"="bridleway"]({{bbox}});
  way["designation"="public_bridleway"]({{bbox}});
  way["designation"="byway_open_to_all_traffic"]({{bbox}});
  way["designation"="restricted_byway"]({{bbox}});
);
out tags geom;
