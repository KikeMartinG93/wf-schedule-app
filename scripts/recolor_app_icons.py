#!/usr/bin/env python3
"""Paint each alternate app icon's background with that theme's exact accent,
leaving the calendar/clock artwork untouched."""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "WFSchedule/App/Assets.xcassets"
SOURCES = ROOT / "scripts/icon_sources"

THEMES = {
    "green": {
        "accent": (0x31, 0xD1, 0x58),
        "deep": (0x00, 0x4E, 0x36),
        "source": SOURCES / "AppIcon.png",
        "path": ASSETS / "AppIcon.appiconset/icon-1024.png",
    },
    "blue": {
        "accent": (0x3A, 0xA8, 0xE0),
        "deep": (0x0B, 0x2A, 0x4A),
        "source": SOURCES / "AppIcon-blue.png",
        "path": ASSETS / "AppIcon-blue.appiconset/icon-1024.png",
    },
    "purple": {
        "accent": (0xA8, 0x55, 0xF7),
        "deep": (0x3B, 0x1E, 0x5E),
        "source": SOURCES / "AppIcon-purple.png",
        "path": ASSETS / "AppIcon-purple.appiconset/icon-1024.png",
    },
    "rose": {
        "accent": (0xF4, 0x3F, 0x87),
        "deep": (0x5E, 0x1E, 0x3A),
        "source": SOURCES / "AppIcon-rose.png",
        "path": ASSETS / "AppIcon-rose.appiconset/icon-1024.png",
    },
    "amber": {
        "accent": (0xFF, 0x9F, 0x1C),
        "deep": (0x5E, 0x35, 0x10),
        "source": SOURCES / "AppIcon-amber.png",
        "path": ASSETS / "AppIcon-amber.appiconset/icon-1024.png",
    },
    "teal": {
        "accent": (0x2D, 0xD4, 0xBF),
        "deep": (0x07, 0x3B, 0x3A),
        "source": SOURCES / "AppIcon-teal.png",
        "path": ASSETS / "AppIcon-teal.appiconset/icon-1024.png",
    },
    "crimson": {
        "accent": (0xEF, 0x44, 0x44),
        "deep": (0x5A, 0x14, 0x20),
        "source": SOURCES / "AppIcon-crimson.png",
        "path": ASSETS / "AppIcon-crimson.appiconset/icon-1024.png",
    },
    "indigo": {
        "accent": (0x63, 0x66, 0xF1),
        "deep": (0x24, 0x1B, 0x5E),
        "source": SOURCES / "AppIcon-indigo.png",
        "path": ASSETS / "AppIcon-indigo.appiconset/icon-1024.png",
    },
    "halloween": {
        "accent": (0xFF, 0x7A, 0x0D),
        "deep": (0xA5, 0x2D, 0xF2),
        "source": SOURCES / "AppIcon-halloween.png",
        "path": ASSETS / "AppIcon-halloween.appiconset/icon-1024.png",
        "gradient": [(0xFF, 0x7A, 0x0D), (0xA5, 0x2D, 0xF2)],
    },
    "colorful": {
        "accent": (0x4F, 0xC3, 0xF7),
        "deep": (0x5A, 0x57, 0x9A),
        "source": SOURCES / "AppIcon-colorful.png",
        "path": ASSETS / "AppIcon-colorful.appiconset/icon-1024.png",
        "gradient": [(0x4F, 0xC3, 0xF7), (0xA6, 0xB1, 0xE1), (0xF0, 0x60, 0x9E)],
    },
    "rainbow": {
        "accent": (0xFF, 0x85, 0x1E),
        "deep": (0x5B, 0x3A, 0xC9),
        "source": SOURCES / "AppIcon-colorful.png",
        "path": ASSETS / "AppIcon-rainbow.appiconset/icon-1024.png",
        "gradient": [
            (0xF2, 0x38, 0x51),
            (0xFF, 0x85, 0x1E),
            (0xFF, 0xD1, 0x29),
            (0x2D, 0xD4, 0xBF),
            (0x3A, 0xA8, 0xE0),
            (0xA8, 0x55, 0xF7),
        ],
    },
}


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def mix(c1, c2, t: float):
    return tuple(int(lerp(c1[i], c2[i], t) + 0.5) for i in range(3))


def dist(a, b) -> float:
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def flood_background(img: Image.Image, step: float = 4.0) -> Image.Image:
    """Walk the smooth background from the corners. A hard edge (calendar
    header, clock) stops the walk so artwork is preserved."""
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
    return img.filter(ImageFilter.GaussianBlur(radius=10))


def shaded_background(size: int, accent, deep) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = img.load()
    bottom = mix(accent, deep, 0.22)
    for y in range(size):
        t = (y / (size - 1)) ** 2
        row = mix(accent, bottom, t)
        for x in range(size):
            px[x, y] = row
    return img


def composite(background: Image.Image, artwork: Image.Image, mask: Image.Image) -> Image.Image:
    bg = background.convert("RGBA")
    art_mask = ImageChops.invert(mask)
    art = artwork.convert("RGBA")
    art.putalpha(art_mask)
    return Image.alpha_composite(bg, art).convert("RGB")


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


def render(theme: dict) -> Image.Image:
    src = Image.open(theme["source"]).convert("RGB")
    mask = flood_background(src)
    size = src.size[0]
    if "gradient" in theme:
        background = make_gradient(size, theme["gradient"])
    else:
        background = shaded_background(size, theme["accent"], theme["deep"])
    return composite(background, src, mask)


def main() -> None:
    for name, theme in THEMES.items():
        ensure_appiconset(theme["path"])
        print(f"rendering {name} ← {theme['source'].name}")
        img = render(theme)
        img.save(theme["path"], "PNG")
        sample = img.getpixel((12, 12))
        print(f"  corner #{sample[0]:02X}{sample[1]:02X}{sample[2]:02X}")


if __name__ == "__main__":
    main()
