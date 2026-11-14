"""Validate the manifest contract used by Android's default SMS role."""
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = '{http://schemas.android.com/apk/res/android}'
manifest = ET.parse(Path(__file__).resolve().parent.parent / 'android/app/src/main/AndroidManifest.xml').getroot()
app = manifest.find('application')
assert app is not None
assert app.get(ANDROID + 'label') == '@string/app_name'
requirements = [
    ('activity', '.MainActivity', 'android.intent.action.SENDTO', None, {'sms', 'smsto', 'mms', 'mmsto'}),
    ('service', '.RespondViaMessageService', 'android.intent.action.RESPOND_VIA_MESSAGE',
     'android.permission.SEND_RESPOND_VIA_MESSAGE', {'sms', 'smsto', 'mms', 'mmsto'}),
    ('receiver', '.IncomingSmsReceiver', 'android.provider.Telephony.SMS_DELIVER',
     'android.permission.BROADCAST_SMS', set()),
    ('receiver', '.IncomingMmsReceiver', 'android.provider.Telephony.WAP_PUSH_DELIVER',
     'android.permission.BROADCAST_WAP_PUSH', set()),
]
for tag, name, action, permission, schemes in requirements:
    component = next(node for node in app.findall(tag) if node.get(ANDROID + 'name') == name)
    assert component.get(ANDROID + 'exported') == 'true', name
    if permission:
        assert component.get(ANDROID + 'permission') == permission, name
    matching = [node for node in component.findall('intent-filter') if any(
        item.get(ANDROID + 'name') == action for item in node.findall('action'))]
    assert matching, action
    declared = {item.get(ANDROID + 'scheme') for node in matching for item in node.findall('data')}
    assert schemes <= declared, (name, declared)
    if name == '.IncomingMmsReceiver':
        assert any(item.get(ANDROID + 'mimeType') == 'application/vnd.wap.mms-message'
                   for node in matching for item in node.findall('data'))
print('Default SMS role: activity, receivers, service, permissions and schemes passed.')
