import Foundation
import UserNotifications
import WidgetKit

/// 実行している OS で、ウィジェットを置ける大きさの一覧を返す。小・中・大サイズと、iOS 27 以降では縦長の特大サイズ (`systemExtraLargePortrait`)。
///
/// 縦長の特大サイズは iOS・iPadOS 27.0 以降でホーム画面に置ける (https://developer.apple.com/documentation/widgetkit/widgetfamily/systemextralargeportrait 、2026-11-19 に確認)。
/// iOS 27 の SDK を持たない Xcode (Swift 6.3 以前) ではこの名前を使えないため、Swift 6.4 (Xcode 27 が含む版。https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes 、2026-11-19 に確認) 以降でビルドした時だけ足す。
func favoritesWidgetSupportedFamilies() -> [WidgetFamily] {
    #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return [.systemSmall, .systemMedium, .systemLarge, .systemExtraLargePortrait]
        }
    #endif
    return [.systemSmall, .systemMedium, .systemLarge]
}

/// ウィジェットの大きさごとの、並べるお気に入りの行の数の上限を返す。
///
/// 大サイズは 3 行 (画面の見本 documents/design/mock-2026-11-18/project/WidgetPush.dc.html の並べ方)。
/// 中サイズは 2 行、小サイズは 1 行 (ホーム画面に置いて、名前・種類と個数・「カートイン」が読める数を simtunnel の iOS Simulator で確かめた数。documents/DIRECTION.md「決めたこと」)。
/// 縦長の特大サイズは 5 行。大サイズの 3 行と中サイズの 2 行を合わせた数で、HIG に載る縦長の特大サイズの寸法の小さい方 (338x450 pt。https://developer.apple.com/design/human-interface-guidelines/widgets 、2026-11-19 に確認) に、
/// 大サイズと同じ見出し・5 行 (1 行は名前・種類と個数・「そろそろ買う頃」を重ねて約 52 pt、行の間隔 10 pt)・通知の許可の 1 行を、上下の余白を除いた高さ約 418 pt に足しても約 360 pt で収まる計算の数。iOS 27 の端末に置いて測った数ではない (documents/DIRECTION.md「決めたこと」)。
/// ウィジェットが対応していない大きさ (`favoritesWidgetSupportedFamilies()` に無いもの) は、並べ方を決めていないため 0 を返す。
func favoritesWidgetCapacity(widgetFamily: WidgetFamily) -> Int {
    #if compiler(>=6.4)
        if #available(iOS 27.0, *), widgetFamily == .systemExtraLargePortrait {
            return 5
        }
    #endif
    switch widgetFamily {
    case .systemSmall:
        return 1
    case .systemMedium:
        return 2
    case .systemLarge:
        return 3
    default:
        return 0
    }
}

/// ウィジェットの大きさが、見出し「Quick Buy のお気に入り」と大きいアイコンの行で並べる大きさ (大サイズと縦長の特大サイズ) かを返す。
func isFavoritesWidgetLargeLayout(widgetFamily: WidgetFamily) -> Bool {
    #if compiler(>=6.4)
        if #available(iOS 27.0, *), widgetFamily == .systemExtraLargePortrait {
            return true
        }
    #endif
    return widgetFamily == .systemLarge
}

/// 保存済みのお気に入りの並びから、ウィジェットに表示するものを返す。並びの先頭から、その大きさの上限までを保存した並びのまま返す。
func widgetFavorites(favorites: [Favorite], widgetFamily: WidgetFamily) -> [Favorite] {
    Array(favorites.prefix(favoritesWidgetCapacity(widgetFamily: widgetFamily)))
}

/// 通知が許可されていない時にウィジェットに出す、ボタンには通知の許可が要ることの文を返す。
///
/// 文に出すボタンの名前は、並べているお気に入りの店で決める (`cartInButtonTitle(favorite:)`)。Shopify の店の商品だけなら「カートイン」、
/// Amazon の商品だけなら「Amazon で開く」、両方を並べている時は両方の名前を出す (Amazon の商品の行に「カートイン」と書かないため)。
/// お気に入りが空の時は「カートイン」にする。空のウィジェットはこの文を出さず「お気に入りはまだありません」を出すため使われないが、変更前の文言と同じにしておく。
func widgetNotificationRequiredText(favorites: [Favorite]) -> String {
    var buttonTitles: [String] = []
    for buttonTitle in favorites.map(cartInButtonTitle(favorite:)) where !buttonTitles.contains(buttonTitle) {
        buttonTitles.append(buttonTitle)
    }
    return "\(buttonTitles.isEmpty ? "カートイン" : buttonTitles.joined(separator: "・"))には通知の許可が要ります"
}

/// ウィジェットの行の、名前の下に出す 1 行を返す。
///
/// Shopify の店の商品は、商品バリアントの名前 (持つお気に入りだけ) と個数を「・」で区切って並べる (documents/design/mock-2026-11-18/project/WidgetPush.dc.html の行の見本「200g / 豆のまま ・ 2 個」)。
/// Amazon の商品は個数を持たないため (`amazonFavorite(asin:name:id:)`)、店を見分ける `Amazon` を出す。
func favoriteWidgetRowCaption(favorite: Favorite) -> String {
    switch favorite.product {
    case .shopify:
        [favorite.variantName, "\(favorite.quantity) 個"].compactMap { $0 }.joined(separator: " ・ ")
    case .amazon:
        "Amazon"
    }
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

/// ウィジェットの行に「カートイン」(Amazon の商品は「Amazon で開く」) のボタンを出すかを返す。通知が許可されていて、開く URL (`openingURL(favorite:)`) を組み立てられるお気に入りの時だけ true。
func isCartInButtonShown(favorite: Favorite, isNotificationAuthorized: Bool) -> Bool {
    isNotificationAuthorized && openingURL(favorite: favorite) != nil
}

/// ウィジェットの表示内容の作り直しを OS に頼む時刻を返す。`now` の 1 時間後。
///
/// 通知の許可の状態はアプリを開かずに設定アプリで変わり得て、ウィジェットはその変化を知らされない。作り直すまで「カートイン」の出し方が古いままになるため、時刻で作り直す。
/// 1 時間は、許可した後にボタンが出るまでの遅れを 1 時間以内に収めつつ、1 日 24 回で WidgetKit の作り直しの回数の目安 (1 日 40〜70 回。https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date ) に収まる値。
func favoritesWidgetTimelineReloadDate(now: Date) -> Date {
    now.addingTimeInterval(3600)
}
