import Foundation
import Metal
import MetaphorCore

/// An internal output plugin that publishes the final frame via a Syphon server.
///
/// Because this conforms to `MetaphorOutputPlugin`, its `post()` runs after every
/// other plugin's `post()` (the output phase), so it can always publish the final texture.
///
/// `SyphonMetalServer` is created at `onAttach(renderer:)` time (not `onStart`). This
/// matches the traditional behavior of keeping the server alive even after `noLoop()`
/// stops the loop (the last frame remains visible in MadMapper and similar clients
/// after stopping). The server is destroyed in `onDetach()` (= `removePlugin` / `renderer.shutdown()`).
///
/// Not part of the public API (metaphor ADR-0007 Decision 6 / metaphor#388): `internal` に退避済み。
/// 利用者はこれを直接生成せず、`PluginFactory.syphon(name:)`、`METAPHOR_SYPHON_NAME` による
/// 自動配線、または `MetaphorRenderer.startSyphonServer(name:)` 互換 facade を使う。
@MainActor
final class SyphonPlugin: MetaphorOutputPlugin {
    /// A stable plugin identifier. The facade (`startSyphonServer`/`stopSyphonServer`/
    /// `syphonOutput`) looks up the plugin by this ID.
    static let id = "org.metaphor.syphon-output"

    let pluginID: String

    /// The name requested at construction (`nil` = resolve lazily at attach time).
    private let requestedName: String?

    /// The Syphon server name this plugin publishes under.
    ///
    /// Resolved at attach time when ``requestedName`` is `nil`: `PluginFactory.syphon()` on a
    /// `SketchConfig` publishes under `SketchConfig.title` (set in `onAttach(sketch:)`, which
    /// `MetaphorRenderer.addPlugin(_:sketch:)` calls before `onAttach(renderer:)`); on a
    /// `SketchWindowConfig` there is no `Sketch`, so it falls back to the process name.
    private(set) var name: String?

    /// The underlying ``SyphonOutput``. Created in `onAttach(renderer:)`, destroyed in `onDetach()`.
    private(set) var output: SyphonOutput?

    /// - Parameter name: The Syphon server name. Pass `nil` to resolve it at attach time
    ///   (sketch title, else process name).
    init(name: String? = nil) {
        self.pluginID = Self.id
        self.requestedName = name
        self.name = name
    }

    // MARK: - Lifecycle

    func onAttach(sketch: any Sketch) {
        // `.syphon()`（名前省略）は「そのスケッチのタイトルで publish」（metaphor#792 D7）。
        // `SketchWindowConfig.plugins` 経由では呼ばれない（Sketch が無い）ので、その場合は
        // onAttach(renderer:) がプロセス名へ落とす。
        if name == nil {
            name = sketch.config.title
        }
    }

    func onAttach(renderer: MetaphorRenderer) {
        let resolved = name ?? ProcessInfo.processInfo.processName
        name = resolved
        // サーバーは attach 時に生成（onStart ではない）。noLoop でも生存させる。
        output = SyphonOutput(device: renderer.device, name: resolved)
    }

    func onDetach() {
        output?.stop()
        output = nil
    }

    // MARK: - Output phase

    func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        // 従来のハードコード publish と同じく flipped: true を堅持（CLI/MadMapper 受信側が
        // この向きを前提にしているため）。
        output?.publish(texture: texture, commandBuffer: commandBuffer, flipped: true)
    }
}

// MARK: - PluginFactory.syphon

extension PluginFactory {
    /// Syphon 出力を宣言します（metaphor-syphon の入口）。
    ///
    /// ```swift
    /// import MetaphorCore
    /// import MetaphorSyphon
    ///
    /// var config: SketchConfig {
    ///     SketchConfig(title: "Preview", plugins: [.syphon()])          // "Preview" で publish
    ///     // SketchConfig(plugins: [.syphon(name: "Main Out")])        // 明示名
    /// }
    /// ```
    ///
    /// 名前を省略すると ``MetaphorCore/SketchConfig/title`` で publish します
    /// （``MetaphorCore/SketchWindowConfig/plugins`` に渡した場合は `Sketch` が無いのでプロセス名）。
    /// ``MetaphorCore/PluginRequirements/externalRenderLoop`` を宣言するので、`.displayLink` の
    /// スケッチはウィンドウが隠れても publish が止まらないようタイマー駆動へ切り替わります。
    ///
    /// 環境変数 `METAPHOR_SYPHON_NAME`（`metaphor run --syphon` / `metaphor watch --syphon`）は
    /// このファクトリとは独立に、もう 1 本のサーバーをその名前で立てます。
    ///
    /// - Parameter name: Syphon クライアントから見えるサーバー名。`nil` ならスケッチのタイトル。
    /// - Returns: ``MetaphorCore/SketchConfig/plugins`` / ``MetaphorCore/SketchWindowConfig/plugins`` に渡すファクトリ。
    public static func syphon(name: String? = nil) -> PluginFactory {
        PluginFactory(requirements: [.externalRenderLoop]) { SyphonPlugin(name: name) }
    }
}
