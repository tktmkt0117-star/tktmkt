#include <metal_stdlib>
#include "../Shared/ShaderTypes.h"
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

// 画面全体を覆う三角形。uv は左上原点。
vertex VOut vs_full(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

constexpr sampler smp(filter::linear, address::clamp_to_edge);

// 解析用の縮小コピー
fragment float4 fs_copy(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
    return tex.sample(smp, in.uv);
}

static float fall(float t) {           // 0..1 の滑らかな減衰（t=距離/半径）
    t = saturate(1.0 - t);
    return t * t * (3.0 - 2.0 * t);
}

static float2 rot(float2 v, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// 出力画素 pos に対して「元画像のどこを読むか」のずれ量を返す（逆写像）
static float2 warpDisp(float2 pos, constant WarpHandle *H, int n) {
    float2 d = float2(0.0);
    for (int i = 0; i < n; i++) {
        int   type = int(H[i].p0.x);
        float R    = H[i].p0.y;
        float2 s   = H[i].p0.zw;
        float2 a   = H[i].p1.xy;
        float2 b   = H[i].p1.zw;
        if (type == HandleRadial) {
            float2 v = pos - a;
            float w = fall(length(v) / R);
            float2 ay = float2(-b.y, b.x);
            float x = dot(v, b), y = dot(v, ay);
            d += b * (-x * s.x * w) + ay * (-y * s.y * w);
        } else if (type == HandleTranslate) {
            float w = fall(length(pos - a) / R);
            d += -b * (s.x * w);
        } else if (type == HandleCapsule) {
            float2 ab = b - a;
            float t = clamp(dot(pos - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
            float2 v = pos - (a + ab * t);
            float w = fall(length(v) / R);
            d += v * (s.x * w);
        } else if (type == HandleRotate) {
            float2 v = pos - a;
            float w = fall(length(v) / R);
            d += rot(v, -s.x * w) - v;
        }
    }
    return d;
}

static float ellipseMask(float2 p, SkinEllipse e) {
    float2 v = p - e.p0.xy;
    float c = e.p1.x, s = e.p1.y;
    float2 q = float2(c * v.x + s * v.y, -s * v.x + c * v.y) / e.p0.zw;
    return 1.0 - smoothstep(1.0 - e.p1.z, 1.0, length(q));
}

static float skinMask(float2 p, constant SkinEllipse *E, int n) {
    float inc = 0.0, exc = 0.0;
    for (int i = 0; i < n; i++) {
        float m = ellipseMask(p, E[i]);
        if (E[i].p1.w > 0.5) inc = max(inc, m); else exc = max(exc, m);
    }
    return inc * (1.0 - exc);
}

// 肌色らしさ（髪・唇・背景を避ける）
static float skinColor(float3 c) {
    float y  = dot(c, float3(0.299, 0.587, 0.114));
    float cb = (c.b - y) * 0.564 + 0.5;
    float cr = (c.r - y) * 0.713 + 0.5;
    float a = smoothstep(0.28, 0.34, cb) * (1.0 - smoothstep(0.47, 0.53, cb));
    float b = smoothstep(0.50, 0.54, cr) * (1.0 - smoothstep(0.66, 0.72, cr));
    return a * b;
}

fragment float4 fs_main(VOut in [[stage_in]],
                        texture2d<float> tex [[texture(0)]],
                        constant Uniforms &U [[buffer(0)]],
                        constant WarpHandle *H [[buffer(1)]],
                        constant SkinEllipse *E [[buffer(2)]]) {
    float2 pos = float2(in.uv.x * U.aspect, in.uv.y);
    float2 src = pos + warpDisp(pos, H, U.handleCount);
    float2 suv = float2(src.x / U.aspect, src.y);
    float4 c = tex.sample(smp, suv);
    float3 rgb = c.rgb;

    float m = (U.ellipseCount > 0) ? skinMask(src, E, U.ellipseCount) : 0.0;
    m *= skinColor(rgb);

    if (m > 0.001) {
        float3 orig = rgb;
        float3 result = orig;

        if (U.smooth > 0.001) {
            // エッジ保存ぼかし（バイラテラル）。螺旋状に 24 タップ。
            float lumO = dot(orig, float3(0.299, 0.587, 0.114));
            float sigmaR = mix(0.03, 0.16, U.smooth);
            float3 acc = orig;
            float wsum = 1.0;
            for (int i = 0; i < 24; i++) {
                float r = sqrt((float(i) + 0.5) / 24.0) * U.radius;
                float ang = float(i) * 2.39996;
                float2 off = float2(cos(ang), sin(ang)) * r;
                float3 s = tex.sample(smp, float2((src.x + off.x) / U.aspect, src.y + off.y)).rgb;
                float dl = dot(s, float3(0.299, 0.587, 0.114)) - lumO;
                float w = exp(-(dl * dl) / (2.0 * sigmaR * sigmaR))
                        * exp(-(r * r) / (2.0 * U.radius * U.radius * 0.36));
                acc += s * w;
                wsum += w;
            }
            float3 smoothed = acc / wsum;

            // 毛穴レベルの細かい質感だけ戻す
            float px = U.pixel;
            float3 tiny = orig;
            tiny += tex.sample(smp, float2((src.x + px) / U.aspect, src.y)).rgb;
            tiny += tex.sample(smp, float2((src.x - px) / U.aspect, src.y)).rgb;
            tiny += tex.sample(smp, float2(src.x / U.aspect, src.y + px)).rgb;
            tiny += tex.sample(smp, float2(src.x / U.aspect, src.y - px)).rgb;
            tiny *= 0.2;
            float3 detail = orig - tiny;

            result = mix(orig, smoothed + detail * U.texture, U.smooth);
        }

        // 色補正
        float red = max(0.0, result.r - 0.5 * (result.g + result.b));
        result.r -= red * U.redness * 0.5;
        result *= 1.0 + U.brighten * 0.25;
        result.r += U.warmth * 0.04;
        result.b -= U.warmth * 0.02;

        rgb = mix(orig, result, m);
    }

    // デバッグ表示: ハンドル位置(中心の点と影響半径の輪)・肌補正範囲
    if (U.debug != 0) {
        for (int i = 0; i < U.handleCount; i++) {
            float2 a = H[i].p1.xy;
            float R = H[i].p0.y;
            float dist = length(pos - a);
            if (dist < 0.004) rgb = float3(1.0, 0.1, 0.1);
            else if (abs(dist - R) < 0.0012) rgb = mix(rgb, float3(0.1, 1.0, 0.3), 0.7);
        }
        float dm = skinMask(pos, E, U.ellipseCount);
        rgb = mix(rgb, float3(0.2, 0.5, 1.0), dm * 0.25);
    }

    return float4(rgb, c.a);
}
