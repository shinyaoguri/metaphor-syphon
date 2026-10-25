# metaphor-syphon

> [!IMPORTANT]
> **metaphor-syphon の開発は終了しました。後継パッケージ [mokume-syphon](https://github.com/mokume-metal/mokume-syphon) に引き継いでいます。**（本体 metaphor も後継 [mokume](https://github.com/mokume-metal/mokume) に引き継がれ、開発を終了しています。）
> 本リポジトリは参照用にアーカイブしていますが、今後の機能追加・不具合修正・Issue / PR への対応は行いません。新しく使い始める場合や移行する場合は mokume-syphon をご利用ください。

[metaphor](https://github.com/shinyaoguri/metaphor) のスケッチを **Syphon サーバーとして publish** する公式プラグイン。MadMapper / Resolume / VDMX / TouchDesigner など Syphon クライアントから、スケッチの最終フレームをそのまま受け取れます。

metaphor 0.12 で本体から分離されました（[ADR-0014](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0014-viewer-frame-ipc-and-syphon-plugin.md) / [metaphor#792](https://github.com/shinyaoguri/metaphor/issues/792)）。Syphon.framework（xcframework）を抱えるのはこのパッケージだけで、**Syphon を使わないスケッチはダウンロードもリンクもしません**。

## 使い方

`Package.swift` に 1 行足して、`import MetaphorSyphon` し、`plugins:` に `.syphon()` を渡すだけです。

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.13.0"),
    .package(url: "https://github.com/shinyaoguri/metaphor-syphon.git", from: "0.2.0"),
],
targets: [
    .executableTarget(
        name: "MySketch",
        dependencies: [
            .product(name: "metaphor", package: "metaphor"),              // または "MetaphorCore"
            .product(name: "MetaphorSyphon", package: "metaphor-syphon"),
        ]
    )
]
```

```swift
import metaphor          // MetaphorCore だけでも可
import MetaphorSyphon

@main
final class MySketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "Preview", plugins: [.syphon()])
    }
    func draw() {
        background(10, 10, 15)
        circle(width / 2, height / 2, 200 + sin(time) * 100)
    }
}
```

- `.syphon()` は **スケッチのタイトル**（`SketchConfig.title`）でサーバーを立てます。`.syphon(name: "Main Out")` で名前を明示できます。
- セカンダリウィンドウ（`createWindow(SketchWindowConfig(..., plugins: [.syphon(name: "Sub")]))`）も同じ書き方です。ウィンドウごとに別のサーバーになります（`Examples/Samples/Syphon/SyphonMultiWindow`）。
- Syphon を宣言したスケッチは、ウィンドウが隠れても publish が止まらないよう**レンダーループが自動的にタイマー駆動**になります（`renderLoopMode: .displayLink` のままで OK）。
- サーバーはスケッチ起動時に立ち、`noLoop()` で止めても最後のフレームが残ります（MadMapper 側で消えない）。

### VSCode で補完が効かないとき

このパッケージを依存に足すと、**VSCode で `MetaphorSyphon` の補完・hover・定義ジャンプが効かなくなります**（診断に `No such module 'MetaphorSyphon'` が出ます）。ビルドと実行は正常で、壊れるのはエディタ体験だけです。metaphor 本体の API は補完が出たままなので気づきにくい症状です。

原因は上流のツールチェーン側にあります。sourcekit-lsp の背景インデックスが走らせる `swift build --experimental-prepare-for-indexing` が binaryTarget の framework をコピーせず、`MetaphorSyphon` のコンパイルが `no such module 'Syphon'` で落ちるためです（[swift-package-manager#9567](https://github.com/swiftlang/swift-package-manager/issues/9567)。Swift Build バックエンドでは修正済みですが、sourcekit-lsp は背景インデックスにだけ native を使い続けています）。metaphor 本体が同じ問題を踏んでいた [metaphor#578](https://github.com/shinyaoguri/metaphor/issues/578) と同一機序で、xcframework がこのパッケージへ移った結果、依存に足した人が踏む形になりました。

スケッチ側に `.sourcekit-lsp/config.json` を置くと直ります。

```json
{ "swiftPM": { "buildSystem": "swiftbuild", "scratchPath": ".build/index-build" } }
```

置いて VSCode を開き直せば、`.syphon()` の補完も `SyphonOutput` の定義ジャンプも通ります。`{ "backgroundIndexing": false }` でも補完自体は戻りますが、背景インデックスが止まるので一度 `swift build` するまで何も出ません。

[metaphor-cli](https://github.com/shinyaoguri/metaphor-cli) の `metaphor doctor` は、この設定が無いスケッチで `[warn] Editor cannot resolve plugin symbols` と名指しします。上流が背景インデックスを Swift Build へ移せば、この設定は不要になります。

### コードを変えずに publish する: `METAPHOR_SYPHON_NAME`

このパッケージをリンクしているスケッチは、環境変数 `METAPHOR_SYPHON_NAME=<名前>` だけでその名前のサーバーを立てます。[metaphor-cli](https://github.com/shinyaoguri/metaphor-cli) の `metaphor run --syphon[=name]` / `metaphor watch --syphon[=name]` はこれを子プロセスへ渡します。

```bash
METAPHOR_SYPHON_NAME="Main Out" swift run
```

`.syphon(name:)` と環境変数を同時に使うと、**それぞれの名前でサーバーが 2 本**立ちます（片方を消したければ宣言を 1 つにする）。

### 0.11 以前からの移行

metaphor 0.12 で `SketchConfig` / `SketchWindowConfig` の Syphon フィールドは deprecated になり、**0.13 で削除**されました。metaphor-syphon 0.1.x（metaphor 0.12.x 向け）は移行期間として旧フィールドも読んでいましたが、0.2.0 以降（metaphor 0.13 以降）は `.syphon(name:)` と `METAPHOR_SYPHON_NAME` だけです。

| 0.11 まで | 0.12 から |
|---|---|
| `import metaphor` だけで Syphon が使えた | `Package.swift` に metaphor-syphon を足し、`import MetaphorSyphon` |
| `SketchConfig(syphon: true)` | `SketchConfig(plugins: [.syphon()])`（タイトルで publish） |
| `SketchConfig(syphonName: "X")` | `SketchConfig(plugins: [.syphon(name: "X")])` |
| `SketchWindowConfig(syphonName: "X")` | `SketchWindowConfig(plugins: [.syphon(name: "X")])` |
| `METAPHOR_SYPHON_NAME` | 変更なし（リンクしていれば効く） |
| `renderer.startSyphonServer(name:)` / `stopSyphonServer()` / `syphonOutput` | 変更なし（`MetaphorRenderer` の拡張としてこのパッケージが提供） |

依存を足さずに `METAPHOR_SYPHON_NAME` で出そうとすると、本体が起動時に `metaphor-syphon` を足すよう案内する診断を 1 行出します（publish はされません）。

## 要件

- macOS 14.0+ / Apple Silicon（metaphor と同じ）
- Swift 5.10+（Xcode 15.4+）
- metaphor **0.13.0 以上**（`.package(..., from: "0.13.0")`。metaphor 0.12.x には metaphor-syphon 0.1.x を）

Syphon.framework はこのリポジトリの Release に `Syphon.xcframework.zip` として添付され、`Package.swift` の `binaryTarget` がそれを指します。SwiftPM が `Package.swift` の checksum と照合するので、手で取ってくるものはありません。

## Examples

| Example | 内容 |
|---|---|
| [SyphonOutput](Examples/Samples/Syphon/SyphonOutput) | FHD のジェネラティブ映像を 1 本のサーバーで publish |
| [SyphonMultiWindow](Examples/Samples/Syphon/SyphonMultiWindow) | メイン + セカンダリウィンドウをそれぞれ別サーバーで publish |
| [SyphonTripleWindow](Examples/Samples/Syphon/SyphonTripleWindow) | 3 ウィンドウ = 3 サーバー |

```bash
cd Examples/Samples/Syphon/SyphonOutput && swift run
```

Example はこのリポジトリに path 依存しています。自分のスケッチでは上の「使い方」どおり url 依存にしてください。

## 開発

```bash
make setup      # 初回: Syphon-Framework submodule + Syphon.xcframework のローカルビルド（Xcode が必要）
make build      # swift build
make test       # swift test
make ci-check   # CI と同条件（-Xswiftc -warnings-as-errors）
./scripts/verify.sh   # workflow / シェルスクリプトの静的検査 + Python テスト
```

`Frameworks/Syphon.xcframework` が手元にあれば `Package.swift` はそれを使い、無ければ Release の asset を取ります。Syphon-Framework（submodule）を更新するときは `make setup` で焼き直してから動かせます。リリース手順（asset の作り方・self-pin）は [docs/releasing.md](docs/releasing.md)、設計判断は [docs/decisions/](docs/decisions/) を参照。

## metaphor まわりのリポジトリ

| リポジトリ | 役割 |
|---|---|
| [metaphor](https://github.com/shinyaoguri/metaphor) | ライブラリ本体。描画・`Sketch` API・プラグインのホスト |
| [metaphor-cli](https://github.com/shinyaoguri/metaphor-cli) | `metaphor new` / `run` / `watch` / `mcp` コマンド |
| **metaphor-syphon** | Syphon 出力（このリポジトリ） |
| [metaphor-plugins](https://github.com/shinyaoguri/metaphor-plugins) | 本体に入れない任意プラグイン |
| [metaphor-sketches](https://github.com/shinyaoguri/metaphor-sketches) | 実運用しながら作品を作るスケッチブック |

## License

MIT（[LICENSE](LICENSE)）。同梱する Syphon-Framework のライセンスは [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。
