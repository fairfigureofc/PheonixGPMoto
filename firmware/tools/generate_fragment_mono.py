#!/usr/bin/env python3
"""Generate compact LovyanGFX/Adafruit-GFX headers from Fragment Mono."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = ROOT / "assets/fonts/FragmentMono-Regular.ttf"
OUTPUT_PATH = ROOT / "PheonixMotoDisplay/fragment_mono.hpp"
FIRST_CHARACTER = 0x20
LAST_CHARACTER = 0x7E
SIZES = (("Small", 11), ("Medium", 18), ("Large", 32))


def byte_lines(values: list[int], width: int = 12) -> list[str]:
    return [
        "    " + ", ".join(f"0x{value:02X}" for value in values[index : index + width]) + ","
        for index in range(0, len(values), width)
    ]


def generate_font(name: str, pixel_size: int) -> list[str]:
    font = ImageFont.truetype(FONT_PATH, pixel_size)
    ascent, descent = font.getmetrics()
    bitmap: list[int] = []
    glyphs: list[tuple[int, int, int, int, int, int]] = []

    for codepoint in range(FIRST_CHARACTER, LAST_CHARACTER + 1):
        character = chr(codepoint)
        left, top, right, bottom = font.getbbox(character, anchor="ls")
        width = max(0, right - left)
        height = max(0, bottom - top)
        offset = len(bitmap)

        if width and height:
            image = Image.new("1", (width, height), 0)
            draw = ImageDraw.Draw(image)
            draw.text((-left, -top), character, font=font, fill=1, anchor="ls")
            packed = 0
            bit_count = 0
            for y in range(height):
                for x in range(width):
                    packed = (packed << 1) | int(image.getpixel((x, y)) != 0)
                    bit_count += 1
                    if bit_count == 8:
                        bitmap.append(packed)
                        packed = 0
                        bit_count = 0
            if bit_count:
                bitmap.append(packed << (8 - bit_count))

        advance = round(font.getlength(character))
        glyphs.append((offset, width, height, advance, left, top))

    lines = [f"static uint8_t FragmentMono{name}Bitmaps[] PROGMEM = {{"]
    lines.extend(byte_lines(bitmap))
    lines.append("};")
    lines.append("")
    lines.append(f"static lgfx::GFXglyph FragmentMono{name}Glyphs[] PROGMEM = {{")
    for codepoint, glyph in zip(range(FIRST_CHARACTER, LAST_CHARACTER + 1), glyphs):
        offset, width, height, advance, x_offset, y_offset = glyph
        lines.append(
            f"    {{{offset}, {width}, {height}, {advance}, {x_offset}, {y_offset}}},"
            f"  // 0x{codepoint:02X} {chr(codepoint)!r}"
        )
    lines.append("};")
    lines.append("")
    lines.append(
        f"static const lgfx::GFXfont FragmentMono{name} = {{"
        f"FragmentMono{name}Bitmaps, FragmentMono{name}Glyphs, "
        f"0x{FIRST_CHARACTER:02X}, 0x{LAST_CHARACTER:02X}, {ascent + descent}}};"
    )
    return lines


def main() -> None:
    lines = [
        "// Generated from Fragment Mono Regular. Do not edit by hand.",
        "// Source and OFL license: firmware/assets/fonts/",
        "#pragma once",
        "",
        "#include <LovyanGFX.hpp>",
        "",
        "namespace pheonix::fonts {",
        "",
    ]
    for index, (name, pixel_size) in enumerate(SIZES):
        if index:
            lines.append("")
        lines.extend(generate_font(name, pixel_size))
    lines.extend(["", "}  // namespace pheonix::fonts", ""])
    OUTPUT_PATH.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
