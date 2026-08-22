# リリース手順

metaphor-syphon のリリースは **手動 dispatch のタグ駆動**。本体 metaphor の週次トレインのような自動発車は無い（変更は本体の Syphon 分離に追随するときと Syphon-Framework の更新くらいで、頻度が低い）。

## 1 リリースで起きること（`.github/workflows/release.yml`）

`Actions → Release → Run workflow`（`bump` = patch / minor / major / prerelease、任意で `prerelease_label`）。CLI なら:

```bash
gh workflow run release.yml -f bump=minor
```

1. `Vendor/Syphon-Framework` submodule から `scripts/build-syphon.sh` で `Syphon.xcframework` を焼く（macos-14 = 最小サポート Xcode 15.4。submodule ハッシュ + スクリプト + Xcode 版でキャッシュ）
2. zip + SHA256 を作る
3. 次の版を最新タグから計算し、`release/<tag>` ブランチに **署名付きコミット**（GitHub API の `createCommitOnBranch`。runner は署名鍵を持たないので `scripts/signed-commit.py` で API 経由 — ruleset の signed commits 必須に当たらないため）で次を書き換える:
   - `Package.swift` の `binaryTarget` — **url をこのリポジトリの `releases/download/<tag>/Syphon.xcframework.zip` に、checksum を 2 の値に**（self-pin）
   - `Sources/MetaphorSyphon/MetaphorSyphon.swift` の `version`
   - 安定版だけ: README.md / llms.txt の `metaphor-syphon.git", from: "<version>"`
4. PR を開き、CI を `workflow_dispatch` で起動して green を待ち、`ci-gate` を legacy status にブリッジして squash merge
5. マージコミットにタグを打ち、Release を作って `Syphon.xcframework.zip` と `checksum.txt` を添付
6. 公開された asset をダウンロードして checksum を照合する（asset の欠落は tag が不変なので後から直せない）

## 守ること

- **asset は不変・追記型。** 過去の Release の asset を消さない・差し替えない。SwiftPM は `binaryTarget(url:)` を resolve のたびに取りに来るので、消した瞬間にその版を pin している全員がビルドできなくなる
- **`Package.swift` の url / checksum を手で触らない。** release workflow だけが書く。PR の CI（`validate` の `check-syphon-pin.sh`）は url が実在し checksum が一致することを確かめる（release ブランチは asset がまだ無いので除外）
- **version は `MetaphorSyphon.version`** 1 箇所。手で上げない
- 初回（v0.1.0 以前）の pin は本体 metaphor v0.11.0 の asset を間借りしていた（[decisions/0001](decisions/0001-separate-package-for-syphon.md) 決定 4）。v0.1.0 以降は常に自リポの asset

## bump の目安

- Syphon-Framework の更新・挙動が変わる修正: **minor**（0.x の間は breaking も minor — 本体の [ADR-0009](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0009-unfreeze-api-until-1-0.md) に倣う）
- ドキュメント・CI だけ: リリースしない
- 本体 metaphor の minor が provider / plugin API を変えたとき: 追随の PR → **minor**。`from:` の下限も上げる

## 失敗したとき

| 症状 | 対処 |
|---|---|
| 「Require CHANGELOG」系で止まる | このリポには無い（CHANGELOG は GitHub Release の自動生成ノート + checksum） |
| release PR が merge できない（policy） | コミットが署名されていない = `signed-commit.py` を経ずに `git commit` した。ブランチを消して再 dispatch |
| asset の検証で落ちる | `gh release upload <tag> Frameworks/Syphon.xcframework.zip --clobber` で上げ直し、`Package.swift` の checksum と一致することを確かめる |
| tag は打たれたが Release が無い | `gh release create <tag> Frameworks/Syphon.xcframework.zip Frameworks/checksum.txt --generate-notes` |
