import Foundation

/// FxPlug の pluginState として GPU レンダリング側へ渡す値。
struct RenderState: Codable {
    var amount: Float = 1          // 全体の強度 0..1
    var debug: Bool = false
    var values: [String: Float] = [:]

    func v(_ key: String) -> Float { (values[key] ?? 0) / 100 * amount }
    /// 肌の「なめらかさ」などは 0..1 のまま使う(強度は掛ける)
    func raw(_ key: String) -> Float { (values[key] ?? 0) / 100 }

    private func anyNonZero(_ region: Region, excluding: Set<String> = []) -> Bool {
        for g in ParamCatalog.groups where g.region == region {
            for p in g.params where !excluding.contains(p.key) {
                if abs(values[p.key] ?? 0) > 0.01 { return true }
            }
        }
        return false
    }

    /// 顔の検出が必要か(肌補正も顔の範囲を使うので含む)
    var needsFace: Bool {
        anyNonZero(.skin, excluding: ["skinScale", "skinTexture"]) || anyNonZero(.face)
    }
    var needsBody: Bool { anyNonZero(.body) }
    var isNeutral: Bool { !needsFace && !needsBody }
}
