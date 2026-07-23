#!/usr/bin/env python3
"""Build production GIFs from the generated 6×4 pixel-pet sprite sheets."""

from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = (
    ROOT / "CodexPulse/Resources/PetsV2",
    ROOT / "windows/src/renderer/assets/pets-v2",
)

CELL_STRIDE = 256
CELL_MARGIN = 8
CELL_CONTENT = 240  # Excludes chroma fringe and the generated grid gutter.
PET_SIZE = 280
CANVAS_SIZE = (480, 288)

ACTION_ROWS = {"idle": 0, "typing": 1, "scratch": 2, "auth": 3}

# Character-specific timing is intentional: pets share product states, not the
# same motion.  Uneven frame holds avoid the vibrating look of uniform GIFs.
PET_TIMINGS = {
    "dino": {
        "idle": [420, 320, 360, 500, 360, 650],
        "typing": [170, 145, 180, 230, 165, 320],
        "scratch": [280, 320, 430, 360, 320, 520],
        "auth": [260, 280, 320, 420, 300, 560],
    },
    "cat": {
        "idle": [400, 350, 420, 500, 480, 700],
        "typing": [190, 150, 210, 165, 220, 360],
        "scratch": [300, 360, 460, 420, 340, 600],
        "auth": [300, 260, 380, 300, 360, 580],
    },
    "bunny": {
        "idle": [420, 360, 440, 520, 480, 700],
        "typing": [210, 165, 220, 180, 240, 380],
        "scratch": [340, 420, 500, 440, 380, 640],
        "auth": [280, 320, 360, 380, 320, 600],
    },
    "ghost": {
        "idle": [360, 340, 380, 420, 460, 620],
        "typing": [230, 180, 240, 190, 250, 420],
        "scratch": [360, 420, 520, 460, 420, 680],
        "auth": [320, 360, 400, 360, 400, 620],
    },
    "robot": {
        "idle": [380, 340, 380, 420, 420, 600],
        "typing": [165, 140, 175, 145, 190, 320],
        "scratch": [280, 340, 400, 380, 320, 560],
        "auth": [240, 280, 320, 300, 340, 540],
    },
}


def gif_frame(image: Image.Image) -> Image.Image:
    """Quantize without sacrificing the transparent outer canvas."""
    alpha = image.getchannel("A")
    palette = image.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    transparent = alpha.point(lambda value: 255 if value <= 18 else 0)
    palette.paste(255, mask=transparent)
    palette.info["transparency"] = 255
    return palette


def action_frames(sheet: Image.Image, row: int, columns=range(6)) -> list[Image.Image]:
    frames: list[Image.Image] = []
    for column in columns:
        left = column * CELL_STRIDE + CELL_MARGIN
        top = row * CELL_STRIDE + CELL_MARGIN
        sprite = sheet.crop((left, top, left + CELL_CONTENT, top + CELL_CONTENT))
        sprite = sprite.resize((PET_SIZE, PET_SIZE), Image.Resampling.NEAREST)
        canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
        canvas.alpha_composite(sprite, (0, 4))
        frames.append(gif_frame(canvas))
    return frames


def main() -> None:
    for output in OUTPUTS:
        output.mkdir(parents=True, exist_ok=True)
    for pet, timings in PET_TIMINGS.items():
        source = ROOT / f"tmp/imagegen/{pet}-sprite-sheet-alpha.png"
        if not source.exists():
            raise FileNotFoundError(f"Missing generated sprite sheet: {source}")
        sheet = Image.open(source).convert("RGBA")
        for action, row in ACTION_ROWS.items():
            # Idle is a playful hands-off loop with the keyboard fully put away.
            # Typing frames are never reused by the idle state.
            frames = action_frames(sheet, row)
            for output in OUTPUTS:
                destination = output / f"codex_{pet}_v2_{action}.gif"
                frames[0].save(
                    destination,
                    save_all=True,
                    append_images=frames[1:],
                    duration=timings[action],
                    loop=0,
                    disposal=2,
                    transparency=255,
                    optimize=False,
                )
                print(destination.relative_to(ROOT))


if __name__ == "__main__":
    main()
