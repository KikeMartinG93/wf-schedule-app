#!/usr/bin/env python3
"""Paint each alternate app icon's background with that theme's exact accent
from AppColorTheme.swift, leaving the calendar/clock (or classic wordmark)
artwork untouched — except the calendar's deep-green chrome, which is remapped
to the theme's deep tint so accents read cleanly.

Also builds AppIcon-classic-<theme> so the WF wordmark icon follows accent
while "WF Icon" mode is on.

Run from repo root:
  python3 scripts/recolor_app_icons.py
"""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "WFSchedule/App/Assets.xcassets"
SOURCES = ROOT / "scripts/icon_sources"
# Neutral green calendar master — flood-fill is reliable; we replace its background.
MASTER = SOURCES / "AppIcon.png"
CLASSIC_MASTER = SOURCES / "AppIcon-classic.png"

# Accents / deep tints must stay in lockstep with AppColorTheme.swift.
THEMES = {
    "green": {
        "accent": (0x31, 0xD1, 0x58),
        "deep": (0x00, 0x4E, 0x36),
        "path": ASSETS / "AppIcon.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic.appiconset/icon-1024.png",
    },
    "blue": {
        "accent": (0x3A, 0xA8, 0xE0),
        "deep": (0x0B, 0x2A, 0x4A),
        "path": ASSETS / "AppIcon-blue.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic-blue.appiconset/icon-1024.png",
    },
    "purple": {
        "accent": (0xA8, 0x55, 0xF7),
        "deep": (0x3B, 0x1E, 0x5E),
        "path": ASSETS / "AppIcon-purple.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic-purple.appiconset/icon-1024.png",
    },
    "rose": {
        "accent": (0xF4, 0x3F, 0x87),
        "deep": (0x5E, 0x1E, 0x3A),
        "path": ASSETS / "AppIcon-rose.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic-rose.appiconset/icon-1024.png",
    },
    "amber": {
        "accent": (0xFF, 0x9F, 0x1C),
        "deep": (0x5E, 0x35, 0x10),
        "path": ASSETS / "AppIcon-amber.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic-amber.appiconset/icon-1024.png",
    },
    "teal": {
        "accent": (0x2D, 0xD4, 0xBF),
        "deep": (0x07, 0x3B, 0x3A),
        "path": ASSETS / "AppIcon-teal.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic-teal.appiconset/icon-1024.png",
    },
    "crimson": {
        "accent": (0xEF, 0x44, 0x44),
        "deep": (0x5A, 0x14, 0x20),
        "path": ASSETS / "AppIcon-crimson.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic-crimson.appiconset/icon-1024.png",
    },
    "indigo": {
        "accent": (0x63, 0x66, 0xF1),
        "deep": (0x24, 0x1B, 0x5E),
        "path": ASSETS / "AppIcon-indigo.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic-indigo.appiconset/icon-1024.png",
    },
    "halloween": {
        # Pumpkin accent fills the icon; purple deep only shades the bottom.
        "accent": (0xFF, 0x7A, 0x0D),  # 1.00, 0.48, 0.05
        "deep": (0xA5, 0x2D, 0xF2),
        "path": ASSETS / "AppIcon-halloween.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic-halloween.appiconset/icon-1024.png",
    },
    "colorful": {
        # Primary selection accent (sky blue) — matches ThemeManager tint.
        "accent": (0x4F, 0xC3, 0xF7),
        "deep": (0x1A, 0x5A, 0x8A),
        "path": ASSETS / "AppIcon-colorful.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic-colorful.appiconset/icon-1024.png",
    },
    "rainbow": {
        # Same rule as every other theme: Home Screen icon fill = selection accent.
        # In-app Rainbow still morphs gradients; the icon stays identifiable.
        "accent": (0xFF, 0x85, 0x1E),  # 1.00, 0.52, 0.12
        "deep": (0x5B, 0x3A, 0xC9),
        "path": ASSETS / "AppIcon-rainbow.appiconset/icon-1024.png",
        "classic_path": ASSETS / "AppIcon-classic-rainbow.appiconset/icon-1024.png",
    },
}

# Deep green chrome in the calendar master (header, selected day, clock).
MASTER_DEEP = (0x00, 0x4E, 0x36)
# Classic wordmark background (forest green).
CLASSIC_BG = (59, 125, 85)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix(c1, c2, t: float):
    return tuple(int(lerp(c1[i], c2[i], t) + 0.5) for i in range(3))


def dist(a, b) -> float:
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def flood_background(img: Image.Image, step: float = 4.0) -> Image.Image:
    """Walk the smooth background from the corners. A hard edge (calendar
    header, clock, or wordmark) stops the walk so artwork is preserved."""
    px = img.load()
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    visited = bytearray(w * h)
    q = deque(
        [
            (0, 0),
            (w - 1, 0),
            (0, h - 1),
            (w - 1, h - 1),
            (w // 2, 0),
            (0, h // 2),
            (w - 1, h // 2),
        ]
    )
    while q:
        x, y = q.popleft()
        idx = y * w + x
        if visited[idx]:
            continue
        visited[idx] = 1
        mp[x, y] = 255
        here = px[x, y][:3]
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if not (0 <= nx < w and 0 <= ny < h):
                continue
            nidx = ny * w + nx
            if visited[nidx]:
                continue
            if dist(px[nx, ny][:3], here) <= step:
                q.append((nx, ny))
    return mask.filter(ImageFilter.GaussianBlur(radius=0.7))


def make_gradient(size: int, stops: list[tuple[int, int, int]]) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    n = len(stops) - 1
    for y in range(size):
        for x in range(size):
            t = min(1.0, max(0.0, (x + y) / (2 * (size - 1))))
            f = t * n
            i = min(n - 1, int(f))
            px[x, y] = mix(stops[i], stops[i + 1], f - i)
    return img.filter(ImageFilter.GaussianBlur(radius=8))


def shaded_background(size: int, accent, deep) -> Image.Image:
    """Mostly the accent; only a light bottom shade so Home Screen icons read
    as that theme's selection color."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    bottom = mix(accent, deep, 0.18)
    for y in range(size):
        t = (y / (size - 1)) ** 2.4
        row = mix(accent, bottom, t * 0.55)
        for x in range(size):
            px[x, y] = row
    return img


def composite(background: Image.Image, artwork: Image.Image, mask: Image.Image) -> Image.Image:
    bg = background.convert("RGBA")
    art_mask = ImageChops.invert(mask)
    art = artwork.convert("RGBA")
    art.putalpha(art_mask)
    return Image.alpha_composite(bg, art).convert("RGB")


def remap_near(img: Image.Image, src, dst, threshold: float = 42.0) -> Image.Image:
    """Replace pixels near `src` with `dst` (keeps white / light cells intact)."""
    out = img.convert("RGB")
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            # Skip near-white / pale cells so the calendar body stays light.
            if c[0] > 200 and c[1] > 200 and c[2] > 200:
                continue
            if dist(c, src) <= threshold:
                # Blend by how close we are so soft edges don't posterize.
                t = 1.0 - dist(c, src) / threshold
                px[x, y] = mix(c, dst, 0.55 + 0.45 * t)
    return out


def ensure_appiconset(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    contents = path.parent / "Contents.json"
    if not contents.exists():
        contents.write_text(
            """{
  "images": [
    {
      "filename": "icon-1024.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
"""
        )


def render_calendar(theme: dict, master: Image.Image, mask: Image.Image) -> Image.Image:
    size = master.size[0]
    if "gradient" in theme:
        background = make_gradient(size, theme["gradient"])
    else:
        background = shaded_background(size, theme["accent"], theme["deep"])
    composed = composite(background, master, mask)
    # Swap the calendar's deep-green chrome for this theme's deep tint.
    if theme["deep"] != MASTER_DEEP:
        composed = remap_near(composed, MASTER_DEEP, theme["deep"], threshold=48.0)
    return composed


def render_classic(theme: dict, master: Image.Image, mask: Image.Image) -> Image.Image:
    size = master.size[0]
    background = shaded_background(size, theme["accent"], theme["deep"])
    composed = composite(background, master, mask)
    # Letter counters (O holes) are closed islands the flood fill never reaches —
    # remap leftover forest green to the accent so holes match the new background.
    return remap_near(composed, CLASSIC_BG, theme["accent"], threshold=55.0)


def main() -> None:
    master = Image.open(MASTER).convert("RGB")
    mask = flood_background(master)
    classic = Image.open(CLASSIC_MASTER).convert("RGB")
    classic_mask = flood_background(classic, step=6.0)

    for name, theme in THEMES.items():
        ensure_appiconset(theme["path"])
        print(f"rendering calendar {name}")
        img = render_calendar(theme, master, mask)
        img.save(theme["path"], "PNG")
        if name != "green":
            (SOURCES / f"AppIcon-{name}.png").write_bytes(theme["path"].read_bytes())
        sample = img.getpixel((12, 12))
        accent = theme["accent"]
        print(f"  corner #{sample[0]:02X}{sample[1]:02X}{sample[2]:02X}  accent=#{accent[0]:02X}{accent[1]:02X}{accent[2]:02X}  Δ={dist(sample, accent):.1f}")

        ensure_appiconset(theme["classic_path"])
        print(f"rendering classic {name}")
        cimg = render_classic(theme, classic, classic_mask)
        cimg.save(theme["classic_path"], "PNG")
        csample = cimg.getpixel((12, 12))
        print(f"  corner #{csample[0]:02X}{csample[1]:02X}{csample[2]:02X}  Δ={dist(csample, accent):.1f}")


if __name__ == "__main__":
    main()
