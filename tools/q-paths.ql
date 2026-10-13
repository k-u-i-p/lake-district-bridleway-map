[out:json][timeout:300];
(
  way["highway"~"^(path|footway|cycleway|steps)$"](54.22,-3.52,54.74,-2.68);
  way["designation"~"^(public_footpath|permissive_footpath)$"](54.22,-3.52,54.74,-2.68);
);
out tags geom;
