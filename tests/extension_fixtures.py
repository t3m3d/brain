"""Create disposable VSIX fixtures for brain --extensions-test <folder>."""
import json
from pathlib import Path
import sys
import warnings
import zipfile

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
manifest = dict(name='fixture', publisher='brain-test', version='1.0.0',
                displayName='Unicode café 🦋', description='Brain extension fixture')

def archive(name, content, entry='extension/package.json'):
    with zipfile.ZipFile(root / (name + '.vsix'), 'w', zipfile.ZIP_DEFLATED) as target:
        target.writestr(entry, content)

archive('Unicode café 🦋', json.dumps(manifest))
archive('bad-json', '{ invalid JSON }')
archive('missing', '{}', 'unrelated/file.json')
archive('oversized', ' ' * 1100000 + '{}')
archive('traversal', json.dumps({**manifest, 'publisher': '../escape'}))
with warnings.catch_warnings():
    warnings.simplefilter('ignore', UserWarning)
    with zipfile.ZipFile(root / 'duplicate.vsix', 'w') as target:
        for _ in range(2):
            target.writestr('extension/package.json', json.dumps(manifest))
(root / 'corrupt.vsix').write_text('This is not a ZIP archive. ' * 4)
print(root)
