import CMetaphorSyphonBootstrap
import Metal
import MetaphorCore

/// The Syphon output module (the `metaphor-syphon` package).
///
/// Publishes a sketch's final frame as a Syphon server so MadMapper / Resolume / VDMX and
/// other Syphon clients can read it. Linking this module registers its output provider with
/// ``MetaphorCore/MetaphorOutputProviders`` at load time (C constructor), so the only thing a
/// sketch has to do is declare the output:
///
/// ```swift
/// import MetaphorCore
/// import MetaphorSyphon
///
/// @main
/// final class MySketch: Sketch {
///     var config: SketchConfig {
///         SketchConfig(title: "Preview", plugins: [.syphon()])   // publishes as "Preview"
///     }
///     func draw() { /* ... */ }
/// }
/// ```
///
/// The environment variable `METAPHOR_SYPHON_NAME` (set by `metaphor run --syphon` /
/// `metaphor watch --syphon`) enables a server under that name without touching the sketch.
///
/// Until metaphor removes them, the deprecated `SketchConfig.syphon` / `syphonName` and
/// `SketchWindowConfig.syphonName` are still honoured by the provider, so existing sketches
/// keep publishing once they link this package.
public enum MetaphorSyphon {
    /// このパッケージのリリース版（`release.yml` が毎リリースで書き換える）。
    ///
    /// 依存している metaphor 本体の版は `MetaphorVersion` を見る。
    public static let version = "0.1.1"

    /// Explicitly registers the Syphon output provider.
    ///
    /// This normally does not need to be called, since registration happens automatically
    /// at load time via a C constructor. It is exposed as a fallback for unusual
    /// configurations where automatic registration does not run (e.g. static linking that never references the output target).
    /// Calling it more than once is harmless: the provider is keyed by its id and replaced, not duplicated.
    public static func enable() {
        installSyphonOutputProvider()
    }
}

/// Registers ``SyphonOutputProvider`` with ``MetaphorOutputProviders``.
///
/// Registration is lock-protected storage, so it can be called from the non-isolated
/// context at load time (the constructor). Plugin creation happens later on `MainActor`
/// (`SketchRunner` / `SketchWindow` call `makeOutput(context:)`).
private func installSyphonOutputProvider() {
    // bootstrap.o（ロード時コンストラクタを含む）への実参照。静的アーカイブ経由の
    // リンクでは、シンボル参照のないオブジェクトファイルが selective loading で
    // 落とされ、__attribute__((constructor)) ごと消える。この no-op 呼び出しが
    // MetaphorSyphon → CMetaphorSyphonBootstrap の依存辺を作り、どのリンク構成でも
    // コンストラクタを確実にバイナリへ残す（アンカー）。
    cmetaphor_syphon_bootstrap_touch()
    MetaphorOutputProviders.register(SyphonOutputProvider())
}

/// The registration function called from C's `__attribute__((constructor))` (`CMetaphorSyphonBootstrap`).
///
/// When `MetaphorSyphon` (-> `CMetaphorSyphonBootstrap`) is linked, this function is called
/// at process startup, registering the output provider even if user code never references
/// a symbol of `MetaphorSyphon` beyond the `import`.
///
/// `internal` で十分（metaphor ADR-0007 論点 6）。`@_cdecl` はアクセス修飾子と独立に C リンケージの
/// シンボル `metaphor_syphon_register` を生成するため、`public` にしなくても bootstrap.c から
/// 解決できる。debug/release × クロスパッケージで自動登録が生きることは CI の
/// `registration-matrix`（scripts/check-registration.sh）が毎 PR で確かめる（metaphor ADR-0001）。
@_cdecl("metaphor_syphon_register")
func metaphorSyphonRegister() {
    installSyphonOutputProvider()
}

// MARK: - 後方互換 facade

extension MetaphorRenderer {
    /// An optional Syphon output for sharing video between applications.
    ///
    /// Backward-compatibility facade: Syphon output is implemented internally as
    /// `SyphonPlugin`; this property returns the ``SyphonOutput`` held by the registered `SyphonPlugin`.
    public var syphonOutput: SyphonOutput? {
        (plugin(id: SyphonPlugin.id) as? SyphonPlugin)?.output
    }

    /// Starts a Syphon server under the given name for sharing textures between applications.
    ///
    /// Internally, this registers a `SyphonPlugin` that runs in the output phase. If Syphon
    /// is already running, it is replaced (preventing double publishing).
    /// - Parameter name: The name to publish as the Syphon server
    public func startSyphonServer(name: String) {
        if plugin(id: SyphonPlugin.id) != nil {
            removePlugin(id: SyphonPlugin.id)   // onDetach → 旧サーバー停止
        }
        addPlugin(SyphonPlugin(name: name))     // onAttach(renderer:) → 新サーバー生成
    }

    /// Stops the Syphon server and releases its resources.
    public func stopSyphonServer() {
        removePlugin(id: SyphonPlugin.id)       // onDetach → stop + 配列から除去
    }
}
