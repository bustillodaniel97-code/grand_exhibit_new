#!/usr/bin/env python3
"""Validate native frozen-scene captures from world_edges_campaign.gd."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw

root = Path(sys.argv[1])
rows = []
for path in sorted((root / 'campaign').glob('*-original.png')):
    name = path.name.removesuffix('-original.png')
    original = Image.open(path).convert('RGB')
    passthrough = Image.open(path.with_name(name + '-passthrough.png')).convert('RGB')
    smoothed = Image.open(path.with_name(name + '-smoothed.png')).convert('RGB')
    def same_region(box):
        return ImageChops.difference(original.crop(box), smoothed.crop(box)).getbbox() is None
    row = {
        'scene': name,
        'passthrough_exact': ImageChops.difference(original, passthrough).getbbox() is None,
        'world_changed': ImageChops.difference(original, smoothed).getbbox() == (0, 198, 720, 1106),
        'hud_exact': same_region((0, 0, 720, 198)),
        'bottom_ui_exact': same_region((0, 1106, 720, 1280)),
        # The rail has translucent panels: changed scenery correctly shows
        # through them. Compare the opaque icon center, not its blended edges.
        'stats_opaque_icon_exact': same_region((662, 232, 671, 241)),
    }
    rows.append(row)
(root / 'pixel-checks.json').write_text(json.dumps(rows, indent=2))
assert len(rows) == 24, f'Expected 12 venues x 2 zooms, got {len(rows)}'
for row in rows:
    assert all(v for k, v in row.items() if k != 'scene'), row
files = [p for p in sorted((root / 'campaign').glob('*-smoothed.png')) if '-close-' not in p.name]
sheet = Image.new('RGB', (1440, 1350), (26, 26, 30))
draw = ImageDraw.Draw(sheet)
for i, path in enumerate(files):
    im = Image.open(path).crop((0, 198, 720, 1106))
    im.thumbnail((360, 422))
    x, y = i % 4 * 360, i // 4 * 450
    sheet.paste(im, (x, y + 22))
    draw.text((x + 8, y + 5), path.name.removesuffix('-smoothed.png'), fill='white')
sheet.save(root / 'campaign-review.png')
a = Image.open(root / 'campaign/whispering_pines-original.png')
b = Image.open(root / 'campaign/whispering_pines-smoothed.png')
comparison = Image.new('RGB', (960, 540), (26, 26, 30))
draw = ImageDraw.Draw(comparison)
for x, label, im in [(0, 'Before', a), (480, 'World smoothing', b)]:
    draw.text((x + 12, 10), label, fill='white')
    comparison.paste(im.crop((0, 230, 240, 480)).resize((480, 500)), (x, 40))
comparison.save(root / 'before-after.png')
print('PASS: 24 rendered scene comparisons; exact passthrough, HUD, navigation and opaque Stats icon.')
