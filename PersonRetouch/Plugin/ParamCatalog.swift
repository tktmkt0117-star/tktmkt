import Foundation

/// スライダー1本の定義。key は WarpBuilder が参照する。
struct ParamDef {
    let id: UInt32
    let key: String
    let name: String
    let def: Float
    let min: Float
    let max: Float
}

enum Region { case skin, face, body }

struct ParamGroup {
    let id: UInt32
    let name: String
    let region: Region
    let params: [ParamDef]
}

/// 全パラメータのカタログ。UI の並び・範囲・初期値はここだけで決まる。
/// ⚠️ 既存プロジェクトとの互換のため、ID は「末尾に追加のみ」。並び替え・途中挿入をしないこと。
enum ParamCatalog {
    static let amountID: UInt32 = 1
    static let debugID: UInt32 = 2

    static let groups: [ParamGroup] = build()

    static var allParams: [ParamDef] { groups.flatMap { $0.params } }

    private static func build() -> [ParamGroup] {
        var nextGroup: UInt32 = 10
        var nextParam: UInt32 = 100

        func param(_ key: String, _ name: String, def: Float = 0, min: Float = -100, max: Float = 100) -> ParamDef {
            defer { nextParam += 1 }
            return ParamDef(id: nextParam, key: key, name: name, def: def, min: min, max: max)
        }
        func group(_ name: String, _ region: Region, _ params: [ParamDef]) -> ParamGroup {
            defer { nextGroup += 1 }
            return ParamGroup(id: nextGroup, name: name, region: region, params: params)
        }
        // 0〜100 のスライダー
        func pos(_ key: String, _ name: String, def: Float = 0) -> ParamDef { param(key, name, def: def, min: 0, max: 100) }

        return [
            group("肌", .skin, [
                pos("skinSmooth", "なめらかさ", def: 30),
                pos("skinTexture", "質感を残す", def: 60),
                pos("skinScale", "補正の粒度(大きいほどシミ・くすみまで)", def: 40),
                pos("skinRedness", "赤み・ニキビ跡を抑える"),
                param("skinBright", "明るさ"),
                param("skinWarm", "血色(＋で赤み/－で青白く)"),
            ]),
            group("顔の輪郭", .face, [
                param("faceWidth", "顔の幅(－で小顔)"),
                param("faceLength", "顔の縦の長さ"),
                param("cheek", "頬(－でシャープ)"),
                param("jaw", "エラ(－で細く)"),
                param("chinLen", "あごの長さ"),
                param("chinWidth", "あご先の幅"),
                param("faceTilt", "顔の傾き補正", min: 0, max: 100),
            ]),
            group("額(デコ)", .face, [
                param("foreHeight", "額の広さ(＋で広く)"),
                param("foreRound", "額のふくらみ"),
            ]),
            group("眉", .face, [
                param("browHeight", "眉の高さ"),
            ]),
            group("目", .face, [
                param("eyeSize", "目の大きさ"),
                param("eyeWidth", "目の横幅"),
                param("eyeHeight", "目の縦幅"),
                param("eyeTilt", "目尻(＋で上げる/－で下げる)"),
                param("eyeSpacing", "目の間隔(＋で離す)"),
                param("eyeY", "目の位置(＋で上)"),
            ]),
            group("鼻", .face, [
                param("noseBridge", "鼻筋の太さ(－で細く)"),
                param("noseWing", "小鼻の幅(－で小さく)"),
                param("noseLength", "鼻の長さ(＋で先端を下げる)"),
                param("noseSize", "鼻全体の大きさ"),
            ]),
            group("口", .face, [
                param("mouthWidth", "口の横幅"),
                param("lipThick", "唇の厚み"),
                param("mouthY", "口の位置(＋で下)"),
                param("mouthCorner", "口角(＋で上げる)"),
            ]),
            group("中顔面", .face, [
                param("midLen", "中顔面の長さ(目〜口。－で短く)"),
                param("philtrum", "人中の長さ(鼻の下)"),
            ]),
            group("体・姿勢", .body, [
                pos("posture", "肩の水平補正"),
                pos("lean", "体軸の傾き補正(猫背・傾き)"),
                param("shoulderWidth", "肩幅"),
                param("chestDent", "胸をへこます", min: 0, max: 100),
                param("waist", "ウエストの細さ"),
                param("torsoSlim", "胴体全体の細さ"),
            ]),
            group("腕", .body, [
                param("upperArm", "二の腕の細さ"),
                param("foreArm", "前腕の細さ"),
            ]),
            group("脚", .body, [
                param("thigh", "太ももの細さ"),
                param("calf", "ふくらはぎの細さ"),
                param("legAll", "脚全体の細さ"),
            ]),
        ]
    }
}
