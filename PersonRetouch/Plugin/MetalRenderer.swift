import Metal
import CoreVideo
import CoreMedia

/// Metal 描画。ワープ+肌補正の本パスと、Vision 用の縮小コピーを担当する。
final class MetalRenderer {
    static let shared = MetalRenderer()

    private var devices: [UInt64: MTLDevice] = [:]
    private var queues: [UInt64: MTLCommandQueue] = [:]
    private var libraries: [UInt64: MTLLibrary] = [:]
    private var pipelines: [String: MTLRenderPipelineState] = [:]
    private let lock = NSLock()

    func device(for registryID: UInt64) -> MTLDevice? {
        lock.lock(); defer { lock.unlock() }
        if let d = devices[registryID] { return d }
        guard let d = MTLCopyAllDevices().first(where: { $0.registryID == registryID }) else { return nil }
        devices[registryID] = d
        return d
    }

    private func queue(_ dev: MTLDevice) -> MTLCommandQueue? {
        lock.lock(); defer { lock.unlock() }
        if let q = queues[dev.registryID] { return q }
        let q = dev.makeCommandQueue()
        queues[dev.registryID] = q
        return q
    }

    private func pipeline(_ dev: MTLDevice, fragment: String, format: MTLPixelFormat) -> MTLRenderPipelineState? {
        lock.lock(); defer { lock.unlock() }
        let key = "\(dev.registryID)-\(fragment)-\(format.rawValue)"
        if let p = pipelines[key] { return p }
        var lib = libraries[dev.registryID]
        if lib == nil {
            lib = try? dev.makeDefaultLibrary(bundle: Bundle(for: MetalRenderer.self))
            libraries[dev.registryID] = lib
        }
        guard let lib = lib else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = lib.makeFunction(name: "vs_full")
        d.fragmentFunction = lib.makeFunction(name: fragment)
        d.colorAttachments[0].pixelFormat = format
        guard let p = try? dev.makeRenderPipelineState(descriptor: d) else { return nil }
        pipelines[key] = p
        return p
    }

    // MARK: - Vision 用の縮小コピー

    /// 元テクスチャを長辺 maxSide に縮小して BGRA8 の CVPixelBuffer にする(CPU 読み出しのため同期待ち)。
    func makeAnalysisBuffer(device dev: MTLDevice, source: MTLTexture, maxSide: Int = 640) -> CVPixelBuffer? {
        guard let q = queue(dev), let pso = pipeline(dev, fragment: "fs_copy", format: .bgra8Unorm) else { return nil }
        let scale = Double(maxSide) / Double(max(source.width, source.height))
        let w = max(Int(Double(source.width) * min(scale, 1)), 16)
        let h = max(Int(Double(source.height) * min(scale, 1)), 16)

        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let small = dev.makeTexture(descriptor: td) else { return nil }

        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = small
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let cb = q.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return nil }
        enc.setRenderPipelineState(pso)
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(w), height: Double(h), znear: -1, zfar: 1))
        enc.setFragmentTexture(source, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let buf = pb else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        small.getBytes(base, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                       from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return buf
    }

    // MARK: - 本描画

    func render(device dev: MTLDevice,
                source: MTLTexture, destination: MTLTexture,
                state: RenderState, warp: WarpOutput) throws {
        guard let q = queue(dev),
              let pso = pipeline(dev, fragment: "fs_main", format: destination.pixelFormat),
              let cb = q.makeCommandBuffer() else { throw NSError(domain: "PersonRetouch", code: 1) }

        let aspect = Float(source.width) / Float(source.height)
        let scaleParam = state.raw("skinScale")                       // 0..1
        var u = Uniforms(aspect: aspect,
                         handleCount: Int32(warp.handles.count),
                         ellipseCount: Int32(warp.ellipses.count),
                         debug: state.debug ? 1 : 0,
                         smooth: state.raw("skinSmooth") * state.amount,
                         texture: state.raw("skinTexture"),
                         redness: state.raw("skinRedness") * state.amount,
                         brighten: state.raw("skinBright") * state.amount,
                         warmth: state.raw("skinWarm") * state.amount,
                         radius: (0.004 + 0.012 * scaleParam),          // 画像高さの 0.4%〜1.6%
                         pixel: 1 / Float(source.height),
                         pad: 0)

        // 空配列でも buffer が必要なのでダミーを 1 つ入れる
        var handles = warp.handles
        if handles.isEmpty { handles = [WarpHandle()] }
        var ells = warp.ellipses
        if ells.isEmpty { ells = [SkinEllipse()] }
        let hBuf = dev.makeBuffer(bytes: handles, length: MemoryLayout<WarpHandle>.stride * handles.count, options: .storageModeShared)
        let eBuf = dev.makeBuffer(bytes: ells, length: MemoryLayout<SkinEllipse>.stride * ells.count, options: .storageModeShared)

        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = destination
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        rp.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { throw NSError(domain: "PersonRetouch", code: 2) }
        enc.setRenderPipelineState(pso)
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(destination.width), height: Double(destination.height), znear: -1, zfar: 1))
        enc.setFragmentTexture(source, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.setFragmentBuffer(hBuf, offset: 0, index: 1)
        enc.setFragmentBuffer(eBuf, offset: 0, index: 2)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }
}
