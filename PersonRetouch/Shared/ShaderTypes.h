// Swift と Metal で共有する構造体。
// 座標系は「画像の高さ = 1.0、x は aspect 倍、y は下向き」の正規化空間（pos 空間）。
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

#define MAX_HANDLES 160
#define MAX_ELLIPSES 24

// ワープハンドルの種類
enum {
    HandleRadial    = 1, // 中心 a、軸 b(単位ベクトル) 基準の異方性拡大縮小。s=(軸方向, 軸直交方向) 正で拡大
    HandleTranslate = 2, // 中心 a の周囲を、単位ベクトル b の向きへ s.x だけ動かす
    HandleCapsule   = 3, // 線分 a-b を軸に周囲を細く(s.x>0)/太く(s.x<0)する
    HandleRotate    = 4  // 中心 a の周囲を s.x ラジアン回転
};

typedef struct {
    simd_float4 p0; // x=type, y=radius, z=s.x, w=s.y
    simd_float4 p1; // xy=a, zw=b
} WarpHandle;

// 肌補正を効かせる/除外する楕円
typedef struct {
    simd_float4 p0; // xy=center, zw=radii
    simd_float4 p1; // x=cos, y=sin (顔の ex 軸), z=feather(0..1), w=include(1) / exclude(0)
} SkinEllipse;

typedef struct {
    float aspect;       // 幅/高さ
    int   handleCount;
    int   ellipseCount;
    int   debug;
    float smooth;       // 0..1 なめらかさ
    float texture;      // 0..1 質感を残す量
    float redness;      // 0..1 赤み軽減
    float brighten;     // -1..1
    float warmth;       // -1..1
    float radius;       // 肌補正のぼかし半径（画像高さ=1 の単位）
    float pixel;        // 1px の大きさ（画像高さ=1 の単位）
    float pad;
} Uniforms;

#endif
