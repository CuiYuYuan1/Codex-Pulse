#!/usr/bin/env python3
"""Extract generated anime companion poses into stable runtime cells and QA media."""

from collections import deque
from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "tmp/imagegen/anime-pets"
MAC_OUTPUT = ROOT / "CodexPulse/Resources/AnimePets"
WINDOWS_OUTPUT = ROOT / "windows/src/renderer/assets/anime-pets"
QA_OUTPUT = ROOT / "output/anime-pets"
WORKING_OVERRIDE_ROOT = SOURCE_ROOT / "working-keyboards"
WORKING_SEQUENCE_PETS = ("cat", "dino", "bunny", "ghost", "robot", "fox")

PETS = ("dino", "bunny", "ghost", "robot", "fox")
STATE_NAMES = (
    "idle-0",
    "idle-1",
    "idle-2",
    "idle-3",
    "thinking-0",
    "thinking-1",
    "thinking-2",
    "thinking-3",
    "working",
    "waiting-auth",
    "success",
    "error",
    "sleeping",
    "stretch",
    "grooming",
    "curious",
)
PET_FRAME_MS = {
    "dino": 112,
    "bunny": 128,
    "ghost": 118,
    "robot": 104,
    "fox": 140,
}


def grid_cell(image: Image.Image, columns: int, rows: int, index: int) -> Image.Image:
    column = index % columns
    row = index // columns
    left = round(column * image.width / columns)
    top = round(row * image.height / rows)
    right = round((column + 1) * image.width / columns)
    bottom = round((row + 1) * image.height / rows)
    return image.crop((left, top, right, bottom))


def trim(image: Image.Image, padding: int = 8) -> Image.Image:
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("empty generated anime pet cell")
    left, top, right, bottom = bounds
    return image.crop(
        (
            max(0, left - padding),
            max(0, top - padding),
            min(image.width, right + padding),
            min(image.height, bottom + padding),
        )
    )


def remove_small_detached_components(
    image: Image.Image,
    keep_only_largest: bool = False,
) -> Image.Image:
    """Remove generator specks without touching substantial props or limbs."""
    result = image.copy()
    alpha = result.getchannel("A")
    width, height = result.size
    visible = alpha.load()
    visited = bytearray(width * height)
    components: list[list[tuple[int, int]]] = []

    for y in range(height):
        for x in range(width):
            offset = y * width + x
            if visited[offset] or visible[x, y] <= 12:
                continue
            visited[offset] = 1
            queue = deque([(x, y)])
            component: list[tuple[int, int]] = []
            while queue:
                current_x, current_y = queue.popleft()
                component.append((current_x, current_y))
                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if not (0 <= next_x < width and 0 <= next_y < height):
                        continue
                    next_offset = next_y * width + next_x
                    if visited[next_offset] or visible[next_x, next_y] <= 12:
                        continue
                    visited[next_offset] = 1
                    queue.append((next_x, next_y))
            components.append(component)

    if not components:
        return result
    largest = max(len(component) for component in components)
    minimum_area = largest if keep_only_largest else max(24, round(largest * 0.006))
    pixels = result.load()
    for component in components:
        if len(component) >= minimum_area:
            continue
        for x, y in component:
            red, green, blue, _ = pixels[x, y]
            pixels[x, y] = (red, green, blue, 0)
    return result


def normalize(image: Image.Image, keep_only_largest: bool = False) -> Image.Image:
    pose = trim(remove_small_detached_components(image, keep_only_largest))
    scale = min(182 / pose.width, 198 / pose.height)
    width = max(1, round(pose.width * scale))
    height = max(1, round(pose.height * scale))
    pose = pose.resize((width, height), Image.Resampling.LANCZOS)
    cell = Image.new("RGBA", (192, 208))
    cell.alpha_composite(pose, ((192 - width) // 2, 203 - height))
    return cell


def normalize_sequence(
    images: list[Image.Image],
    keep_only_largest: bool = False,
) -> list[Image.Image]:
    """Normalize a generated motion family with one shared scale and baseline."""
    poses = [
        trim(remove_small_detached_components(image, keep_only_largest))
        for image in images
    ]
    maximum_width = max(pose.width for pose in poses)
    maximum_height = max(pose.height for pose in poses)
    scale = min(182 / maximum_width, 198 / maximum_height)
    cells: list[Image.Image] = []
    for pose in poses:
        width = max(1, round(pose.width * scale))
        height = max(1, round(pose.height * scale))
        resized = pose.resize((width, height), Image.Resampling.LANCZOS)
        cell = Image.new("RGBA", (192, 208))
        cell.alpha_composite(resized, ((192 - width) // 2, 203 - height))
        cells.append(cell)
    return cells


def save_runtime(image: Image.Image, filename: str) -> None:
    for output in (MAC_OUTPUT, WINDOWS_OUTPUT):
        output.mkdir(parents=True, exist_ok=True)
        image.save(output / filename, optimize=True)


def build_pet(pet: str) -> tuple[list[Image.Image], list[Image.Image]]:
    states_sheet = Image.open(SOURCE_ROOT / f"{pet}-states-alpha.png").convert("RGBA")
    walk_sheet = Image.open(SOURCE_ROOT / f"{pet}-walk-alpha.png").convert("RGBA")

    states: list[Image.Image] = []
    for index, state in enumerate(STATE_NAMES):
        cell = normalize(grid_cell(states_sheet, 4, 4, index), keep_only_largest=True)
        if pet == "fox":
            cell.putalpha(cell.getchannel("A").point(lambda value: 0 if value <= 8 else value))
        states.append(cell)
        save_runtime(cell, f"anime-{pet}-state-{state}.png")

    walk_right: list[Image.Image] = []
    for index in range(8):
        cell = normalize(grid_cell(walk_sheet, 4, 2, index), keep_only_largest=True)
        if pet == "fox":
            cell.putalpha(cell.getchannel("A").point(lambda value: 0 if value <= 8 else value))
        walk_right.append(cell)
        save_runtime(cell, f"anime-{pet}-walk-right-{index}.png")
        save_runtime(
            cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT),
            f"anime-{pet}-walk-left-{index}.png",
        )
    return states, walk_right


def build_cat_thinking() -> list[Image.Image]:
    source = Image.open(SOURCE_ROOT / "cat-thinking-alpha.png").convert("RGBA")
    # Generated strips can bleed a sliver of the neighboring pose across a
    # cell boundary. The cat and its real tail form one connected silhouette,
    # so retaining only that largest component removes the detached flash.
    frames = [
        normalize(
            grid_cell(source, 4, 2, index),
            keep_only_largest=True,
        )
        for index in range(8)
    ]
    for index, frame in enumerate(frames):
        for output in (
            ROOT / "CodexPulse/Resources/AnimeCat",
            ROOT / "windows/src/renderer/assets/anime-cat",
        ):
            output.mkdir(parents=True, exist_ok=True)
            frame.save(output / f"anime-cat-state-thinking-{index}.png", optimize=True)
    return frames


def save_cat_runtime(image: Image.Image, filename: str) -> None:
    for output in (
        ROOT / "CodexPulse/Resources/AnimeCat",
        ROOT / "windows/src/renderer/assets/anime-cat",
    ):
        output.mkdir(parents=True, exist_ok=True)
        image.save(output / filename, optimize=True)


def build_working_sequences() -> dict[str, list[Image.Image]]:
    sequences: dict[str, list[Image.Image]] = {}
    for pet in WORKING_SEQUENCE_PETS:
        source = Image.open(
            SOURCE_ROOT / f"{pet}-working-eight-alpha.png"
        ).convert("RGBA")
        frames = normalize_sequence(
            [grid_cell(source, 4, 2, index) for index in range(8)],
            keep_only_largest=True,
        )
        sequences[pet] = frames
        for index, frame in enumerate(frames):
            if pet == "cat":
                save_cat_runtime(frame, f"anime-cat-state-working-{index}.png")
            else:
                save_runtime(frame, f"anime-{pet}-state-working-{index}.png")
    return sequences


def build_fox_idle_sequence() -> list[Image.Image]:
    source = Image.open(SOURCE_ROOT / "fox-idle-eight-alpha.png").convert("RGBA")
    frames = normalize_sequence(
        [grid_cell(source, 4, 2, index) for index in range(8)],
        keep_only_largest=True,
    )
    for index, frame in enumerate(frames):
        save_runtime(frame, f"anime-fox-state-idle-loop-{index}.png")
    return frames


def install_working_overrides(all_states: dict[str, list[Image.Image]]) -> None:
    """Install the approved keyboard-working pose without rebuilding other states."""
    for pet in PETS:
        source = WORKING_OVERRIDE_ROOT / f"{pet}-working-alpha.png"
        if not source.exists():
            continue
        frame = normalize(Image.open(source).convert("RGBA"), keep_only_largest=True)
        all_states[pet][STATE_NAMES.index("working")] = frame
        save_runtime(frame, f"anime-{pet}-state-working.png")


def contact_sheet(all_states: dict[str, list[Image.Image]], cat_thinking: list[Image.Image]) -> None:
    labels = (*PETS, "cat-thinking")
    groups = [all_states[pet] for pet in PETS] + [cat_thinking]
    canvas = Image.new("RGB", (4 * 208, len(groups) * 236), "#152035")
    draw = ImageDraw.Draw(canvas)
    for row, (label, frames) in enumerate(zip(labels, groups)):
        draw.text((10, row * 236 + 6), label, fill="white")
        for column, frame in enumerate(frames[:4]):
            stage = Image.new("RGBA", (208, 208), (0, 0, 0, 0))
            stage.alpha_composite(frame, (8, 0))
            canvas.paste(stage, (column * 208, row * 236 + 28), stage)
    canvas.save(QA_OUTPUT / "state-contact-sheet.png", optimize=True)


def working_contact_sheet(all_states: dict[str, list[Image.Image]]) -> None:
    canvas = Image.new("RGB", (len(PETS) * 224, 246), "#152035")
    draw = ImageDraw.Draw(canvas)
    working_index = STATE_NAMES.index("working")
    for column, pet in enumerate(PETS):
        draw.text((column * 224 + 10, 8), pet, fill="white")
        frame = all_states[pet][working_index]
        canvas.paste(frame, (column * 224 + 16, 30), frame)
    canvas.save(QA_OUTPUT / "working-keyboards-contact-sheet.png", optimize=True)


def motion_preview(
    name: str,
    frames: list[Image.Image],
    durations: list[int],
) -> None:
    preview_frames: list[Image.Image] = []
    for frame in frames:
        stage = Image.new("RGBA", (256, 224), (20, 30, 48, 255))
        stage.alpha_composite(frame, (32, 8))
        preview_frames.append(stage)
    preview_frames[0].save(
        QA_OUTPUT / f"{name}-preview.gif",
        save_all=True,
        append_images=preview_frames[1:],
        duration=durations,
        loop=0,
        disposal=2,
    )


def working_sequences_contact_sheet(
    sequences: dict[str, list[Image.Image]],
) -> None:
    canvas = Image.new(
        "RGB",
        (8 * 200, len(WORKING_SEQUENCE_PETS) * 232),
        "#152035",
    )
    draw = ImageDraw.Draw(canvas)
    for row, pet in enumerate(WORKING_SEQUENCE_PETS):
        draw.text((10, row * 232 + 6), pet, fill="white")
        for column, frame in enumerate(sequences[pet]):
            stage = Image.new("RGBA", (200, 208), (0, 0, 0, 0))
            stage.alpha_composite(frame, (4, 0))
            canvas.paste(stage, (column * 200, row * 232 + 24), stage)
    canvas.save(QA_OUTPUT / "working-sequences-contact-sheet.png", optimize=True)


def walk_preview(pet: str, frames: list[Image.Image]) -> None:
    preview_frames: list[Image.Image] = []
    for frame in frames:
        stage = Image.new("RGBA", (256, 224), (20, 30, 48, 255))
        stage.alpha_composite(frame, (32, 8))
        preview_frames.append(stage)
    preview_frames[0].save(
        QA_OUTPUT / f"{pet}-walk-preview.gif",
        save_all=True,
        append_images=preview_frames[1:],
        duration=PET_FRAME_MS[pet],
        loop=0,
        disposal=2,
    )


def walk_contact_sheet(all_walks: dict[str, list[Image.Image]]) -> None:
    canvas = Image.new("RGB", (8 * 200, len(PETS) * 232), "#152035")
    draw = ImageDraw.Draw(canvas)
    for row, pet in enumerate(PETS):
        draw.text((10, row * 232 + 6), pet, fill="white")
        for column, frame in enumerate(all_walks[pet]):
            stage = Image.new("RGBA", (200, 208), (0, 0, 0, 0))
            stage.alpha_composite(frame, (4, 0))
            canvas.paste(stage, (column * 200, row * 232 + 24), stage)
    canvas.save(QA_OUTPUT / "walk-contact-sheet.png", optimize=True)


def main() -> None:
    QA_OUTPUT.mkdir(parents=True, exist_ok=True)
    all_states: dict[str, list[Image.Image]] = {}
    all_walks: dict[str, list[Image.Image]] = {}
    for pet in PETS:
        states, walk = build_pet(pet)
        all_states[pet] = states
        all_walks[pet] = walk
        walk_preview(pet, walk)
    install_working_overrides(all_states)
    cat_thinking = build_cat_thinking()
    working_sequences = build_working_sequences()
    fox_idle = build_fox_idle_sequence()
    contact_sheet(all_states, cat_thinking)
    working_contact_sheet(all_states)
    working_sequences_contact_sheet(working_sequences)
    working_durations = [520, 220, 180, 340, 220, 180, 340, 800]
    for pet, frames in working_sequences.items():
        motion_preview(f"{pet}-working", frames, working_durations)
    motion_preview("fox-idle", fox_idle, [700] * 8)
    walk_contact_sheet(all_walks)
    print(f"runtime assets: {MAC_OUTPUT.relative_to(ROOT)}")
    print(f"runtime assets: {WINDOWS_OUTPUT.relative_to(ROOT)}")
    print(f"QA: {QA_OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
