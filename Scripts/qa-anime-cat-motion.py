#!/usr/bin/env python3
"""Build deterministic QA artifacts for the anime cat walk cycle."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
FRAMES = ROOT / "CodexPulse/Resources/AnimeCat"
OUTPUT = ROOT / "output/anime-cat-motion"
FRAME_DURATION_MS = 112  # 896 ms per complete gait cycle.
STATE_NAMES = (
    "idle",
    "thinking",
    "working",
    "waiting-auth",
    "sleeping",
    "stretch",
    "grooming",
    "wave",
)


def load_frames(direction: str) -> list[Image.Image]:
    return [
        Image.open(FRAMES / f"anime-cat-walk-{direction}-{index}.png").convert("RGBA")
        for index in range(8)
    ]


def metrics(frame: Image.Image, index: int) -> dict[str, object]:
    alpha = frame.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError(f"walk frame {index} is empty")
    left, top, right, bottom = bounds
    return {
        "index": index,
        "bbox": [left, top, right, bottom],
        "center_x": round((left + right) / 2, 2),
        "center_y": round((top + bottom) / 2, 2),
        "bottom": bottom,
        "opaque_area": sum(1 for value in alpha.get_flattened_data() if value > 8),
    }


def make_contact_sheet(frames: list[Image.Image]) -> Image.Image:
    cell_width, cell_height = 220, 240
    sheet = Image.new("RGBA", (cell_width * 4, cell_height * 2), "#152238")
    draw = ImageDraw.Draw(sheet)
    for index, frame in enumerate(frames):
        column, row = index % 4, index // 4
        x = column * cell_width + (cell_width - frame.width) // 2
        y = row * cell_height + 22
        sheet.alpha_composite(frame, (x, y))
        draw.text(
            (column * cell_width + 10, row * cell_height + 8),
            f"{index} · {index * FRAME_DURATION_MS}ms",
            fill="#EAF4FF",
        )
        baseline = row * cell_height + 22 + 203
        draw.line(
            (column * cell_width + 8, baseline, (column + 1) * cell_width - 8, baseline),
            fill="#43D7FF",
            width=1,
        )
    return sheet


def make_state_sheet() -> Image.Image:
    cell_width, cell_height = 220, 240
    sheet = Image.new("RGBA", (cell_width * 4, cell_height * 2), "#152238")
    draw = ImageDraw.Draw(sheet)
    for index, name in enumerate(STATE_NAMES):
        frame = Image.open(FRAMES / f"anime-cat-state-{name}.png").convert("RGBA")
        column, row = index % 4, index // 4
        x = column * cell_width + (cell_width - frame.width) // 2
        y = row * cell_height + 22
        sheet.alpha_composite(frame, (x, y))
        draw.text(
            (column * cell_width + 10, row * cell_height + 8),
            name,
            fill="#EAF4FF",
        )
    return sheet


def make_preview(frames: list[Image.Image]) -> list[Image.Image]:
    rendered: list[Image.Image] = []
    for frame in frames:
        canvas = Image.new("RGBA", (256, 240), "#152238")
        canvas.alpha_composite(frame, ((canvas.width - frame.width) // 2, 16))
        rendered.append(canvas.convert("P", palette=Image.Palette.ADAPTIVE))
    return rendered


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    frames = load_frames("right")
    report = {
        "ok": True,
        "frame_duration_ms": FRAME_DURATION_MS,
        "cycle_duration_ms": FRAME_DURATION_MS * len(frames),
        "frames": [metrics(frame, index) for index, frame in enumerate(frames)],
    }
    (OUTPUT / "walk-metrics.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    make_contact_sheet(frames).save(OUTPUT / "walk-contact-sheet.png", optimize=True)
    make_state_sheet().save(OUTPUT / "state-contact-sheet.png", optimize=True)
    preview = make_preview(frames)
    preview[0].save(
        OUTPUT / "walk-preview.gif",
        save_all=True,
        append_images=preview[1:],
        duration=FRAME_DURATION_MS,
        loop=0,
        disposal=2,
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
