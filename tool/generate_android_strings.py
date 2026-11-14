"""Keep Android notification resources consistent with the offline UI catalogs."""
import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

KEYS = {
    'app_name': 'Qingniao',
    'push_title': 'Synced messages available',
    'push_body': 'Open Qingniao to sync securely.',
    'notification_reply': 'Reply',
    'notification_messages': 'Messages',
    'notification_new_message': 'New message',
    'notification_mark_read': 'Mark as read',
    'notification_copy_code': 'Copy',
    'notification_code_copied': 'Copied',
    'notification_loading': 'Loading…',
    'notification_new_mms': 'New MMS',
    'notification_failed': 'Failed to send',
    'notification_retry': 'Could not complete the action. Try again.',
    'notification_test_title': 'Notification test',
    'notification_test_body': 'Test code: 864213. No SMS was sent.',
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    stale = []
    for catalog in sorted(Path('assets/l10n').glob('*.json')):
        strings = json.loads(catalog.read_text(encoding='utf-8'))
        root = ET.Element('resources')
        for resource, key in KEYS.items():
            node = ET.SubElement(root, 'string', name=resource)
            node.text = strings[key].replace('\\', '\\\\').replace("'", "\\'")
        tree = ET.ElementTree(root)
        ET.indent(tree, space='    ')
        content = ET.tostring(root, encoding='utf-8', xml_declaration=True) + b'\n'
        values = 'values' if catalog.stem == 'en' else f'values-{catalog.stem}'
        target = Path('android/app/src/main/res') / values / 'strings.xml'
        if args.check:
            if not target.exists() or target.read_bytes().replace(b'\r\n', b'\n') != content:
                stale.append(str(target))
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
    if stale:
        print('Regenerate Android resources: ' + ', '.join(stale), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
