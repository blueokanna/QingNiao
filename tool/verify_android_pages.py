"""Validate native ELF segments, RELRO and APK storage alignment without dependencies."""
import argparse
import json
import struct
import zipfile
from pathlib import Path

PAGE = 16384


def verify(apk):
    records = []
    with zipfile.ZipFile(apk) as archive, open(apk, 'rb') as raw:
        for entry in archive.infolist():
            if not entry.filename.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) or not entry.filename.endswith('.so'):
                continue
            data = archive.read(entry)
            if data[:6] != b'\x7fELF\x02\x01':
                raise ValueError(f'Unsupported ELF: {entry.filename}')
            offset = struct.unpack_from('<Q', data, 32)[0]
            size, count = struct.unpack_from('<HH', data, 54)
            headers = [struct.unpack_from('<IIQQQQQQ', data, offset + i * size) for i in range(count)]
            loads = [h for h in headers if h[0] == 1]
            problems = []
            if not loads or any(h[7] < PAGE or (h[3] - h[2]) % PAGE for h in loads):
                problems.append('ELF LOAD alignment')
            for h in (h for h in headers if h[0] == 0x6474e552):
                end = h[3] + h[6]
                if end % PAGE and any(l[1] & 2 and l[3] <= h[3] and end < l[3] + l[6] for l in loads):
                    problems.append('RELRO shares trailing page with writable data')
            raw.seek(entry.header_offset + 26)
            name_length, extra_length = struct.unpack('<HH', raw.read(4))
            payload = entry.header_offset + 30 + name_length + extra_length
            if entry.compress_type != zipfile.ZIP_STORED or payload % PAGE:
                problems.append('APK native library is compressed or not 16 KB aligned')
            records.append({'library': entry.filename, 'loadAlignment': [h[7] for h in loads], 'errors': problems})
    if not records:
        raise ValueError('No 64-bit native libraries found')
    return records


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('apk', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.apk)
    output = json.dumps(result, indent=2)
    print(output)
    if args.report:
        args.report.write_text(output + '\n', encoding='utf-8')
    raise SystemExit(1 if any(r['errors'] for r in result) else 0)
