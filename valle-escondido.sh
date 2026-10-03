#!/bin/sh
# Topo map PNG of Valle Escondido, Boquete, from a 30 m DEM plus OSM roads and streams.
# Paths are relative to this directory; intermediates go in work/.
set -eu
cd "$(dirname "$0")"

# Usage: valle-escondido.sh [DEM [NODATA [OUT [SOURCE-CREDIT [OSM-LINES.geojson]]]]]
# With no arguments it renders FABDEM with the OSM overlay. Pass "" as the
# fifth argument for no overlay. For the JAXA DEM:
#   ./valle-escondido.sh ../dem/Pma_DEM_30m.tif 32767 aw3d.png "Source: JAXA ALOS AW3D30" ""
DEM=${1:-input/N08W083_FABDEM_V1-2.tif}
NODATA=${2:--9999}
OUT=${3:-valle-escondido-topo.png}
CREDIT=${4:-"Elevation: FABDEM V1-2, Univ. of Bristol (CC BY-NC-SA 4.0) · Roads and streams © OpenStreetMap contributors (ODbL)"}
OVERLAY=${5-input/lines.geojson}
mkdir -p work
LON=-82.44169
LAT=8.78157
FONT=/System/Library/Fonts/Supplemental/Arial.ttf
BOLD="/System/Library/Fonts/Supplemental/Arial Bold.ttf"

# 1. crop (WGS 84 bbox) and reproject to UTM 17N at 5 m
gdalwarp -q -overwrite -te_srs EPSG:4326 -te -82.47 8.755 -82.41 8.81 \
  -t_srs EPSG:32617 -tr 5 5 -r cubicspline \
  -srcnodata "$NODATA" -dstnodata -32768 -ot Float32 "$DEM" work/crop.tif

# 2. hillshade
gdaldem hillshade -q -multidirectional -z 1.5 work/crop.tif work/hs.tif

# 3. hypsometric tint over the crop's range
cat > work/ramp.txt <<'EOF'
1000 46 110 60
1150 112 160 84
1300 196 196 120
1450 214 170 110
1600 170 120 80
1800 240 236 230
nv 0 0 0 0
EOF
gdaldem color-relief -q work/crop.tif work/ramp.txt work/tint.tif

# 4. blend
magick work/tint.tif \( work/hs.tif -level 25%,100% \) -compose multiply -composite work/base.png

# 5. contours: 10 m minor, 50 m index
rm -f work/contours.gpkg
gdal_contour -q -a elev -i 10 work/crop.tif work/contours.gpkg
W=$(gdalinfo work/crop.tif | awk '/Size is/{gsub(",","");print $3}')
H=$(gdalinfo work/crop.tif | awk '/Size is/{print $4}')
TE=$(gdalinfo -json work/crop.tif | python3 -c 'import json,sys;g=json.load(sys.stdin)["geoTransform"];print(g[0],g[3]+g[5]*'"$H"',g[0]+g[1]*'"$W"',g[3])')
rm -f work/minor.tif work/index.tif
gdal_rasterize -q -burn 255 -init 0 -ot Byte -te $TE -ts "$W" "$H" work/contours.gpkg work/minor.tif
gdal_rasterize -q -burn 255 -init 0 -ot Byte -te $TE -ts "$W" "$H" \
  -where "CAST(elev AS INTEGER) % 50 = 0" work/contours.gpkg work/index.tif

magick work/base.png \
  \( -size ${W}x${H} xc:'rgb(90,60,40)' \( work/minor.tif -evaluate multiply 0.55 \) -alpha off -compose copy-opacity -composite \) \
  -compose over -composite \
  \( -size ${W}x${H} xc:'rgb(70,40,25)' \( work/index.tif -morphology dilate disk:1 \) -alpha off -compose copy-opacity -composite \) \
  -compose over -composite work/contoured.png

# 5b. optional roads and streams (OSM lines in EPSG:32617)
if [ -n "$OVERLAY" ]; then
  python3 osm2mvg.py "$OVERLAY" work/crop.tif > work/overlay.mvg
  magick work/contoured.png -draw @work/overlay.mvg work/contoured.png
fi

# 6. annotate
read PX PY <<EOF
$(gdallocationinfo -wgs84 work/crop.tif $LON $LAT | sed -n 's/.*(\([0-9]*\)P,\([0-9]*\)L).*/\1 \2/p')
EOF
ELEV=$(gdallocationinfo -valonly -wgs84 work/crop.tif $LON $LAT | awk '{printf "%d", $1+0.5}')
SB=$((1000 / 5))   # 1 km in pixels
FOOT=90

magick work/contoured.png \
  -fill red -stroke white -strokewidth 2 -draw "circle $PX,$PY $((PX+8)),$PY" \
  -font "$BOLD" -pointsize 26 -stroke white -strokewidth 5 -fill none \
  -annotate +$((PX+14))+$((PY-10)) "Valle Escondido" \
  -stroke none -fill black -annotate +$((PX+14))+$((PY-10)) "Valle Escondido" \
  -font "$FONT" -pointsize 18 -stroke white -strokewidth 4 -fill none \
  -annotate +$((PX+14))+$((PY+14)) "${ELEV} m" \
  -stroke none -fill black -annotate +$((PX+14))+$((PY+14)) "${ELEV} m" \
  -fill 'rgba(255,255,255,0.85)' -stroke none -draw "roundrectangle $((W-70)),15 $((W-15)),95 8,8" \
  -fill black -draw "polygon $((W-42)),25 $((W-56)),70 $((W-42)),60 $((W-28)),70" \
  -font "$BOLD" -pointsize 20 -annotate +$((W-49))+90 "N" \
  -gravity north -background white -splice 0x0 \
  -gravity south -background white -splice 0x$FOOT \
  -gravity northwest \
  -font "$BOLD" -pointsize 24 -fill black -annotate +20+$((H+12)) "Valle Escondido, Boquete, Chiriquí, Panama" \
  -font "$FONT" -pointsize 15 -fill '#333' \
  -annotate +20+$((H+46)) "Contours 10 m (index 50 m) · marker at ${ELEV} m · UTM 17N, north up" \
  -annotate +20+$((H+66)) "$CREDIT" \
  -fill black -draw "rectangle $((W-20-SB)),$((H+30)) $((W-20-SB/2)),$((H+40))" \
  -fill white -stroke black -strokewidth 1 -draw "rectangle $((W-20-SB/2)),$((H+30)) $((W-20)),$((H+40))" \
  -stroke none -fill black -pointsize 15 \
  -annotate +$((W-24-SB))+$((H+46)) "0" -annotate +$((W-30-SB/2))+$((H+46)) "500" \
  -annotate +$((W-40))+$((H+46)) "1 km" \
  "$OUT"

echo "wrote $(pwd)/$OUT (${W}x$((H+FOOT)))"
