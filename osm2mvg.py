#!/usr/bin/env python3
"""Turn OSM lines (GeoJSON in the raster's CRS) into ImageMagick MVG draw commands.

Usage: osm2mvg.py LINES.geojson RASTER.tif > overlay.mvg
"""
import json
import re
import subprocess
import sys

FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
ITALIC = "/System/Library/Fonts/Supplemental/Arial Italic.ttf"
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

# style: (casing color, casing width, fill color, fill width, dash)
WATER = {
    "river": ("#1f5fa8", 3.5),
    "stream": ("#2f7fcf", 1.6),
    "canal": ("#5aa0e0", 1.2),
    "ditch": ("#5aa0e0", 1.0),
    "drain": ("#5aa0e0", 1.0),
}
ROADS = {
    "primary": ("#5a2d0c", 8, "#f08a3c", 5.5, None),
    "secondary": ("#5a2d0c", 7, "#f6d36b", 4.5, None),
    "tertiary": ("#444444", 5.5, "#ffffff", 3.5, None),
    "unclassified": ("#444444", 5, "#ffffff", 3, None),
    "residential": ("#555555", 4, "#ffffff", 2.4, None),
    "living_street": ("#555555", 4, "#ffffff", 2.4, None),
    "service": ("#666666", 3, "#ffffff", 1.6, None),
    "track": (None, 0, "#7a4a1e", 1.6, "6 4"),
    "path": (None, 0, "#333333", 1.1, "3 3"),
    "footway": (None, 0, "#333333", 1.1, "3 3"),
    "pedestrian": (None, 0, "#333333", 1.1, "3 3"),
    "steps": (None, 0, "#333333", 1.1, "2 2"),
}
ORDER = ["path", "footway", "pedestrian", "steps", "track", "service",
         "residential", "living_street", "unclassified", "tertiary",
         "secondary", "primary"]


def tags(p):
    t = {k: v for k, v in p.items() if k != "other_tags" and v is not None}
    for k, v in re.findall(r'"([^"]+)"=>"([^"]*)"', p.get("other_tags") or ""):
        t.setdefault(k, v)
    return t


def esc(s):
    return s.replace("\\", "\\\\").replace("'", "\\'")


def main():
    lines_path, raster = sys.argv[1], sys.argv[2]
    info = json.loads(subprocess.check_output(["gdalinfo", "-json", raster]))
    x0, dx, _, y0, _, dy = info["geoTransform"]
    W, H = info["size"]

    def pix(c):
        return ((c[0] - x0) / dx, (c[1] - y0) / dy)

    water, roads = [], {k: [] for k in ORDER}
    for f in json.load(open(lines_path))["features"]:
        g = f["geometry"]
        parts = g["coordinates"] if g["type"] == "MultiLineString" else [g["coordinates"]]
        t = tags(f["properties"])
        for part in parts:
            pts = [pix(c) for c in part]
            if t.get("waterway") in WATER:
                water.append((t["waterway"], t.get("name"), pts))
            elif t.get("highway") in roads:
                roads[t["highway"]].append((t.get("name"), pts))

    out = []
    poly = lambda pts: "polyline " + " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    out.append("push graphic-context")
    out.append("fill none stroke-linecap round stroke-linejoin round")

    # water under roads
    for kind in ("ditch", "drain", "canal", "stream", "river"):
        color, w = WATER[kind]
        for k, _, pts in water:
            if k == kind and len(pts) > 1:
                out.append(f"stroke '{color}' stroke-width {w} {poly(pts)}")

    # casings, then fills, so junctions merge cleanly
    for k in ORDER:
        case, cw, _, _, _ = ROADS[k]
        if case:
            for _, pts in roads[k]:
                out.append(f"stroke '{case}' stroke-width {cw} {poly(pts)}")
    for k in ORDER:
        _, _, fill, fw, dash = ROADS[k]
        out.append(f"stroke-dasharray {dash}" if dash else "stroke-dasharray none")
        for _, pts in roads[k]:
            out.append(f"stroke '{fill}' stroke-width {fw} {poly(pts)}")
    out.append("stroke-dasharray none")
    out.append("pop graphic-context")

    # labels: one per named river/main road, at the middle of its longest piece
    def longest_inside(items):
        best = {}
        for name, pts in items:
            if not name:
                continue
            inside = [p for p in pts if 40 < p[0] < W - 200 and 30 < p[1] < H - 30]
            if len(inside) < 2:
                continue
            n = sum(((a[0]-b[0])**2 + (a[1]-b[1])**2) ** .5 for a, b in zip(inside, inside[1:]))
            if n > best.get(name, (0,))[0]:
                best[name] = (n, inside[len(inside) // 2])
        return best

    def label(text, at, font, size, color):
        x, y = at
        out.append(f"font '{font}' font-size {size} text-antialias true")
        out.append(f"stroke white stroke-width 4 fill none text {x+6:.0f},{y-6:.0f} '{esc(text)}'")
        out.append(f"stroke none fill '{color}' text {x+6:.0f},{y-6:.0f} '{esc(text)}'")

    rivers = longest_inside((n, p) for k, n, p in water if k == "river")
    for name, (n, at) in rivers.items():
        if n > 150:
            label(name.replace("Rio ", "Río "), at, ITALIC, 17, "#14467e")
    mains = longest_inside(r for k in ("primary", "secondary") for r in roads[k])
    for name, (n, at) in mains.items():
        if n > 150:
            label(name, at, BOLD, 15, "#5a2d0c")

    # legend, lower left
    lx, ly, lw, lh = 15, H - 205, 190, 190
    out.append("push graphic-context")
    out.append(f"stroke none fill 'rgba(255,255,255,0.88)' roundrectangle {lx},{ly} {lx+lw},{ly+lh} 8,8")
    out.append(f"font '{BOLD}' font-size 15 fill black text {lx+12},{ly+22} 'Legend'")
    rows = [
        ("Primary road", ROADS["primary"]),
        ("Secondary road", ROADS["secondary"]),
        ("Local road", ROADS["residential"]),
        ("Track", ROADS["track"]),
        ("Path", ROADS["path"]),
        ("River", (None, 0, WATER["river"][0], WATER["river"][1], None)),
        ("Stream", (None, 0, WATER["stream"][0], WATER["stream"][1], None)),
    ]
    out.append("stroke-linecap butt")
    for i, (txt, (case, cw, fill, fw, dash)) in enumerate(rows):
        y = ly + 45 + i * 21
        seg = f"line {lx+12},{y} {lx+52},{y}"
        out.append("fill none stroke-dasharray none")
        if case:
            out.append(f"stroke '{case}' stroke-width {cw} {seg}")
        out.append(f"stroke-dasharray {dash}" if dash else "stroke-dasharray none")
        out.append(f"stroke '{fill}' stroke-width {fw} {seg}")
        out.append("stroke-dasharray none")
        out.append(f"stroke none fill black font '{FONT}' font-size 14 text {lx+62},{y+5} '{txt}'")
    out.append("pop graphic-context")

    print("\n".join(out))


if __name__ == "__main__":
    main()
