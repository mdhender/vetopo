#!/bin/sh
# Download the inputs for valle-escondido.sh into input/.
#   - FABDEM V1-2 tile N08W083, read straight out of the remote 10° zip (~52 MB, not the 166 MB zip)
#   - OSM roads and waterways for the map bbox, via the public Overpass API
set -eu
cd "$(dirname "$0")"
mkdir -p input

ZIP=https://data.bris.ac.uk/datasets/s5hqmjcdj8yo2ibzi9b4ew3sn/N00W090-N10W080_FABDEM_V1-2.zip
TILE=N08W083_FABDEM_V1-2.tif
if [ ! -f "input/$TILE" ]; then
  gdal_translate -q "/vsizip//vsicurl/$ZIP/$TILE" "input/$TILE"
fi

# bbox is south,west,north,east, matching the gdalwarp -te in valle-escondido.sh
/usr/bin/curl -sS --fail --max-time 180 -A "tpty-topod/0.1" https://overpass-api.de/api/interpreter \
  --data-urlencode 'data=[out:xml][timeout:120][bbox:8.755,-82.47,8.81,-82.41];(way[highway];way[waterway~"^(river|stream|canal|ditch|drain)$"];);(._;>;);out body;' \
  -o input/osm.xml

rm -f input/lines.geojson
ogr2ogr -q -f GeoJSON -t_srs EPSG:32617 -lco COORDINATE_PRECISION=1 \
  input/lines.geojson input/osm.xml lines -where "highway IS NOT NULL OR waterway IS NOT NULL"

echo "inputs ready in $(pwd)/input"
