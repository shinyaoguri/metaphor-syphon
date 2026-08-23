import Foundation
import Metal
import Testing
@testable import MetaphorCore
@testable import MetaphorSyphon

// Syphon の自動配線（名前解決と provider の判定）を固定する。
// metaphor v0.11.0 の in-tree 版（Tests/metaphorTests/SyphonOutputProviderTests.swift）を
// S0（metaphor#1039）で持ち出したもの。MetaphorCore の公開 API と MetaphorSyphon の
// internal だけに依存する。旧 `syphon:` / `syphonName:` を読む窓は本体 0.13 の削除に合わせて
// 0.2.0 で外した（#6）ので、自動配線の入口は `METAPHOR_SYPHON_NAME` だけ。

// MARK: - 名前解決

@Suite("Syphon output name resolution")
struct SyphonOutputNameResolutionTests {

    @Test("no output by default")
    func disabledByDefault() {
        #expect(SyphonOutputProvider.resolveSyphonName(env: [:]) == nil)
    }

    @Test("METAPHOR_SYPHON_NAME alone enables output")
    func envAloneEnables() {
        #expect(SyphonOutputProvider.resolveSyphonName(env: ["METAPHOR_SYPHON_NAME": "FromEnv"]) == "FromEnv")
    }

    @Test("empty METAPHOR_SYPHON_NAME is treated as unset")
    func emptyEnvIsUnset() {
        #expect(SyphonOutputProvider.resolveSyphonName(env: ["METAPHOR_SYPHON_NAME": ""]) == nil)
    }

}

// MARK: - provider の判定

@Suite("SyphonOutputProvider")
struct SyphonOutputProviderTests {

    @Test("id と要件（外部ループ）")
    func identity() {
        let provider = SyphonOutputProvider()
        #expect(provider.id == "org.metaphor.syphon")
        #expect(provider.requirements == [.externalRenderLoop])
    }

    @Test("プライマリ: env だけで publish。ヘッドレスでも暗黙には publish しない（ADR-0014）")
    func primaryScopeWithoutLegacyFields() {
        func name(_ config: SketchConfig, env: [String: String] = [:], headless: Bool = false) -> String? {
            SyphonOutputProvider.resolveOutputName(context: MetaphorOutputContext(
                scope: .primary(config), environment: env, isHeadless: headless
            ))
        }
        #expect(name(SketchConfig(title: "T")) == nil)
        #expect(name(SketchConfig(title: "T"), env: ["METAPHOR_SYPHON_NAME": "E"]) == "E")
        #expect(name(SketchConfig(title: "T"), headless: true) == nil,
                "ヘッドレスの観測は viewer frame IPC / Probe が担う。Syphon は明示の要求だけ")
        #expect(name(SketchConfig(title: "T"), env: ["METAPHOR_SYPHON_NAME": "W"], headless: true) == "W",
                "cli の --syphon が注入する METAPHOR_SYPHON_NAME は従来どおり効く")
    }

    @Test("セカンダリウィンドウ: env / ヘッドレスでは publish しない")
    func windowScopeWithoutLegacyFields() {
        func name(_ config: SketchWindowConfig, env: [String: String] = [:], headless: Bool = false) -> String? {
            SyphonOutputProvider.resolveOutputName(context: MetaphorOutputContext(
                scope: .window(config), environment: env, isHeadless: headless
            ))
        }
        #expect(name(SketchWindowConfig()) == nil)
        #expect(name(SketchWindowConfig(), env: ["METAPHOR_SYPHON_NAME": "E"]) == nil)
        #expect(name(SketchWindowConfig(), headless: true) == nil, "セカンダリはヘッドレスでも暗黙に publish しない（従来どおり）")
    }

    @Test("makeOutput は名前が決まるときだけ SyphonPlugin を返す")
    @MainActor
    func makeOutput() {
        let provider = SyphonOutputProvider()
        let on = provider.makeOutput(context: MetaphorOutputContext(
            scope: .primary(SketchConfig(title: "T")), environment: ["METAPHOR_SYPHON_NAME": "E"], isHeadless: false
        ))
        let plugin = on as? SyphonPlugin
        #expect(plugin != nil)
        #expect(plugin?.name == "E")

        let off = provider.makeOutput(context: MetaphorOutputContext(
            scope: .primary(SketchConfig(title: "T")), environment: [:], isHeadless: false
        ))
        #expect(off == nil)
    }
}

// MARK: - 自動登録（C コンストラクタ）

@Suite("MetaphorSyphon registration")
struct MetaphorSyphonRegistrationTests {

    /// このテスト target が MetaphorSyphon をリンクしているだけで、ロード時の C コンストラクタ
    /// （CMetaphorSyphonBootstrap → `metaphor_syphon_register`）が provider を登録している。
    /// `enable()` は明示呼び出しの保険で、二重に呼んでも置換になる（重複しない）。
    @Test("auto-registers an output provider at load; enable() is idempotent")
    @MainActor
    func autoRegistered() throws {
        func registeredSyphonProviders() -> [any MetaphorOutputProvider] {
            MetaphorOutputProviders.registered.filter { $0.id == SyphonOutputProvider.providerID }
        }
        let before = registeredSyphonProviders()
        #expect(before.count == 1, "C constructor から 1 件だけ登録されている")
        #expect(before.first?.requirements == [.externalRenderLoop])

        MetaphorSyphon.enable()
        MetaphorSyphon.enable()
        #expect(registeredSyphonProviders().count == 1, "enable() の重複呼び出しは置換で吸収される")

        // 走査結果にも Syphon が含まれ、要件が集計される（= 従来の自動タイマー切替）。
        let context = MetaphorOutputContext(
            scope: .primary(SketchConfig(title: "metaphor-registry-test")),
            environment: ["METAPHOR_SYPHON_NAME": "metaphor-registry-test"], isHeadless: false
        )
        let outputs = MetaphorOutputProviders.makeOutputs(context: context)
        #expect(outputs.contains { $0.providerID == SyphonOutputProvider.providerID && $0.plugin is SyphonPlugin })
        #expect(outputs.first { $0.providerID == SyphonOutputProvider.providerID }?.requirements == [.externalRenderLoop])
    }

    @Test("version is a semantic version string")
    func version() {
        let parts = MetaphorSyphon.version.split(separator: ".")
        #expect(parts.count == 3, "MAJOR.MINOR.PATCH（release.yml が書き換える）: \(MetaphorSyphon.version)")
        #expect(parts.allSatisfy { Int($0) != nil })
    }
}

// MARK: - PluginFactory.syphon（D7 の到達形）

/// `.syphon()` の名前解決に使う最小の Sketch。`onAttach(sketch:)` が読むのは `config.title` だけ。
@MainActor
private final class TitledSketch: Sketch {
    init() {}
    var config: SketchConfig { SketchConfig(title: "FromTitle") }
    func draw() {}
}

@Suite("PluginFactory.syphon")
struct PluginFactorySyphonTests {

    @Test("declares externalRenderLoop and creates a SyphonPlugin")
    @MainActor
    func factoryShape() {
        let factory = PluginFactory.syphon(name: "Main Out")
        #expect(factory.requirements == [.externalRenderLoop], "ウィンドウが隠れても publish を続ける = timer を要求")
        let plugin = factory.create() as? SyphonPlugin
        #expect(plugin != nil)
        #expect(plugin?.pluginID == SyphonPlugin.id)
        #expect(plugin?.name == "Main Out")
        #expect(plugin?.output == nil, "サーバーは onAttach(renderer:) まで作らない")
    }

    @Test(".syphon() resolves the name from the sketch title at attach time")
    @MainActor
    func lazyNameFromSketchTitle() {
        let plugin = PluginFactory.syphon().create() as? SyphonPlugin
        #expect(plugin?.name == nil, "名前は attach まで未定")
        plugin?.onAttach(sketch: TitledSketch())
        #expect(plugin?.name == "FromTitle")
    }

    @Test("an explicit name wins over the sketch title")
    @MainActor
    func explicitNameWins() {
        let plugin = PluginFactory.syphon(name: "Explicit").create() as? SyphonPlugin
        plugin?.onAttach(sketch: TitledSketch())
        #expect(plugin?.name == "Explicit")
    }
}

// MARK: - サーバー生成（GPU が要る）

/// Syphon サーバーの生成は Metal デバイスが要る。GitHub-hosted の macos-14 は
/// `MTLCreateSystemDefaultDevice()` が nil（metaphor#332）なので、そこでは skip する。
@Suite("Syphon server lifecycle", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SyphonServerLifecycleTests {

    /// ヘッドレスモードのフレーム出力先 Syphon サーバーが起動でき、`syphonOutput` facade
    /// （= 登録済み SyphonPlugin の SyphonOutput）から参照できる。
    @Test("startSyphonServer activates the frame sink; stopSyphonServer releases it")
    func facade() throws {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        #expect(renderer.syphonOutput == nil)
        #expect(renderer.plugin(id: SyphonPlugin.id) == nil)

        renderer.startSyphonServer(name: "metaphor-syphon-facade-test")
        #expect(renderer.syphonOutput?.isActive == true)
        #expect(renderer.syphonOutput?.serverName == "metaphor-syphon-facade-test")
        #expect(renderer.plugin(id: SyphonPlugin.id) != nil)

        // 再起動は置換（二重 publish にならない）。
        renderer.startSyphonServer(name: "metaphor-syphon-facade-test-2")
        #expect(renderer.syphonOutput?.serverName == "metaphor-syphon-facade-test-2")

        renderer.stopSyphonServer()
        #expect(renderer.syphonOutput == nil)
        #expect(renderer.plugin(id: SyphonPlugin.id) == nil)
    }

    /// `.syphon()` を SketchWindowConfig（Sketch 無し）で使ったときはプロセス名で publish する。
    @Test(".syphon() without a sketch falls back to the process name")
    func processNameFallback() throws {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        let plugin = try #require(PluginFactory.syphon().create() as? SyphonPlugin)
        renderer.addPlugin(plugin)   // onAttach(renderer:) のみ = セカンダリウィンドウの経路
        #expect(plugin.name == ProcessInfo.processInfo.processName)
        #expect(plugin.output?.isActive == true)
        renderer.removePlugin(id: SyphonPlugin.id)
        #expect(plugin.output == nil, "onDetach でサーバーを止める")
    }
}
