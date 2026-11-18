import Foundation
import Testing
import WidgetKit
@testable import QuickBuy

/// ウィジェットに表示するお気に入りの選び方と、ウィジェットのタップで開く購入画面の URL を確かめる。
struct FavoritesWidgetTests {
    /// テストごとに別の、まだ存在しない保存先のファイルの URL を返す。
    private func temporaryFavoritesFileURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "favorites-\(UUID().uuidString).json")
    }

    /// テストでリマインドの日数を数え始めた日時として使う、決まった日時 (2026-11-01 00:00:00 UTC)。
    private let countedFrom = Date(timeIntervalSince1970: 1_793_491_200)
    /// テストでウィジェットをタップした時刻として使う、`countedFrom` の 40 日後。
    private let tappedAt = Date(timeIntervalSince1970: 1_793_491_200 + 40 * 86400)

    /// 名前・店のドメイン・商品バリアントの ID・個数を指定した Shopify の商品のお気に入りを返す。
    private func favorite(name: String, shopDomain: String, variantID: String, quantity: Int) -> Favorite {
        Favorite(
            id: UUID(),
            name: name,
            imageURL: nil,
            quantity: quantity,
            product: .shopify(ShopifyProduct(shopDomain: shopDomain, variantID: variantID)),
            reminder: nil
        )
    }

    /// 「洗剤」「電池」「水」「米」の順の 4 件のうち、先頭から `count` 件を返す。
    private func favorites(count: Int) -> [Favorite] {
        ["洗剤", "電池", "水", "米"].prefix(count).map {
            favorite(name: $0, shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 1)
        }
    }

    // MARK: - 表示する件数

    /// 小サイズは先頭の 1 件、中サイズは先頭から 3 件までを、保存した並びのまま表示する。保存が上限より少ない時はある分だけ、0 件の時は何も表示しない。
    @Test(arguments: [
        (WidgetFamily.systemSmall, 0, [String]()),
        (WidgetFamily.systemSmall, 1, ["洗剤"]),
        (WidgetFamily.systemSmall, 4, ["洗剤"]),
        (WidgetFamily.systemMedium, 0, [String]()),
        (WidgetFamily.systemMedium, 2, ["洗剤", "電池"]),
        (WidgetFamily.systemMedium, 3, ["洗剤", "電池", "水"]),
        (WidgetFamily.systemMedium, 4, ["洗剤", "電池", "水"]),
    ])
    func ウィジェットの大きさごとに先頭から表示する(widgetFamily: WidgetFamily, savedCount: Int, expectedNames: [String]) {
        #expect(widgetFavorites(favorites: favorites(count: savedCount), widgetFamily: widgetFamily).map(\.name) == expectedNames)
    }

    /// ウィジェットが対応していない大サイズには、お気に入りを表示しない。
    @Test func 対応していない大きさには表示しない() {
        #expect(widgetFavorites(favorites: favorites(count: 4), widgetFamily: .systemLarge) == [])
    }

    // MARK: - タップで開く URL

    /// 2 件を保存した状態で、それぞれのタップが、タップした方の店のドメイン・商品バリアントの ID・個数の購入画面の URL になる。
    @Test func タップしたお気に入りの購入画面のURLになる() throws {
        let fileURL = temporaryFavoritesFileURL()
        let coffeeFavorite = favorite(name: "コーヒー豆", shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
        let soapFavorite = favorite(name: "せっけん", shopDomain: "sukoyaka-soap.example", variantID: "70881382", quantity: 5)
        try saveFavorites(favorites: [coffeeFavorite, soapFavorite], fileURL: fileURL)
        #expect(
            try tappedFavoritePurchaseURL(tapURL: favoriteTapURL(favoriteID: coffeeFavorite.id), now: tappedAt, fileURL: fileURL)?.absoluteString
                == "https://mori-coffee.example/cart/70881412:2"
        )
        #expect(
            try tappedFavoritePurchaseURL(tapURL: favoriteTapURL(favoriteID: soapFavorite.id), now: tappedAt, fileURL: fileURL)?.absoluteString
                == "https://sukoyaka-soap.example/cart/70881382:5"
        )
    }

    /// タップで渡る URL が載せるのはお気に入りの識別子だけで、形は `quickbuy://favorite/{識別子}`。
    @Test func タップで渡るURLはお気に入りの識別子だけを載せる() throws {
        let favoriteID = try #require(UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1"))
        #expect(favoriteTapURL(favoriteID: favoriteID).absoluteString == "quickbuy://favorite/5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")
        #expect(tappedFavoriteID(tapURL: favoriteTapURL(favoriteID: favoriteID)) == favoriteID)
    }

    /// 保存済みのお気に入りの識別子を含んでいても、決まった形と違う URL では購入画面を開かない。外から渡された店の URL もそのまま開かない。
    @Test(arguments: [
        "https://favorite/5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1",
        "quickbuy://other/5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1",
        "quickbuy://favorite/extra/5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1",
        "quickbuy://favorite/5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1?url=https://evil.example/cart/1:1",
        "quickbuy://favorite/5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1#fragment",
        "quickbuy://favorite/not-a-uuid",
        "quickbuy://favorite/",
        "https://evil.example/cart/70881412:2",
    ])
    func 決まった形と違うURLでは購入画面を開かない(tapURLText: String) throws {
        let fileURL = temporaryFavoritesFileURL()
        try saveFavorites(
            favorites: [
                Favorite(
                    id: #require(UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")),
                    name: "コーヒー豆",
                    imageURL: nil,
                    quantity: 2,
                    product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
                    reminder: nil
                ),
            ],
            fileURL: fileURL
        )
        #expect(try tappedFavoritePurchaseURL(tapURL: #require(URL(string: tapURLText)), now: tappedAt, fileURL: fileURL) == nil)
    }

    /// 削除した後のお気に入りのタップ (ウィジェットの表示が更新される前のタップ) では、購入画面を開かない。
    @Test func 保存先に無いお気に入りのタップでは購入画面を開かない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let deletedFavorite = favorite(name: "コーヒー豆", shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
        try saveFavorites(
            favorites: [deletedFavorite, favorite(name: "せっけん", shopDomain: "sukoyaka-soap.example", variantID: "70881382", quantity: 1)],
            fileURL: fileURL
        )
        #expect(
            try tappedFavoritePurchaseURL(tapURL: favoriteTapURL(favoriteID: deletedFavorite.id), now: tappedAt, fileURL: fileURL)?.absoluteString
                == "https://mori-coffee.example/cart/70881412:2"
        )
        try deleteFavorite(id: deletedFavorite.id, fileURL: fileURL)
        #expect(try tappedFavoritePurchaseURL(tapURL: favoriteTapURL(favoriteID: deletedFavorite.id), now: tappedAt, fileURL: fileURL) == nil)
    }

    /// 購入画面の URL を組み立てない Amazon の商品のお気に入りのタップでは、購入画面を開かない。
    @Test func Amazonの商品のお気に入りのタップでは購入画面を開かない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let amazonFavorite = Favorite(id: UUID(), name: "電池", imageURL: nil, quantity: 1, product: .amazon(AmazonProduct(asin: "B00EXAMPLE")), reminder: nil)
        try saveFavorites(favorites: [amazonFavorite], fileURL: fileURL)
        #expect(try tappedFavoritePurchaseURL(tapURL: favoriteTapURL(favoriteID: amazonFavorite.id), now: tappedAt, fileURL: fileURL) == nil)
    }

    /// タップしたお気に入りだけを、タップした時刻から数え直す。ほかのお気に入りのリマインドは変えない。
    @Test func タップしたお気に入りのリマインドをタップした時刻から数え直す() throws {
        let fileURL = temporaryFavoritesFileURL()
        var tappedFavorite = favorite(name: "コーヒー豆", shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
        tappedFavorite.reminder = Reminder(intervalDays: 30, countedFrom: countedFrom)
        var otherFavorite = favorite(name: "せっけん", shopDomain: "sukoyaka-soap.example", variantID: "70881382", quantity: 1)
        otherFavorite.reminder = Reminder(intervalDays: 7, countedFrom: countedFrom)
        try saveFavorites(favorites: [tappedFavorite, otherFavorite], fileURL: fileURL)

        #expect(
            try tappedFavoritePurchaseURL(tapURL: favoriteTapURL(favoriteID: tappedFavorite.id), now: tappedAt, fileURL: fileURL)?.absoluteString
                == "https://mori-coffee.example/cart/70881412:2"
        )
        #expect(try loadFavorites(fileURL: fileURL).map(\.reminder) == [Reminder(intervalDays: 30, countedFrom: tappedAt), otherFavorite.reminder])
    }

    /// 決まった形と違う URL では、URL が含む識別子のお気に入りのリマインドを数え直さない。
    @Test func 決まった形と違うURLではリマインドを数え直さない() throws {
        let fileURL = temporaryFavoritesFileURL()
        var savedFavorite = favorite(name: "コーヒー豆", shopDomain: "mori-coffee.example", variantID: "70881412", quantity: 2)
        savedFavorite.reminder = Reminder(intervalDays: 30, countedFrom: countedFrom)
        try saveFavorites(favorites: [savedFavorite], fileURL: fileURL)

        #expect(
            try tappedFavoritePurchaseURL(
                tapURL: #require(URL(string: "quickbuy://favorite/\(savedFavorite.id.uuidString)?url=https://evil.example/cart/1:1")),
                now: tappedAt,
                fileURL: fileURL
            ) == nil
        )
        #expect(try loadFavorites(fileURL: fileURL) == [savedFavorite])
    }

    /// 保存先のファイルを読めない時は、購入画面の URL を返さずエラーを投げる。
    @Test func 保存先を読めない時はエラーを投げる() throws {
        let fileURL = temporaryFavoritesFileURL()
        try Data("壊れたファイル".utf8).write(to: fileURL)
        #expect(throws: (any Error).self) {
            try tappedFavoritePurchaseURL(tapURL: favoriteTapURL(favoriteID: UUID()), now: tappedAt, fileURL: fileURL)
        }
    }
}
