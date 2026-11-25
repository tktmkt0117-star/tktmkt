import AppKit

// プラグインを Final Cut Pro に登録するための入れ物アプリ。
// 一度起動して /Applications に置くだけで、中の XPC サービスが FCP から見える。
let app = NSApplication.shared
let alert = NSAlert()
alert.messageText = "人物補正エフェクトがインストールされました"
alert.informativeText = "Final Cut Pro を再起動し、エフェクト › 人物補正 から使えます。"
alert.runModal()
