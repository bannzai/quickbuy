import Foundation
import Testing
@testable import QuickBuy

/// お気に入りの一覧の並べ替えの位置の計算・店のドメインの表示・開発者メニューの操作を確かめる。
struct FavoritesListTests {
    /// テストごとに別の、まだ存在しない保存先のファイルの URL を返す。
    private func temporaryFavoritesFileURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "favorites-\(UUID().uuidString).json")
    }

    /// 名前だけを指定した Shopify の商品のお気に入りを返す。
    private func favorite(name: String) -> Favorite {
        Favorite(
            id: UUID(),
            name: name,
            imageURL: nil,
            quantity: 1,
            product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
            reminder: nil
        )
    }

    // MARK: - 並べ替え

    /// 「洗剤」「電池」「水」の並びで、一覧のドラッグが渡す (元の位置, 差し込む位置) ごとに、保存される並びが画面で見た並びと同じになる。
    /// 差し込む位置は、移動する前の並びで「この位置の前に入れる」(3 は末尾の後ろ)。
    @Test(arguments: [
        (0, 2, ["電池", "洗剤", "水"]),
        (0, 3, ["電池", "水", "洗剤"]),
        (2, 0, ["水", "洗剤", "電池"]),
        (2, 1, ["洗剤", "水", "電池"]),
        (1, 0, ["電池", "洗剤", "水"]),
        (1, 3, ["洗剤", "水", "電池"]),
        (1, 1, ["洗剤", "電池", "水"]),
        (1, 2, ["洗剤", "電池", "水"]),
    ])
    func ドラッグの位置から保存される並びが決まる(sourceIndex: Int, destinationOffset: Int, expectedNames: [String]) throws {
        let fileURL = temporaryFavoritesFileURL()
        let favorites = [favorite(name: "洗剤"), favorite(name: "電池"), favorite(name: "水")]
        try saveFavorites(favorites: favorites, fileURL: fileURL)
        try moveFavorite(
            id: favorites[sourceIndex].id,
            destinationIndex: destinationIndexAfterMove(sourceIndex: sourceIndex, destinationOffset: destinationOffset),
            fileURL: fileURL
        )
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == expectedNames)
    }

    // MARK: - 店のドメインの表示

    /// Shopify の商品は保存した店のドメイン、Amazon の商品は `amazon.co.jp` を表示する。
    @Test func 店のドメインを表示の文字列にする() {
        #expect(shopDomainText(favorite: favorite(name: "コーヒー豆")) == "mori-coffee.example")
        #expect(
            shopDomainText(
                favorite: Favorite(id: UUID(), name: "電池", imageURL: nil, quantity: 1, product: .amazon(AmazonProduct(asin: "B00EXAMPLE")), reminder: nil)
            ) == "amazon.co.jp"
        )
    }

    // MARK: - 開発者メニュー

    /// 見本は 3 件で、どれも購入画面の URL を組み立てられ、店のドメインは実在しない `.example`。
    @Test func 見本のお気に入りは購入画面を開ける形で実在しない店を指す() {
        #expect(sampleFavorites().map(\.name) == ["コーヒー豆 200g", "洗濯用せっけん", "プロテイン 1kg"])
        #expect(
            sampleFavorites().map { purchaseURL(favorite: $0)?.absoluteString } == [
                "https://mori-coffee.example/cart/70881412:2",
                "https://sukoyaka-soap.example/cart/70881382:1",
                "https://karada-store.example/cart/70881999:1",
            ]
        )
    }

    /// 見本を入れると、保存済みのお気に入りの後ろに 3 件が足される。もう一度入れても増えず、利用者が変えた見本の名前も戻らない。
    @Test func 見本を入れると末尾に足され2回目は増えない() throws {
        let fileURL = temporaryFavoritesFileURL()
        let existingFavorite = favorite(name: "自分で入れた商品")
        try saveFavorites(favorites: [existingFavorite], fileURL: fileURL)
        try insertSampleFavorites(fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [existingFavorite] + sampleFavorites())
        try updateFavorite(id: sampleFavorites()[0].id, name: "名前を変えた見本", quantity: 4, fileURL: fileURL)
        try insertSampleFavorites(fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["自分で入れた商品", "名前を変えた見本", "洗濯用せっけん", "プロテイン 1kg"])
    }

    /// すべて消すと、見本も自分で入れたお気に入りも無くなる。空の状態でもう一度消しても空のまま。
    @Test func すべて消すとお気に入りが0件になる() throws {
        let fileURL = temporaryFavoritesFileURL()
        try saveFavorites(favorites: [favorite(name: "自分で入れた商品")], fileURL: fileURL)
        try insertSampleFavorites(fileURL: fileURL)
        try deleteAllFavorites(fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [])
        try deleteAllFavorites(fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [])
    }
}
