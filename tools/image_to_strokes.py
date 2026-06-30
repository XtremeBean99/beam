#!/usr/bin/env python3
"""Convert a line-drawing image (PNG) into a strokes JSON for InkTerrain.

This is the "upload an image to make a level" pipeline. It thresholds the dark
lines, thins them to a 1px skeleton, traces the skeleton into polylines, and
simplifies them (Ramer-Douglas-Peucker). The output JSON is consumed at runtime
by `scripts/ink_terrain.gd`, which builds one glowing InkStroke (visual +
collision) per stroke.

Usage:
    python tools/image_to_strokes.py INPUT.png OUTPUT.json [--eps 1.2] [--min-len 12]

Output shape:
    {"W": <int>, "H": <int>, "strokes": [{"pts": [[x,y], ...]}, ...]}

Notes:
- Coordinates are in IMAGE pixels; InkTerrain.world_scale scales them to world.
- For a true vector SVG (with <path> elements), parsing the path data directly
  would give crisper, simplification-free strokes — a planned enhancement.
  (map2.svg embeds a raster PNG, so it is traced like a PNG.)

Requires: numpy, pillow.
"""
import argparse
import json
import numpy as np
from PIL import Image


def _neighbors(m):
    P = [np.zeros_like(m) for _ in range(8)]
    P[0][1:, :] = m[:-1, :]
    P[4][:-1, :] = m[1:, :]
    P[2][:, :-1] = m[:, 1:]
    P[6][:, 1:] = m[:, :-1]
    P[1][1:, :-1] = m[:-1, 1:]
    P[3][:-1, :-1] = m[1:, 1:]
    P[5][:-1, 1:] = m[1:, :-1]
    P[7][1:, 1:] = m[:-1, :-1]
    return P


def thin(mask):
    """Zhang-Suen thinning to a 1px skeleton (vectorized)."""
    m = mask.copy()
    while True:
        changed = False
        for step in (0, 1):
            P = _neighbors(m)
            seq = P + [P[0]]
            A = np.zeros_like(m, np.int32)
            for i in range(8):
                A += ((seq[i] == 0) & (seq[i + 1] == 1)).astype(np.int32)
            B = sum(P)
            if step == 0:
                c2 = (P[0] * P[2] * P[4] == 0)
                c3 = (P[2] * P[4] * P[6] == 0)
            else:
                c2 = (P[0] * P[2] * P[6] == 0)
                c3 = (P[0] * P[4] * P[6] == 0)
            cond = (m == 1) & (A == 1) & (B >= 2) & (B <= 6) & c2 & c3
            if cond.any():
                m[cond] = 0
                changed = True
        if not changed:
            break
    return m


def trace(skel):
    """Trace a skeleton into ordered polylines, splitting at junctions/endpoints."""
    ys, xs = np.where(skel)
    pts = set(zip(xs.tolist(), ys.tolist()))

    def nb(p):
        x, y = p
        return [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                if (dx or dy) and (x + dx, y + dy) in pts]

    deg = {p: len(nb(p)) for p in pts}
    visited = set()
    paths = []

    def walk(start):
        path = [start]
        visited.add(start)
        prev, cur = None, start
        while True:
            nxt = [q for q in nb(cur) if q != prev and q not in visited]
            if not nxt:
                break
            if prev is not None:
                vx, vy = cur[0] - prev[0], cur[1] - prev[1]
                nxt.sort(key=lambda q: (q[0] - cur[0]) * vx + (q[1] - cur[1]) * vy, reverse=True)
            q = nxt[0]
            path.append(q)
            visited.add(q)
            prev, cur = cur, q
            if deg[q] != 2:
                break
        return path

    for s in [p for p in pts if deg[p] == 1] + [p for p in pts if deg[p] >= 3]:
        for q in nb(s):
            if q not in visited:
                p = walk(s)
                if len(p) >= 2:
                    paths.append(p)
    for s in list(pts):
        if s not in visited:
            p = walk(s)
            if len(p) >= 2:
                paths.append(p)
    return paths


def rdp(points, eps):
    """Ramer-Douglas-Peucker polyline simplification."""
    if len(points) < 3:
        return points
    A = np.array(points, float)

    def go(i, j):
        if j <= i + 1:
            return [i]
        d = A[j] - A[i]
        L = np.hypot(*d)
        seg = A[i + 1:j] - A[i]
        if L > 0:
            dist = np.abs(d[0] * seg[:, 1] - d[1] * seg[:, 0]) / L
        else:
            dist = np.hypot(seg[:, 0], seg[:, 1])
        k = int(np.argmax(dist))
        if dist[k] > eps:
            return go(i, i + 1 + k) + go(i + 1 + k, j)
        return [i]

    keep = go(0, len(A) - 1) + [len(A) - 1]
    return [points[i] for i in keep]


def image_to_strokes(path, eps=1.2, min_len=12.0, threshold=128):
    a = np.array(Image.open(path).convert("L"))
    H, W = a.shape
    mask = (a < threshold).astype(np.uint8)
    skel = thin(mask)
    strokes = []
    for p in trace(skel):
        sp = rdp(p, eps)
        L = sum(((sp[i + 1][0] - sp[i][0]) ** 2 + (sp[i + 1][1] - sp[i][1]) ** 2) ** 0.5
                for i in range(len(sp) - 1))
        if L >= min_len and len(sp) >= 2:
            strokes.append({"pts": [[int(x), int(y)] for x, y in sp]})
    return {"W": W, "H": H, "strokes": strokes}


def main():
    ap = argparse.ArgumentParser(description="Trace a line-drawing image into a strokes JSON.")
    ap.add_argument("input", help="input image (PNG)")
    ap.add_argument("output", help="output strokes JSON")
    ap.add_argument("--eps", type=float, default=1.2, help="RDP simplify epsilon (lower = more faithful)")
    ap.add_argument("--min-len", type=float, default=12.0, help="drop strokes shorter than this (px)")
    ap.add_argument("--threshold", type=int, default=128, help="darkness threshold (0-255)")
    args = ap.parse_args()
    data = image_to_strokes(args.input, args.eps, args.min_len, args.threshold)
    with open(args.output, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    pts = sum(len(s["pts"]) for s in data["strokes"])
    print(f"wrote {args.output}: {len(data['strokes'])} strokes, {pts} points "
          f"(image {data['W']}x{data['H']})")


if __name__ == "__main__":
    main()
