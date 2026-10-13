[out:json][timeout:300];
(
  way["highway"~"^(trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|service|track|living_street|pedestrian|road)$"]({{bbox}});
  way["route"="ferry"]({{bbox}});
);
out tags geom;
