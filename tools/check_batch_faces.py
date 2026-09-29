#!/usr/bin/env python3
"""Verify that batching changes no pixels in the 12-venue/two-zoom review."""
from pathlib import Path
import json
import sys
from PIL import Image, ImageChops

root = Path(sys.argv[1])
rows = []
def same(a, b):
    return all(channel.getbbox() is None for channel in ImageChops.difference(a, b).split())
for path in sorted((root / 'campaign').glob('*-batched.png')):
    name = path.name.removesuffix('-batched.png')
    a = Image.open(path.with_name(name + '-original.png')).convert('RGBA')
    b = Image.open(path).convert('RGBA')
    repeat = Image.open(path.with_name(name + '-repeat.png')).convert('RGBA')
    rows.append({'scene': name, 'original_repeat_exact': same(a, repeat),
                 'batched_exact': same(a, b), 'size': list(a.size)})
(root / 'pixel-checks.json').write_text(json.dumps(rows, indent=2))
assert len(rows) == 24, f'Expected 24 scene/zoom pairs, got {len(rows)}'
assert all(r['original_repeat_exact'] and r['batched_exact'] for r in rows), rows
print('PASS: 24/24 exact RGBA comparisons, including repeated originals.')
