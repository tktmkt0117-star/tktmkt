import Foundation
import CoreMedia
import Metal

/// FxPlug 4 のエフェクト本体。
/// ⚠️ FxPlug SDK のシグネチャは SDK のバージョンで微妙に変わる。ビルドで差異が出たら
///    SDK 付属の "FxPlug 4 Metal" サンプルの同名メソッドに合わせて直すこと。
@objc(PersonRetouchPlugIn)
class PersonRetouchPlugIn: NSObject, FxTileableEffect {

    private let apiManager: PROAPIAccessing

    @objc required init?(apiManager: PROAPIAccessing) {
        self.apiManager = apiManager
        super.init()
    }

    // MARK: - プロパティ

    @objc func properties(_ properties: AutoreleasingUnsafeMutablePointer<NSDictionary>?) throws {
        let dict: [AnyHashable: Any] = [
            kFxPropertyKey_MayRemapTime: false,
            kFxPropertyKey_PixelTransformSupport: NSNumber(value: kFxPixelTransform_ScaleTranslate),
            kFxPropertyKey_VariesWhenParamsAreStatic: false,
            kFxPropertyKey_NeedsFullBuffer: true,       // ワープは周辺画素を読むため全体バッファが必要
            kFxPropertyKey_ChangesOutputSize: false,
        ]
        properties?.pointee = dict as NSDictionary
    }

    // MARK: - パラメータ

    @objc func addParameters() throws {
        guard let api = apiManager.api(for: FxParameterCreationAPI_v5.self) as? FxParameterCreationAPI_v5 else {
            throw NSError(domain: FxPlugErrorDomain, code: kFxError_APIUnavailable)
        }
        let flags = FxParameterFlags(kFxParameterFlag_DEFAULT)

        api.addFloatSlider(withName: "全体の強度", parameterID: ParamCatalog.amountID,
                           defaultValue: 100, parameterMin: 0, parameterMax: 100,
                           sliderMin: 0, sliderMax: 100, delta: 1, parameterFlags: flags)
        api.addToggleButton(withName: "デバッグ表示(検出位置を確認)", parameterID: ParamCatalog.debugID,
                            defaultValue: false, parameterFlags: flags)

        for g in ParamCatalog.groups {
            api.startParameterSubGroup(g.name, parameterID: g.id, parameterFlags: flags)
            for p in g.params {
                api.addFloatSlider(withName: p.name, parameterID: p.id,
                                   defaultValue: Double(p.def),
                                   parameterMin: Double(p.min), parameterMax: Double(p.max),
                                   sliderMin: Double(p.min), sliderMax: Double(p.max),
                                   delta: 1, parameterFlags: flags)
            }
            api.endParameterSubGroup()
        }
    }

    @objc func parameterChanged(_ paramID: UInt32, at time: CMTime) throws {}

    // MARK: - pluginState(パラメータをレンダリングスレッドへ渡す)

    @objc func pluginState(_ pluginState: AutoreleasingUnsafeMutablePointer<NSData>?,
                           at renderTime: CMTime, quality qualityLevel: UInt) throws {
        guard let get = apiManager.api(for: FxParameterRetrievalAPI_v6.self) as? FxParameterRetrievalAPI_v6 else {
            throw NSError(domain: FxPlugErrorDomain, code: kFxError_APIUnavailable)
        }
        var st = RenderState()
        var amount = 100.0
        get.getFloatValue(&amount, fromParameter: ParamCatalog.amountID, at: renderTime)
        st.amount = Float(amount) / 100
        var dbg = ObjCBool(false)
        get.getBoolValue(&dbg, fromParameter: ParamCatalog.debugID, at: renderTime)
        st.debug = dbg.boolValue
        for p in ParamCatalog.allParams {
            var v = 0.0
            get.getFloatValue(&v, fromParameter: p.id, at: renderTime)
            st.values[p.key] = Float(v)
        }
        pluginState?.pointee = try JSONEncoder().encode(st) as NSData
    }

    // MARK: - 領域

    @objc func destinationImageRect(_ destinationImageRect: UnsafeMutablePointer<FxRect>,
                                    sourceImages: [FxImageTile], destinationImage: FxImageTile,
                                    pluginState: Data?, at renderTime: CMTime) throws {
        destinationImageRect.pointee = sourceImages[0].imagePixelBounds
    }

    @objc func sourceTileRect(_ sourceTileRect: UnsafeMutablePointer<FxRect>,
                              sourceImageIndex: UInt, sourceImages: [FxImageTile],
                              destinationTileRect: FxRect, destinationImage: FxImageTile,
                              pluginState: Data?, at renderTime: CMTime) throws {
        // ワープは画面のどこからでも読みうるので、常に画像全体を要求する(タイル分割は未対応)
        sourceTileRect.pointee = sourceImages[0].imagePixelBounds
    }

    // MARK: - レンダリング

    @objc func renderDestinationImage(_ destinationImage: FxImageTile, sourceImages: [FxImageTile],
                                      pluginState: Data?, at renderTime: CMTime) throws {
        guard let data = pluginState,
              let state = try? JSONDecoder().decode(RenderState.self, from: data),
              let dev = MetalRenderer.shared.device(for: destinationImage.deviceRegistryID),
              let src = sourceImages.first?.metalTexture(for: dev),
              let dst = destinationImage.metalTexture(for: dev) else {
            throw NSError(domain: FxPlugErrorDomain, code: kFxError_InvalidParameter)
        }

        var warp = WarpOutput()
        if !state.isNeutral,
           let buf = MetalRenderer.shared.makeAnalysisBuffer(device: dev, source: src) {
            let res = Analyzer.shared.analyze(pixelBuffer: buf, time: renderTime,
                                              wantFaces: state.needsFace, wantBody: state.needsBody)
            warp = WarpBuilder.build(result: res, state: state, aspect: Float(src.width) / Float(src.height))
        }
        try MetalRenderer.shared.render(device: dev, source: src, destination: dst, state: state, warp: warp)
    }
}
