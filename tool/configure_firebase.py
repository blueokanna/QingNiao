"""Generate Firebase public Android resources from a real project configuration."""
import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path


def resources(config):
    project = config['project_info']
    clients = [client for client in config['client'] if
               client['client_info']['android_client_info']['package_name'] == 'com.blue.qingniao']
    if len(clients) != 1:
        raise ValueError('Configuration must contain exactly one com.blue.qingniao client')
    client = clients[0]
    values = {
        'google_app_id': client['client_info']['mobilesdk_app_id'],
        'gcm_defaultSenderId': project['project_number'],
        'project_id': project['project_id'],
        'google_api_key': client['api_key'][0]['current_key'],
    }
    if any(not isinstance(value, str) or not value.strip() or len(value) > 512 for value in values.values()):
        raise ValueError('Missing or invalid Firebase identifiers')
    if not values['google_app_id'].startswith('1:') or not values['gcm_defaultSenderId'].isdigit():
        raise ValueError('Invalid Firebase Android application or sender identifier')
    root = ET.Element('resources')
    for name, value in values.items():
        ET.SubElement(root, 'string', name=name, translatable='false').text = value
    ET.indent(root, space='    ')
    return ET.tostring(root, encoding='utf-8', xml_declaration=True) + b'\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('configuration', type=Path)
    args = parser.parse_args()
    output = resources(json.loads(args.configuration.read_text(encoding='utf-8')))
    destination = Path(__file__).resolve().parent.parent / 'android/app/src/main/res/values/firebase_project.xml'
    destination.write_bytes(output)
    print('Generated public Firebase resources for com.blue.qingniao. Rebuild the APK.')
