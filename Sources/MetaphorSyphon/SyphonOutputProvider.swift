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
/// 自動配線の入口は環境変数 `METAPHOR_SYPHON_NAME`（metaphor-cli の `run --syphon` /
/// `watch --syphon`）だけ。スケッチ側で宣言するなら `plugins: [.syphon(name:)]`
/// （``MetaphorCore/PluginFactory/syphon(name:)``）を使う。metaphor 0.12 までの
/// `SketchConfig.syphon` / `syphonName` / `SketchWindowConfig.syphonName` は本体 0.13 で削除され、
/// このパッケージも 0.2.0 で読むのをやめた。
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
    /// プライマリは `resolveSyphonName(env:)`（環境変数）。セカンダリウィンドウには環境変数を
    /// 当てない（従来どおり。窓ごとの出力は `SketchWindowConfig.plugins` の `.syphon(name:)` で宣言する）。
    /// ヘッドレス（`METAPHOR_VIEWER=1`）でも**明示の要求が無ければ publish しない**
    /// （ADR-0014。ライブビューアへの転送は viewer frame IPC が担い、`metaphor watch` が
    /// `METAPHOR_SYPHON_NAME` を注入するのは `--syphon` を明示したときだけ）。
    nonisolated static func resolveOutputName(context: MetaphorOutputContext) -> String? {
        switch context.scope {
        case .primary:
            return resolveSyphonName(env: context.environment)
        case .window:
            return nil
        }
    }

    /// 環境変数から出力（Syphon）サーバー名を解決します。
    ///
    /// `METAPHOR_SYPHON_NAME` が設定されていればその値、空文字は未設定として扱い `nil`（= 出力無効）。
    ///
    /// - Parameter env: 参照する環境変数（テストから注入可能）。
    /// - Returns: 出力サーバー名。無効なら `nil`。
    nonisolated static func resolveSyphonName(env: [String: String]) -> String? {
        if let name = env["METAPHOR_SYPHON_NAME"], !name.isEmpty { return name }
        return nil
    }
}
