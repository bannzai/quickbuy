import Foundation
import UserNotifications
import WidgetKit

/// ウィジェットの大きさごとの、並べるお気に入りの行の数の上限を返す。
///
/// 大サイズは 3 行 (画面の見本 documents/design/mock-2026-11-18/project/WidgetPush.dc.html の並べ方)。
/// 中サイズは 2 行、小サイズは 1 行 (ホーム画面に置いて、名前・種類と個数・「カートイン」が読める数を simtunnel の iOS Simulator で確かめた数。documents/DIRECTION.md「決めたこと」)。
/// ウィジェットが対応していない大きさ (`FavoritesWidget` の `supportedFamilies` に無いもの) は、並べ方を決めていないため 0 を返す。
func favoritesWidgetCapacity(widgetFamily: WidgetFamily) -> Int {
    switch widgetFamily {
    case .systemSmall:
        1
    case .systemMedium:
        2
    case .systemLarge:
        3
    default:
        0
    }
}

/// 保存済みのお気に入りの並びから、ウィジェットに表示するものを返す。並びの先頭から、その大きさの上限までを保存した並びのまま返す。
func widgetFavorites(favorites: [Favorite], widgetFamily: WidgetFamily) -> [Favorite] {
    Array(favorites.prefix(favoritesWidgetCapacity(widgetFamily: widgetFamily)))
}

/// ウィジェットの行の、名前の下に出す 1 行を返す。商品バリアントの名前 (持つお気に入りだけ) と個数を「・」で区切って並べる。
///
/// 並べ方は documents/design/mock-2026-11-18/project/WidgetPush.dc.html の行の見本「200g / 豆のまま ・ 2 個」。
func favoriteWidgetRowCaption(favorite: Favorite) -> String {
    [favorite.variantName, "\(favorite.quantity) 個"].compactMap { $0 }.joined(separator: " ・ ")
}

/// ウィジェットの表示を切り替える時刻を、早い順に返す。先頭は `now` で、続けて `now` より後にリマインドの日数が過ぎる時刻を返す。
///
/// ウィジェットは時刻での更新を自分では行わないため、日数が過ぎた時に「そろそろ買う頃」を出すには、その時刻の表示内容を前もって渡しておく必要がある。
/// 同じ時刻に日数が過ぎるお気に入りが複数ある時は、その時刻を 1 つにまとめる。
func favoritesWidgetTimelineDates(favorites: [Favorite], now: Date) -> [Date] {
    [now] + Set(
        favorites
            .compactMap(\.reminder)
            .map { $0.countedFrom.addingTimeInterval(reminderTimeInterval(reminder: $0)) }
            .filter { $0 > now }
    ).sorted()
}

/// 通知の許可の状態と表示の設定から、ウィジェットに「カートイン」を出せるかを返す。許可 (authorized) で、バナー・通知センター・ロック画面のどれかの表示が有効な時だけ true。
///
/// 仮の許可 (provisional) と一時的な許可 (ephemeral) は、通知を通知センターにだけ静かに届ける・App Clip 向けの許可で、押した直後にバナーで確認を見せられないため false にする。
/// 許可されていても表示をすべて無効にした端末では、確認の通知をタップできる場所が無く購入画面へ進めないため false にする (許可と表示は別の設定。https://developer.apple.com/documentation/usernotifications/unnotificationsettings/alertsetting )。
func isCartInAvailable(authorizationStatus: UNAuthorizationStatus, alertSetting: UNNotificationSetting, notificationCenterSetting: UNNotificationSetting, lockScreenSetting: UNNotificationSetting) -> Bool {
    authorizationStatus == .authorized && [alertSetting, notificationCenterSetting, lockScreenSetting].contains(.enabled)
}

/// ウィジェットの行に「カートイン」のボタンを出すかを返す。通知が許可されていて、購入画面の URL を組み立てられるお気に入り (Amazon の商品以外) の時だけ true。
func isCartInButtonShown(favorite: Favorite, isNotificationAuthorized: Bool) -> Bool {
    isNotificationAuthorized && purchaseURL(favorite: favorite) != nil
}

/// ウィジェットの表示内容の作り直しを OS に頼む時刻を返す。`now` の 1 時間後。
///
/// 通知の許可の状態はアプリを開かずに設定アプリで変わり得て、ウィジェットはその変化を知らされない。作り直すまで「カートイン」の出し方が古いままになるため、時刻で作り直す。
/// 1 時間は、許可した後にボタンが出るまでの遅れを 1 時間以内に収めつつ、1 日 24 回で WidgetKit の作り直しの回数の目安 (1 日 40〜70 回。https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date ) に収まる値。
func favoritesWidgetTimelineReloadDate(now: Date) -> Date {
    now.addingTimeInterval(3600)
}
