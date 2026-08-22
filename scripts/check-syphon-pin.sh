#!/usr/bin/env bash
# Package.swift の binaryTarget pin（url + checksum）が、実在する asset と一致することを確かめる。
#
# SwiftPM は binaryTarget(url:) を resolve のたびに取りに来るので、url が消えている・checksum が
# 違う pin は「その版を誰も使えない」を意味する。release.yml が self-pin を書き換えるのが唯一の
# 変更経路で、手で触った PR や、asset を消してしまった Release をここで捕まえる。
#
# release/<tag> ブランチは asset がまだ無い（Release 作成前に pin を書く）ので呼び出し側で除外する。
# SwiftPM は不要: url を curl で取り、shasum で照合するだけ（ubuntu ランナーで回せる）。
set -euo pipefail

cd "$(dirname "$0")/.."

url=$(sed -n 's/^[[:space:]]*url: "\([^"]*\)".*/\1/p' Package.swift | head -1)
checksum=$(sed -n 's/^[[:space:]]*checksum: "\([^"]*\)".*/\1/p' Package.swift | head -1)

if [ -z "$url" ] || [ -z "$checksum" ]; then
  echo "::error::Package.swift に binaryTarget の url / checksum が見つからない" >&2
  exit 1
fi
case "$url" in
  */Syphon.xcframework.zip) ;;
  *) echo "::error::url が Syphon.xcframework.zip を指していない: $url" >&2; exit 1 ;;
esac

tmp=$(mktemp "${TMPDIR:-/tmp}/syphon-pin.XXXXXX")
trap 'rm -f "$tmp"' EXIT
echo "Downloading $url"
if ! curl -fsSL --retry 3 -o "$tmp" "$url"; then
  echo "::error::pin の url をダウンロードできない: $url" >&2
  exit 1
fi
if command -v shasum >/dev/null 2>&1; then
  actual=$(shasum -a 256 "$tmp" | awk '{print $1}')
else
  actual=$(sha256sum "$tmp" | awk '{print $1}')
fi
if [ "$actual" != "$checksum" ]; then
  echo "::error::checksum が一致しない: Package.swift=$checksum asset=$actual ($url)" >&2
  exit 1
fi
echo "OK: $url (sha256 $actual)"
