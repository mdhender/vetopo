# Session notes: Valle Escondido topo map (2026-10-02)

A record of how `topod/` came about, what we found, and why the map looks the way it does.
For how to run it, see [README.md](README.md).

## The ask

Make a topographic map of Valle Escondido, a community at the edge of Boquete, Chiriquí, Panama, from the DEM in `../dem/`.
It was a proof of concept, so a viewable PNG was enough.

## How it went

1. **Planned the approach.**
   We used the GDAL command-line tools and ImageMagick because both were already installed.
   Python has no numpy, matplotlib or rasterio, so the scripts don't use them.
   The map reads the GeoTIFF directly, so the hex pipeline's 90° rotation doesn't apply and north stays up.
2. **Found the location.**
   Mapcarta puts Valle Escondido at 8.78157° N, 82.44169° W, elevation 1,132 m.
   The JAXA DEM reads 1,134 m there, so the georeference checks out.
3. **First map, from the JAXA ALOS AW3D30 DEM** (`../dem/Pma_DEM_30m.tif`).
   - Cropped a box of about 6.6 × 6 km (lon −82.47 to −82.41, lat 8.755 to 8.81).
   - Reprojected it to UTM zone 17N (EPSG:32617) at 5 m pixels, so shading and contours use real metres.
   - Shaded the terrain, coloured it by elevation (green → tan → brown, about 1,000–1,800 m), and drew 10 m contours with darker lines every 50 m.
   - Added a marker, title, north arrow, 1 km scale bar and credit line.
4. **Asked whether better DEM data exists for Panama.**
   - Free options are all 30 m: FABDEM (bare earth, non-commercial licence), Copernicus GLO-30 and NASADEM.
   - Finer data needs TanDEM-X 12 m (science proposal only) or a commercial 5 m or 2.5 m product.
   - "ALOS PALSAR 12.5 m" is resampled SRTM, so it adds no real detail.
   - We found no public LiDAR for Chiriquí. The Canal Authority and STRI data covers the Canal basin, not Boquete.
5. **Compared JAXA and FABDEM side by side** (`valle-escondido-compare.png`).
   GDAL read just the Boquete tile out of FABDEM's 166 MB remote zip, which took about 35 seconds.
   Across the box, the JAXA surface averages 8 m higher than FABDEM (standard deviation 5 m); that's the tree canopy.
   FABDEM is a little smoother over forest, but the landforms are the same. It's a modest gain, not new detail.
6. **Final map: FABDEM plus OpenStreetMap roads and streams.**
   - Fetched about 550 roads and waterways from the public Overpass API and converted them to UTM GeoJSON with `ogr2ogr`.
   - `osm2mvg.py` turns them into ImageMagick drawing commands. Roads are styled by type, rivers are labelled, and there's a legend.
   - OSM has only Valle Escondido's private roads, not a boundary polygon, so the marker is the published point.
7. **Saved and shared.**
   - Copied the map to `~/Downloads/valle-escondido-boquete-topo.png` for WhatsApp, under a new name so the existing `valle-escondido-topo.png` there wasn't overwritten.
   - Moved the scripts and inputs into `topod/` and made FABDEM with the OSM overlay the script's default.
   - Re-running from `topod/` produces an image identical pixel for pixel to the shared one.

## Things worth remembering

- **No 3 m data:** `../dem/Pma_DEM_3m.zip` contains the same 30 m file as `Pma_DEM_30m.tif` (identical byte for byte).
- **Detail limit:** every free source is 30 m. Valle Escondido is only about 35 source pixels across, so contours closer than 10 m would be noise.
- **Licences:**
  - FABDEM is CC BY-NC-SA 4.0, so it can't be used commercially.
  - OSM is ODbL, and its credit line must stay on shared copies.
- **GDAL can read one file out of a remote zip:** `/vsizip//vsicurl/<url>/<file>` fetches only the bytes it needs, which works when the server supports range requests.
- **ImageMagick gotchas we hit:**
  - A leftover `-gravity` setting moves later `-splice` and `-crop` operations.
  - Use `+repage` after `+append`.
- **Shell gotcha:** a `-where` clause passed through an unquoted variable gets split into separate words. Write it out in full.

## Better elevation data: what it costs (checked 2026-10-02)

The maps are for a local hiking group, which is not commercial use.
Our map box is about 40 km² (6.6 × 6 km).
Minimum order sizes matter more than the price per km².

| Product | Resolution | Price per km² | Minimum order | Cost for our box |
| --- | --- | --- | --- | --- |
| **WorldDEM Neo via UP42** | 5 m | from 750 credits (€7.50) | 1 km² | **about €300** (about €75 for 10 km² around town) |
| WorldDEM Neo via Apollo Mapping | 5 m | treetop $8.75 · ground (Level 1) $11.25 | 100 km² | $875 · $1,125 |
| AW3D 5 m (NTT Data) | 5 m | treetop $5 · ground $30 | treetop 400 km² · ground 100 km² | $2,000 · $3,000 |
| AW3D 2.5 m | 2.5 m | ground $32 | 100 km² | $3,200 |
| Satellite-photo models (Pléiades and similar) | 1–2 m | $35–80+ | 100 km² | $3,500+ |

On UP42, 100 credits = €1.
The Apollo Mapping prices come from its price list dated 2025-12-12.

- **The pick:** WorldDEM Neo on UP42. It's the only option with a small minimum.
  - Get the ground version (Level 1), not the treetop one. UP42's "from" price may only cover the treetop version.
    Apollo charges about 30% more for the ground version, so budget about €400 for our box.
  - 5 m is a real six-fold improvement over 30 m. Vertical accuracy is about 1.4–4 m, so 5 m contours would be meaningful.
  - Get a current quote from UP42 for the exact area before buying.
- **Licence:** commercial elevation data usually comes with a licence for a single organisation.
  Sharing finished images is normally allowed; handing the raw data to others is not.
  Confirm this in UP42's terms before buying.
- **FABDEM fits the hiking group:** it's free and non-commercial.
  Its CC BY-NC-SA 4.0 licence requires credit, and maps made from it must be shared under the same licence.

## Sharing plan

- **What gets shared with the group:** only the generated PNGs and the scripts (`valle-escondido.sh`, `osm2mvg.py`, `fetch-inputs.sh`).
  Never the purchased raw elevation data.
- **Members who want custom maps** need their own Claude subscription and, for the paid elevation data, their own UP42 account.
  The free path (FABDEM plus OSM, using `fetch-inputs.sh`) needs neither.
- **Credit lines stay on every map:** FABDEM (CC BY-NC-SA 4.0), or the purchased product's required credit, plus "© OpenStreetMap contributors (ODbL)".
- **Licence for the scripts:** MIT (`LICENSE`, © 2026 Michael Henderson). It covers only the code; the data and maps keep their own licences.

## GPS tracks: contribute through OSM

Trails matter more than finer elevation for hiking, and OSM has few paths around Boquete.
Members are encouraged to add their own GPS tracks to OSM rather than sending them to us.
Then `fetch-inputs.sh` picks the trails up for everyone, and the rest of the OSM community gets them too.

- Upload the track at openstreetmap.org (GPS Traces), then trace the path in the iD editor, tagged `highway=path` or `highway=track`.
  Useful extra tags: `sac_scale`, `trail_visibility`, `surface`, `name`.
- Contribute only your own tracks or observations, never anything copied from Google Maps, AllTrails or other copyrighted sources.
  Contributions become ODbL.
- Don't map trails on private land (Valle Escondido's roads are tagged `access=private`) without tagging the access correctly.
- New OSM edits show up on the next run of `fetch-inputs.sh`, usually within minutes.
- `osm2mvg.py` already draws `path`, `footway` and `track`. If the trail network grows, it could style them by `sac_scale`.

## Ideas if this goes further

- Outline Valle Escondido's boundary (it would have to be added to OSM, or drawn by hand).
- Buy WorldDEM Neo (ground version, Level 1) on UP42 for the area the group actually hikes. See the pricing section above.
- Label the 50 m contours and add place names (OSM `place=*` nodes).
- Style trails by difficulty (`sac_scale`) once members have added them to OSM.
- Generalise the script: take a centre point or bounding box and a title as arguments, so members can map other hikes.
