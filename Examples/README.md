# Examples

metaphor v0.11.0 の `Examples/Samples/Syphon/` から移植した 3 本。各 example は独立した SwiftPM パッケージで、metaphor-syphon には **path 依存**（このリポジトリの作業コピー）、metaphor 本体には Release タグの url 依存をしている。

| Example | 内容 | 見どころ |
|---|---|---|
| [SyphonOutput](Samples/Syphon/SyphonOutput) | FHD のジェネラティブ映像を 1 本の Syphon サーバーで publish | `SketchConfig(plugins: [.syphon(name: "metaphor")])` の最小形 |
| [SyphonMultiWindow](Samples/Syphon/SyphonMultiWindow) | メイン + セカンダリウィンドウを別サーバーで publish | `SketchWindowConfig(plugins: [.syphon(name:)])` |
| [SyphonTripleWindow](Samples/Syphon/SyphonTripleWindow) | 3 ウィンドウ = 3 サーバー | 複数サーバーの同時 publish |

```bash
cd Samples/Syphon/SyphonOutput && swift run
```

起動したら MadMapper / Resolume / Syphon Simple Client などの入力一覧に、上の名前のサーバーが現れる。`METAPHOR_SYPHON_NAME=Other swift run` とすると、その名前のサーバーが**もう 1 本**立つ（cli の `metaphor run --syphon=Other` と同じ経路）。

実行結果画像（`*.png`）は本体リポジトリで撮ったもので、Syphon の publish とは無関係なスケッチの見た目。
