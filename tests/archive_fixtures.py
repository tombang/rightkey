"""Generate hostile archives inside the ignored test build directory."""
import io
from pathlib import Path
import sys
import tarfile
import zipfile

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
for label, name in [('parent', '../escape.txt'), ('absolute', str(root / 'escape.txt')),
                    ('nested', 'a/../../escape.txt'), ('windows', 'C:\\escape.txt'),
                    ('newline', 'ok\n../../escape.txt')]:
    with zipfile.ZipFile(root / (label + '.zip'), 'w') as archive:
        archive.writestr(name, 'must not be extracted')
for label, kind in [('symbolic', tarfile.SYMTYPE), ('hard', tarfile.LNKTYPE)]:
    with tarfile.open(root / (label + '.tar'), 'w') as archive:
        link = tarfile.TarInfo('link')
        link.type = kind
        link.linkname = str(root / 'outside')
        archive.addfile(link)
        data = b'bad'
        item = tarfile.TarInfo('link/payload')
        item.size = len(data)
        archive.addfile(item, io.BytesIO(data))
with zipfile.ZipFile(root / 'empty.zip', 'w'):
    pass
(root / 'corrupt.zip').write_bytes(b'not an archive')
