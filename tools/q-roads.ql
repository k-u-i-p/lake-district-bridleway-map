[out:json][timeout:300];
(
  way["highway"~"^(trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|service|track|living_street|pedestrian|road)$"](54.22,-3.52,54.74,-2.68);
  way["route"="ferry"](54.22,-3.52,54.74,-2.68);
);
out tags geom;
