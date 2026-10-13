[out:json][timeout:300];
(
  way["highway"~"^(path|footway|cycleway|steps)$"]({{bbox}});
  way["designation"~"^(public_footpath|permissive_footpath)$"]({{bbox}});
);
out tags geom;
