import FirebaseCore
import SwiftUI
import UserNotifications

/// Quick Buy のアプリ本体の入口。
@main
struct QuickBuyApp: App {
    /// リマインドの通知のタップを受け取るオブジェクト。通知の仕組みはこのオブジェクトを弱い参照でしか持たないため、アプリが動いている間ここで持ち続ける。
    private let reminderNotificationDelegate = ReminderNotificationDelegate()

    /// 通知のタップを受け取るオブジェクトを、アプリの起動が終わる前に通知の仕組みへ渡す。
    ///
    /// 起動が終わった後に渡すと、通知のタップでアプリが起動した時にそのタップを受け取れないため、`init` で渡している
    /// (https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/delegate の
    /// 「you must set the value of this property before your app finishes launching」)。
    ///
    /// Firebase (利用の記録とクラッシュの記録) も、通知のタップでの起動で購入画面を開いた記録を落とさないよう、同じく `init` で初期化する。
    init() {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = reminderNotificationDelegate
    }

    /// アプリのウィンドウ。最初の画面を表示する。
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
