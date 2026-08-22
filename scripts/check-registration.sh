#!/usr/bin/env bash
# 自動登録（C コンストラクタ → MetaphorOutputProviders）が「別パッケージの consumer」から
# 生きていることを、debug / release の両方で実行体として確かめる（metaphor ADR-0001 の
# クロスパッケージ組合せ。このリポジトリ内の swift test は同一パッケージ内なので代わりにならない）。
#
# 一時ディレクトリに path 依存の consumer を作り、import MetaphorSyphon しただけのシンボル
# 参照無しの実行体を build → run して `org.metaphor.syphon` が registered に居ることを見る。
# 静的アーカイブ経由のリンクで bootstrap.o が selective loading に落とされると、ここが
# release で赤くなる（MetaphorSyphon.swift の touch アンカーが守っているもの）。
#
# 使い方: ./scripts/check-registration.sh [debug|release ...]   (既定: 両方)
set -euo pipefail

cd "$(dirname "$0")/.."
PKG_DIR=$(pwd)
CONFIGS=("$@")
if [ ${#CONFIGS[@]} -eq 0 ]; then
  CONFIGS=(debug release)
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/metaphor-syphon-registration.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Sources/Consumer"
cat > "$WORK/Package.swift" <<EOF
// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Consumer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "metaphor-syphon", path: "${PKG_DIR}"),
        .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [
                .product(name: "MetaphorCore", package: "metaphor"),
                .product(name: "MetaphorSyphon", package: "metaphor-syphon"),
            ]
        ),
    ]
)
EOF
cat > "$WORK/Sources/Consumer/main.swift" <<'EOF'
import MetaphorCore
import MetaphorSyphon   // シンボルは一切参照しない: リンクされているだけで登録されるのが契約

let ids = MetaphorOutputProviders.registered.map(\.id)
print("registered providers: \(ids)")
guard ids.contains("org.metaphor.syphon") else {
    print("::error::org.metaphor.syphon is not registered — the C constructor did not run")
    exit(1)
}
let syphon = MetaphorOutputProviders.registered.first { $0.id == "org.metaphor.syphon" }!
guard syphon.requirements == [.externalRenderLoop] else {
    print("::error::unexpected requirements: \(syphon.requirements)")
    exit(1)
}
print("OK: org.metaphor.syphon registered with externalRenderLoop")
EOF

# consumer の resolve は同じ metaphor 版を使い回す（このリポの Package.resolved に合わせる）。
if [ -f Package.resolved ]; then
  cp Package.resolved "$WORK/Package.resolved"
fi

status=0
for config in "${CONFIGS[@]}"; do
  echo "::group::registration ($config)"
  if (cd "$WORK" && swift build -c "$config" 2>&1 | tail -5 && "./.build/$config/Consumer"); then
    echo "registration ($config): OK"
  else
    echo "::error::registration check failed for configuration '$config'"
    status=1
  fi
  echo "::endgroup::"
done
exit $status
