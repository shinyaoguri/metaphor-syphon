# CLAUDE.md

[metaphor](https://github.com/shinyaoguri/metaphor) の **Syphon 出力プラグイン**（独立パッケージ）。ブランチ運用・コミット規約・Issue の作法はグローバル CLAUDE.md に従い、ここでは繰り返さない。

## このリポジトリが存在する理由（先に読む）

SwiftPM は `binaryTarget(url:)` を **使わない product 経由でも resolve のたびに download する**。そのため Syphon.xcframework を本体に置くと metaphor を入れた全員が xcframework を取らされる。metaphor 0.12（[metaphor#792](https://github.com/shinyaoguri/metaphor/issues/792) M4）で本体から `MetaphorSyphon` / `Syphon` / `CMetaphorSyphonBootstrap` を外し、**同名のターゲット**をここへ移した（[ADR-0014](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0014-viewer-frame-ipc-and-syphon-plugin.md)、このリポの [decisions/0001](docs/decisions/0001-separate-package-for-syphon.md)）。

到達形の使い方は `Package.swift` に 1 行 + `import MetaphorSyphon` + `SketchConfig(plugins: [.syphon()])`（README）。

## 構成

```
Package.swift                      # product MetaphorSyphon / binaryTarget Syphon（self-pin）/ CMetaphorSyphonBootstrap
Sources/MetaphorSyphon/
  MetaphorSyphon.swift             # version・enable()・MetaphorRenderer 互換 facade・@_cdecl 登録関数
  SyphonOutputProvider.swift       # MetaphorOutputProvider（METAPHOR_SYPHON_NAME / 旧フィールドの自動配線）
  SyphonPlugin.swift               # MetaphorOutputPlugin（internal）+ PluginFactory.syphon(name:)
  SyphonOutput.swift               # SyphonMetalServer のラッパ（公開 API）
Sources/CMetaphorSyphonBootstrap/  # __attribute__((constructor)) → metaphor_syphon_register
Vendor/Syphon-Framework/           # submodule（Syphon.xcframework の元）
scripts/build-syphon.sh            # submodule → Frameworks/Syphon.xcframework
scripts/check-registration.sh      # 一時 consumer で debug/release の自動登録を実行確認（CI: registration-matrix）
scripts/check-syphon-pin.sh        # Package.swift の url + checksum が実在する asset と一致するか
scripts/verify.sh                  # actionlint + shellcheck + Python テスト（CI: validate）
Examples/Samples/Syphon/           # 3 本（path 依存。本体 v0.11.0 から移植）
Tests/MetaphorSyphonTests/         # Swift Testing
llms.txt                           # 手書きの AI 向け API リファレンス（生成物ではない。公開 API を変えたら手で直す）
docs/releasing.md                  # リリース手順（asset・self-pin）
docs/decisions/                    # ADR
```

## コマンド

```bash
make setup      # submodule 初期化 + Syphon.xcframework をローカルビルド（Frameworks/ へ。gitignore 済み）
make build / make test
make ci-check   # -Xswiftc -warnings-as-errors で build + test（push 前に通す）
./scripts/verify.sh
./scripts/check-registration.sh    # registration-matrix をローカルで
```

`Frameworks/Syphon.xcframework` があれば `Package.swift` は path の binaryTarget を、無ければ Release asset の url を使う。**手元で asset 側を確かめたいときは `make clean-syphon`**。どちらも最後に `swift package purge-cache` を打つ — SwiftPM は manifest の評価結果を内容ハッシュで共有キャッシュし、`Frameworks/` の出現・消失では無効化しない（焼いたのに url 側のまま resolve される。実測）。

## 非自明な注意

- **本体の deprecated フィールドは protocol 要件経由で読む。** `SketchConfig.syphon` / `syphonName` / `SketchWindowConfig.syphonName` は 0.12 で deprecated。CI は `-warnings-as-errors` なので直接参照できず、`SyphonOutputProvider.swift` 末尾の `private protocol LegacySyphonFields` の witness（`@available(*, deprecated)`）越しに読む。テストで旧 init を使う関数も `@available(*, deprecated)` を付ける。本体がフィールドを削除する minor が出たら、この窓とテストごと消す（metaphor#1042 M6 と同時）
- **`PluginFactory.syphon()` の名前は attach 時に解決する。** `PluginFactory` は config を知らないので、`SyphonPlugin.onAttach(sketch:)` で `sketch.config.title` を読む（`addPlugin(_:sketch:)` は `onAttach(sketch:)` → `onAttach(renderer:)` の順）。`SketchWindowConfig.plugins` 経由では Sketch が無く、プロセス名へ落ちる
- **自動登録は C コンストラクタ。** `MetaphorSyphon.swift` の `cmetaphor_syphon_bootstrap_touch()` 呼び出しは、静的アーカイブ経由のリンク（Xcode プロジェクト等）で bootstrap.o が selective loading に落とされないためのアンカー。SwiftPM の実行体（object 直リンク）では無くても登録されるので消しても CI は赤くならないが、守っている経路が違うだけなので消さない。`registration-matrix` が見るのは「別パッケージの consumer から debug / release で登録されること」
- **Syphon サーバーの生成には GPU が要る。** GitHub-hosted の macos-14 は Metal デバイスが無い（metaphor#332）ので、サーバー生成を伴う suite は `.enabled(if: MTLCreateSystemDefaultDevice() != nil)`。`build-and-test` は macos-26 で回す
- **`MetaphorLog` は product に無い。** `metaphorWarning` 等は `import MetaphorCore` で届く（`@_exported`）
- **binaryTarget の pin は release.yml が書き換える（self-pin）。** 手で url / checksum を触らない。過去の asset は消さない（SwiftPM は resolve のたびに取りに来る）。初回だけ metaphor v0.11.0 の asset を間借りしていた（同じ submodule コミット・同じ build-syphon.sh の成果物）
- **metaphor への依存は `"0.12.0"..<"0.13.0"` と minor で上限を切っている。** `from:` にすると `< 1.0.0` になり、deprecated フィールドを消す本体 0.13.0（metaphor#1042）が出た瞬間に、`metaphor-syphon from: "0.1.0"` の利用者が 0.13.0 + この版に解決されてビルドが壊れる（SwiftPM は 0.x の minor を breaking と扱わない）。本体 minor ごとに上限を上げた版を出す（#3、docs/releasing.md）。読み取り窓が消えたら `from:` に戻してよい。本体 main との互換は `nightly.yml` が見る。本体の provider / plugin API が変わる PR は metaphor 側に起票する（このリポは本体の公開 API だけに依存する）
- テストは Swift Testing（`@Suite` / `@Test`）。XCTest は使わない
- ドキュメントの画像はリポジトリに置かず Gyazo へ上げて外部 URL で参照する

## 気付きは Issue へ

本題以外のバグ・改善アイデアはその場で直さず起票する。本体の話は [metaphor](https://github.com/shinyaoguri/metaphor/issues)、CLI の話（`--syphon` フラグ・template）は [metaphor-cli](https://github.com/shinyaoguri/metaphor-cli/issues) へ。
