import Vision
import CoreVideo
import CoreMedia

struct AnalysisResult {
    var faces: [VNFaceObservation] = []
    var bodies: [VNHumanBodyPoseObservation] = []
}

/// Vision による顔ランドマーク・体の骨格検出。
/// フレームごとに実行し、同じ時刻の再レンダリングはキャッシュを使う。
final class Analyzer {
    static let shared = Analyzer()

    private let lock = NSLock()
    private var cache: [Int64: (key: String, result: AnalysisResult)] = [:]

    func analyze(pixelBuffer: CVPixelBuffer, time: CMTime, wantFaces: Bool, wantBody: Bool) -> AnalysisResult {
        let tkey = Int64((time.seconds * 1000).rounded())
        let flags = "\(wantFaces)\(wantBody)\(CVPixelBufferGetWidth(pixelBuffer))"
        lock.lock()
        if let hit = cache[tkey], hit.key == flags { lock.unlock(); return hit.result }
        lock.unlock()

        var requests: [VNRequest] = []
        let faceReq = VNDetectFaceLandmarksRequest()
        let bodyReq = VNDetectHumanBodyPoseRequest()
        if wantFaces { requests.append(faceReq) }
        if wantBody { requests.append(bodyReq) }

        var result = AnalysisResult()
        if !requests.isEmpty {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? handler.perform(requests)
            result.faces = Array((faceReq.results ?? []).prefix(3))
            result.bodies = Array((bodyReq.results ?? []).prefix(2))
        }

        lock.lock()
        if cache.count > 64 { cache.removeAll() }
        cache[tkey] = (flags, result)
        lock.unlock()
        return result
    }
}
