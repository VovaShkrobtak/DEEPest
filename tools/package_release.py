#!/usr/bin/env python3
"""Package tested source + optionally a portable Linux runtime. No publishing."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime', type=Path, help='Godot 4.6.3 Linux x86_64 executable')
    args = parser.parse_args()
    output = ROOT / 'builds'
    output.mkdir(exist_ok=True)
    godot = os.environ.get('GODOT_BIN') or shutil.which('godot')
    env = os.environ.copy()
    for key, name in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
        env.setdefault(key, str(output / ('xdg-' + name)))
    subprocess.run([godot,'--headless','--editor','--path',str(ROOT),'--import','--quit'], env=env, check=True, stdout=subprocess.DEVNULL)
    subprocess.run([godot,'--headless','--path',str(ROOT),'--export-pack','Linux',str(output/'DEEPest.pck')], env=env, check=True, stdout=subprocess.DEVNULL)
    tracked = subprocess.check_output(['git','ls-files','-z'],cwd=ROOT).decode().split('\0')
    with zipfile.ZipFile(output/'DEEPest-0.1.0-source.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for name in tracked:
            if name and (ROOT/name).is_file(): archive.write(ROOT/name,'DEEPest/'+name)
    if args.runtime:
        if not args.runtime.is_file(): parser.error('Runtime executable missing')
        # No SDK/editor installation required; PCK is already imported/exported.
        license_text = (ROOT/'assets/licenses/Godot-LICENSE.txt').read_text()
        notices = (ROOT/'assets/licenses/Godot-COPYRIGHT.txt').read_text()
        start = '#!/bin/sh\ncd "$(dirname "$0")" || exit 1\nexec ./godot --main-pack DEEPest.pck "$@"\n'
        with zipfile.ZipFile(output/'DEEPest-0.1.0-linux-x86_64.zip','w',zipfile.ZIP_DEFLATED) as archive:
            archive.write(args.runtime,'DEEPest/godot')
            archive.write(output/'DEEPest.pck','DEEPest/DEEPest.pck')
            info = zipfile.ZipInfo('DEEPest/Играть.sh')
            info.external_attr = 0o100755 << 16
            archive.writestr(info,start)
            archive.writestr('DEEPest/GODOT-LICENSE.txt',license_text)
            archive.writestr('DEEPest/GODOT-COPYRIGHT.txt',notices)
            archive.write(ROOT/'docs/PROTOTYPE_STATUS.md','DEEPest/STATUS.md')
            archive.write(ROOT/'docs/walkthrough.md','DEEPest/ПРОХОЖДЕНИЕ.md')
            for name in ['LICENSE.txt','NOTICE.txt']:
                archive.write(ROOT/'assets/fonts'/name,'DEEPest/OpenSans-'+name)
    for name in output.glob('DEEPest*'):
        print(name.name, name.stat().st_size)

if __name__ == '__main__': main()
