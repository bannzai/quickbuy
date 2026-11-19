import FirebaseAnalytics
import Foundation
import WidgetKit

/// Firebase Analytics に記録する 1 件のイベント。
///
/// 引数には、個人も商品も特定しない値 (開いた入口の種類・店の種類・ウィジェットの大きさ) だけを入れる。
/// 商品・店・お気に入りの名前と、購入画面の URL は入れない (documents/adr/0003、.claude/rules/purchase-url.md)。
struct AnalyticsEvent: Equatable {
    /// イベントの名前。
    let name: String
    /// イベントの引数。
    let parameters: [String: String]
}

/// 購入画面を開いた入口。イベントの引数 `entry_point` の値に使う。
enum PurchaseScreenEntryPoint: String {
    /// アプリのお気に入りの一覧で「カートイン」を押し、確認の「開く」を押した。
    case favoritesList = "favorites_list"
    /// ウィジェットの「カートイン」で届いた確認の通知をタップした。
    case cartInNotification = "cart_in_notification"
    /// リマインドの通知をタップした。
    case reminderNotification = "reminder_notification"
}

/// 購入画面を開いた時のイベントを返す。引数は開いた入口 (`entry_point`) と店の種類 (`store`) だけ。
func purchaseScreenOpenEvent(entryPoint: PurchaseScreenEntryPoint, product: Favorite.Product) -> AnalyticsEvent {
    AnalyticsEvent(
        name: "purchase_screen_open",
        parameters: ["entry_point": entryPoint.rawValue, "store": storeName(product: product)]
    )
}

/// 商品の店の種類の、イベントの引数での名前を返す。店のドメインは返さない。
func storeName(product: Favorite.Product) -> String {
    switch product {
    case .shopify: "shopify"
    case .amazon: "amazon"
    }
}

/// お気に入りのウィジェットを置いている時のイベントを返す。置かれていない時は nil (記録しない)。
///
/// `widgetFamilies` は、置かれているお気に入りのウィジェットの大きさ (同じ大きさを複数置いていれば、その数だけ並ぶ)。
/// 引数 `widget_families` は、置かれている大きさを重複なしで名前の順に `,` でつないだ値。
func widgetPlacedEvent(widgetFamilies: [WidgetFamily]) -> AnalyticsEvent? {
    guard !widgetFamilies.isEmpty else {
        return nil
    }
    return AnalyticsEvent(
        name: "widget_placed",
        parameters: ["widget_families": Set(widgetFamilies.map(widgetFamilyName(widgetFamily:))).sorted().joined(separator: ",")]
    )
}

/// ウィジェットの大きさのイベントの引数での名前を返す。
///
/// お気に入りのウィジェットが対応する大きさ (`FavoritesWidget` の `supportedFamilies`) 以外は届かないが、
/// WidgetKit が大きさを足した時に記録を落とさないよう、それ以外は `other` にまとめる。
func widgetFamilyName(widgetFamily: WidgetFamily) -> String {
    switch widgetFamily {
    case .systemSmall: "small"
    case .systemMedium: "medium"
    case .systemLarge: "large"
    default: "other"
    }
}

/// 置かれているウィジェットの構成から、お気に入りのウィジェットの大きさだけを返す。
func favoritesWidgetFamilies(widgetInfos: [(kind: String, family: WidgetFamily)]) -> [WidgetFamily] {
    widgetInfos.filter { $0.kind == favoritesWidgetKind }.map(\.family)
}

/// 置かれているウィジェットの構成を読んだ結果から、記録するイベントを返す。記録しない時は nil。
///
/// 読めなかった時 (`.failure`) は記録しない (置いていない時と区別できないため、置いていない扱いで記録を作らない)。
func widgetPlacedEvent(widgetInfosResult: Result<[(kind: String, family: WidgetFamily)], any Error>) -> AnalyticsEvent? {
    guard case let .success(widgetInfos) = widgetInfosResult else {
        return nil
    }
    return widgetPlacedEvent(widgetFamilies: favoritesWidgetFamilies(widgetInfos: widgetInfos))
}

/// 置かれているウィジェットを OS から読み、お気に入りのウィジェットを置いていれば `recordAnalyticsEvent` に記録を渡す。アプリが前面に来た時に呼ぶ。
///
/// async 版の `currentConfigurations()` は iOS 18 からのため、iOS 17 から使える完了ハンドラ版で読む。
func recordWidgetPlacement(recordAnalyticsEvent: @escaping (AnalyticsEvent) -> Void) {
    WidgetCenter.shared.getCurrentConfigurations { result in
        if let event = widgetPlacedEvent(widgetInfosResult: result.map { $0.map { (kind: $0.kind, family: $0.family) } }.mapError { $0 as any Error }) {
            recordAnalyticsEvent(event)
        }
    }
}

/// 指定した識別子の保存済みのお気に入りの購入画面を開く時に呼び、開く URL を返す。開く時は `entryPoint` を入口にした購入画面を開いた記録を `recordAnalyticsEvent` に渡す。
///
/// 保存とリマインドの数え直しは `purchaseURLForOpening(favoriteID:now:fileURL:)` と同じ。nil を返す時 (購入画面を開かない時) は記録しない。
func purchaseURLForOpening(
    favoriteID: UUID,
    entryPoint: PurchaseScreenEntryPoint,
    now: Date,
    fileURL: URL,
    recordAnalyticsEvent: (AnalyticsEvent) -> Void
) throws -> URL? {
    guard let favorite = try loadFavorites(fileURL: fileURL).first(where: { $0.id == favoriteID }),
          let openingURL = try purchaseURLForOpening(favoriteID: favoriteID, now: now, fileURL: fileURL)
    else {
        return nil
    }
    recordAnalyticsEvent(purchaseScreenOpenEvent(entryPoint: entryPoint, product: favorite.product))
    return openingURL
}

/// イベントを Firebase Analytics に送る。アプリの画面と通知の受け取りが記録先として渡す。
///
/// Debug の設定のビルドでは、`QuickBuy/Info-Debug.plist` の `FIREBASE_ANALYTICS_COLLECTION_ENABLED` が false のため送られない。
func recordAnalyticsEventToFirebase(event: AnalyticsEvent) {
    Analytics.logEvent(event.name, parameters: event.parameters)
}
