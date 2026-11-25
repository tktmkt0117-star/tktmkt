# 導入ガイド（自分で行う作業）

所要時間の目安は 30〜60 分です。大半は Xcode と SDK のダウンロード待ちです。

## 0. 必要なもの

| 必要なもの | 備考 |
|---|---|
| Mac | macOS 13 以降 |
| Final Cut Pro | 最新版を推奨 |
| Xcode | App Store で無料。容量が大きい（約 10GB 以上） |
| Apple ID | 無料のままで可。署名に使う |
| Homebrew | https://brew.sh の1行コマンドで導入 |

## 1. Xcode を入れて初期設定する

1. App Store で Xcode をインストールします。
2. 一度起動し、使用許諾に同意して追加コンポーネントを入れます。
3. ターミナルで次を実行します。

   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   xcodebuild -version        # バージョンが出れば OK
   ```
4. Xcode › Settings › Accounts › 「＋」で自分の Apple ID を追加します。

## 2. FxPlug SDK を入れる

1. https://developer.apple.com/final-cut-pro/ を開きます。
2. 「FxPlug SDK」をダウンロードします（Apple ID でのログインが必要です）。
3. dmg を開き、中のインストーラ（pkg）を実行します。
4. 次の結果が出れば成功です。

   ```bash
   ls /Library/Developer/Frameworks/FxPlug.framework
   ```

## 3. Team ID を調べる

次のどちらかで調べます。

- Xcode で任意のプロジェクトを開き、Signing & Capabilities の Team 欄で自分のチームを選びます。
- https://developer.apple.com/account の Membership details に「Team ID」（英数字10文字）があります。

## 4. 導入スクリプトを実行する

```bash
git clone https://github.com/tktmkt0117-star/tktmkt.git
cd tktmkt
git checkout claude/final-cut-face-body-correction-haalgm
DEVELOPMENT_TEAM=<Team ID> ./scripts/install.sh
```

スクリプトが次の処理をします。

1. XcodeGen を入れます。
2. Xcode プロジェクトを生成します。
3. ビルドします。
4. `/Applications/PersonRetouch.app` に置きます。
5. 一度起動します。「インストールされました」というダイアログが出れば登録完了です。

署名や権限のダイアログが出たら許可してください。

## 5. ビルドエラーが出たら

この初版は未ビルドなので、**ビルドエラーが出る可能性が高い**です。

- 直す場所の見当は、`PersonRetouchPlugIn.swift` の FxPlug 関連メソッドです。
- 次のどちらかを私（Claude）に渡してください。直します。
  - ターミナルに出たエラーの赤い部分
  - Xcode の Issue Navigator のスクリーンショット
- 自分で調べる場合は、SDK 付属の「FxPlug 4 Metal」サンプルと、同名のメソッドを見比べてください。

## 6. Final Cut Pro で使う

1. Final Cut Pro を**完全に終了してから**起動し直します。
2. エフェクトブラウザで「人物補正」を探します。
3. 顔が映っているクリップにドラッグします。
4. ビデオインスペクタに、部位ごとのグループ（肌、顔の輪郭、額、眉、目、鼻、口、中顔面、体・姿勢、腕、脚）が出ます。

## 7. 動作確認の順番

1. **「デバッグ表示」をオンにします。**
   - 赤い点が目・鼻・口・輪郭の上にあれば、検出は成功です。
   - 青い楕円が顔にかかっているか見ます。
2. 「目の大きさ」を＋50 にして、目が大きくなるか確認します。
3. 「肌 › なめらかさ」を 0 と 80 で切り替えて比べます。
4. 全身が映るクリップで、腕や脚の細さ、肩の水平補正を試します。
5. デバッグ表示をオフに戻します。

## 8. うまくいかないとき

| 症状 | 確認すること |
|---|---|
| エフェクトが一覧に出ない | `/Applications/PersonRetouch.app` を一度起動したか。FCP を完全終了して再起動したか。署名の Team が設定されているか。 |
| エフェクトは出るが画面が黒い、または変化しない | デバッグ表示で何か出るか。出なければ Metal 描画の不具合の可能性があります。Console.app で `PersonRetouch` を検索し、ログを送ってください。 |
| 検出位置が上下逆、または左右にずれる | 画像の上下の向きの食い違いです。スクリーンショットを送ってください。1 か所の修正で直ります。 |
| 補正が強すぎる、弱すぎる | 想定内です。`WarpBuilder.swift` の係数が仮置きです。どのスライダーをどう感じたか教えてください。 |
| 再生が重い | 想定内です。初版はフレームごとに顔を検出します。 |

## 9. フィードバックのお願い

次を教えてもらえれば、次の改善に反映します。

- ビルドエラー、またはデバッグ表示のスクリーンショット
- 効き方が不自然だったスライダーと、そのときの映像（顔の向き、サイズ）
- 動画で顔の補正が揺れる量
