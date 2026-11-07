#!/usr/bin/env python3
"""Generates the Lumen icon assets from one shape definition.

Writes the Icon Composer glyph (SVG), the pre-iOS 26 fallback app icon (PNG)
and the settings-row icon (PNG). Run from the repository root:
    python ci/branding/make_icons.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

TOP = (123, 92, 255)      # #7B5CFF
BOTTOM = (43, 26, 140)    # #2B1A8C

# Sparkles in a 1080-unit canvas: (centre x, centre y, radius, waist).
# The waist pulls the sides toward the centre and gives the concave star look.
SPARKLES = [(540, 560, 360, 0.16), (812, 262, 112, 0.18)]


def sparkle_path(cx, cy, r, waist):
    w = r * waist
    return (f'M{cx} {cy - r} Q{cx + w} {cy - w} {cx + r} {cy} '
            f'Q{cx + w} {cy + w} {cx} {cy + r} '
            f'Q{cx - w} {cy + w} {cx - r} {cy} '
            f'Q{cx - w} {cy - w} {cx} {cy - r} Z')


def sparkle_points(cx, cy, r, waist, scale, steps=48):
    w = r * waist
    tips = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    controls = [(cx + w, cy - w), (cx + w, cy + w), (cx - w, cy + w), (cx - w, cy - w)]
    points = []
    for i in range(4):
        (x0, y0), (cx1, cy1), (x1, y1) = tips[i], controls[i], tips[(i + 1) % 4]
        for s in range(steps):
            t = s / steps
            x = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx1 + t * t * x1
            y = (1 - t) ** 2 * y0 + 2 * (1 - t) * t * cy1 + t * t * y1
            points.append((x * scale, y * scale))
    return points


def gradient(size):
    image = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = min(1.0, y / (size * 0.85))
        draw.line([(0, y), (size, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return image


def render(size, rounded):
    supersample = 4
    big = size * supersample
    image = gradient(big).convert('RGBA')
    glyph = Image.new('L', (big, big), 0)
    draw = ImageDraw.Draw(glyph)
    for cx, cy, r, waist in SPARKLES:
        draw.polygon(sparkle_points(cx, cy, r, waist, big / 1080), fill=255)
    # Soft glow under the glyph, so it reads as light rather than a flat cut-out.
    glow = glyph.filter(ImageFilter.GaussianBlur(big * 0.03))
    image.paste(Image.new('RGBA', (big, big), (255, 255, 255, 110)), mask=glow)
    image.paste(Image.new('RGBA', (big, big), (255, 255, 255, 255)), mask=glyph)
    if rounded:
        mask = Image.new('L', (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=big * 0.225, fill=255)
        image.putalpha(mask)
    return image.resize((size, size), Image.LANCZOS)


def main():
    root = Path(__file__).resolve().parents[2]
    icon = root / 'Telegram/Telegram-iOS/Swiftgram.icon'
    paths = ''.join(f'<path d="{sparkle_path(*s)}" fill="white"/>\n' for s in SPARKLES)
    (icon / 'Assets/Default@3x 2.svg').write_text(
        '<svg width="1080" height="1080" viewBox="0 0 1080 1080" fill="none" '
        'xmlns="http://www.w3.org/2000/svg">\n' + paths + '</svg>\n', encoding='utf-8')

    # The App Store icon must be opaque and square; iOS applies the mask itself.
    render(1024, rounded=False).convert('RGB').save(
        root / 'Telegram/Telegram-iOS/DefaultAppIcon.xcassets/AppIconLLC.appiconset/Swiftgram.png')

    settings = root / 'Swiftgram/SGSettingsUI/Images.xcassets/SwiftgramSettings.imageset'
    for old in settings.glob('*.pdf'):
        old.unlink()
    render(512, rounded=True).save(settings / 'Lumen.png')
    (settings / 'Contents.json').write_text(
        '{\n  "images" : [\n    {\n      "filename" : "Lumen.png",\n      "idiom" : "universal",\n'
        '      "scale" : "1x"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n',
        encoding='utf-8')
    print('icons written')


if __name__ == '__main__':
    main()
