"""Draws the addon's own art (white or grey on transparent, tinted in game) as 32-bit TGA files: icons, each also
drawn pixel for pixel at every small size (the disc's halves and quarters round the settings window's pills and
corners), and the Loot Window's burnt page background.

Usage: python tools/make_art.py [icons-preview.png [page-preview.png]]
"""
from pathlib import Path
import math
import random
import sys

from PIL import Image

ART = Path(__file__).resolve().parent.parent / 'HastesSuperTweaks' / 'Art'


def cog(size=64, teeth=8, outer=0.47, root=0.36, hole=0.15, samples=4):
    """Gear with trapezoid teeth and a center hole, antialiased by supersampling."""
    image = Image.new('RGBA', (size, size))
    period = 2 * math.pi / teeth
    tip, base = 0.30, 0.52  # tooth width at the tip and at the root, as a fraction of the period
    for py in range(size):
        for px in range(size):
            hits = 0
            for sy in range(samples):
                for sx in range(samples):
                    x = (px + (sx + 0.5) / samples) / size - 0.5
                    y = (py + (sy + 0.5) / samples) / size - 0.5
                    r = math.hypot(x, y)
                    if r < hole or r > outer:
                        continue
                    # Distance from the nearest tooth center, as a fraction of the period.
                    phase = abs(((math.atan2(y, x) / period) % 1.0) - 0.5)
                    if phase <= tip / 2:
                        edge = outer
                    elif phase >= base / 2:
                        edge = root
                    else:
                        edge = outer - (outer - root) * (phase - tip / 2) / ((base - tip) / 2)
                    if r <= edge:
                        hits += 1
            image.putpixel((px, py), (255, 255, 255, round(255 * hits / samples ** 2)))
    return image


# GitHub's mark (Octicons mark-github, 16x16 view box), for linking to the project on GitHub.
GITHUB_PATH = (
    'M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49'
    '-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82'
    '.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15'
    '-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04'
    ' 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.28.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25'
    '.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z'
)


def path_points(path, steps=16):
    """Flattens an SVG path (M, L, H, V, C, S, A, Z; absolute or relative) into polygons."""
    import re
    tokens = re.findall(r'[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?', path)
    polygons, points = [], []
    x = y = cx = cy = 0.0  # current point and the last cubic control point
    command, i = None, 0

    def number():
        nonlocal i
        i += 1
        return float(tokens[i - 1])

    def flag():
        # Arc flags may be written without separators ("0016"): take one digit.
        nonlocal i
        token = tokens[i]
        if len(token) > 1:
            tokens[i] = token[1:]
            return int(token[0])
        i += 1
        return int(token)

    def cubic(x1, y1, x2, y2, x3, y3):
        for s in range(1, steps + 1):
            t = s / steps
            u = 1 - t
            points.append((u ** 3 * x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t ** 3 * x3,
                           u ** 3 * y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t ** 3 * y3))

    def arc(rx, ry, sweep_large, sweep, x2, y2):
        # Circular arcs only (rx == ry, no rotation), which is all these paths use.
        r = rx
        dx, dy = (x2 - x) / 2, (y2 - y) / 2
        d = math.hypot(dx, dy)
        r = max(r, d)
        h = math.sqrt(max(r * r - d * d, 0))
        sign = 1 if sweep_large != sweep else -1
        mx, my = (x + x2) / 2, (y + y2) / 2
        ox, oy = mx - sign * h * dy / d, my + sign * h * dx / d
        a1, a2 = math.atan2(y - oy, x - ox), math.atan2(y2 - oy, x2 - ox)
        delta = a2 - a1
        if sweep and delta < 0:
            delta += 2 * math.pi
        if not sweep and delta > 0:
            delta -= 2 * math.pi
        for s in range(1, steps * 2 + 1):
            a = a1 + delta * s / (steps * 2)
            points.append((ox + r * math.cos(a), oy + r * math.sin(a)))

    while i < len(tokens):
        if tokens[i].isalpha():
            command = tokens[i]
            i += 1
        rel = command.islower()
        ox, oy = (x, y) if rel else (0.0, 0.0)
        c = command.upper()
        if c == 'M':
            if points:
                polygons.append(points)
            x, y = ox + number(), oy + number()
            points = [(x, y)]
            command = 'l' if rel else 'L'  # further pairs are line segments
        elif c == 'L':
            x, y = ox + number(), oy + number()
            points.append((x, y))
        elif c == 'H':
            x = ox + number()
            points.append((x, y))
        elif c == 'V':
            y = oy + number()
            points.append((x, y))
        elif c in 'CS':
            if c == 'C':
                x1, y1 = ox + number(), oy + number()
            else:
                x1, y1 = 2 * x - cx, 2 * y - cy
            x2, y2 = ox + number(), oy + number()
            x3, y3 = ox + number(), oy + number()
            cubic(x1, y1, x2, y2, x3, y3)
            cx, cy, x, y = x2, y2, x3, y3
            continue
        elif c == 'A':
            rx, ry = number(), number()
            number()  # rotation
            large, sweep = flag(), flag()
            x2, y2 = ox + number(), oy + number()
            arc(rx, ry, large, sweep, x2, y2)
            x, y = x2, y2
        elif c == 'Z':
            if points:
                polygons.append(points)
            points = []
        cx, cy = x, y
    if points:
        polygons.append(points)
    return polygons


def svg_icon(path, view=16, size=64, margin=0.04, samples=8):
    """Fills an SVG path (even-odd) into a white-on-transparent image, antialiased by supersampling."""
    from PIL import ImageDraw, ImageChops
    big = size * samples
    scale = big * (1 - 2 * margin) / view
    offset = big * margin
    mask = Image.new('L', (big, big))
    for polygon in path_points(path):
        layer = Image.new('L', (big, big))
        ImageDraw.Draw(layer).polygon([(offset + px * scale, offset + py * scale) for px, py in polygon], fill=255)
        mask = ImageChops.difference(mask, layer)
    image = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    image.putalpha(mask.resize((size, size), Image.BOX))  # area average: each pixel's exact coverage, no ringing
    return image


# The Haste brand logo: its three paths, each drawn at (tx + x, ty - y), within LOGO_BOX.
# The logo (this data and the art drawn from it) is not covered by the project's license: see TRADEMARKS.md.
LOGO_PATHS = [
    (2444.9884, 1791.459, 'M0 0 79.041 35.35 130.774 214.396C84.979 217.554 41.059 227.516 0 243.269-41.057 227.516'
     '-84.981 217.554-130.774 214.396L-79.04 35.35Z'),
    (2476.832, 2336.6925, 'M0 0C-10.31-7.276-20.936-14.12-31.844-20.523-42.753-14.12-53.377-7.276-63.688 0H-63.697'
     'L-181.993-152.183C-134.893-184.068-84.653-211.669-31.844-234.424 20.965-211.669 71.204-184.068 118.307-152.183'
     'L.011 0Z'),
    (2985.958, 1428.8828, 'M0 0C-9.866-12.31-19.206-25.04-28.011-38.171V-38.182C-88.222-127.9-123.34-235.845-123.34'
     '-352.003-123.34-453.547-96.51-548.812-49.522-631.107-79.071-707.894-118.685-779.68-166.757-844.839-212.215'
     '-906.441-265.214-962.124-324.416-1010.521L-446.006-854.105C-404.655-811.869-371.475-761.598-349.045-705.84'
     'L-540.969-791.915-732.891-705.84C-710.463-761.598-677.283-811.869-635.93-854.105L-757.521-1010.521C-816.723'
     '-962.124-869.721-906.441-915.18-844.839-963.252-779.68-1002.866-707.894-1032.414-631.107-985.428-548.812'
     '-958.598-453.547-958.598-352.003-958.598-235.845-993.716-127.9-1053.928-38.182V-38.171C-1062.73-25.04'
     '-1072.07-12.31-1081.938 0L-773.907-143.884-701.986-392.777-540.969-464.256-379.951-392.777-308.028-143.884Z'),
]
LOGO_BOX = (1904.02, 1428.883, 2985.958, 2571.116)
LOGO_COLOR = (245, 194, 50)  # gold, close to the accent: the logo is shown untinted
LOGO_WHITE = (246, 241, 233)  # near white, as in LogoSearch: the settings window's title bar


def logo_mask(big, margin=0.04):
    """The logo's shape, filled white on black in a big-by-big square."""
    from PIL import ImageDraw
    x0, y0, x1, y1 = LOGO_BOX
    scale = big * (1 - 2 * margin) / max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    mask = Image.new('L', (big, big))
    draw = ImageDraw.Draw(mask)
    for tx, ty, path in LOGO_PATHS:
        for polygon in path_points(path):
            draw.polygon([(big / 2 + (tx + px - cx) * scale, big / 2 + (ty - py - cy) * scale) for px, py in polygon],
                         fill=255)
    return mask


def logo(size=64, margin=0.04, samples=8, color=LOGO_COLOR):
    """The logo in gold (or `color`) on transparent, centered in a square."""
    mask = logo_mask(size * samples, margin)
    image = Image.new('RGBA', (size, size), color + (0,))
    image.putalpha(mask.resize((size, size), Image.BOX))
    return image


def logo_off(size=64, samples=8, stroke=0.06, gap=0.04, reach=0.12):
    """The logo struck through, top left to bottom right, with a gap cut around the stroke (as a muted bell is drawn),
    white on transparent to be tinted in game: the settings window shows it over a tweak that's off."""
    from PIL import ImageDraw, ImageChops
    big = size * samples
    shape = logo_mask(big, margin=0.1)

    def bar(half):
        mask = Image.new('L', (big, big))
        draw = ImageDraw.Draw(mask)
        a, b, r = reach * big, (1 - reach) * big, half * big
        draw.line([(a, a), (b, b)], fill=255, width=round(2 * r))
        for x in (a, b):
            draw.ellipse([x - r, x - r, x + r, x + r], fill=255)
        return mask
    cut = ImageChops.subtract(shape, bar(stroke / 2 + gap))
    mask = ImageChops.lighter(cut, bar(stroke / 2))
    image = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    image.putalpha(mask.resize((size, size), Image.BOX))
    return image


def logo_search(size=64, samples=8, logo_size=0.8, lens=(0.67, 0.67), radius=0.17, stroke=0.07, handle=0.085,
                gap=0.045, color=LOGO_WHITE, glass=LOGO_COLOR):
    """The logo, up and left, searched by a magnifying glass at its lower right, a gap cut around the glass: the
    settings window's empty search. In color, shown untinted: the logo near white, the glass gold. Inside the lens is
    left empty: bits of logo there read as noise at small sizes."""
    from PIL import ImageDraw, ImageChops
    big = size * samples
    inner = round(big * logo_size)
    shape = Image.new('L', (big, big))
    shape.paste(logo_mask(inner), (0, 0))
    cx, cy = lens[0] * big, lens[1] * big
    r, s, h, g = radius * big, stroke * big / 2, handle * big / 2, gap * big
    end = (0.93 * big, 0.93 * big)

    def glass_mask(extra, hollow=True):
        mask = Image.new('L', (big, big))
        draw = ImageDraw.Draw(mask)
        outer, hole = r + s + extra, r - s - extra
        draw.ellipse([cx - outer, cy - outer, cx + outer, cy + outer], fill=255)
        if hollow:
            draw.ellipse([cx - hole, cy - hole, cx + hole, cy + hole], fill=0)
        start = (cx + r * 0.7071, cy + r * 0.7071)
        draw.line([start, end], fill=255, width=round(2 * (h + extra)))
        draw.ellipse([end[0] - h - extra, end[1] - h - extra, end[0] + h + extra, end[1] + h + extra], fill=255)
        return mask
    cut = ImageChops.subtract(shape, glass_mask(g, hollow=False))
    image = Image.new('RGBA', (size, size), color + (0,))
    image.putalpha(cut.resize((size, size), Image.BOX))
    lens_layer = Image.new('RGBA', (size, size), glass + (0,))
    lens_layer.putalpha(glass_mask(0).resize((size, size), Image.BOX))
    image.alpha_composite(lens_layer)
    return image


def coverage(width, height, inside, samples=4):
    """White image whose alpha is the share of each pixel's subsamples for which inside(x, y) holds (x, y in pixels)."""
    image = Image.new('RGBA', (width, height))
    for py in range(height):
        for px in range(width):
            hits = sum(inside(px + (sx + 0.5) / samples, py + (sy + 0.5) / samples)
                       for sy in range(samples) for sx in range(samples))
            image.putpixel((px, py), (255, 255, 255, round(255 * hits / samples ** 2)))
    return image


def disc(size=64, samples=4):
    """A filled circle touching the square's edges: a switch's knob, the status dots, and parts for round shapes."""
    r = size / 2
    return coverage(size, size, lambda x, y: (x - r) ** 2 + (y - r) ** 2 <= r * r, samples)


def ring(size, stroke, samples=16):
    """A circle's outline `stroke` pixels wide, touching the square's edges: parts for rounded controls' rims."""
    r = size / 2
    return coverage(size, size, lambda x, y: (r - stroke) ** 2 < (x - r) ** 2 + (y - r) ** 2 <= r * r, samples)


# The game blends in gamma space, so a half-covered edge pixel of a light shape on a dark ground looks less than half
# lit: thin light outlines look broken on curves. Weighting coverage evens it out: 1 - (1 - a)^BOLD lifts half-covered
# pixels most and leaves barely covered ones faint (a gamma curve would lift those too, into a ghost line).
BOLD = 2.2


def weighted(image, weight=BOLD):
    image.putalpha(image.getchannel('A').point(lambda a: round(255 * (1 - (1 - a / 255) ** weight))))
    return image


# Round shapes, in screen pixels: Art/RoundSizes holds the disc and Art/RingSizes the ring (a 64-pixel row for each
# stroke, 1 and 2 pixels) at every even size from 2 to ROUND_MAX, side by side with a pixel between them (Widgets.lua's
# FitRound has the same layout). Even, so halves and quarters end on a texel.
ROUND_MAX = 62


def round_atlas(rows):
    atlas = Image.new('RGBA', (1024, 64 * len(rows)), (255, 255, 255, 0))
    for row, draw in enumerate(rows):
        x = 0
        for n in range(2, ROUND_MAX + 1, 2):
            atlas.paste(draw(n), (x, row * 64))
            x += n + 1
    return atlas


def chevron(size=64, thickness=0.11, samples=4):
    """A right-pointing chevron with round ends; turned in game to point other ways."""
    points = [(0.38, 0.18), (0.66, 0.5), (0.38, 0.82)]
    t = thickness * size

    def near(x, y):
        for (ax, ay), (bx, by) in zip(points, points[1:]):
            ax, ay, bx, by = ax * size, ay * size, bx * size, by * size
            dx, dy = bx - ax, by - ay
            k = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
            if (x - ax - k * dx) ** 2 + (y - ay - k * dy) ** 2 <= t * t:
                return True
        return False
    return coverage(size, size, near, samples)


# Icon sizes, in screen pixels: Art/Close and each Art/<name>Sizes hold the icon drawn at every size from SIZES_MIN to
# SIZES_MAX, side by side with a pixel between them, so the game can show the one that maps texel for texel onto the
# screen (Widgets.lua's FitIcon has the same layout). Bigger, it scales down the 64-pixel Art/<name>.
SIZES_MIN, SIZES_MAX = 2, 32


def sizes_atlas(draw):
    atlas = Image.new('RGBA', (1024, 32), (255, 255, 255, 0))
    x = 0
    for n in range(SIZES_MIN, SIZES_MAX + 1):
        atlas.paste(draw(n), (x, 0))
        x += n + 1
    return atlas


def close_x(n):
    """An n-by-n X: both diagonals through pixel centers, cut square by the box, so it has all eight symmetries of the
    square. Lines are a pixel's diagonal wide (on-line pixels solid, their neighbors half), twice that from 20 pixels."""
    half = (math.sqrt(2) if n < 20 else 2 * math.sqrt(2)) / 2
    return coverage(n, n, lambda x, y: min(abs(x - y), abs(x + y - n)) / math.sqrt(2) <= half, samples=16)


def magnifier(size=64, samples=4, radius=0.27, stroke=0.085, handle=0.105):
    """A magnifying glass, the lens up and left and the handle down to the right: search's icon."""
    cx = cy = 0.42 * size
    r, s, h = radius * size, stroke * size / 2, handle * size / 2
    a, b = (cx + (r + s) * 0.7071, cy + (r + s) * 0.7071), (0.86 * size, 0.86 * size)

    def inside(x, y):
        d = math.hypot(x - cx, y - cy)
        if abs(d - r) <= s:
            return True
        dx, dy = b[0] - a[0], b[1] - a[1]
        k = max(0.0, min(1.0, ((x - a[0]) * dx + (y - a[1]) * dy) / (dx * dx + dy * dy)))
        return (x - a[0] - k * dx) ** 2 + (y - a[1] - k * dy) ** 2 <= h * h
    return coverage(size, size, inside, samples)


def grip(size=64):
    """The window's resize grip: six dots in a triangle filling the lower right corner, square at small sizes so each
    is whole pixels."""
    image = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    cell = size / 3
    dot = max(2, round(cell * 0.5))
    from PIL import ImageDraw
    draw = ImageDraw.Draw(image)
    for row in range(3):
        for col in range(3):
            if row + col >= 2:
                x, y = round(col * cell + (cell - dot) / 2), round(row * cell + (cell - dot) / 2)
                draw.rounded_rectangle([x, y, x + dot - 1, y + dot - 1], radius=dot // 4 if dot >= 6 else 0,
                                       fill=(255, 255, 255, 255))
    return image


def heart(size=64, samples=4):
    """Heart from the curve (x^2 + y^2 - 1)^3 = x^2 y^3, antialiased by supersampling."""
    image = Image.new('RGBA', (size, size))
    for py in range(size):
        for px in range(size):
            hits = 0
            for sy in range(samples):
                for sx in range(samples):
                    x = ((px + (sx + 0.5) / samples) / size - 0.5) * 2.7
                    y = (0.5 - (py + (sy + 0.5) / samples) / size) * 2.7 + 0.15
                    if (x * x + y * y - 1) ** 3 - x * x * y ** 3 <= 0:
                        hits += 1
            image.putpixel((px, py), (255, 255, 255, round(255 * hits / samples ** 2)))
    return image


# The burnt page is drawn with nine-slice rendering: a MARGIN-wide rim (the corners and edges) around a center that
# tiles. Everything the rim does (the ragged burnt edge, charring, scorch) fades out before the center starts, and all
# noise repeats every PERIOD pixels from the rim, so edges and center tile seamlessly at any window size.
PAGE_SIZE, PAGE_MARGIN = 272, 20
PAGE_PERIOD = PAGE_SIZE - 2 * PAGE_MARGIN


def tiling_noise(cells_x, cells_y, seed):
    """Value noise on a cells_x by cells_y lattice spanning one PAGE_PERIOD, wrapping at its edges; 0..1."""
    rng = random.Random(seed)
    grid = [[rng.random() for _ in range(cells_x)] for _ in range(cells_y)]

    def sample(u, v):
        u, v = u / PAGE_PERIOD * cells_x, v / PAGE_PERIOD * cells_y
        x0, y0 = math.floor(u), math.floor(v)
        fx, fy = u - x0, v - y0
        sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        x0, y0 = x0 % cells_x, y0 % cells_y
        x1, y1 = (x0 + 1) % cells_x, (y0 + 1) % cells_y
        top = grid[y0][x0] + (grid[y0][x1] - grid[y0][x0]) * sx
        bottom = grid[y1][x0] + (grid[y1][x1] - grid[y1][x0]) * sx
        return top + (bottom - top) * sy
    return sample


def burnt_page():
    """The page (grey paper grain, darkened toward a ragged burnt edge; tinted with the page color) and its scorch (black
    char at the edge turning to white scorch just inside it; tinted with the scorch color and drawn over the page at
    its own strength, so the burn stays bold on a faint page), as two images with the same outline."""
    # Lattice sizes divide PAGE_PERIOD (232 = 8 x 29) so every octave wraps.
    broad, blotch, grain, fine = tiling_noise(4, 4, 1), tiling_noise(8, 8, 2), tiling_noise(29, 29, 3), tiling_noise(116, 116, 4)
    fiber = tiling_noise(8, 58, 5)  # long horizontal fibers
    ragged, jagged, spots = tiling_noise(8, 8, 6), tiling_noise(29, 29, 7), tiling_noise(29, 29, 8)
    bites, frays = tiling_noise(8, 8, 9), tiling_noise(116, 116, 10)
    page, scorch = Image.new('RGBA', (PAGE_SIZE, PAGE_SIZE)), Image.new('RGBA', (PAGE_SIZE, PAGE_SIZE))
    m = PAGE_MARGIN
    for py in range(PAGE_SIZE):
        for px in range(PAGE_SIZE):
            x, y = px + 0.5, py + 0.5
            u, v = x - m, y - m
            # Depth into the page from its outer edge; corners are slightly rounded.
            ex, ey, r = min(x, PAGE_SIZE - x), min(y, PAGE_SIZE - y), 8
            depth = r - math.hypot(r - ex, r - ey) if ex < r and ey < r else min(ex, ey)
            # The burnt edge wanders 1 to 11 pixels in, with the odd deeper bite; charring and scorch reach 7 pixels
            # past it, so the rim is plain paper again before the center.
            edge = 0.5 + 8 * (0.55 * ragged(u, v) + 0.3 * jagged(u, v) + 0.15 * frays(u, v))
            edge += 3.5 * max(0.0, bites(u, v) - 0.6) / 0.4
            inside = depth - edge
            alpha = min(1.0, max(0.0, inside))
            char = max(0.0, 1 - inside / 7) ** 1.5
            burn = max(0.0, 1 - inside / 7) ** 1.2 * (0.7 + 0.3 * spots(u, v))
            ember = min(1.0, max(0.0, (inside - 0.5) / 3)) ** 1.5
            light = (0.84 + 0.12 * (broad(u, v) - 0.5) + 0.10 * (grain(u, v) - 0.5) + 0.09 * (fiber(u, v) - 0.5)
                     + 0.06 * (fine(u, v) - 0.5) - 0.2 * max(0.0, blotch(u, v) - 0.55) / 0.45)
            light *= 1 - 0.92 * char
            grey = round(255 * min(1.0, max(0.0, light)))
            page.putpixel((px, py), (grey, grey, grey, round(255 * alpha)))
            glow = round(255 * ember)
            scorch.putpixel((px, py), (glow, glow, glow, round(255 * alpha * min(1.0, burn))))
    return page, scorch


def nine_slice(image, width, height, margin=PAGE_MARGIN):
    """How the game draws image at width x height with tiled nine-slice rendering (for previews)."""
    size = image.size[0]
    out = Image.new('RGBA', (width, height))
    inner, target_w, target_h = size - 2 * margin, width - 2 * margin, height - 2 * margin
    for oy in range(height):
        sy = oy if oy < margin else size - (height - oy) if oy >= height - margin else margin + (oy - margin) % inner
        for ox in range(width):
            sx = ox if ox < margin else size - (width - ox) if ox >= width - margin else margin + (ox - margin) % inner
            out.putpixel((ox, oy), image.getpixel((sx, sy)))
    return out


def tint(image, color, opacity=1.0):
    r, g, b = color
    out = Image.new('RGBA', image.size)
    for y in range(image.size[1]):
        for x in range(image.size[0]):
            grey, _, _, a = image.getpixel((x, y))
            k = grey / 255
            out.putpixel((x, y), (round(r * k), round(g * k), round(b * k), round(a * opacity)))
    return out


def page_preview(page, scorch, path):
    """The page at the Loot Window's default colors and 50% opacity, at a few window sizes, over a busy backdrop."""
    backdrop = Image.new('RGBA', (520, 420))
    rng = random.Random(9)
    for y in range(420):
        for x in range(520):
            n = rng.random() * 30
            backdrop.putpixel((x, y), (round(52 + n), round(78 + n), round(34 + n / 2), 255))
    y = 10
    for width, height in [(220, 150), (400, 60), (160, 40), (300, 120)]:
        layer = tint(nine_slice(page, width, height), (84, 66, 48), 0.5)
        layer.alpha_composite(tint(nine_slice(scorch, width, height), (150, 72, 24), 0.9))
        backdrop.alpha_composite(layer, (10, y))
        y += height + 12
    backdrop.resize((1040, 840), Image.NEAREST).save(path)
    print(f'Preview: {path}')


if __name__ == '__main__':
    ART.mkdir(exist_ok=True)
    images = {'Cog': cog(), 'GitHub': svg_icon(GITHUB_PATH), 'Heart': heart(), 'Chevron': chevron(), 'Logo': logo(),
              'LogoWhite': logo(color=LOGO_WHITE), 'LogoOff': logo_off(), 'Search': magnifier(),
              'LogoSearch': logo_search(), 'Grip': grip()}
    # Every size drawn on its own pixel grid, with fine supersampling since the pixels are few.
    rounds = {
        'RoundSizes': [lambda n: weighted(disc(n, samples=16))],
        'RingSizes': [lambda n: weighted(ring(n, 1)), lambda n: weighted(ring(n, 2))],
    }
    for name, rows in rounds.items():
        image = round_atlas(rows)
        image.save(ART / f'{name}.tga')
        print(f'Wrote {ART / (name + ".tga")} ({image.size[0]}x{image.size[1]})')
    atlases = {
        'Close': close_x,
        'ChevronSizes': lambda n: chevron(n, samples=16),
        'GitHubSizes': lambda n: svg_icon(GITHUB_PATH, size=n, samples=16),
        'HeartSizes': lambda n: heart(n, samples=16),
        'LogoSizes': lambda n: logo(n, samples=16),
        'LogoWhiteSizes': lambda n: logo(n, samples=16, color=LOGO_WHITE),
        'LogoOffSizes': lambda n: logo_off(n, samples=16),
        'SearchSizes': lambda n: weighted(magnifier(n, samples=16)),
        'LogoSearchSizes': lambda n: logo_search(n, samples=16),
        'GripSizes': grip,
    }
    for name, draw in atlases.items():
        sizes_atlas(draw).save(ART / f'{name}.tga')
        print(f'Wrote {ART / (name + ".tga")} (1024x32)')
    for name, image in images.items():
        image.save(ART / f'{name}.tga')  # uncompressed 32-bit with alpha
        print(f'Wrote {ART / (name + ".tga")} ({image.size[0]}x{image.size[1]})')
    page, scorch = burnt_page()
    for name, image in {'LootPage': page, 'LootScorch': scorch}.items():
        image.save(ART / f'{name}.tga')
        print(f'Wrote {ART / (name + ".tga")} ({image.size[0]}x{image.size[1]})')
    if len(sys.argv) > 2:
        page_preview(page, scorch, sys.argv[2])
    if len(sys.argv) > 1:
        # Preview on the window's row color at a few sizes, tinted like the settings window.
        sheet = Image.new('RGBA', (200, 72 * len(images)), (24, 20, 18, 255))
        for row, image in enumerate(images.values()):
            x = 8
            for size, color in [(16, (168, 140, 110)), (16, (255, 204, 102)), (32, (168, 140, 110)), (64, (255, 204, 102))]:
                icon = image.resize((size, size), Image.LANCZOS)
                tinted = Image.new('RGBA', icon.size, color + (0,))
                tinted.putalpha(icon.getchannel('A'))
                sheet.alpha_composite(tinted, (x, row * 72 + (72 - size) // 2))
                x += size + 12
        sheet.resize((600, 216 * len(images)), Image.NEAREST).save(sys.argv[1])
        print(f'Preview: {sys.argv[1]}')
