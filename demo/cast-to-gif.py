#!/usr/bin/env python3
"""
cka-practice · demo/cast-to-gif.py

Render an asciicast v2 recording to an animated GIF.

    python3 demo/cast-to-gif.py demo/out/foo.cast demo/out/foo.gif

This is a stand-in for `agg`, which is the tool demo/README.md recommends and
which needs a Rust toolchain to install. This needs pyte and Pillow:

    pip install pyte pillow

It works the way agg does: replay the cast through a terminal emulator (pyte),
sample the screen, and write one GIF frame per distinct screen with a duration
taken from the cast's own timings. Identical consecutive screens collapse into
one long frame, which is why a recording with long pauses costs almost nothing
and one with fast scrolling costs a lot — the same trade-off demo/README.md
describes.
"""
import json
import sys
from pathlib import Path

import pyte
from PIL import Image, ImageDraw, ImageFont

# The asciinema palette, so the output matches what `agg --theme asciinema`
# produces and what the exam scripts were designed against.
BG = (18, 18, 18)
FG = (204, 204, 204)
PALETTE = {
    "black": (18, 18, 18),      "red": (221, 60, 105),
    "green": (77, 204, 102),    "brown": (240, 195, 100),
    "blue": (91, 158, 232),     "magenta": (185, 121, 235),
    "cyan": (77, 189, 202),     "white": (204, 204, 204),
    "brightblack": (110, 110, 110), "brightred": (255, 116, 133),
    "brightgreen": (140, 232, 140), "brightbrown": (255, 224, 140),
    "brightblue": (140, 190, 255), "brightmagenta": (215, 170, 255),
    "brightcyan": (140, 220, 232), "brightwhite": (255, 255, 255),
}

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf",
    "/System/Library/Fonts/Menlo.ttc",
]
FONT_BOLD_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
    "/usr/share/fonts/truetype/liberation2/LiberationMono-Bold.ttf",
]


def _font(cands, size):
    for c in cands:
        if Path(c).exists():
            return ImageFont.truetype(c, size)
    return ImageFont.load_default()


def colour(name, default):
    if not name or name == "default":
        return default
    if name in PALETTE:
        return PALETTE[name]
    # pyte hands back bare hex for 256-colour and truecolour codes.
    try:
        return tuple(int(name[i:i + 2], 16) for i in (0, 2, 4))
    except (ValueError, IndexError):
        return default


def render(cast_path, gif_path, font_size=15, fps=10, pad=12):
    lines = Path(cast_path).read_text(encoding="utf-8").splitlines()
    header = json.loads(lines[0])
    cols, rows = header.get("width", 100), header.get("height", 30)
    events = [json.loads(l) for l in lines[1:] if l.strip()]
    events = [e for e in events if len(e) >= 3 and e[1] == "o"]

    screen = pyte.Screen(cols, rows)
    stream = pyte.Stream(screen)

    font = _font(FONT_CANDIDATES, font_size)
    bold = _font(FONT_BOLD_CANDIDATES, font_size)
    cw = int(round(font.getlength("M"))) or font_size * 3 // 5
    ch = int(font_size * 1.35)
    W, H = cols * cw + pad * 2, rows * ch + pad * 2

    def snapshot():
        """Draw the emulator's current screen."""
        img = Image.new("RGB", (W, H), BG)
        d = ImageDraw.Draw(img)
        for y in range(rows):
            row = screen.buffer[y]
            for x in range(cols):
                c = row[x]
                if c.data in ("", " ") and c.bg == "default":
                    continue
                fg = colour(c.fg, FG)
                bg = colour(c.bg, BG)
                if c.reverse:
                    fg, bg = bg, fg
                px, py = pad + x * cw, pad + y * ch
                if bg != BG:
                    d.rectangle([px, py, px + cw, py + ch], fill=bg)
                if c.data.strip():
                    d.text((px, py), c.data, font=bold if c.bold else font, fill=fg)
        return img

    # Replay, sampling on a fixed grid so pauses become long frames.
    frames, durations = [], []
    step = 1.0 / fps
    t = 0.0
    idx = 0
    last = None
    end = events[-1][0] if events else 0.0
    while t <= end + step:
        while idx < len(events) and events[idx][0] <= t:
            stream.feed(events[idx][2])
            idx += 1
        key = "\n".join(screen.display) + repr(sorted(
            (y, x, screen.buffer[y][x].fg, screen.buffer[y][x].bold)
            for y in range(rows) for x in range(cols)
            if screen.buffer[y][x].data.strip()
        ))
        if key == last and frames:
            durations[-1] += step          # same screen: extend, do not redraw
        else:
            frames.append(snapshot())
            durations.append(step)
            last = key
        t += step

    durations[-1] = max(durations[-1], 2.5)   # hold the final frame
    frames[0].save(
        gif_path, save_all=True, append_images=frames[1:],
        duration=[int(d * 1000) for d in durations], loop=0, optimize=True,
    )
    print(f"  {gif_path}  {len(frames)} frames  "
          f"{sum(durations):.1f}s  {Path(gif_path).stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: cast-to-gif.py IN.cast OUT.gif [font_size] [fps]")
    render(sys.argv[1], sys.argv[2],
           font_size=int(sys.argv[3]) if len(sys.argv) > 3 else 15,
           fps=int(sys.argv[4]) if len(sys.argv) > 4 else 10)
