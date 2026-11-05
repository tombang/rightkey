# Third-party notices

RightKey invokes the following standalone tools as separate processes. These tools are not covered by RightKey's MIT license.

## 7-Zip 26.05

- Upstream: https://www.7-zip.org/
- Official source: https://github.com/ip7z/7zip/releases/tag/26.05
- Complete corresponding source and LGPL text accompany the app in `Contents/Resources/ThirdParty/7z2605-src.tar.xz` and `7zip-LGPL.txt`. You may replace the standalone executable with a compatible modified version; RightKey does not require a particular vendor signature.
- Runtime: `RightKey/Resources/7zz`, official universal macOS binary.
- License: GNU LGPL 2.1 or later, with BSD portions and the unRAR restriction. See `RightKey/Resources/7zz-License.txt` in source and the application bundle.
- RAR decompression code cannot be used to recreate the proprietary RAR compression algorithm. RightKey does not offer RAR creation.

## zstd 1.5.7

- Upstream and source: https://github.com/facebook/zstd/releases/tag/v1.5.7
- Runtime: `RightKey/Resources/zstd`, built as an arm64/x86_64 universal executable with macOS 13 as the deployment target.
- License: BSD 3-clause. See `RightKey/Resources/ThirdParty/zstd-LICENSE`.
- Complete source accompanies the app in `Contents/Resources/ThirdParty/zstd-1.5.7.tar.gz`.
- Build: `make -C programs zstd-release CC=clang CFLAGS='-O2 -arch arm64 -arch x86_64 -mmacosx-version-min=13.0' LDFLAGS='-arch arm64 -arch x86_64 -mmacosx-version-min=13.0' HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0`.

RightKey also invokes `/usr/bin/bsdtar` and links the libarchive library provided by macOS for archive inspection.
