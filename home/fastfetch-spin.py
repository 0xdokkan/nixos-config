"""Render the NixOS snowflake as a spinning 3D solid, as ANSI text frames.

Runs once at build time (home/fastfetch-spin.nix); the player only replays
the frames next to the fastfetch output. Each lambda of the official logo
is extruded into a prism and ray-cast per sub-cell sample: no point clouds,
so there are no holes at any angle. Output in --out:
  frames.txt   FRAMES*HEIGHT lines, frame k = one turn * k / FRAMES
  logo.txt     frame 0 (facing front): the static fastfetch logo
  schedule.txt frame index per tick: SPINS turns slowing down to frame 0
"""

import argparse
import math
from pathlib import Path

import numpy as np

# One lambda of nix-snowflake.svg (nixos-icons, path3336-6): first point
# absolute, then relative steps, in SVG units (y points down). The other
# five are rotations by k*60 degrees about CENTRE (the <use> elements).
LAMBDA_PATH = [
    (309.54892, -710.38827), (122.19683, 211.67512), (-56.15706, 0.5268),
    (-32.6236, -56.8692), (-32.85645, 56.5653), (-27.90237, -0.011),
    (-14.29086, -24.6896), (46.81047, -80.4901), (-33.22946, -57.8257),
]
CENTRE = (407.29, -715.84)
# The official logo alternates a dark and a light blue; here the Tokyo
# Night Storm blue and blue1, distinct enough to tell the lambdas apart.
COLOURS = ((0x7A, 0xA2, 0xF7), (0x2A, 0xC3, 0xDE))
RAMP = ".,-~:;=!*#$@"

THICKNESS = 0.2   # radius of the logo = 1
TILT = math.radians(12)   # seen slightly from above, like a spinning coin
EXTENT = 1.02     # half-width of the view, in logo radii
SUPER_X, SUPER_Y = 3, 6   # samples per cell (cells are twice as tall)
CAMERA = 5.0
LIGHT = np.array([-2.0, 2.5, 5.0])
FPS = 30


def lambdas():
    """Six CCW polygons (9 vertices each) in logo radii, y pointing up."""
    pts = np.cumsum(np.array(LAMBDA_PATH), axis=0)
    base = np.column_stack([pts[:, 0] - CENTRE[0], CENTRE[1] - pts[:, 1]])
    base /= np.linalg.norm(base, axis=1).max()
    x, y = base[:, 0], base[:, 1]
    if np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y) < 0:
        base = base[::-1]
    polys = []
    for k in range(6):
        a = math.radians(60 * k)
        rot = np.array([[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]])
        polys.append(base @ rot.T)
    return polys


def rotation(theta):
    """Object -> view: spin about the vertical axis, then the fixed tilt."""
    c, s = math.cos(theta), math.sin(theta)
    ry = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    c, s = math.cos(TILT), math.sin(TILT)
    rx = np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    return rx @ ry


def cross(ax, ay, bx, by):
    return ax * by - ay * bx


def cast(polys, rot, px, py):
    """Nearest hit of the orthographic rays: distance, view normal, lambda."""
    n = px.size
    origin = rot.T @ np.vstack([px, py, np.full(n, CAMERA)])
    d = rot.T @ np.array([0.0, 0.0, -1.0])
    h = THICKNESS / 2
    if abs(d[2]) > 1e-9:
        sa = (-h - origin[2]) / d[2]
        sb = (h - origin[2]) / d[2]
        s0, s1 = np.minimum(sa, sb), np.maximum(sa, sb)
        cap_normal = np.array([0.0, 0.0, 1.0 if d[2] < 0 else -1.0])
    else:   # edge-on: the rays run inside or outside the slab
        inside = np.abs(origin[2]) <= h
        s0 = np.where(inside, 0.0, np.inf)
        s1 = np.where(inside, 2 * CAMERA, -np.inf)
        cap_normal = np.zeros(3)
    s0 = np.maximum(s0, 0.0)
    crosses = s1 > s0
    s0 = np.where(crosses, s0, 0.0)
    s1 = np.where(crosses, s1, 0.0)
    ax, ay = origin[0] + s0 * d[0], origin[1] + s0 * d[1]
    rx, ry = (s1 - s0) * d[0], (s1 - s0) * d[1]

    best = np.full(n, np.inf)
    normal = np.zeros((3, n))
    which = np.full(n, -1)
    for k, poly in enumerate(polys):
        inside = np.zeros(n, dtype=bool)
        hit = np.full(n, np.inf)
        hit_normal = np.zeros((2, n))
        for p, q in zip(poly, np.roll(poly, -1, axis=0)):
            ex, ey = q - p
            # crossing-number test for the entry point A
            straddles = (p[1] > ay) != (q[1] > ay)
            with np.errstate(divide="ignore", invalid="ignore"):
                xcross = p[0] + (ay - p[1]) * ex / ey
            inside ^= straddles & (ax < xcross)
            # first wall crossed by the segment A -> B inside the slab
            denom = cross(rx, ry, ex, ey)
            wx, wy = p[0] - ax, p[1] - ay
            with np.errstate(divide="ignore", invalid="ignore"):
                u = cross(wx, wy, ex, ey) / denom
                v = cross(wx, wy, rx, ry) / denom
            ok = (np.abs(denom) > 1e-12) & (u >= 0) & (u <= 1) & (v >= 0) & (v <= 1)
            with np.errstate(invalid="ignore"):
                s = np.where(ok, s0 + u * (s1 - s0), np.inf)
            closer = s < hit
            hit = np.where(closer, s, hit)
            length = math.hypot(ex, ey)
            hit_normal[0] = np.where(closer, ey / length, hit_normal[0])
            hit_normal[1] = np.where(closer, -ex / length, hit_normal[1])
        cap = inside & crosses
        s = np.where(cap, s0, np.where(crosses, hit, np.inf))
        closer = s < best
        best = np.where(closer, s, best)
        which = np.where(closer, k, which)
        obj_normal = np.where(
            cap, cap_normal[:, None], np.vstack([hit_normal, np.zeros(n)])
        )
        normal = np.where(closer, rot @ obj_normal, normal)
    return best, normal, which


def shade(px, py, dist, normal):
    point = np.vstack([px, py, CAMERA - dist])
    to_light = LIGHT[:, None] - point
    to_light /= np.linalg.norm(to_light, axis=0)
    diffuse = np.clip(np.sum(normal * to_light, axis=0), 0, 1)
    half = to_light + np.array([0.0, 0.0, 1.0])[:, None]
    half /= np.linalg.norm(half, axis=0)
    specular = np.clip(np.sum(normal * half, axis=0), 0, 1) ** 16
    return np.clip(0.2 + 0.75 * diffuse + 0.35 * specular, 0, 1)


def render(polys, theta, width, height):
    cols, rows = width * SUPER_X, height * SUPER_Y
    extent_y = EXTENT * 2 * height / width   # cells are twice as tall
    xs = (np.arange(cols) + 0.5) / cols * 2 * EXTENT - EXTENT
    ys = extent_y - (np.arange(rows) + 0.5) / rows * 2 * extent_y
    px, py = (a.ravel() for a in np.meshgrid(xs, ys))
    dist, normal, which = cast(polys, rotation(theta), px, py)
    hit = np.isfinite(dist)
    light = np.where(hit, shade(px, py, np.where(hit, dist, 0), normal), 0)

    def cells(a):
        return a.reshape(height, SUPER_Y, width, SUPER_X).sum(axis=(1, 3))

    count = cells(hit.astype(float))
    coverage = count / (SUPER_X * SUPER_Y)
    brightness = cells(light) / np.maximum(count, 1)
    odd = cells((hit & (which % 2 == 1)).astype(float))
    value = brightness * (0.3 + 0.7 * coverage)

    lines = []
    for r in range(height):
        out, current = [], None
        for c in range(width):
            if coverage[r, c] < 0.12:
                out.append(" ")
                continue
            level = int(np.clip(round(value[r, c] * (len(RAMP) - 1)), 0, len(RAMP) - 1))
            base = COLOURS[1 if odd[r, c] * 2 > count[r, c] else 0]
            scale = 0.35 + 0.8 * level / (len(RAMP) - 1)
            rgb = tuple(min(255, round(ch * scale)) for ch in base)
            if rgb != current:
                out.append("\x1b[38;2;%d;%d;%dm" % rgb)
                current = rgb
            out.append(RAMP[level])
        out.append("\x1b[0m")
        lines.append("".join(out))
    return lines


def schedule(frames, spins, seconds):
    """Ease-out: starts at full speed, settles on the front-facing frame."""
    ticks = round(seconds * FPS)
    total = spins * frames
    out = []
    for t in range(1, ticks + 1):
        x = t / ticks
        out.append(round(total * (1 - (1 - x) ** 2)) % frames)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--frames", type=int, required=True)
    parser.add_argument("--spins", type=int, required=True)
    parser.add_argument("--seconds", type=float, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    polys = lambdas()
    frames = [
        render(polys, 2 * math.pi * k / args.frames, args.width, args.height)
        for k in range(args.frames)
    ]
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "frames.txt").write_text(
        "".join(line + "\n" for frame in frames for line in frame)
    )
    (args.out / "logo.txt").write_text("".join(line + "\n" for line in frames[0]))
    (args.out / "schedule.txt").write_text(
        "".join(f"{k}\n" for k in schedule(args.frames, args.spins, args.seconds))
    )


if __name__ == "__main__":
    main()
