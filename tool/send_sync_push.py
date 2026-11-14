"""Send an opaque sync hint with Firebase HTTP v1 and Application Default Credentials."""
import argparse
import json
import re
from pathlib import Path
from urllib.request import Request, urlopen
import google.auth
from google.auth.transport.requests import Request as AuthRequest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', required=True)
    parser.add_argument('--space-id', required=True)
    parser.add_argument('--installation-id-file', required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9-]{4,28}[a-z0-9]', args.project):
        parser.error('Invalid Firebase project ID')
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', args.space_id):
        parser.error('Invalid sync space ID')
    installation_id = args.installation_id_file.read_text(encoding='utf-8').strip()
    if not re.fullmatch(r'[A-Za-z0-9_-]{22}', installation_id):
        parser.error('Invalid Firebase installation ID file')
    credentials, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/firebase.messaging'])
    credentials.refresh(AuthRequest())
    payload = {'message': {'fid': installation_id,
        'data': {'type': 'sync_available', 'spaceId': args.space_id},
        'android': {'priority': 'normal', 'ttl': '300s', 'collapse_key': 'sync_available'}}}
    request = Request(f'https://fcm.googleapis.com/v1/projects/{args.project}/messages:send',
        data=json.dumps(payload).encode(), headers={'Authorization': f'Bearer {credentials.token}',
        'Content-Type': 'application/json'}, method='POST')
    with urlopen(request, timeout=20) as response:
        result = json.load(response)
    print('FCM accepted the sync hint: ' + result['name'])


if __name__ == '__main__':
    main()
