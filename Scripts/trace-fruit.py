#!/usr/bin/env python3
# Traces the black shapes of an image into point lists for FruitPaint (RenderWings.swift).
# Usage: python3 Scripts/trace-fruit.py silhouette.png
import sys, math
from PIL import Image
from collections import deque

im = Image.open(sys.argv[1]).convert("L")
W, H = im.size
px = im.load()
ink = [[px[x, y] < 110 for x in range(W)] for y in range(H)]

# Connected black regions (4-neighbour), biggest first.
label = [[0] * W for _ in range(H)]
regions = []
for y in range(H):
    for x in range(W):
        if ink[y][x] and not label[y][x]:
            n = len(regions) + 1
            q = deque([(x, y)]); label[y][x] = n; size = 0; start = (x, y)
            while q:
                cx, cy = q.popleft(); size += 1
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < W and 0 <= ny < H and ink[ny][nx] and not label[ny][nx]:
                        label[ny][nx] = n; q.append((nx, ny))
            regions.append((size, n, start))
regions.sort(reverse=True)
regions = [r for r in regions if r[0] > 400]

def inside(n, x, y):
    return 0 <= x < W and 0 <= y < H and label[y][x] == n

def outline(n, start):
    """Moore-neighbour boundary tracing, clockwise, from the topmost-leftmost pixel."""
    dirs = [(-1,0),(-1,-1),(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1)]  # W NW N NE E SE S SW
    cur = start
    back = (start[0]-1, start[1])
    first = (cur, back)
    pts = [cur]
    for _ in range(400000):
        bx, by = back[0]-cur[0], back[1]-cur[1]
        idx = dirs.index((bx, by))
        prev = back
        moved = False
        for k in range(1, 9):
            dx, dy = dirs[(idx+k) % 8]
            c = (cur[0]+dx, cur[1]+dy)
            if inside(n, *c):
                back = prev
                cur = c
                moved = True
                break
            prev = c
        if not moved: break
        if (cur, back) == first: break
        pts.append(cur)
    return pts

def rdp(points, eps):
    if len(points) < 3: return points
    a, b = points[0], points[-1]
    dx, dy = b[0]-a[0], b[1]-a[1]; L = math.hypot(dx, dy) or 1e-9
    far, idx = -1, 0
    for i in range(1, len(points)-1):
        p = points[i]
        dist = abs(dy*p[0] - dx*p[1] + b[0]*a[1] - b[1]*a[0]) / L
        if dist > far: far, idx = dist, i
    if far > eps:
        return rdp(points[:idx+1], eps)[:-1] + rdp(points[idx:], eps)
    return [a, b]

def smooth(points, k=3):
    n = len(points); out = []
    for i in range(n):
        sx = sy = 0
        for j in range(-k, k+1):
            sx += points[(i+j) % n][0]; sy += points[(i+j) % n][1]
        out.append((sx/(2*k+1), sy/(2*k+1)))
    return out

# Fit into a 24 x 24 box, centred.
scale = 22.6 / H
ox = (24 - W * scale) / 2; oy = (24 - H * scale) / 2
names = ["body", "leaves"]
for (size, n, start), name in zip(regions, names):
    pts = outline(n, start)
    pts = smooth(pts, 4)
    # Close the loop for rdp, then drop the repeat.
    # A closed loop: split at the point farthest from the start, simplify both halves.
    far = max(range(len(pts)), key=lambda i: math.hypot(pts[i][0]-pts[0][0], pts[i][1]-pts[0][1]))
    simple = rdp(pts[:far+1], 1.6)[:-1] + rdp(pts[far:] + [pts[0]], 1.6)[:-1]
    q = [(round(x*scale+ox, 2), round(y*scale+oy, 2)) for x, y in simple]
    print(f"// {name}: {len(q)} points (from {len(pts)})")
    print(f"static let {name}: [CGPoint] = [" + ", ".join(f"CGPoint(x: {x}, y: {y})" for x, y in q) + "]")
