#!/usr/bin/env python3
"""Local re-vendor: copy the bludex library + dlac adapter into the live
dlac working tree, exactly what .github/workflows/sync-dlac.yml does in CI.
This is the DEVELOPER loop for field-testing the dlac flavor between
releases; the CI sync on pushes to bludex main is the real pipeline.

Run from anywhere:  python bludex/tools/vendor_local.py
Then in game:       /addon reload dlac
"""
import os
import shutil

HERE   = os.path.dirname(os.path.abspath(__file__))
BLUDEX = os.path.normpath(os.path.join(HERE, '..'))
ADDONS = os.path.normpath(os.path.join(BLUDEX, '..'))
DEST   = os.path.join(ADDONS, 'dlac', 'jobhelpers', 'blu', 'bludex')


def main():
    if not os.path.isdir(os.path.join(ADDONS, 'dlac')):
        raise SystemExit('no dlac addon found beside bludex (looked in %s)' % ADDONS)
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)
    os.makedirs(DEST)
    for d in ('lib', 'ui', 'data', 'icons'):
        shutil.copytree(os.path.join(BLUDEX, d), os.path.join(DEST, d))
    for f in ('init.lua', 'README.md'):
        shutil.copy2(os.path.join(BLUDEX, 'dlacmodule', f), os.path.join(DEST, f))
    lic = os.path.join(BLUDEX, 'LICENSE')
    if os.path.isfile(lic):
        shutil.copy2(lic, os.path.join(DEST, 'LICENSE'))
    with open(os.path.join(DEST, 'VENDORED.md'), 'w') as fh:
        fh.write('# VENDORED -- do not hand-edit\n'
                 '\n'
                 'Local developer sync from the bludex repo (tools/vendor_local.py).\n'
                 'The real pipeline is .github/workflows/sync-dlac.yml on pushes to\n'
                 'bludex main. Edit in the bludex repo; this folder is overwritten\n'
                 'wholesale by either path.\n')
    print('vendored -> %s' % DEST)
    print('now, in game:  /addon reload dlac')


if __name__ == '__main__':
    main()
