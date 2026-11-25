import Vision
import simd

typealias V2 = SIMD2<Float>

/// ランドマークとスライダー値から、GPU に渡すワープハンドルと肌補正の範囲を作る。
/// 符号の約束: 顔のスライダーは「＋で大きく/広く/高く/長く」。細さ系(腕・脚・腰)は「＋で細く」。
struct WarpOutput {
    var handles: [WarpHandle] = []
    var ellipses: [SkinEllipse] = []
}

enum WarpBuilder {

    static func build(result: AnalysisResult, state: RenderState, aspect: Float) -> WarpOutput {
        var out = WarpOutput()
        for f in result.faces { addFace(f, state, aspect, &out) }
        for b in result.bodies { addBody(b, state, aspect, &out) }
        if out.handles.count > Int(MAX_HANDLES) { out.handles = Array(out.handles.prefix(Int(MAX_HANDLES))) }
        if out.ellipses.count > Int(MAX_ELLIPSES) { out.ellipses = Array(out.ellipses.prefix(Int(MAX_ELLIPSES))) }
        return out
    }

    // MARK: - ハンドル生成ヘルパー

    private static func add(_ out: inout WarpOutput, _ type: Int32, r: Float, s: V2, a: V2, b: V2) {
        guard abs(s.x) > 1e-4 || abs(s.y) > 1e-4, r > 1e-5 else { return }
        out.handles.append(WarpHandle(p0: SIMD4(Float(type), r, s.x, s.y), p1: SIMD4(a.x, a.y, b.x, b.y)))
    }
    private static func radial(_ o: inout WarpOutput, _ a: V2, _ ax: V2, r: Float, sx: Float, sy: Float) {
        add(&o, Int32(HandleRadial), r: r, s: V2(sx, sy), a: a, b: ax)
    }
    private static func translate(_ o: inout WarpOutput, _ a: V2, dir: V2, dist: Float, r: Float) {
        add(&o, Int32(HandleTranslate), r: r, s: V2(dist, 0), a: a, b: dir)
    }
    private static func capsule(_ o: inout WarpOutput, _ a: V2, _ b: V2, r: Float, s: Float) {
        add(&o, Int32(HandleCapsule), r: r, s: V2(s, 0), a: a, b: b)
    }
    private static func rotate(_ o: inout WarpOutput, _ a: V2, r: Float, angle: Float) {
        add(&o, Int32(HandleRotate), r: r, s: V2(angle, 0), a: a, b: .zero)
    }

    private static func mean(_ p: [V2]) -> V2 { p.isEmpty ? .zero : p.reduce(.zero, +) / Float(p.count) }
    /// axis 方向の両端の点
    private static func extremes(_ p: [V2], _ axis: V2) -> (lo: V2, hi: V2) {
        let sorted = p.sorted { dot($0, axis) < dot($1, axis) }
        return (sorted.first ?? .zero, sorted.last ?? .zero)
    }

    // MARK: - 顔

    private static func addFace(_ f: VNFaceObservation, _ st: RenderState, _ aspect: Float, _ out: inout WarpOutput) {
        guard let lm = f.landmarks else { return }
        let bb = f.boundingBox

        func pts(_ r: VNFaceLandmarkRegion2D?) -> [V2] {
            guard let r = r else { return [] }
            return r.normalizedPoints.map { p in
                V2(Float(bb.minX + p.x * bb.width) * aspect, 1 - Float(bb.minY + p.y * bb.height))
            }
        }

        let eyesRaw = [pts(lm.leftEye), pts(lm.rightEye)].filter { !$0.isEmpty }
        let contour = pts(lm.faceContour)
        guard eyesRaw.count == 2, contour.count >= 9 else { return }

        // 画像上の左右(x の小さい方が image-left)
        let eyes = eyesRaw.sorted { mean($0).x < mean($1).x }
        let eyeCenters = eyes.map(mean)
        let eyeVec = eyeCenters[1] - eyeCenters[0]
        let D = length(eyeVec)                        // 目の間隔(顔のスケール基準)
        guard D > 1e-4 else { return }
        let ex = eyeVec / D                           // 顔の右向き
        let ey = V2(-ex.y, ex.x)                      // 顔の下向き(y 下向き座標)

        let faceCenter = mean(contour)
        let (cLo, cHi) = extremes(contour, ex)
        let faceW = max(dot(cHi - cLo, ex), D)
        let (_, chinPt) = extremes(contour, ey)
        let (topPt, _) = extremes(contour, ey)
        let faceH = max(dot(chinPt - topPt, ey), D)

        let browsRaw = [pts(lm.leftEyebrow), pts(lm.rightEyebrow)].filter { !$0.isEmpty }
        let browMid = browsRaw.isEmpty ? (eyeCenters[0] + eyeCenters[1]) / 2 - ey * (0.35 * D)
                                       : mean(browsRaw.flatMap { $0 })

        // ---- 肌補正の範囲 ----
        let ang = ex
        let skinC = faceCenter - ey * (0.2 * faceH)
        out.ellipses.append(SkinEllipse(p0: SIMD4(skinC.x, skinC.y, faceW * 0.52, faceH * 0.78),
                                        p1: SIMD4(ang.x, ang.y, 0.3, 1)))
        for e in eyes {
            let (lo, hi) = extremes(e, ex); let w = length(hi - lo)
            let c = mean(e)
            out.ellipses.append(SkinEllipse(p0: SIMD4(c.x, c.y, w * 0.62, w * 0.42), p1: SIMD4(ang.x, ang.y, 0.5, 0)))
        }
        for b in browsRaw {
            let (lo, hi) = extremes(b, ex); let w = length(hi - lo); let c = mean(b)
            out.ellipses.append(SkinEllipse(p0: SIMD4(c.x, c.y, w * 0.62, w * 0.28), p1: SIMD4(ang.x, ang.y, 0.5, 0)))
        }
        let lips = pts(lm.outerLips)
        if !lips.isEmpty {
            let (lo, hi) = extremes(lips, ex); let w = length(hi - lo); let c = mean(lips)
            out.ellipses.append(SkinEllipse(p0: SIMD4(c.x, c.y, w * 0.6, w * 0.36), p1: SIMD4(ang.x, ang.y, 0.4, 0)))
        }

        // ---- 顔の傾き補正 ----
        let roll = atan2(ex.y, ex.x)
        rotate(&out, faceCenter, r: faceW * 1.4, angle: -roll * st.raw("faceTilt") * st.amount)

        // ---- 輪郭 ----
        let n = contour.count
        func contourPt(_ frac: Float, mirrored: Bool) -> V2 {
            let i = Int(frac * Float(n - 1))
            return contour[mirrored ? n - 1 - i : i]
        }
        func outward(_ p: V2) -> V2 { dot(p - faceCenter, ex) >= 0 ? ex : -ex }
        func sides(_ frac: Float, amount: Float, r: Float) {
            for m in [false, true] {
                let p = contourPt(frac, mirrored: m)
                translate(&out, p, dir: outward(p), dist: amount, r: r)
            }
        }
        let vw = st.v("faceWidth") * 0.10 * faceW
        sides(0.14, amount: vw * 0.6, r: 0.34 * faceW)
        sides(0.26, amount: vw * 1.0, r: 0.34 * faceW)
        sides(0.38, amount: vw * 0.8, r: 0.30 * faceW)
        sides(0.20, amount: st.v("cheek") * 0.10 * faceW, r: 0.30 * faceW)
        sides(0.32, amount: st.v("jaw") * 0.10 * faceW, r: 0.28 * faceW)
        sides(0.43, amount: st.v("chinWidth") * 0.10 * faceW, r: 0.22 * faceW)
        translate(&out, chinPt, dir: ey, dist: st.v("chinLen") * 0.15 * faceW, r: 0.45 * faceW)
        radial(&out, faceCenter, ex, r: 1.4 * faceW, sx: 0, sy: st.v("faceLength") * 0.12)

        // ---- 額 ----
        let foreC = browMid - ey * (0.55 * D)
        translate(&out, foreC, dir: -ey, dist: st.v("foreHeight") * 0.20 * D, r: 1.0 * D)
        let fr = st.v("foreRound") * 0.25
        radial(&out, foreC, ex, r: 0.8 * D, sx: fr, sy: fr)

        // ---- 眉 ----
        for b in browsRaw {
            let (lo, hi) = extremes(b, ex); let w = length(hi - lo)
            translate(&out, mean(b), dir: -ey, dist: st.v("browHeight") * 0.15 * D, r: max(w, 0.3 * D))
        }

        // ---- 目 ----
        for (idx, e) in eyes.enumerated() {
            let side: Float = idx == 0 ? -1 : 1          // -1: 画像の左, +1: 画像の右
            let (lo, hi) = extremes(e, ex); let w = max(length(hi - lo), 0.2 * D)
            let c = mean(e)
            let outer = side < 0 ? lo : hi
            let s = st.v("eyeSize") * 0.35
            radial(&out, c, ex, r: w * 1.3, sx: s + st.v("eyeWidth") * 0.30, sy: s + st.v("eyeHeight") * 0.40)
            translate(&out, outer, dir: -ey, dist: st.v("eyeTilt") * 0.15 * w, r: 0.55 * w)
            translate(&out, c, dir: ex * side, dist: st.v("eyeSpacing") * 0.15 * D, r: w * 1.1)
            translate(&out, c, dir: -ey, dist: st.v("eyeY") * 0.12 * D, r: w * 1.2)
        }

        // ---- 鼻 ----
        let nose = pts(lm.nose)
        if !nose.isEmpty {
            let noseC = mean(nose)
            let (wl, wh) = extremes(nose, ex)
            let noseW = max(length(wh - wl), 0.2 * D)
            let (_, tip) = extremes(nose, ey)
            let crest = pts(lm.noseCrest)
            let crestC = crest.isEmpty ? noseC - ey * (0.15 * D) : mean(crest)
            radial(&out, crestC, ex, r: 0.6 * D, sx: st.v("noseBridge") * 0.30, sy: 0)
            translate(&out, wl, dir: -ex, dist: st.v("noseWing") * 0.25 * noseW, r: 0.55 * noseW)
            translate(&out, wh, dir: ex, dist: st.v("noseWing") * 0.25 * noseW, r: 0.55 * noseW)
            translate(&out, tip, dir: ey, dist: st.v("noseLength") * 0.20 * D, r: 0.45 * D)
            let ns = st.v("noseSize") * 0.25
            radial(&out, noseC, ex, r: 0.8 * D, sx: ns, sy: ns)

            // ---- 中顔面 ----
            if !lips.isEmpty {
                let lipC = mean(lips)
                let mid = (tip + lipC) / 2
                translate(&out, mid, dir: ey, dist: st.v("midLen") * 0.18 * D, r: 0.9 * D)
                radial(&out, mid, ex, r: 0.6 * D, sx: 0, sy: st.v("philtrum") * 0.40)
            }
        }

        // ---- 口 ----
        if !lips.isEmpty {
            let c = mean(lips)
            let (lo, hi) = extremes(lips, ex); let w = max(length(hi - lo), 0.3 * D)
            radial(&out, c, ex, r: w * 1.1, sx: st.v("mouthWidth") * 0.30, sy: 0)
            radial(&out, c, ex, r: w * 0.7, sx: 0, sy: st.v("lipThick") * 0.40)
            translate(&out, c, dir: ey, dist: st.v("mouthY") * 0.12 * D, r: w * 0.9)
            translate(&out, lo, dir: -ey, dist: st.v("mouthCorner") * 0.08 * D, r: 0.3 * w)
            translate(&out, hi, dir: -ey, dist: st.v("mouthCorner") * 0.08 * D, r: 0.3 * w)
        }
    }

    // MARK: - 体

    private static func addBody(_ o: VNHumanBodyPoseObservation, _ st: RenderState, _ aspect: Float, _ out: inout WarpOutput) {
        guard let jp = try? o.recognizedPoints(.all) else { return }
        func J(_ n: VNHumanBodyPoseObservation.JointName) -> V2? {
            guard let p = jp[n], p.confidence > 0.25 else { return nil }
            return V2(Float(p.location.x) * aspect, 1 - Float(p.location.y))
        }
        guard let ls = J(.leftShoulder), let rs = J(.rightShoulder) else { return }
        let (A, B) = ls.x < rs.x ? (ls, rs) : (rs, ls)
        let sw = length(B - A)
        guard sw > 1e-3 else { return }
        let sm = (A + B) / 2
        let bx = (B - A) / sw

        var hm = sm + V2(0, 1) * (sw * 1.6)
        if let lh = J(.leftHip), let rh = J(.rightHip) { hm = (lh + rh) / 2 }
        let tlen = max(length(hm - sm), sw)
        let tdir = normalize(hm - sm)
        let tperp = V2(-tdir.y, tdir.x)

        // 肩の水平・体軸
        let theta = atan2(B.y - A.y, B.x - A.x)
        rotate(&out, sm, r: sw * 1.3, angle: -theta * st.raw("posture") * st.amount)
        let neck = J(.neck) ?? sm
        translate(&out, neck, dir: V2(1, 0), dist: (hm.x - neck.x) * st.raw("lean") * st.amount * 0.8, r: tlen * 0.9)

        // 肩幅
        translate(&out, A, dir: -bx, dist: st.v("shoulderWidth") * 0.12 * sw, r: 0.5 * sw)
        translate(&out, B, dir: bx, dist: st.v("shoulderWidth") * 0.12 * sw, r: 0.5 * sw)

        // 胸をへこます(＋でへこむ)
        let dent = -st.v("chestDent") * 0.30
        for sgn: Float in [-1, 1] {
            let c = sm + tdir * (0.28 * tlen) + tperp * (sgn * 0.2 * sw)
            radial(&out, c, bx, r: 0.34 * sw, sx: dent, sy: dent)
        }

        // 胴(＋で細く)
        capsule(&out, sm + tdir * (0.5 * tlen), sm + tdir * (0.9 * tlen), r: sw * 0.75, s: st.v("waist") * 0.35)
        capsule(&out, sm + tdir * (0.1 * tlen), hm, r: sw * 0.8, s: st.v("torsoSlim") * 0.25)

        // 腕
        let arms: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] =
            [(.leftShoulder, .leftElbow, .leftWrist), (.rightShoulder, .rightElbow, .rightWrist)]
        for (s, e, w) in arms {
            if let ps = J(s), let pe = J(e) {
                capsule(&out, ps, pe, r: max(0.45 * length(pe - ps), 0.02), s: st.v("upperArm") * 0.35)
                if let pw = J(w) {
                    capsule(&out, pe, pw, r: max(0.45 * length(pw - pe), 0.02), s: st.v("foreArm") * 0.35)
                }
            }
        }

        // 脚
        let legs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] =
            [(.leftHip, .leftKnee, .leftAnkle), (.rightHip, .rightKnee, .rightAnkle)]
        for (h, k, a) in legs {
            if let ph = J(h), let pk = J(k) {
                let r1 = max(0.4 * length(pk - ph), 0.02)
                capsule(&out, ph, pk, r: r1, s: (st.v("thigh") + st.v("legAll")) * 0.35)
                if let pa = J(a) {
                    let r2 = max(0.4 * length(pa - pk), 0.02)
                    capsule(&out, pk, pa, r: r2, s: (st.v("calf") + st.v("legAll")) * 0.35)
                }
            }
        }
    }
}
