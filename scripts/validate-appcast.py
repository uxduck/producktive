#!/usr/bin/env python3
"""Check the generated feed against the built app and local update archives."""
import base64
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlparse, unquote
import xml.etree.ElementTree as ET
import zipfile

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def validate(plist_path, updates):
    updates = Path(updates)
    with open(plist_path, 'rb') as stream:
        info = plistlib.load(stream)
    feed = info['SUFeedURL']
    base = feed.removesuffix('/appcast.xml') + '/'
    if not feed.endswith('/appcast.xml') or urlparse(feed).scheme != 'https':
        raise ValueError('The built app must use an HTTPS appcast.xml feed')
    key = info['SUPublicEDKey']
    if len(base64.b64decode(key, validate=True)) != 32:
        raise ValueError('Invalid public signing key')
    root = ET.parse(updates / 'appcast.xml').getroot()
    items = root.findall('./channel/item')
    if not items:
        raise ValueError('Appcast contains no releases')
    found_current = False
    files = ['appcast.xml']
    signatures = []
    for item in items:
        enclosure = item.find('enclosure')
        if enclosure is None:
            raise ValueError('Appcast item is missing an archive')
        url = enclosure.attrib['url']
        name = unquote(urlparse(url).path.rsplit('/', 1)[-1])
        if not name or Path(name).name != name or url != base + name:
            raise ValueError('Archive URL must be directly under the app feed directory')
        archive = updates / name
        if archive.stat().st_size != int(enclosure.attrib['length']):
            raise ValueError(f'Archive length does not match: {name}')
        signature = enclosure.attrib.get(SPARKLE + 'edSignature', '')
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError(f'Archive is missing a valid Ed25519 signature: {name}')
        with zipfile.ZipFile(archive) as bundle:
            archived_info = plistlib.loads(bundle.read('Producktive.app/Contents/Info.plist'))
        build = item.findtext(SPARKLE + 'version') or enclosure.attrib.get(SPARKLE + 'version')
        if archived_info['CFBundleVersion'] != build:
            raise ValueError(f'Build number does not match: {name}')
        if archived_info['SUPublicEDKey'] != key or archived_info['SUFeedURL'] != feed:
            raise ValueError(f'Update key or feed changed: {name}')
        if build == info['CFBundleVersion']:
            if archived_info['CFBundleShortVersionString'] != info['CFBundleShortVersionString']:
                raise ValueError('Current release version does not match')
            found_current = True
        files.append(name)
        signatures.append((archive, signature))
    if not found_current:
        raise ValueError('Current build is missing from the appcast')
    for notes in root.findall('./channel/item/' + SPARKLE + 'releaseNotesLink'):
        url = notes.text or ''
        name = unquote(urlparse(url).path.rsplit('/', 1)[-1])
        if not name or Path(name).name != name or url != base + name:
            raise ValueError('Release notes URL must be under the app feed directory')
        note_file = updates / name
        if note_file.stat().st_size != int(notes.attrib[SPARKLE + 'length']):
            raise ValueError('Release notes length does not match')
        signature = notes.attrib[SPARKLE + 'edSignature']
        signatures.append((note_file, signature))
        files.append(name)
    # Sparkle signs all bytes before its final signature comment. Match its
    # SPUExtractAppcastContent format without reserializing or changing the XML.
    feed_path = updates / 'appcast.xml'
    feed_data = feed_path.read_bytes()
    marker = b'<!-- sparkle-signatures:\n'
    offset = feed_data.rfind(marker)
    if offset < 0:
        raise ValueError('Appcast is missing its feed signature')
    trailer = feed_data[offset:]
    signature = re.search(rb'^edSignature: (\S+)\s*$', trailer, re.M)
    length = re.search(rb'^length: (\d+)\s*$', trailer, re.M)
    if not signature or not length or int(length[1]) != offset:
        raise ValueError('Invalid signed appcast length or signature block')
    checks = [dict(path=str(feed_path), signature=signature[1].decode(), length=offset)]
    checks += [dict(path=str(file), signature=sig, length=file.stat().st_size)
               for file, sig in signatures]
    # Apple's CryptoKit verifies against the actual public key embedded in the
    # app. This also catches using an unrelated key to sign the release.
    source = Path(__file__).with_name('verify-update-signature.swift')
    tools = Path('.build/producktive-update-tools')
    tools.mkdir(parents=True, exist_ok=True)
    verifier = tools / 'verify-signature'
    with tempfile.TemporaryDirectory(prefix='producktive-verify-') as work:
        if not verifier.exists() or verifier.stat().st_mtime < source.stat().st_mtime:
            staging = Path(work) / 'verify-signature'
            subprocess.run(['swiftc', '-module-cache-path', str(tools / 'modules'),
                            str(source), '-o', str(staging)], check=True)
            staging.replace(verifier)
        manifest = Path(work) / 'signatures.json'
        manifest.write_text(json.dumps(checks))
        subprocess.run([str(verifier), key, str(manifest)], check=True)
    return files


if __name__ == '__main__':
    try:
        files = validate(sys.argv[1], sys.argv[2])
        if '--files' in sys.argv[3:]:
            print('\n'.join(files))
        else:
            print('Verified signed feed, archive signatures, sizes, versions, and URLs.')
    except (ValueError, KeyError, OSError, ET.ParseError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        sys.exit(f'Invalid update release: {error}')
