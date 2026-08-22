# 0001: Syphon 出力を独立パッケージにし、本体と同名のターゲットで引き継ぐ

- **状態**: 採用 (2026-08-23, リポジトリ開設時の判断。本体側の根拠は [metaphor ADR-0014](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0014-viewer-frame-ipc-and-syphon-plugin.md) と [metaphor#792](https://github.com/shinyaoguri/metaphor/issues/792) §2 D1 / D6 / D7 / D13)

- **文脈**: metaphor 0.11 までは `MetaphorSyphon` ターゲットと Syphon.xcframework の `binaryTarget` が本体の `Package.swift` にあった。SwiftPM は `binaryTarget(url:)` を**使わない product にしか属していなくても resolve のたびに download する**（[実測](https://github.com/shinyaoguri/metaphor/issues/792#issuecomment-5379755705)。tools 6.1 の package traits でも回避不可）。つまり Syphon を使わないスケッチも、metaphor を入れた全員が xcframework を取らされ、Release ごとに pin を追う bot PR の連鎖（2 か月で 11 本）が本体の週次トレインを重くしていた。metaphor-cli のライブビューアも Syphon 経由だったが、親子プロセスの転送は frame IPC へ移った（ADR-0014）ので、Syphon の用途は「外部アプリへの出力」だけになった。

  出力を分離する先として metaphor-plugins（任意プラグインの monorepo）も候補だったが、同リポの [ADR 0001](https://github.com/shinyaoguri/metaphor-plugins/blob/main/docs/decisions/0001-monorepo-multi-product.md) は「バイナリ配布物を抱えるものは同居させない」を例外条項として持つ。理由は上と同じで、monorepo に xcframework を置くと、別のプラグインだけ使う人も取らされる。

- **決定**:

  1. **独立リポジトリ `metaphor-syphon`**（1 パッケージ = 1 product `MetaphorSyphon`）にする。binary artifact を抱えるのはこのパッケージだけで、取得コストは Syphon を使う人だけが払う。
  2. **ターゲット名は本体時代と同じ**（`MetaphorSyphon` / `Syphon` / `CMetaphorSyphonBootstrap`）にする。モジュール名が同じなので、利用者の `import MetaphorSyphon` と `startSyphonServer` 等の facade はそのまま動く。SwiftPM はパッケージグラフ内の**ターゲット名の重複を許さない**（`multiple packages declare targets with a conflicting name`。`moduleAliases` でも回避不可 — 実測）ため、本体側でこれらを削除した 0.12.0 以降だけを依存対象にする。本体が同名ターゲットを持つ 0.11 と組み合わせるとビルドできないが、0.11 には in-tree 版があるのでこのパッケージは要らない。
     **上限も切る（追記 2026-08-23、#3）**: 依存は `from: "0.12.0"` ではなく `"0.12.0"..<"0.13.0"`。このパッケージは移行期間のあいだ本体の deprecated フィールド（`syphon` / `syphonName`）を読んでおり、それを消す本体の minor（metaphor#1042）が出ると `from:` のままでは利用者の解決が 0.13.0 + 旧版になって壊れる（SwiftPM は 0.x の minor を breaking と扱わない）。本体 minor ごとに上限を上げた版を出し、読み取り窓が消えたら `from:` に戻す。
  3. **到達形は宣言的**: `SketchConfig(plugins: [.syphon()])`（`PluginFactory.syphon(name:)`。名前省略はスケッチのタイトル）。`METAPHOR_SYPHON_NAME` による自動配線（cli の `--syphon`）は `MetaphorOutputProvider` として残し、本体の deprecated フィールド（`syphon` / `syphonName`）も本体が削除するまで読む。
  4. **Syphon.xcframework はこのリポジトリの Release asset として配り、`Package.swift` が自分の asset を指す（self-pin）**。release workflow が毎リリースで url と checksum を書き換える。asset は不変・追記型で、過去の asset は消さない（SwiftPM は resolve のたびに取りに来るので、消すとその版が二度と使えなくなる）。**初回リリースまでは本体 v0.11.0 の asset を間借り**する — 同じ Syphon-Framework コミット（71351d4）を同じ `scripts/build-syphon.sh` で焼いたもので、まだ無い自リポの asset を指すと最初のビルドが resolve 不能になるため。
  5. ローカルに `Frameworks/Syphon.xcframework` があれば path の binaryTarget を優先する（submodule の更新を Release 前に試せる）。CI の `build-and-test` はローカルビルド側、`check-syphon-pin.sh` は asset 側を見る。

- **影響**:
  - 本体 0.12 で `import metaphor` だけでは Syphon が使えなくなり、利用者は `Package.swift` に 1 行足す（README の移行表）。本体は依存無しで旧フィールドが使われたとき、このリポジトリを案内する診断を出す。
  - metaphor-cli は framework を持たず、`--syphon` で環境変数を渡すだけになる（cli [ADR 0014](https://github.com/shinyaoguri/metaphor-cli/blob/main/docs/decisions/0014-viewer-frame-ipc-drops-syphon-bundle.md)）。`metaphor new --template syphon` がこのパッケージへの依存を足す（cli#166）。
  - 本体の provider / plugin API（`MetaphorOutputProvider` / `PluginFactory(requirements:)` / `MetaphorOutputPlugin`）はこのパッケージの前提。変えるときは本体側 PR で、`nightly.yml`（本体 main との組合せビルド）が早期に気付く。
  - 本体が deprecated フィールドを削除する minor（metaphor#1042）で、`SyphonOutputProvider.swift` の読み取り窓とそのテストを消す。
