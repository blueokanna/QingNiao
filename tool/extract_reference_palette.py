"""Extract selected reference swatches; retain CMYK labels and rendered RGB provenance."""
import argparse
import hashlib
import json
from pathlib import Path
import pymupdf

parser = argparse.ArgumentParser()
parser.add_argument('pdf', type=Path)
parser.add_argument('--output', type=Path, default=Path('assets/palettes/coated_reference.json'))
args = parser.parse_args()
selected = {'3295 C': 'jade', '2725 C': 'aurora', '3015 C': 'lagoon', '1665 C': 'dawn', '2587 C': 'plum', 'Cool Gray 11 C': 'graphite'}
swatches = []
with pymupdf.open(args.pdf) as document:
    for index, page in enumerate(document):
        drawings = page.get_drawings()
        for block in page.get_text('blocks'):
            lines = block[4].splitlines()
            if len(lines) < 3 or lines[0] != 'PANTONE' or lines[1] not in selected:
                continue
            candidates = [d for d in drawings if d['fill'] is not None and d['rect'].width > 40 and d['rect'].height > 20 and abs(d['rect'].x0 - block[0]) < 6 and d['rect'].y1 <= block[1] + 2]
            drawing = min(candidates, key=lambda d: abs(d['rect'].y1 - block[1]))
            rgb = [round(c * 255) for c in drawing['fill']]
            swatches.append({'id': selected[lines[1]], 'label': f'PANTONE {lines[1]}', 'page': index + 1, 'cmykLabel': ' '.join(lines[2:]), 'rgb': rgb, 'hex': '#' + ''.join(f'{c:02X}' for c in rgb)})
if len(swatches) != len(selected):
    raise ValueError('Missing or duplicated reference swatches')
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps({'sourceSha256': hashlib.sha256(args.pdf.read_bytes()).hexdigest(), 'conversion': f'PyMuPDF {pymupdf.VersionBind} PDF colorspace conversion to RGB; screen simulation, not certified spot color', 'swatches': swatches}, indent=2) + '\n', encoding='utf-8')
