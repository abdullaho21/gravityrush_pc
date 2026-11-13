#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Makes the Linux release folder run on systems other than the one that built it, and checks it.

  portable.py bundle STAGE   copy the shared libraries the binaries in STAGE/out need, and that a
                             player's system cannot be expected to have, into STAGE/out/gpu
  portable.py check STAGE    fail if anything in STAGE would not load on another system

A binary linked on the build machine asks for that machine's libraries by exact name and version:
the 0.1.15-1 release wanted libavcodec.so.63 (FFmpeg 9), libfmt.so.12, glibc 2.43 and the
libstdc++ of GCC 16, so it only started on an up-to-date Arch Linux (issue #1, Steam Deck).
packaging/linux/package.sh runs both steps; packaging/linux/build-release.sh provides the old
enough glibc by building in a container.
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

# The newest glibc a release may ask for: Ubuntu 24.04's. SteamOS 3.7/3.8 and Debian 13 have 2.41.
GLIBC_MAX = (2, 39)
# Taken from the player's system: glibc, and libraries with one stable name on every desktop
# system (the graphics driver is found through the system's Vulkan loader). Everything else a
# binary needs has to be in the package. libstdc++ is left out on purpose: its version is the
# version of the system's GCC, so it is linked statically (GOW3_STATIC_CXX in gpu/CMakeLists.txt).
GLIBC_LIBRARIES = {'libc.so.6', 'libm.so.6', 'libdl.so.2', 'libpthread.so.0', 'librt.so.1',
                   'ld-linux-x86-64.so.2'}
SYSTEM_LIBRARIES = GLIBC_LIBRARIES | {'libvulkan.so.1', 'libX11.so.6', 'libfreetype.so.6', 'libz.so.1'}
# Where bundled libraries go: next to libgow3gpu.so, where gravityrush-runtime already looks
# (its RUNPATH is $ORIGIN/gpu).
LIBRARY_FOLDER = Path('out') / 'gpu'


class Dynamic(NamedTuple):
    needed: list
    runpath: list


def parse_dynamic(text):
    """NEEDED names and RUNPATH/RPATH folders from `readelf -dW`."""
    needed = re.findall(r'\(NEEDED\)\s+Shared library: \[(.*?)\]', text)
    runpath = []
    for value in re.findall(r'\((?:RUNPATH|RPATH)\)\s+Library r(?:un)?path: \[(.*?)\]', text):
        runpath.extend(part for part in value.split(':') if part)
    return Dynamic(needed, runpath)


def parse_version_needs(text):
    """{library: [symbol versions wanted from it]} from `readelf -VW` (section .gnu.version_r)."""
    needs, library, inside = {}, None, False
    for line in text.splitlines():
        if line.startswith('Version needs section'):
            inside = True
        elif line and not line[0].isspace():
            inside = False
        elif inside:
            if match := re.search(r'\bFile: (\S+)', line):
                library = needs.setdefault(match.group(1), [])
            elif (match := re.search(r'\bName: (\S+)', line)) and library is not None:
                library.append(match.group(1))
    return needs


def glibc_version(name):
    match = re.fullmatch(r'GLIBC_(\d+(?:\.\d+)+)', name)
    return tuple(int(part) for part in match.group(1).split('.')) if match else None


def newest_glibc(version_needs):
    versions = [version for library, names in version_needs.items() if library in GLIBC_LIBRARIES
                for name in names if (version := glibc_version(name))]
    return max(versions, default=None)


def problems(path, dynamic, version_needs, glibc_max=GLIBC_MAX):
    """Reasons the ELF file at `path` would not load on a system that is not the build machine."""
    found = []
    folders = [Path(entry.replace('$ORIGIN', str(path.parent)).replace('${ORIGIN}', str(path.parent)))
               for entry in dynamic.runpath]
    for entry in dynamic.runpath:
        if not entry.startswith(('$ORIGIN', '${ORIGIN}')):
            found.append(f'{path.name}: looks for libraries in {entry}, a folder outside the package')
    for name in dynamic.needed:
        if name in SYSTEM_LIBRARIES or any((folder / name).exists() for folder in folders):
            continue
        where = ', '.join(dynamic.runpath) or 'nowhere: no RUNPATH'
        found.append(f'{path.name}: needs {name}, which not every system has in this version and '
                     f'which is not bundled where the loader looks for it ({where})')
    for library, names in version_needs.items():
        if library not in GLIBC_LIBRARIES:
            continue
        for name in names:
            version = glibc_version(name)
            if version and version > glibc_max:
                found.append(f'{path.name}: needs {name}, newer than glibc '
                             f'{".".join(map(str, glibc_max))} (build with packaging/linux/build-release.sh)')
    return found


def readelf(option, path):
    return subprocess.run(['readelf', option, str(path)], check=True, capture_output=True, text=True,
                          env={**os.environ, 'LC_ALL': 'C'}).stdout


def elf_files(folder):
    for path in sorted(folder.rglob('*')):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as file:
                if file.read(4) == b'\x7fELF':
                    yield path


def check(stage, glibc_max=GLIBC_MAX):
    stage = Path(stage)
    found = []
    for path in elf_files(stage):
        found.extend(problems(path, parse_dynamic(readelf('-dW', path)),
                              parse_version_needs(readelf('-VW', path)), glibc_max))
    return found


def locate(name, needed_by, search):
    for folder in search:
        if (Path(folder) / name).exists():
            return Path(folder) / name
    # ldd: the path the loader of this machine uses for each library of the file.
    listing = subprocess.run(['ldd', str(needed_by)], capture_output=True, text=True).stdout
    for line in listing.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == name and parts[1] == '=>' and parts[2].startswith('/'):
            return Path(parts[2])
    raise SystemExit(f'portable.py: {needed_by.name} needs {name}, which is not installed here')


def bundle(stage, search=()):
    """Copies the libraries that are not system ones into STAGE/out/gpu; returns their names."""
    folder = Path(stage) / LIBRARY_FOLDER
    folder.mkdir(parents=True, exist_ok=True)
    copied = []
    pending = list(elf_files(Path(stage) / 'out'))
    while pending:
        path = pending.pop()
        for name in parse_dynamic(readelf('-dW', path)).needed:
            if name in SYSTEM_LIBRARIES or (folder / name).exists():
                continue
            shutil.copyfile(locate(name, path, search), folder / name)
            (folder / name).chmod(0o755)
            copied.append(name)
            pending.append(folder / name)
    for path in elf_files(Path(stage) / 'out'):
        if path.parent == folder:
            # RUNPATH is not inherited: each library here finds its own libraries through its own.
            runpath = ['$ORIGIN']
        else:
            # Folders of the build machine (pkg-config adds -rpath for libraries outside /usr) go.
            runpath = [entry for entry in parse_dynamic(readelf('-dW', path)).runpath
                       if entry.startswith(('$ORIGIN', '${ORIGIN}'))]
        subprocess.run(['patchelf', '--set-rpath', ':'.join(runpath), str(path)], check=True)
    return copied


def main(arguments):
    if len(arguments) != 2 or arguments[0] not in ('bundle', 'check'):
        print(__doc__, file=sys.stderr)
        return 2
    command, stage = arguments
    if command == 'bundle':
        copied = bundle(stage)
        print('Bundled libraries:', ', '.join(sorted(copied)) or 'none')
        return 0
    found = check(stage)
    for line in found:
        print(line, file=sys.stderr)
    if found:
        print(f'{len(found)} problem(s): this package would not start on another system.', file=sys.stderr)
        return 1
    print(f'Portable: needs glibc {".".join(map(str, GLIBC_MAX))} or newer and '
          f'{", ".join(sorted(SYSTEM_LIBRARIES - GLIBC_LIBRARIES))} from the system.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
