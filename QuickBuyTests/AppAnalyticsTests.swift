import Foundation
import Testing
import WidgetKit
@testable import QuickBuy

/// 購入画面を開いた記録とウィジェットを置いている記録 (Firebase Analytics に送るイベント) を、記録先を差し替えて確かめる。
struct AppAnalyticsTests {
    /// テストごとに別の、まだ存在しない保存先のファイルの URL を返す。
    private func temporaryFavoritesFileURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "favorites-\(UUID().uuidString).json")
    }

    /// 名前・商品バリアントの名前・店のドメインに、イベントに入ってはいけない値を持たせたお気に入りを返す。
    private func favorite(product: Favorite.Product) -> Favorite {
        Favorite(
            id: UUID(),
            name: "森の珈琲 深煎り",
            variantName: "200g / 豆のまま",
            imageURL: URL(string: "https://cdn.mori-coffee.example/beans.png"),
            quantity: 2,
            product: product,
            reminder: nil
        )
    }

    // MARK: - 購入画面を開いた記録

    /// 一覧の確認の「開く」で購入画面を開いた時は、入口が一覧・店が Shopify のイベントを 1 件だけ記録し、URL を返す。
    @Test func 一覧から購入画面を開くと入口と店の種類だけを記録する() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)
        var recordedEvents: [AnalyticsEvent] = []

        #expect(
            try openingURL(
                favoriteID: savedFavorite.id,
                entryPoint: .favoritesList,
                now: Date(timeIntervalSince1970: 1_800_000_000),
                fileURL: fileURL,
                recordAnalyticsEvent: { recordedEvents.append($0) }
            )?.absoluteString == "https://mori-coffee.example/cart/70881412:2"
        )
        #expect(recordedEvents == [AnalyticsEvent(name: "purchase_screen_open", parameters: ["entry_point": "favorites_list", "store": "shopify"])])
    }

    /// 一覧の確認の「開く」で Amazon の商品ページを開いた時は、入口が一覧・店が Amazon のイベントを 1 件だけ記録し、商品ページの URL を返す。
    @Test func 一覧からAmazonの商品ページを開くと店の種類amazonで記録する() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(product: .amazon(AmazonProduct(asin: "B00EXAMPLE")))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)
        var recordedEvents: [AnalyticsEvent] = []

        #expect(
            try openingURL(
                favoriteID: savedFavorite.id,
                entryPoint: .favoritesList,
                now: Date(timeIntervalSince1970: 1_800_000_000),
                fileURL: fileURL,
                recordAnalyticsEvent: { recordedEvents.append($0) }
            )?.absoluteString == "https://www.amazon.co.jp/dp/B00EXAMPLE"
        )
        #expect(recordedEvents == [AnalyticsEvent(name: "purchase_screen_open", parameters: ["entry_point": "favorites_list", "store": "amazon"])])
    }

    /// 開く URL を組み立てられないお気に入り (ASIN の形でない保存値の Amazon の商品) では、何も開かないので記録しない。
    @Test func 何も開かない時は記録しない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(product: .amazon(AmazonProduct(asin: "b00example")))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)
        var recordedEvents: [AnalyticsEvent] = []

        #expect(
            try openingURL(
                favoriteID: savedFavorite.id,
                entryPoint: .favoritesList,
                now: Date(timeIntervalSince1970: 1_800_000_000),
                fileURL: fileURL,
                recordAnalyticsEvent: { recordedEvents.append($0) }
            ) == nil
        )
        #expect(recordedEvents.isEmpty)
    }

    /// 保存されていないお気に入りの識別子では、購入画面を開かないので記録しない。
    @Test func 保存されていないお気に入りでは記録しない() throws {
        let fileURL = temporaryFavoritesFileURL()
        try saveFavorites(favorites: [], fileURL: fileURL)
        var recordedEvents: [AnalyticsEvent] = []

        #expect(
            try openingURL(
                favoriteID: UUID(),
                entryPoint: .favoritesList,
                now: Date(timeIntervalSince1970: 1_800_000_000),
                fileURL: fileURL,
                recordAnalyticsEvent: { recordedEvents.append($0) }
            ) == nil
        )
        #expect(recordedEvents.isEmpty)
    }

    /// 入口と店の種類の組ごとに、イベントの引数が入口と店の種類の 2 つだけになる。
    @Test(arguments: [
        (PurchaseScreenEntryPoint.favoritesList, "favorites_list"),
        (PurchaseScreenEntryPoint.cartInNotification, "cart_in_notification"),
        (PurchaseScreenEntryPoint.reminderNotification, "reminder_notification"),
    ])
    func 購入画面を開いたイベントの引数は入口と店の種類だけ(entryPoint: PurchaseScreenEntryPoint, entryPointValue: String) {
        #expect(
            purchaseScreenOpenEvent(entryPoint: entryPoint, product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")))
                == AnalyticsEvent(name: "purchase_screen_open", parameters: ["entry_point": entryPointValue, "store": "shopify"])
        )
        #expect(
            purchaseScreenOpenEvent(entryPoint: entryPoint, product: .amazon(AmazonProduct(asin: "B0EXAMPLE1")))
                == AnalyticsEvent(name: "purchase_screen_open", parameters: ["entry_point": entryPointValue, "store": "amazon"])
        )
    }

    /// イベントの引数の値に、お気に入りの名前・商品バリアントの名前・店のドメイン・商品の識別子・URL のどれも含まれない。
    @Test func 購入画面を開いたイベントに名前とURLが入らない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let savedFavorite = favorite(product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")))
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)
        var recordedEvents: [AnalyticsEvent] = []
        #expect(
            try openingURL(
                favoriteID: savedFavorite.id,
                entryPoint: .favoritesList,
                now: Date(timeIntervalSince1970: 1_800_000_000),
                fileURL: fileURL,
                recordAnalyticsEvent: { recordedEvents.append($0) }
            )?.absoluteString == "https://mori-coffee.example/cart/70881412:2"
        )

        let recordedValues = recordedEvents.flatMap { [$0.name] + $0.parameters.keys + $0.parameters.values }
        for forbiddenText in ["森の珈琲", "200g", "mori-coffee", "70881412", "https://", "cdn.mori-coffee.example", savedFavorite.id.uuidString] {
            #expect(!recordedValues.contains { $0.contains(forbiddenText) }, "\(forbiddenText) がイベントに入っている")
        }
        #expect(!recordedValues.isEmpty)
    }

    // MARK: - ウィジェットを置いている記録

    /// お気に入りのウィジェットを置いている時は、置いている大きさを重複なしで名前の順に並べたイベントを返す。
    @Test func ウィジェットを置いている時は大きさを持つイベントを返す() {
        #expect(
            widgetPlacedEvent(widgetFamilies: [.systemMedium, .systemSmall, .systemMedium])
                == AnalyticsEvent(name: "widget_placed", parameters: ["widget_families": "medium,small"])
        )
        #expect(
            widgetPlacedEvent(widgetFamilies: [.systemLarge])
                == AnalyticsEvent(name: "widget_placed", parameters: ["widget_families": "large"])
        )
    }

    #if compiler(>=6.4)
        /// 縦長の特大サイズは `extra_large_portrait` で記録する (iOS 27 以降でだけ置ける)。
        @Test @available(iOS 27.0, *)
        func 縦長の特大サイズはextra_large_portraitで記録する() {
            #expect(widgetFamilyName(widgetFamily: .systemExtraLargePortrait) == "extra_large_portrait")
            #expect(
                widgetPlacedEvent(widgetFamilies: [.systemExtraLargePortrait, .systemSmall])
                    == AnalyticsEvent(name: "widget_placed", parameters: ["widget_families": "extra_large_portrait,small"])
            )
        }
    #endif

    /// 小・中・大と縦長の特大サイズ以外の大きさ (お気に入りのウィジェットが対応しない横長の特大サイズ等) は `other` にまとめる (WidgetKit が大きさを足しても記録を落とさない)。
    @Test func 小中大以外の大きさはotherにまとめる() {
        #expect(widgetFamilyName(widgetFamily: .systemExtraLarge) == "other")
        #expect(widgetFamilyName(widgetFamily: .accessoryCircular) == "other")
        #expect(
            widgetPlacedEvent(widgetFamilies: [.systemSmall, .systemExtraLarge])
                == AnalyticsEvent(name: "widget_placed", parameters: ["widget_families": "other,small"])
        )
    }

    /// ウィジェットの構成を読めた時は、お気に入りのウィジェットだけからイベントを作る。
    @Test func 構成を読めた時はお気に入りのウィジェットからイベントを作る() {
        #expect(
            widgetPlacedEvent(widgetInfosResult: .success([
                (kind: "OtherWidget", family: .systemLarge),
                (kind: favoritesWidgetKind, family: .systemMedium),
            ])) == AnalyticsEvent(name: "widget_placed", parameters: ["widget_families": "medium"])
        )
        #expect(widgetPlacedEvent(widgetInfosResult: .success([(kind: "OtherWidget", family: .systemLarge)])) == nil)
    }

    /// ウィジェットの構成を読めなかった時は記録しない (置いていない時と区別できないため)。
    @Test func 構成を読めなかった時は記録しない() {
        #expect(widgetPlacedEvent(widgetInfosResult: .failure(CocoaError(.fileReadUnknown))) == nil)
    }

    /// お気に入りのウィジェットを 1 つも置いていない時は、記録しない (nil)。
    @Test func ウィジェットを置いていない時は記録しない() {
        #expect(widgetPlacedEvent(widgetFamilies: []) == nil)
    }

    /// 置かれているウィジェットのうち、お気に入りのウィジェットの種類のものだけを数える。
    @Test func お気に入りのウィジェットの種類だけを数える() {
        #expect(
            favoritesWidgetFamilies(widgetInfos: [
                (kind: favoritesWidgetKind, family: .systemSmall),
                (kind: "OtherWidget", family: .systemLarge),
                (kind: favoritesWidgetKind, family: .systemMedium),
            ]) == [.systemSmall, .systemMedium]
        )
        #expect(favoritesWidgetFamilies(widgetInfos: [(kind: "FavoritesWidgetOld", family: .systemSmall)]).isEmpty)
    }

    // MARK: - 開発者向けのビルド

    /// テストと開発者向けのビルド (Debug の設定) では、Firebase に利用の記録とクラッシュの記録を送らない設定が入っている。
    @Test func 開発者向けのビルドでは記録を送らない設定が入っている() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "FIREBASE_ANALYTICS_COLLECTION_ENABLED") as? Bool == false)
        #expect(Bundle.main.object(forInfoDictionaryKey: "FirebaseCrashlyticsCollectionEnabled") as? Bool == false)
    }
}
