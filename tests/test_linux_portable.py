"""The Linux release must run on systems other than the one that built it (issue #1: the 0.1.15-1
tarball needed the build machine's FFmpeg 9, fmt 12, glibc 2.43 and GCC 16 libstdc++)."""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'packaging' / 'linux'))
import portable

# What `readelf -dW` and `readelf -VW` print for the 0.1.15-1 release (shortened).
RUNTIME_DYNAMIC = """
Dynamic section at offset 0x16ad98 contains 34 entries:
  Tag        Type                         Name/Value
 0x0000000000000001 (NEEDED)             Shared library: [libm.so.6]
 0x0000000000000001 (NEEDED)             Shared library: [libgow3gpu.so]
 0x0000000000000001 (NEEDED)             Shared library: [libvulkan.so.1]
 0x0000000000000001 (NEEDED)             Shared library: [libSDL3.so.0]
 0x0000000000000001 (NEEDED)             Shared library: [libavcodec.so.63]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
 0x000000000000001d (RUNPATH)            Library runpath: [$ORIGIN/gpu]
 0x000000000000000c (INIT)               0x403000
"""
RUNTIME_VERSIONS = """
Version symbols section '.gnu.version' contains 3 entries:
 Addr: 0x0000000000404b9e  Offset: 0x00004b9e  Link: 6 (.dynsym)
  000:   0 (*local*)       2 (GLIBC_2.2.5)   3 (LIBAVCODEC_63)

Version needs section '.gnu.version_r' contains 3 entries:
 Addr: 0x0000000000405178  Offset: 0x00005178  Link: 7 (.dynstr)
  000000: Version: 1  File: libavcodec.so.63  Cnt: 1
  0x0010:   Name: LIBAVCODEC_63  Flags: none  Version: 14
  0x0020: Version: 1  File: libm.so.6  Cnt: 2
  0x0030:   Name: GLIBC_2.43  Flags: none  Version: 12
  0x0040:   Name: GLIBC_2.2.5  Flags: none  Version: 4
  0x0050: Version: 1  File: libc.so.6  Cnt: 2
  0x0060:   Name: GLIBC_2.38  Flags: none  Version: 9
  0x0070:   Name: GLIBC_2.34  Flags: none  Version: 5
"""


class ParsingTests(unittest.TestCase):
    def test_needed_and_runpath(self):
        dynamic = portable.parse_dynamic(RUNTIME_DYNAMIC)
        self.assertEqual(dynamic.needed, ['libm.so.6', 'libgow3gpu.so', 'libvulkan.so.1', 'libSDL3.so.0',
                                          'libavcodec.so.63', 'libc.so.6'])
        self.assertEqual(dynamic.runpath, ['$ORIGIN/gpu'])

    def test_no_dynamic_section(self):
        dynamic = portable.parse_dynamic('\nThere is no dynamic section in this file.\n')
        self.assertEqual((dynamic.needed, dynamic.runpath), ([], []))

    def test_version_needs_by_library(self):
        self.assertEqual(portable.parse_version_needs(RUNTIME_VERSIONS), {
            'libavcodec.so.63': ['LIBAVCODEC_63'],
            'libm.so.6': ['GLIBC_2.43', 'GLIBC_2.2.5'],
            'libc.so.6': ['GLIBC_2.38', 'GLIBC_2.34'],
        })

    def test_newest_glibc(self):
        self.assertEqual(portable.newest_glibc(portable.parse_version_needs(RUNTIME_VERSIONS)), (2, 43))
        self.assertEqual(portable.newest_glibc({'libc.so.6': ['GLIBC_2.2.5', 'GLIBC_2.34', 'GLIBC_PRIVATE']}), (2, 34))
        self.assertIsNone(portable.newest_glibc({}))


class ProblemTests(unittest.TestCase):
    """problems(): what stops one staged file from loading on another system."""

    def problems(self, dynamic=RUNTIME_DYNAMIC, versions=RUNTIME_VERSIONS, staged=('gpu/libgow3gpu.so',)):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'out'
            for name in staged:
                (out / name).parent.mkdir(parents=True, exist_ok=True)
                (out / name).write_bytes(b'')
            return portable.problems(out / 'gravityrush-runtime', portable.parse_dynamic(dynamic),
                                     portable.parse_version_needs(versions))

    def test_release_0_1_15_1_is_rejected(self):
        found = '\n'.join(self.problems())
        # The library from the issue, the one the Steam Deck stopped at...
        self.assertIn('libavcodec.so.63', found)
        # ...and what it would have stopped at next.
        self.assertIn('libSDL3.so.0', found)
        self.assertIn('GLIBC_2.43', found)
        # Libraries every system has, and the port's own library next to the binary, are fine.
        for fine in ('libvulkan.so.1', 'libc.so.6', 'libgow3gpu.so'):
            self.assertNotIn(fine, found)

    def test_bundled_libraries_and_old_glibc_pass(self):
        versions = RUNTIME_VERSIONS.replace('GLIBC_2.43', 'GLIBC_2.39')
        staged = ('gpu/libgow3gpu.so', 'gpu/libSDL3.so.0', 'gpu/libavcodec.so.63')
        self.assertEqual(self.problems(versions=versions, staged=staged), [])

    def test_bundled_library_outside_the_runpath_is_not_found(self):
        # The loader only searches the file's own RUNPATH: a copy elsewhere in the package is no help.
        versions = RUNTIME_VERSIONS.replace('GLIBC_2.43', 'GLIBC_2.39')
        staged = ('gpu/libgow3gpu.so', 'gpu/libSDL3.so.0', 'lib/libavcodec.so.63')
        self.assertEqual(len(self.problems(versions=versions, staged=staged)), 1)

    def test_runpath_must_stay_inside_the_package(self):
        dynamic = RUNTIME_DYNAMIC.replace('[$ORIGIN/gpu]', '[$ORIGIN/gpu:/home/builder/gravityrush_pc/out/gpu]')
        self.assertIn('/home/builder', '\n'.join(self.problems(dynamic=dynamic)))

    def test_system_cxx_runtime_is_not_assumed(self):
        # libstdc++ is on every system, but in the version of the system's GCC (GCC 16 on the build machine).
        dynamic = RUNTIME_DYNAMIC.replace('libavcodec.so.63', 'libstdc++.so.6')
        self.assertIn('libstdc++.so.6', '\n'.join(self.problems(dynamic=dynamic)))


@unittest.skipUnless(shutil.which('cc') and shutil.which('readelf') and shutil.which('patchelf'),
                     'needs cc, readelf and patchelf')
class BundleTests(unittest.TestCase):
    """bundle() and check() on a small program with a library that is not a system one."""

    def build(self, root):
        lib, out = root / 'lib', root / 'stage' / 'out'
        lib.mkdir()
        (out / 'gpu').mkdir(parents=True)
        (root / 'dep.c').write_text('int dep(void) { return 7; }\n')
        (root / 'mid.c').write_text('int dep(void); int mid(void) { return dep(); }\n')
        (root / 'main.c').write_text('int mid(void); int main(void) { return mid() == 7 ? 0 : 1; }\n')
        cc = ['cc', '-O0']
        subprocess.run(cc + ['-shared', '-fPIC', 'dep.c', '-Wl,-soname,libgrdep.so.1', '-o', 'lib/libgrdep.so.1'],
                       cwd=root, check=True)
        subprocess.run(cc + ['-shared', '-fPIC', 'mid.c', '-Wl,-soname,libgrmid.so.2', '-o', 'lib/libgrmid.so.2',
                             'lib/libgrdep.so.1', f'-Wl,-rpath,{lib}'], cwd=root, check=True)
        # As build.sh links it: $ORIGIN/gpu, then what pkg-config adds for libraries outside /usr.
        subprocess.run(cc + ['main.c', 'lib/libgrmid.so.2', f'-Wl,-rpath-link,{lib}', '-Wl,-rpath,$ORIGIN/gpu',
                             '-Wl,-rpath,/usr/local/lib', '-Wl,--enable-new-dtags',
                             '-o', str(out / 'gravityrush-runtime')], cwd=root, check=True)
        return lib, root / 'stage'

    def test_bundle_copies_the_whole_chain_and_the_result_runs_without_the_originals(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lib, stage = self.build(root)
            runtime = stage / 'out' / 'gravityrush-runtime'
            self.assertTrue(any('libgrmid.so.2' in line for line in portable.check(stage, glibc_max=(9, 99))))
            copied = portable.bundle(stage, search=[lib])
            self.assertEqual(sorted(copied), ['libgrdep.so.1', 'libgrmid.so.2'])
            self.assertEqual(portable.parse_dynamic(portable.readelf('-dW', runtime)).runpath, ['$ORIGIN/gpu'])
            self.assertEqual(portable.check(stage, glibc_max=(9, 99)), [])
            shutil.rmtree(lib)
            self.assertEqual(subprocess.run([runtime]).returncode, 0)

    def test_check_reports_a_newer_glibc_than_allowed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lib, stage = self.build(root)
            portable.bundle(stage, search=[lib])
            self.assertTrue(any('GLIBC_' in line for line in portable.check(stage, glibc_max=(2, 1))))


if __name__ == '__main__':
    unittest.main()
