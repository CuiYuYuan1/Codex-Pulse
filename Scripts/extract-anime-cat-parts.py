#!/usr/bin/env python3
"""Extract the approved anime cat puppet pieces from its generated parts sheet."""

from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tmp/imagegen/anime-cat/parts-alpha.png"
WHOLE_SOURCE = ROOT / "tmp/imagegen/anime-cat/whole-alpha/anime-cat-whole.png"
WALK_FRAMES = ROOT / "tmp/imagegen/anime-cat/walk-run/frames/running-right"
ACTION_SOURCE = ROOT / "tmp/imagegen/anime-cat/action-run/actions-alpha.png"
OUTPUTS = (
    ROOT / "CodexPulse/Resources/AnimeCat",
    ROOT / "windows/src/renderer/assets/anime-cat",
)

# Stable regions in the approved 1400×1124 source sheet. Each region contains
# exactly one complete, non-overlapping puppet component.
REGIONS = {
    "head": (35, 25, 555, 535),
    "body": (590, 165, 1050, 560),
    "tail": (1050, 125, 1365, 535),
    "front-near": (95, 585, 285, 1020),
    "front-far": (275, 585, 485, 1025),
    "hind-near": (500, 575, 715, 1025),
    "hind-far": (705, 575, 940, 1035),
    "ruff": (970, 690, 1360, 1010),
}
ACTION_NAMES = (
    "idle",
    "thinking",
    "working",
    "waiting-auth",
    "sleeping",
    "stretch",
    "grooming",
    "wave",
)


def trimmed(image: Image.Image, padding: int = 10) -> Image.Image:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError("empty anime cat component")
    left, top, right, bottom = bounds
    left = max(0, left - padding)
    top = max(0, top - padding)
    right = min(image.width, right + padding)
    bottom = min(image.height, bottom + padding)
    return image.crop((left, top, right, bottom))


def normalized_cell(image: Image.Image) -> Image.Image:
    """Fit one complete pose to the same 192×208 stage and foot baseline."""
    pose = trimmed(image, padding=6)
    scale = min(182 / pose.width, 198 / pose.height)
    size = (
        max(1, round(pose.width * scale)),
        max(1, round(pose.height * scale)),
    )
    pose = pose.resize(size, Image.Resampling.LANCZOS)
    cell = Image.new("RGBA", (192, 208))
    x = (cell.width - pose.width) // 2
    y = 203 - pose.height
    cell.alpha_composite(pose, (x, y))
    return cell


def main() -> None:
    sheet = Image.open(SOURCE).convert("RGBA")
    for output in OUTPUTS:
        output.mkdir(parents=True, exist_ok=True)

    # The approved master illustration is the runtime identity source. Keep it
    # intact so facial proportions and fur detail cannot drift when animated.
    whole = trimmed(Image.open(WHOLE_SOURCE).convert("RGBA"), padding=14)
    for output in OUTPUTS:
        destination = output / "anime-cat-whole.png"
        whole.save(destination, optimize=True)
        print(destination.relative_to(ROOT))

    # A complete pose sequence avoids the sliding effect of moving one rigid
    # illustration across the desktop. Mirror each approved rightward pose in
    # place so left/right retain identical cadence and identity.
    for index in range(8):
        right = Image.open(WALK_FRAMES / f"{index:02d}.png").convert("RGBA")
        left = right.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        for output in OUTPUTS:
            for direction, frame in (("right", right), ("left", left)):
                destination = output / f"anime-cat-walk-{direction}-{index}.png"
                frame.save(destination, optimize=True)
                print(destination.relative_to(ROOT))

    action_sheet = Image.open(ACTION_SOURCE).convert("RGBA")
    cell_width = action_sheet.width // 4
    cell_height = action_sheet.height // 2
    for index, name in enumerate(ACTION_NAMES):
        column, row = index % 4, index // 4
        region = (
            column * cell_width,
            row * cell_height,
            (column + 1) * cell_width,
            (row + 1) * cell_height,
        )
        action = normalized_cell(action_sheet.crop(region))
        for output in OUTPUTS:
            destination = output / f"anime-cat-state-{name}.png"
            action.save(destination, optimize=True)
            print(destination.relative_to(ROOT))

    # Retain the authored pieces for future rig experiments, but the shipping
    # renderer deliberately uses the intact master until a pose set passes the
    # full identity and motion QA gates.
    for name, region in REGIONS.items():
        component = trimmed(sheet.crop(region))
        for output in OUTPUTS:
            destination = output / f"anime-cat-{name}.png"
            component.save(destination, optimize=True)
            print(destination.relative_to(ROOT))


if __name__ == "__main__":
    main()
