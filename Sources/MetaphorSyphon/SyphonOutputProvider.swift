import Foundation
import MetaphorCore

/// Syphon 出力の自動配線を担う ``MetaphorCore/MetaphorOutputProvider``。
///
/// ロード時（C コンストラクタ → `metaphor_syphon_register`）または ``MetaphorSyphon/enable()`` で
/// ``MetaphorCore/MetaphorOutputProviders`` に登録され、`SketchRunner` / `SketchWindow` の起動ごとに
/// ``makeOutput(context:)`` が呼ばれる。Syphon サーバー名が決まれば `SyphonPlugin` を返し、
/// 決まらなければ `nil`（= このスケッチでは Syphon を publish しない）。
///
/// Syphon は MadMapper 等の受け手がウィンドウの可視状態と無関係にフレームを期待するため、
/// ``MetaphorCore/PluginRequirements/externalRenderLoop`` を宣言する（`.displayLink` のままの
/// スケッチはタイマー駆動へ切り替わる = 従来の「Syphon ありなら timer」）。
///
/// 自動配線の入口は 3 つ: 環境変数 `METAPHOR_SYPHON_NAME`（metaphor-cli の `run --syphon` /
/// `watch --syphon-name`）、metaphor 0.12 で deprecated になった `SketchConfig.syphon` /
/// `syphonName`（移行期間中だけ読む）、`SketchWindowConfig.syphonName`（同上）。
/// 明示的に有効化するなら `plugins: [.syphon(name:)]`（``MetaphorCore/PluginFactory/syphon(name:)``）を使う。
struct SyphonOutputProvider: MetaphorOutputProvider {
    /// 登録 id（テストや `unregister(id:)` から参照する）。
    static let providerID = "org.metaphor.syphon"

    var id: String { Self.providerID }
    let requirements: PluginRequirements = [.externalRenderLoop]

    @MainActor
    func makeOutput(context: MetaphorOutputContext) -> MetaphorOutputPlugin? {
        guard let name = Self.resolveOutputName(context: context) else { return nil }
        return SyphonPlugin(name: name)
    }

    /// この起動で publish する Syphon サーバー名（無効なら `nil`）。
    ///
    /// プライマリは `resolveSyphonName(config:env:)`、セカンダリウィンドウは旧
    /// `SketchWindowConfig.syphonName` のみ（環境変数・`syphon` フラグは見ない = 従来どおり）。
    /// ヘッドレス（`METAPHOR_VIEWER=1`）でも**明示の要求が無ければ publish しない**
    /// （ADR-0014。ライブビューアへの転送は viewer frame IPC が担い、`metaphor watch` が
    /// `METAPHOR_SYPHON_NAME` を注入するのは `--syphon-name` / `--syphon` を明示したときだけ）。
    nonisolated static func resolveOutputName(context: MetaphorOutputContext) -> String? {
        switch context.scope {
        case .primary(let config):
            return resolveSyphonName(config: config, env: context.environment)
        case .window(let config):
            return (config as LegacySyphonWindowFields).legacySyphonName
        }
    }

    /// 出力（Syphon）サーバーの実効名を解決します（ウィンドウ / ヘッドレス共通）。
    ///
    /// 優先順位: 環境変数 `METAPHOR_SYPHON_NAME` > 旧 `SketchConfig.syphonName` >
    /// （旧 `SketchConfig.syphon` が `true` なら ``MetaphorCore/SketchConfig/title``）。
    /// いずれも無ければ `nil`（= 出力無効）。空文字の環境変数は未設定として扱います。
    ///
    /// - Parameters:
    ///   - config: スケッチ設定。
    ///   - env: 参照する環境変数（テストから注入可能）。
    /// - Returns: 出力サーバー名。無効なら `nil`。
    nonisolated static func resolveSyphonName(config: SketchConfig, env: [String: String]) -> String? {
        if let name = env["METAPHOR_SYPHON_NAME"], !name.isEmpty { return name }
        let legacy = config as LegacySyphonFields
        if let name = legacy.legacySyphonName { return name }
        if legacy.legacySyphonEnabled { return config.title }
        return nil
    }
}

// MARK: - deprecated なフィールドを警告なしに読む窓

// metaphor 0.12 で `SketchConfig.syphon` / `syphonName` / `SketchWindowConfig.syphonName` は
// deprecated になった（次の minor で削除）。移行期間中はこの provider がそれらも読む必要が
// あるが、このパッケージの CI は `-warnings-as-errors` なので deprecated を直接は参照できない
// （deprecated な宣言の**中**でだけ警告が出ない。protocol 要件は deprecated でないので、
// 存在型を通して読めば呼び出し側も黙る — metaphor#1040 で実測）。
// フィールドが本体から消える minor で、この 2 つの protocol ごと削除する。

private protocol LegacySyphonFields {
    var legacySyphonName: String? { get }
    var legacySyphonEnabled: Bool { get }
}

extension SketchConfig: LegacySyphonFields {
    @available(*, deprecated)
    fileprivate var legacySyphonName: String? { syphonName }
    @available(*, deprecated)
    fileprivate var legacySyphonEnabled: Bool { syphon }
}

private protocol LegacySyphonWindowFields {
    var legacySyphonName: String? { get }
}

extension SketchWindowConfig: LegacySyphonWindowFields {
    @available(*, deprecated)
    fileprivate var legacySyphonName: String? { syphonName }
}
