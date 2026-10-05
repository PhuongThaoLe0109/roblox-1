#!/usr/bin/env python3
"""Offline preview renderer for the generated map.

Reads the PART| lines produced by `MAP_DUMP=true tools/map-check.sh` and draws
a perspective image with a z-buffer rasteriser: flat-shaded faces lit by the
moon, glowing neon (with a bloom pass), translucent glass, distance fog in the
atmosphere colour and a gradient sky. It is only a preview of layout and
colour; Roblox's renderer will look smoother.

  MAP_DUMP=true tools/map-check.sh path/to/luau > parts.txt
  tools/render-map.py parts.txt out.png --cam 0,95,560 --look 0,70,-20
"""
import argparse
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SKY_TOP = np.array([10, 22, 44])
SKY_HORIZON = np.array([64, 140, 150])
FOG = np.array([70, 150, 160])
LIGHT = np.array([0.35, 0.85, -0.4])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def parse(path):
    parts = []
    for line in open(path):
        if not line.startswith("PART|"):
            continue
        _, cls, shape, size, pos, rot, color, transparency, material = line.strip().split("|")
        parts.append({
            "cls": cls,
            "shape": shape.split(".")[-1],
            "size": np.array([float(v) for v in size.split(",")]),
            "pos": np.array([float(v) for v in pos.split(",")]),
            "rot": np.array([float(v) for v in rot.split(",")]).reshape(3, 3),  # rows: R, U, B vectors
            "color": np.array([float(v) for v in color.split(",")]) * 255,
            "t": float(transparency),
            "mat": material.split(".")[-1],
        })
    return parts


def box_faces(part):
    sx, sy, sz = part["size"] / 2
    R, U, B = part["rot"]
    p = part["pos"]

    def pt(x, y, z):
        return p + R * x + U * y + B * z

    if part["cls"] == "WedgePart":
        a, b = pt(-sx, -sy, -sz), pt(sx, -sy, -sz)
        c, d = pt(sx, -sy, sz), pt(-sx, -sy, sz)
        e, f = pt(-sx, sy, sz), pt(sx, sy, sz)
        slope_n = np.cross(f - b, a - b)
        return [
            ([a, b, c, d], -U),
            ([d, c, f, e], B),
            ([a, d, e], -R),
            ([b, f, c], R),
            ([a, e, f, b], slope_n / (np.linalg.norm(slope_n) + 1e-9)),
        ]
    if part["shape"] == "Cylinder":
        # Axis along local X; approximate with a 12-sided prism.
        n = 12
        ring = [(math.cos(i / n * 2 * math.pi), math.sin(i / n * 2 * math.pi)) for i in range(n)]
        left = [pt(-sx, sy * c, sz * s) for c, s in ring]
        right = [pt(sx, sy * c, sz * s) for c, s in ring]
        faces = [(left[::-1], -R), (right, R)]
        for i in range(n):
            j = (i + 1) % n
            mid = (ring[i][0] + ring[j][0]) / 2, (ring[i][1] + ring[j][1]) / 2
            normal = U * mid[0] + B * mid[1]
            faces.append(([left[i], left[j], right[j], right[i]], normal / (np.linalg.norm(normal) + 1e-9)))
        return faces
    corners = {}
    for x in (-1, 1):
        for y in (-1, 1):
            for z in (-1, 1):
                corners[(x, y, z)] = pt(sx * x, sy * y, sz * z)
    c = corners
    return [
        ([c[(1, -1, -1)], c[(1, 1, -1)], c[(1, 1, 1)], c[(1, -1, 1)]], R),
        ([c[(-1, -1, -1)], c[(-1, -1, 1)], c[(-1, 1, 1)], c[(-1, 1, -1)]], -R),
        ([c[(-1, 1, -1)], c[(-1, 1, 1)], c[(1, 1, 1)], c[(1, 1, -1)]], U),
        ([c[(-1, -1, -1)], c[(1, -1, -1)], c[(1, -1, 1)], c[(-1, -1, 1)]], -U),
        ([c[(-1, -1, 1)], c[(1, -1, 1)], c[(1, 1, 1)], c[(-1, 1, 1)]], B),
        ([c[(-1, -1, -1)], c[(-1, 1, -1)], c[(1, 1, -1)], c[(1, -1, -1)]], -B),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("parts")
    ap.add_argument("out")
    ap.add_argument("--cam", default="0,95,560")
    ap.add_argument("--look", default="0,70,-20")
    ap.add_argument("--fov", type=float, default=62)
    ap.add_argument("--size", default="1600x900")
    ap.add_argument("--fog", type=float, default=0.0011)
    args = ap.parse_args()

    W, H = (int(v) for v in args.size.split("x"))
    cam = np.array([float(v) for v in args.cam.split(",")])
    look = np.array([float(v) for v in args.look.split(",")])
    fwd = look - cam
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    focal = (H / 2) / math.tan(math.radians(args.fov) / 2)
    near = 0.5

    def to_cam(p):
        d = p - cam
        return np.array([d @ right, d @ up, d @ fwd])

    def project(c):
        return (W / 2 + c[0] / c[2] * focal, H / 2 - c[1] / c[2] * focal)

    def clip_near(poly):
        out = []
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            ina, inb = a[2] >= near, b[2] >= near
            if ina:
                out.append(a)
            if ina != inb:
                t = (near - a[2]) / (b[2] - a[2])
                out.append(a + (b - a) * t)
        return out

    polys = []  # (depth, points, rgba, glow)
    for part in parse(args.parts):
        if part["t"] >= 0.97:
            continue
        neon = part["mat"] == "Neon"
        glass = part["mat"] == "Glass"
        alpha = 1 - part["t"]
        if glass:
            alpha *= 0.7
        base = part["color"]
        if part["shape"] == "Ball":
            c = to_cam(part["pos"])
            if c[2] < near:
                continue
            r = part["size"][0] / 2 / c[2] * focal
            x, y = project(c)
            if r < 0.3 or x + r < 0 or x - r > W or y + r < 0 or y - r > H:
                continue
            shade = 1.25 if neon else 0.75
            color = np.clip(base * shade, 0, 255)
            fog = 1 - math.exp(-c[2] * args.fog)
            color = color * (1 - fog) + FOG * fog
            pts = [(x + r * math.cos(a), y + r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 18, endpoint=False)]
            rgba = (*color.astype(int), int(255 * alpha))
            polys.append((c[2], pts, [c[2]] * len(pts), rgba[3], rgba, neon))
            continue
        for verts, normal in box_faces(part):
            center = np.mean(verts, axis=0)
            to_eye = cam - center
            if not glass and alpha > 0.9 and normal @ to_eye < 0:
                continue  # back face
            cpts = clip_near([to_cam(v) for v in verts])
            if len(cpts) < 3:
                continue
            pts = [project(c) for c in cpts]
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            if max(xs) < 0 or min(xs) > W or max(ys) < 0 or min(ys) > H:
                continue
            depth = np.mean([c[2] for c in cpts])
            if neon:
                color = np.clip(base * 1.15 + 25, 0, 255)
            else:
                lambert = max(0.0, float(normal @ LIGHT))
                color = base * (0.42 + 0.68 * lambert)
            fog = 1 - math.exp(-depth * args.fog)
            if neon:
                fog *= 0.5
            color = color * (1 - fog) + FOG * fog
            rgba = (*np.clip(color, 0, 255).astype(int), int(255 * alpha))
            polys.append((depth, pts, [c[2] for c in cpts], rgba[3], rgba, neon))

    # Z-buffered rasterisation (painter's sorting misorders big faces).
    color_buf = np.zeros((H, W, 3))
    for y in range(H):
        t = min(1, y / (H * 0.62))
        color_buf[y, :] = SKY_TOP * (1 - t) + SKY_HORIZON * t
    depth_buf = np.full((H, W), np.inf)
    glow_buf = np.zeros((H, W, 3))

    def raster(points, depths, rgba, neon, write_depth):
        rgb = np.array(rgba[:3], dtype=float)
        alpha = rgba[3] / 255
        for k in range(1, len(points) - 1):
            tri = [points[0], points[k], points[k + 1]]
            inv = [1 / depths[0], 1 / depths[k], 1 / depths[k + 1]]
            xs = [p[0] for p in tri]
            ys = [p[1] for p in tri]
            x0, x1 = max(0, int(math.floor(min(xs)))), min(W - 1, int(math.ceil(max(xs))))
            y0, y1 = max(0, int(math.floor(min(ys)))), min(H - 1, int(math.ceil(max(ys))))
            if x0 > x1 or y0 > y1:
                continue
            (ax, ay), (bx, by), (cx, cy) = tri
            area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
            if abs(area) < 1e-9:
                continue
            gy, gx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
            px, py = gx + 0.5, gy + 0.5
            w0 = ((bx - px) * (cy - py) - (cx - px) * (by - py)) / area
            w1 = ((cx - px) * (ay - py) - (ax - px) * (cy - py)) / area
            w2 = 1 - w0 - w1
            inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
            if not inside.any():
                continue
            z = 1 / (w0 * inv[0] + w1 * inv[1] + w2 * inv[2])
            region = depth_buf[y0:y1 + 1, x0:x1 + 1]
            visible = inside & (z < region)
            if not visible.any():
                continue
            target = color_buf[y0:y1 + 1, x0:x1 + 1]
            target[visible] = target[visible] * (1 - alpha) + rgb * alpha
            if write_depth:
                region[visible] = z[visible]
            if neon:
                glow = glow_buf[y0:y1 + 1, x0:x1 + 1]
                glow[visible] = np.maximum(glow[visible], rgb * alpha)

    opaque = [p for p in polys if p[3] >= 250]
    translucent = sorted([p for p in polys if p[3] < 250], key=lambda p: -p[0])
    for depth, pts, depths, alpha_byte, rgba, neon in opaque:
        raster(pts, depths, rgba, neon, True)
    for depth, pts, depths, alpha_byte, rgba, neon in translucent:
        raster(pts, depths, rgba, neon, False)

    glow = Image.fromarray(np.clip(glow_buf, 0, 255).astype(np.uint8))
    bloom = np.asarray(glow.filter(ImageFilter.GaussianBlur(14))).astype(float)
    bloom2 = np.asarray(glow.filter(ImageFilter.GaussianBlur(4))).astype(float)
    out = color_buf + bloom * 0.55 + bloom2 * 0.35
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(args.out)
    print(f"{args.out}: {len(polys)} polygons")


if __name__ == "__main__":
    main()
