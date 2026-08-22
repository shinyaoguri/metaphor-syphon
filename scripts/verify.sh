#!/usr/bin/env bash
# このリポジトリの静的検査。CI (.github/workflows/ci.yml の validate) と手元の両方がこれを呼ぶ。
#
# 検査対象は GitHub Actions の workflow (actionlint)、scripts/*.sh (shellcheck)、
# scripts/tests/ の Python ユニットテスト (release 経路の signed-commit.py)。
# Swift のビルド・テストは macOS が要るので別ジョブ (build-and-test = make ci-check)。
#
# ツールは版を固定して落とす。「入っていれば使う」にすると CI と手元で検査範囲が
# 変わり、CI が黙って緩くなる (metaphor の scripts/lint-workflows.sh と同じ方針)。
set -euo pipefail

cd "$(dirname "$0")/.."

ACTIONLINT_VERSION="1.7.12"
SHELLCHECK_VERSION="0.11.0"

# 版を上げるときはチェックサムも一緒に差し替える:
#   curl -fsSL https://github.com/rhysd/actionlint/releases/download/v<ver>/actionlint_<ver>_checksums.txt
#   curl -fsSL <shellcheck の tarball URL> | shasum -a 256
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)
    actionlint_asset="actionlint_${ACTIONLINT_VERSION}_darwin_arm64.tar.gz"
    actionlint_sha="aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f"
    shellcheck_asset="shellcheck-v${SHELLCHECK_VERSION}.darwin.aarch64.tar.gz"
    shellcheck_sha="339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f"
    ;;
  Linux/x86_64)
    actionlint_asset="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
    actionlint_sha="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
    shellcheck_asset="shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.gz"
    shellcheck_sha="b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6"
    ;;
  *)
    echo "::error::未対応の環境 ($(uname -s) $(uname -m))。actionlint ${ACTIONLINT_VERSION} と shellcheck ${SHELLCHECK_VERSION} を手で入れて PATH に通してください。" >&2
    exit 1
    ;;
esac

TOOLS_DIR=".build/tools"

# fetch_tool <url> <期待する sha256> <tarball 内のパス> <strip-components> <配置先>
#
# NOTE: この関数を `x="$(fetch_tool ...)"` の形で呼ばないこと。コマンド置換の
# サブシェルで走ると中の exit が呼び出し元を止められず、チェックサム不一致でも
# 後続が実行されてしまう (metaphor の同種スクリプトが踏んだ)。
fetch_tool() {
  local url=$1 expected=$2 member=$3 strip=$4 dest=$5
  local tarball="${dest}.tar.gz"
  mkdir -p "$TOOLS_DIR"
  echo "Downloading $(basename "$dest")..."
  curl -fsSL -o "$tarball" "$url"
  # 落として即実行するので、配布物の改竄・取り違えをここで止める。
  if ! echo "${expected}  ${tarball}" | shasum -a 256 -c - >/dev/null; then
    echo "::error::$(basename "$dest") のチェックサムが一致しません。配布物を破棄しました。" >&2
    rm -f "$tarball"
    exit 1
  fi
  tar -xzf "$tarball" -C "$TOOLS_DIR" --strip-components="$strip" "$member"
  mv "${TOOLS_DIR}/$(basename "$member")" "$dest"
  rm -f "$tarball"
}

actionlint="${TOOLS_DIR}/actionlint-${ACTIONLINT_VERSION}"
shellcheck="${TOOLS_DIR}/shellcheck-${SHELLCHECK_VERSION}"

[ -x "$actionlint" ] || fetch_tool \
  "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/${actionlint_asset}" \
  "$actionlint_sha" "actionlint" 0 "$actionlint"

[ -x "$shellcheck" ] || fetch_tool \
  "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${shellcheck_asset}" \
  "$shellcheck_sha" "shellcheck-v${SHELLCHECK_VERSION}/shellcheck" 1 "$shellcheck"

echo "actionlint $("$actionlint" -version | head -1) / shellcheck $("$shellcheck" --version | awk '/^version:/ {print $2}')"
echo

status=0

echo "==> shellcheck scripts/*.sh"
"$shellcheck" scripts/*.sh || status=1

# actionlint は workflow の run: の中身も shellcheck に通す。
echo "==> actionlint .github/workflows"
"$actionlint" -oneline -shellcheck "$shellcheck" || status=1

echo "==> python3 -m unittest discover -s scripts/tests"
python3 -m unittest discover -s scripts/tests || status=1

if [ "$status" -eq 0 ]; then
  echo
  echo "OK: 静的検査を通過"
fi
exit "$status"
