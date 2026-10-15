"""Draws the addon's own art (white or grey on transparent, tinted in game) as 32-bit TGA files: icons, each also
drawn pixel for pixel at every small size (the disc's halves and quarters round the settings window's pills and
corners), the Loot Window's burnt page background, Campfire Helper's fire (in color), ring and glow, and
Appearance Collector's marks.

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
LOGO_COLOR = (245, 194, 50)  # gold: Logo, the addon list's icon; the settings window tints a white one by theme


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
                gap=0.045, color=(246, 241, 233), glass=LOGO_COLOR):
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
    square. Lines are one and a half pixel diagonals wide (on-line pixels solid, their neighbors mostly), twice that
    from 20 pixels, and weighted as the cog is, so the two weigh the same side by side."""
    half = (1.5 if n < 20 else 3) * math.sqrt(2) / 2
    return weighted(coverage(n, n, lambda x, y: min(abs(x - y), abs(x + y - n)) / math.sqrt(2) <= half, samples=16))


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


# Appearance Collector's marks, side by side in one atlas, in this order (the module's MARKS give each one's cell).
APPEARANCE_MARKS = ('hanger', 'shirt', 'sparkle', 'dot')


def appearance_marks(cell=32, samples=8, outline=2.5):
    """White marks (tinted in game) with a dark outline baked in, so they read on any item icon at 9 to 13 pixels.
    Each is drawn at supersampled size in a CELL-wide square, then shrunk by area average."""
    from PIL import ImageDraw, ImageFilter
    big = cell * samples
    pad = (outline + 1.5) * samples  # room for the outline inside each cell
    span = big - 2 * pad

    def at(x, y):  # a point in the mark's 0..1 box, in big pixels
        return (pad + x * span, pad + y * span)

    def mask(name):
        m = Image.new('L', (big, big))
        d = ImageDraw.Draw(m)
        if name == 'hanger':
            # A hook over a triangle with a crossbar: thick strokes, so it holds up small.
            w = 0.15 * span
            d.arc([at(0.36, 0.0), at(0.64, 0.30)], 180, 90, fill=255, width=round(w))
            d.line([at(0.5, 0.30), at(0.5, 0.36)], fill=255, width=round(w))
            d.line([at(0.5, 0.36), at(0.03, 0.84), at(0.97, 0.84), at(0.5, 0.36)], fill=255, width=round(w),
                   joint='curve')
        elif name == 'shirt':
            d.polygon([at(0.30, 0.06), at(0.42, 0.06), at(0.5, 0.18), at(0.58, 0.06), at(0.70, 0.06), at(1.0, 0.30),
                       at(0.86, 0.50), at(0.76, 0.42), at(0.76, 0.96), at(0.24, 0.96), at(0.24, 0.42),
                       at(0.14, 0.50), at(0.0, 0.30)], fill=255)
        elif name == 'sparkle':
            # A four-pointed star, and a small one up and to the right.
            def star(cx, cy, r, waist):
                points = []
                for i in range(8):
                    a, rr = math.pi * i / 4, r if i % 2 == 0 else waist
                    points.append(at(cx + rr * math.sin(a), cy - rr * math.cos(a)))
                d.polygon(points, fill=255)
            star(0.42, 0.58, 0.44, 0.15)
            star(0.84, 0.16, 0.18, 0.07)
        elif name == 'dot':
            d.ellipse([at(0.18, 0.18), at(0.82, 0.82)], fill=255)
        return m

    sheet = Image.new('RGBA', (cell * len(APPEARANCE_MARKS), cell), (0, 0, 0, 0))
    for i, name in enumerate(APPEARANCE_MARKS):
        shape = mask(name)
        grown = shape.filter(ImageFilter.MaxFilter(2 * round(outline * samples) + 1))
        dark = Image.new('RGBA', (big, big), (0, 0, 0, 0))
        dark.putalpha(grown.point(lambda v: round(v * 0.85)))
        white = Image.new('RGBA', (big, big), (255, 255, 255, 0))
        white.putalpha(shape)
        dark.alpha_composite(white)
        sheet.alpha_composite(dark.resize((cell, cell), Image.BOX), (i * cell, 0))
    return sheet


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


FIRE_FRAMES, FIRE_COLUMNS, FIRE_SIZE = 16, 4, 64


def _ramp(stops, t):
    t = min(1.0, max(0.0, t))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            k = (t - t0) / (t1 - t0) if t1 > t0 else 0
            return tuple(c0[i] + (c1[i] - c0[i]) * k for i in range(4))
    return stops[-1][1]


# Flame heat to color: dark red edges, orange body, yellow then near white core.
FLAME_RAMP = [(0.0, (150, 20, 5, 0)), (0.12, (190, 40, 8, 150)), (0.3, (240, 95, 15, 235)), (0.55, (255, 165, 35, 255)),
              (0.8, (255, 215, 80, 255)), (1.0, (255, 245, 190, 255))]


def campfire_fire(frames=FIRE_FRAMES, columns=FIRE_COLUMNS, size=FIRE_SIZE, samples=3):
    """A burning campfire as a looping flipbook (frames in rows of `columns`, left to right, top down): crossed logs
    with glowing embers and three flickering tongues of flame with sparks rising. In color; the game draws it as is.
    Every motion is a whole number of cycles per loop, so the last frame runs into the first."""
    rng = random.Random(11)
    rows = (frames + columns - 1) // columns
    atlas = Image.new('RGBA', (columns * size, rows * size))
    # Tongues: center x, height, base half-width, flicker phase, flicker cycles per loop.
    tongues = [(0.0, 0.64, 0.13, 0.0, 2), (-0.12, 0.42, 0.09, 1.7, 3), (0.13, 0.47, 0.09, 3.9, 3),
               (-0.05, 0.34, 0.08, 5.1, 4), (0.06, 0.52, 0.07, 2.6, 2)]
    # Sway: (amplitude, waves along the height, cycles per loop, phase).
    sway = [(0.045, 1.6, 1, 0.3), (0.025, 3.1, 2, 2.1), (0.012, 5.3, 3, 4.4)]
    # Erosion noise moving up the flame: (strength, x frequency, y frequency, cycles per loop, phase).
    erosion = [(0.22, 9.0, 7.0, 2, 0.0), (0.14, 17.0, 13.0, 3, 1.3), (0.08, 29.0, 23.0, 4, 2.9)]
    sparks = [(rng.uniform(-0.18, 0.18), rng.random(), rng.uniform(0.6, 1.4), rng.randint(1, 2)) for _ in range(5)]
    base = 0.30  # flames start this far up from the bottom (in frame heights), over the logs
    logs = [(-0.42, 0.17, 0.62, 0.055, (118, 74, 42)), (0.42, 0.17, 0.62, 0.055, (100, 62, 35)),
            (0.0, 0.12, 0.5, 0.05, (88, 55, 31))]  # angle, y, length, radius, color; drawn in order
    stones = [(-0.33, 0.07, 0.07, 0.045), (-0.17, 0.045, 0.07, 0.04), (0.0, 0.04, 0.07, 0.04), (0.17, 0.045, 0.07, 0.04),
              (0.33, 0.07, 0.07, 0.045)]  # x, y, half width, half height

    def log_color(x, y):
        """The logs, under the fire: (r, g, b, a) or None."""
        hit = None
        for sx0, sy0, rx, ry in stones:
            d = ((x - sx0) / rx) ** 2 + ((y - sy0) / ry) ** 2
            if d <= 1:
                grey = 70 + 40 * (1 - d) + 25 * max(0.0, (y - sy0) / ry)
                hit = (grey, grey * 0.95, grey * 0.9, 255)
        for angle, cy, length, radius, color in logs:
            ca, sa = math.cos(angle), math.sin(angle)
            u, v = (x * ca + (y - cy) * sa), (-x * sa + (y - cy) * ca)
            if abs(u) <= length / 2 and abs(v) <= radius:
                shade = 0.7 + 0.3 * (v / radius)  # lit from above
                if abs(v) > radius * 0.75 or abs(u) > length / 2 - 0.012:
                    shade *= 0.55  # dark rim
                elif abs(u) > length / 2 - 0.04:
                    shade *= 1.45  # end grain
                elif 0.5 + 0.5 * math.sin(u * 70 + v * 25) > 0.85:
                    shade *= 0.8  # bark
                c = tuple(min(255, ch * shade) for ch in color)
                hit = c + (255,)
        return hit

    for f in range(frames):
        t = f / frames
        tau = 2 * math.pi * t
        frame = Image.new('RGBA', (size, size))
        for py in range(size):
            for px in range(size):
                acc = [0.0, 0.0, 0.0, 0.0]
                for sy in range(samples):
                    for sx in range(samples):
                        x = (px + (sx + 0.5) / samples) / size - 0.5
                        y = 1 - (py + (sy + 0.5) / samples) / size  # 0 at the bottom
                        color = (0, 0, 0, 0)
                        # Ground glow under the logs.
                        g = max(0.0, 1 - math.hypot(x / 0.36, (y - 0.15) / 0.11))
                        if g > 0:
                            color = (255, 110, 25, 200 * g ** 1.5)
                        lc = log_color(x, y)
                        if lc:
                            # Embers glow on the logs near the fire's base.
                            heat = max(0.0, 1 - math.hypot(x / 0.2, (y - 0.2) / 0.08)) * (0.8 + 0.2 * math.sin(tau * 2 + x * 40))
                            lc = tuple(lc[i] + ((255, 120, 30)[i] - lc[i]) * heat * 0.8 for i in range(3)) + (255,)
                            color = lc
                        # Flames.
                        fy = y - base
                        heat = 0.0
                        if fy > -0.06:
                            h = max(0.0, fy)
                            dx = sum(a * math.sin(w * h * 2 * math.pi - c * tau + ph) for a, w, c, ph in sway) * h / 0.6
                            fx = x - dx
                            for cx, height, width, ph, cycles in tongues:
                                top = height * (1 + 0.12 * math.sin(cycles * tau + ph))
                                if fy >= top:
                                    continue
                                k = max(0.0, fy) / top
                                # Teardrop: widest a little above the base, a point at the top, rounded at the bottom.
                                half = width * (1 - k) ** 0.75 * (1 + 0.6 * k) if fy >= 0 else width * math.sqrt(max(0.0, 1 - (fy / 0.06) ** 2))
                                if half <= 0:
                                    continue
                                d = 1 - abs(fx - cx) / half
                                if d <= 0:
                                    continue
                                heat = max(heat, d ** 0.8 * (1 - k ** 3) * (1.0 if fy >= 0 else 0.9))
                            if heat > 0:
                                n = sum(s * (0.5 + 0.5 * math.sin(fx * fxq + (fy * fyq - c * tau) + ph)
                                             * math.sin(fy * fyq * 0.7 - c * tau + ph * 1.7)) for s, fxq, fyq, c, ph in erosion)
                                heat = heat * 1.05 * max(0.0, 1 - (x / 0.3) ** 2) - n * (0.4 + fy * 1.4)
                        if heat > 0:
                            fc = _ramp(FLAME_RAMP, heat)
                            a = fc[3] / 255
                            color = tuple(color[i] * (1 - a) + fc[i] * a for i in range(3)) + (max(color[3], fc[3]),)
                        # Sparks rising.
                        for sx0, ph, speed, cycles in sparks:
                            life = (t * cycles * speed + ph) % 1.0
                            spx = sx0 + 0.05 * math.sin(life * 9 + ph * 6)
                            spy = base + 0.25 + life * 0.62
                            r = 0.016 * (1 - life)
                            if r > 0 and (x - spx) ** 2 + (y - spy) ** 2 < r * r:
                                sa = 255 * (1 - life) ** 0.6
                                a = sa / 255
                                color = tuple(color[i] * (1 - a) + (255, 200, 90)[i] * a for i in range(3)) + (max(color[3], sa),)
                        for i in range(4):
                            acc[i] += color[i]
                n = samples * samples
                frame.putpixel((px, py), tuple(round(min(255, c / n)) for c in acc))
        atlas.paste(frame, ((f % columns) * size, (f // columns) * size))
    return atlas


def campfire_ring(size=128, stroke=0.13, samples=8, segments=0, gap=0.35, soft=0.0, rim=0.0):
    """A ring touching the square's edges, white: the campfire timer's track and its countdown (the game sweeps it).
    stroke is its width as a share of the radius times 2; segments splits it into that many pieces with gap (a share of
    each piece) between them; soft fades its edges over that share of the stroke; rim adds a thin outer line that far
    outside the ring's edge (a share of the radius), with the gap between left empty."""
    r = size / 2
    outer = r * (1 - rim) if rim else r
    inner = outer - r * 2 * stroke
    width = outer - inner
    image = Image.new('RGBA', (size, size))
    for py in range(size):
        for px in range(size):
            total = 0.0
            for sy in range(samples):
                for sx in range(samples):
                    x, y = px + (sx + 0.5) / samples - r, py + (sy + 0.5) / samples - r
                    d = math.hypot(x, y)
                    a = 0.0
                    if inner < d <= outer:
                        a = 1.0
                        if soft:
                            edge = min(d - inner, outer - d) / (width * soft)
                            a = min(1.0, edge)
                        if segments:
                            phase = (math.atan2(x, -y) / (2 * math.pi) * segments) % 1.0
                            if phase < gap / 2 or phase > 1 - gap / 2:
                                a = 0.0
                    elif rim and r * (1 - rim * 0.35) < d <= r:
                        a = 1.0
                    total += a
            image.putpixel((px, py), (255, 255, 255, round(255 * total / samples ** 2)))
    return image


# The rings to choose from (Campfire Helper's Ring setting): file name and how it's drawn.
CAMPFIRE_RINGS = {
    'CampfireRing': {},
    'CampfireRingThin': {'stroke': 0.06},
    'CampfireRingThick': {'stroke': 0.22},
    'CampfireRingSegmented': {'stroke': 0.13, 'segments': 12, 'gap': 0.22},
    'CampfireRingSoft': {'stroke': 0.16, 'soft': 0.5},
    'CampfireRingRimmed': {'stroke': 0.1, 'rim': 0.1},
}


def campfire_glow(size=128):
    """A soft round glow, white, fading to nothing at the edges: the campfire's warm light, tinted in game."""
    image = Image.new('RGBA', (size, size))
    r = size / 2
    for py in range(size):
        for px in range(size):
            d = math.hypot(px + 0.5 - r, py + 0.5 - r) / r
            a = max(0.0, 1 - d) ** 2
            image.putpixel((px, py), (255, 255, 255, round(255 * a)))
    return image


if __name__ == '__main__':
    ART.mkdir(exist_ok=True)
    images = {'Cog': cog(), 'GitHub': svg_icon(GITHUB_PATH), 'Heart': heart(), 'Chevron': chevron(), 'Logo': logo(),
              'LogoTint': logo(color=(255, 255, 255)),
              'LogoOff': logo_off(), 'Search': magnifier(),
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
        'CogSizes': lambda n: weighted(cog(n, samples=16)),
        'ChevronSizes': lambda n: chevron(n, samples=16),
        'GitHubSizes': lambda n: svg_icon(GITHUB_PATH, size=n, samples=16),
        'HeartSizes': lambda n: heart(n, samples=16),
        'LogoSizes': lambda n: logo(n, samples=16, color=(255, 255, 255)),
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
    image = appearance_marks()
    image.save(ART / 'AppearanceMarks.tga')
    print(f'Wrote {ART / "AppearanceMarks.tga"} ({image.size[0]}x{image.size[1]})')
    campfire = {'CampfireFire': campfire_fire(), 'CampfireGlow': campfire_glow()}
    campfire.update({name: campfire_ring(**args) for name, args in CAMPFIRE_RINGS.items()})
    for name, image in campfire.items():
        image.save(ART / f'{name}.tga')
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
