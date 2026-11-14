"""Build adaptive, monochrome and raster assets from the shared 108 dp geometry."""
import json
import xml.etree.ElementTree as ET
from pathlib import Path
import pymupdf

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / 'android/app/src/main/res'
SOURCE = ROOT / 'assets/branding'
ANDROID = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ANDROID)


def attr(key):
    return f'{{{ANDROID}}}{key}'


def vector(paths):
    root = ET.Element('vector', {attr('width'): '108dp', attr('height'): '108dp',
        attr('viewportWidth'): '108', attr('viewportHeight'): '108'})
    for color, path in paths:
        ET.SubElement(root, 'path', {attr('fillColor'): color, attr('pathData'): path})
    ET.indent(root, space='    ')
    return ET.tostring(root, encoding='utf-8', xml_declaration=True) + b'\n'


def render(svg, size):
    with pymupdf.open(stream=svg.encode(), filetype='svg') as document:
        with pymupdf.open('pdf', document.convert_to_pdf()) as pdf:
            return pdf[0].get_pixmap(matrix=pymupdf.Matrix(size / 108, size / 108), alpha=False).tobytes('png')


def main():
    geometry = json.loads((SOURCE / 'launcher_geometry.json').read_text(encoding='utf-8'))
    for name in ('bird', 'leaf', 'chat'):
        icon = geometry[name]
        base = 'ic_launcher' + ('' if name == 'bird' else f'_{name}')
        foreground = 'ic_qingniao_foreground' if name == 'bird' else f'{base}_foreground'
        (RES / f'drawable/{foreground}.xml').write_bytes(vector(icon['paths']))
        (RES / f'drawable/{base}_monochrome.xml').write_bytes(vector([['#FFFFFF', icon['monochrome']]]))
        adaptive = ET.Element('adaptive-icon')
        for tag, value in [('background', '@color/launcher_background'), ('foreground', f'@drawable/{foreground}'),
                           ('monochrome', f'@drawable/{base}_monochrome')]:
            ET.SubElement(adaptive, tag, {attr('drawable'): value})
        ET.indent(adaptive, space='    ')
        (RES / 'mipmap-anydpi-v33').mkdir(exist_ok=True)
        (RES / f'mipmap-anydpi-v33/{base}.xml').write_bytes(ET.tostring(adaptive, encoding='utf-8', xml_declaration=True))
        adaptive.remove(adaptive.find('monochrome'))
        (RES / f'mipmap-anydpi-v26/{base}.xml').write_bytes(ET.tostring(adaptive, encoding='utf-8', xml_declaration=True))
        paths = ''.join(f'<path fill="{color}" d="{path}"/>' for color, path in icon['paths'])
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" width="108" height="108"><path fill="{geometry["background"]}" d="M0,0H108V108H0Z"/>{paths}</svg>'
        (SOURCE / f'qingniao_{name}.svg').write_text(svg, encoding='utf-8')
        for density, size in [('mdpi',48), ('hdpi',72), ('xhdpi',96), ('xxhdpi',144), ('xxxhdpi',192)]:
            (RES / f'mipmap-{density}/{base}.png').write_bytes(render(svg, size))
        (SOURCE / f'qingniao_{name}_512.png').write_bytes(render(svg, 512))
    colors = RES / 'values/colors.xml'
    tree = ET.parse(colors)
    tree.find("color[@name='launcher_background']").text = geometry['background']
    tree.write(colors, encoding='utf-8', xml_declaration=True)
    print('Generated three adaptive icons, monochrome layers and five raster densities.')


if __name__ == '__main__':
    main()
