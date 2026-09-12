#!/usr/bin/env python3
"""Check the distributable and prevent accidental publication of local identifiers."""
import pathlib
import plistlib
import re
import socket
import struct
import subprocess
import tempfile
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = (ROOT / 'VERSION').read_text().strip()
APP = ROOT / 'dist/Plip.app'
ALLOWED_EMAIL = 'Rodlip@users.noreply.github.com'
PATTERNS = {
    'personal filesystem path': rb'/(?:Users|home)/[A-Za-z0-9._-]+/',
    'IPv4 address': rb'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])',
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'GitHub credential': rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})',
}
EMAIL = re.compile(rb'[A-Za-z0-9.+_-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
HOST = socket.gethostname().encode()


def audit(path):
    data = path.read_bytes()
    for label, pattern in PATTERNS.items():
        if re.search(pattern, data):
            raise SystemExit(f'Privacy check failed: {label} in {path.name}. Matched data is not logged.')
    if any(value.decode() != ALLOWED_EMAIL and not re.fullmatch(rb'icon_\d+x\d+@2x\.png', value) for value in EMAIL.findall(data)):
        raise SystemExit(f'Privacy check failed: unexpected email in {path.name}.')
    if len(HOST) > 5 and HOST.lower() not in [b'localhost', b'runner'] and HOST.lower() in data.lower():
        raise SystemExit(f'Privacy check failed: local hostname in {path.name}.')


def verify_app(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleShortVersionString'] == VERSION
    assert info['CFBundleVersion'] == VERSION
    assert info['CFBundleIdentifier'] == 'com.plip.editor'
    icon = app / 'Contents/Resources' / info['CFBundleIconFile']
    raw = icon.read_bytes()
    assert raw[:4] == b'icns' and struct.unpack('>I', raw[4:8])[0] == len(raw)
    position = 8
    sizes = set()
    while position < len(raw):
        length = struct.unpack('>I', raw[position + 4:position + 8])[0]
        assert length > 8
        png = raw[position + 8:position + length]
        assert png[:8] == b'\x89PNG\r\n\x1a\n'
        sizes.add(struct.unpack('>II', png[16:24]))
        position += length
    assert position == len(raw) and {(16, 16), (32, 32), (256, 256), (512, 512), (1024, 1024)} <= sizes
    executable = app / 'Contents/MacOS/Plip'
    macho = executable.read_bytes()
    assert struct.unpack('<II', macho[:8]) == (0xFEEDFACF, 0x0100000C), 'Expected a native arm64 executable.'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, capture_output=True)
    for path in app.rglob('*'):
        if path.is_file():
            audit(path)


for directory in ['Sources', 'Resources', 'Scripts', 'Tests', 'Examples', 'docs', '.github']:
    for path in (ROOT / directory).rglob('*'):
        if path.is_file():
            audit(path)
for name in ['README.md', 'CONTRIBUTING.md', 'VERSION', '.gitignore']:
    audit(ROOT / name)
verify_app(APP)
with tempfile.TemporaryDirectory() as temp:
    expanded = pathlib.Path(temp) / 'package'
    subprocess.run(['pkgutil', '--expand-full', str(ROOT / 'dist/Plip-arm64.pkg'), str(expanded)], check=True, capture_output=True)
    info = (expanded / 'PackageInfo').read_bytes()
    assert b'install-location="/Applications"' in info and b'relocatable="false"' in info
    extracted = expanded / 'Payload/Plip.app'
    verify_app(extracted)
    assert (extracted / 'Contents/MacOS/Plip').read_bytes() == (APP / 'Contents/MacOS/Plip').read_bytes()
    for path in expanded.rglob('*'):
        if path.is_file():
            audit(path)
with zipfile.ZipFile(ROOT / 'dist/Plip-arm64.zip') as archive:
    assert archive.read('Plip.app/Contents/MacOS/Plip') == (APP / 'Contents/MacOS/Plip').read_bytes()
subprocess.run(['shasum', '-a', '256', '-c', 'SHA256SUMS.txt'], cwd=ROOT / 'dist', check=True)
print('Verified source privacy, arm64 architecture, icon sizes, signatures, installer destination, portable ZIP, and checksums.')
