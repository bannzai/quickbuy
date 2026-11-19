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

/// 通知の許可の状態から、ウィジェットに「カートイン」を出せるかを返す。許可 (authorized) の時だけ true。
///
/// 仮の許可 (provisional) と一時的な許可 (ephemeral) は、通知を通知センターにだけ静かに届ける・App Clip 向けの許可で、押した直後にバナーで確認を見せられないため false にする。
func isCartInAvailable(authorizationStatus: UNAuthorizationStatus) -> Bool {
    authorizationStatus == .authorized
}

/// ウィジェットの行に「カートイン」のボタンを出すかを返す。通知が許可されていて、購入画面の URL を組み立てられるお気に入り (Amazon の商品以外) の時だけ true。
func isCartInButtonShown(favorite: Favorite, isNotificationAuthorized: Bool) -> Bool {
    isNotificationAuthorized && purchaseURL(favorite: favorite) != nil
}
