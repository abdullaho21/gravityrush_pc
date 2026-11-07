#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Builds dist/gravityrush-pc-bin-<version>-x86_64.pkg.tar.zst from the release tarball that
# packaging/linux/package.sh made, and writes the tarball's checksum into packaging/arch/PKGBUILD.
#   packaging/arch/make-package.sh <version>    (e.g. 0.1.15-1 = pkgver-pkgrel)
# makepkg records the folder it ran in (.BUILDINFO builddir/startdir); this script sets both to
# /build and repacks, so the package does not name the machine it was built on.
set -euo pipefail
cd "$(dirname "$0")/../.."
version=${1:?usage: packaging/arch/make-package.sh VERSION}
pkgver=${version%-*} pkgrel=${version##*-}
tarball="dist/gravityrush-pc-$version-x86_64.tar.gz"
[[ -f $tarball ]] || { echo "Missing $tarball: run packaging/linux/package.sh $version first" >&2; exit 1; }
sum=$(sha256sum "$tarball" | cut -d' ' -f1)
sed -i "s/^pkgver=.*/pkgver=$pkgver/; s/^pkgrel=.*/pkgrel=$pkgrel/; s/^sha256sums=.*/sha256sums=('$sum')/" packaging/arch/PKGBUILD

work=dist/arch
rm -rf "$work" && mkdir -p "$work"
cp packaging/arch/PKGBUILD "$tarball" "$work/"
(cd "$work" && PACKAGER="${PACKAGER:-abdullaho21 <193410144+abdullaho21@users.noreply.github.com>}" \
    makepkg -f --noconfirm >/dev/null)

root="$work/pkg/gravityrush-pc-bin"
sed -i 's#^builddir = .*#builddir = /build#; s#^startdir = .*#startdir = /build#' "$root/.BUILDINFO"
files() {
    printf '%s\0' .PKGINFO .BUILDINFO
    find . -mindepth 1 \( -path ./.PKGINFO -o -path ./.BUILDINFO -o -path ./.MTREE \) -prune -o -printf '%P\0' |
        LC_ALL=C sort -z
}
owner=(--uid 0 --gid 0 --uname root --gname root)
package="$PWD/dist/gravityrush-pc-bin-$version-x86_64.pkg.tar.zst"
(
    cd "$root"
    files | LANG=C bsdtar -cnf - --format=mtree "${owner[@]}" --null --files-from - \
        --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' | gzip -c -f -n > .MTREE
    { printf '%s\0' .MTREE; files; } | LANG=C bsdtar --no-fflags -cnf - "${owner[@]}" --null --files-from - |
        zstd -q -19 -T0 -c > "$package"
)
if bsdtar -xOf "$package" .BUILDINFO .PKGINFO | grep -q "$HOME"; then
    echo "$package still names $HOME" >&2; exit 1
fi
pacman -Qip "$package" | grep -E '^(Name|Version|Packager|Installed Size)'
du -h "$package"
