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

    // MARK: - 削除

    /// 「洗剤」「電池」「水」「米」の並びで、一覧の削除が渡す位置 (1 つ・離れた 2 つ・隣り合う 2 つ・なし) のお気に入りだけが消え、残りの並びは変わらない。
    @Test(arguments: [
        ([1], ["洗剤", "水", "米"]),
        ([0, 2], ["電池", "米"]),
        ([2, 3], ["洗剤", "電池"]),
        ([0, 1, 2, 3], []),
        ([], ["洗剤", "電池", "水", "米"]),
    ] as [([Int], [String])])
    func 渡された位置のお気に入りだけを消す(deletedIndexes: [Int], expectedNames: [String]) throws {
        let fileURL = temporaryFavoritesFileURL()
        let favorites = [favorite(name: "洗剤"), favorite(name: "電池"), favorite(name: "水"), favorite(name: "米")]
        try saveFavorites(favorites: favorites, fileURL: fileURL)
        try deleteFavorites(indexes: IndexSet(deletedIndexes), favorites: favorites, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == expectedNames)
    }

    // MARK: - 「カートイン」の確認

    /// 「カートイン」を押した時刻。2026-11-18 00:00:00 UTC。
    private let pressedAt = Date(timeIntervalSince1970: 1_794_960_000)

    /// 名前・商品バリアントの名前・個数・商品・リマインドを指定したお気に入りを返す。
    private func favorite(name: String, variantName: String?, quantity: Int, product: Favorite.Product, reminder: Reminder?) -> Favorite {
        Favorite(id: UUID(), name: name, variantName: variantName, imageURL: nil, quantity: quantity, product: product, reminder: reminder)
    }

    /// 同じ商品の商品バリアント違いの 2 行と別の商品の 1 行で、「カートイン」を押した行のお気に入りを確認が指す。
    /// 先頭・途中・末尾のどの行でも、確認が持つ識別子の行のお気に入りを指す (別の行を押すと確認が持つ識別子がその行のものに替わるので、その行を指す)。
    @Test(arguments: [0, 1, 2])
    func 確認はカートインを押した行のお気に入りを指す(pressedIndex: Int) {
        let favorites = [
            favorite(
                name: "コーヒー豆 中煎り",
                variantName: "200g / 豆のまま",
                quantity: 2,
                product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
                reminder: nil
            ),
            favorite(
                name: "コーヒー豆 中煎り",
                variantName: "500g / 中挽き",
                quantity: 1,
                product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881413")),
                reminder: nil
            ),
            favorite(
                name: "洗濯用せっけん",
                variantName: nil,
                quantity: 1,
                product: .shopify(ShopifyProduct(shopDomain: "sukoyaka-soap.example", variantID: "70881382")),
                reminder: nil
            ),
        ]
        #expect(
            cartInConfirmationFavorite(confirmation: (favoriteID: favorites[pressedIndex].id, shownAt: pressedAt), favorites: favorites, now: pressedAt)
                == favorites[pressedIndex]
        )
    }

    /// 確認を出していない時・確認が指すお気に入りが一覧から消えた時・お気に入りが 1 件も無い時は、確認が指すお気に入りは無い (先頭のお気に入りなど別のものを指さない)。
    @Test func 確認を出していない時と指すお気に入りが消えた時は確認を出さない() {
        let savedFavorite = favorite(name: "コーヒー豆")
        #expect(cartInConfirmationFavorite(confirmation: nil, favorites: [savedFavorite], now: pressedAt) == nil)
        #expect(cartInConfirmationFavorite(confirmation: (favoriteID: UUID(), shownAt: pressedAt), favorites: [savedFavorite], now: pressedAt) == nil)
        #expect(cartInConfirmationFavorite(confirmation: (favoriteID: savedFavorite.id, shownAt: pressedAt), favorites: [], now: pressedAt) == nil)
    }

    /// 確認は押した時刻から 8 秒未満の間だけ出て、8 秒ちょうどからは出ない。
    @Test(arguments: [
        (elapsedSeconds: 0.0, isShown: true),
        (elapsedSeconds: 7.999, isShown: true),
        (elapsedSeconds: 8.0, isShown: false),
        (elapsedSeconds: 60.0, isShown: false),
    ])
    func 確認は押してから8秒で消える(elapsedSeconds: Double, isShown: Bool) {
        let savedFavorite = favorite(name: "コーヒー豆")
        #expect(
            (cartInConfirmationFavorite(
                confirmation: (favoriteID: savedFavorite.id, shownAt: pressedAt),
                favorites: [savedFavorite],
                now: pressedAt.addingTimeInterval(elapsedSeconds)
            ) != nil) == isShown
        )
    }

    /// 開く URL を組み立てられないお気に入り (ASIN の形でない Amazon の商品・店のドメインがホスト名の形でないもの) は、識別子が合っていても確認が指さない。
    @Test(arguments: [
        Favorite.Product.amazon(AmazonProduct(asin: "B00EXAMPL")),
        Favorite.Product.shopify(ShopifyProduct(shopDomain: "mori-coffee.example/evil", variantID: "70881412")),
    ])
    func 購入画面を開けないお気に入りには確認を出さない(product: Favorite.Product) {
        let unopenableFavorite = favorite(name: "電池", variantName: nil, quantity: 1, product: product, reminder: nil)
        #expect(cartInConfirmationFavorite(confirmation: (favoriteID: unopenableFavorite.id, shownAt: pressedAt), favorites: [unopenableFavorite], now: pressedAt) == nil)
    }

    /// 確認の 2 行目は、名前・商品バリアントの名前 (持つお気に入りだけ)・個数からなる。
    @Test func 確認の文は何を何個カートに入れて開くかを書く() {
        #expect(
            cartInConfirmationText(
                favorite: favorite(
                    name: "コーヒー豆 中煎り",
                    variantName: "200g / 豆のまま",
                    quantity: 2,
                    product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
                    reminder: nil
                ), locale: Locale(identifier: "ja")
            ) == "コーヒー豆 中煎り 200g / 豆のまま を 2 個カートに入れて開きます"
        )
        #expect(
            cartInConfirmationText(
                favorite: favorite(
                    name: "洗濯用せっけん",
                    variantName: nil,
                    quantity: 12,
                    product: .shopify(ShopifyProduct(shopDomain: "sukoyaka-soap.example", variantID: "70881382")),
                    reminder: nil
                ), locale: Locale(identifier: "ja")
            ) == "洗濯用せっけん を 12 個カートに入れて開きます"
        )
    }

    /// Amazon の商品の確認は、個数を出さずに商品ページを開くことと、カートに入らないことを書く。確認は Amazon の商品も指す。
    @Test func Amazonの商品の確認は商品ページを開くことを書く() {
        let amazonFavorite = favorite(name: "単3電池", variantName: nil, quantity: 1, product: .amazon(AmazonProduct(asin: "B0DTESTAB1")), reminder: nil)
        #expect(cartInConfirmationText(favorite: amazonFavorite, locale: Locale(identifier: "ja")) == "単3電池 の商品ページを開きます (カートには入りません)")
        #expect(cartInConfirmationFavorite(confirmation: (favoriteID: amazonFavorite.id, shownAt: pressedAt), favorites: [amazonFavorite], now: pressedAt) == amazonFavorite)
    }

    /// 確認の「開く」で、確認が指すお気に入りの店のドメイン・商品バリアントの ID・保存済みの個数 (確認を出した後に変えた個数を含む) から組み立てた URL が返り、
    /// そのお気に入りのリマインドだけが開いた時刻から数え直される。
    @Test func 開くは確認を出した後に変えた個数で確認が指すお気に入りのURLを返す() throws {
        let fileURL = temporaryFavoritesFileURL()
        // 2026-11-17 00:00:00 UTC。
        let countedFrom = Date(timeIntervalSince1970: 1_794_873_600)
        let pressedFavorite = favorite(
            name: "コーヒー豆 中煎り",
            variantName: "500g / 中挽き",
            quantity: 1,
            product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881413")),
            reminder: Reminder(intervalDays: 7, countedFrom: countedFrom)
        )
        try saveFavorites(
            favorites: [
                favorite(
                    name: "コーヒー豆 中煎り",
                    variantName: "200g / 豆のまま",
                    quantity: 2,
                    product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
                    reminder: Reminder(intervalDays: 30, countedFrom: countedFrom)
                ),
                pressedFavorite,
            ],
            fileURL: fileURL
        )

        // 数え始めてから 10 日後 (10 × 86400 秒)。
        let openedAt = countedFrom.addingTimeInterval(864_000)
        try updateFavorite(id: pressedFavorite.id, name: pressedFavorite.name, quantity: 3, fileURL: fileURL)
        #expect(
            try openingURL(
                favoriteID: try #require(
                    cartInConfirmationFavorite(
                        confirmation: (favoriteID: pressedFavorite.id, shownAt: openedAt),
                        favorites: try loadFavorites(fileURL: fileURL),
                        now: openedAt
                    )
                ).id,
                now: openedAt,
                fileURL: fileURL
            )?.absoluteString
                == "https://mori-coffee.example/cart/70881413:3"
        )
        #expect(try loadFavorites(fileURL: fileURL).map(\.reminder) == [
            Reminder(intervalDays: 30, countedFrom: countedFrom),
            Reminder(intervalDays: 7, countedFrom: openedAt),
        ])
    }

    // MARK: - 店のドメインの表示

    /// Shopify の商品は保存した店のドメイン、Amazon の商品は追加の確認の画面と同じ `www.amazon.co.jp` を表示する。
    @Test func 店のドメインを表示の文字列にする() {
        #expect(shopDomainText(favorite: favorite(name: "コーヒー豆")) == "mori-coffee.example")
        #expect(
            shopDomainText(
                favorite: Favorite(id: UUID(), name: "電池", imageURL: nil, quantity: 1, product: .amazon(AmazonProduct(asin: "B00EXAMPLE")), reminder: nil)
            ) == "www.amazon.co.jp"
        )
    }

    // MARK: - 開発者メニュー

    /// 見本は 3 件で、どれも購入画面の URL を組み立てられ、店のドメインは実在しない `.example`。商品バリアントの名前を持つものと持たないものがある。
    @Test func 見本のお気に入りは購入画面を開ける形で実在しない店を指す() {
        #expect(sampleFavorites().map(\.name) == ["コーヒー豆", "洗濯用せっけん", "プロテイン"])
        #expect(sampleFavorites().map(\.variantName) == ["200g / 豆のまま", nil, "1kg"])
        #expect(
            sampleFavorites().map { openingURL(favorite: $0)?.absoluteString } == [
                "https://mori-coffee.example/cart/70881412:2",
                "https://sukoyaka-soap.example/cart/70881382:1",
                "https://karada-store.example/cart/70881999:1",
            ]
        )
    }

    /// 開発者メニューの見本の商品は、ネットワークに出ない通信で、実在しない店の 3 つの商品バリアントを持つ商品として読める。
    @Test func 見本の商品は追加の画面に3つの商品バリアントを未選択で出す() async throws {
        let favoriteAddition = try await loadFavoriteAddition(text: sampleProductPageURLText, urlSession: sampleProductURLSession())
        #expect(favoriteAddition.productPage.shopDomain == "mori-coffee.example")
        #expect(favoriteAddition.product.title == "コーヒー豆 中煎り")
        #expect(favoriteAddition.product.variants.map(\.title) == ["200g / 豆のまま", "500g / 中挽き", "1kg / 豆のまま"])
        #expect(favoriteAddition.quantitiesByVariantID == [:])
    }

    /// 見本を入れると、保存済みのお気に入りの後ろに 3 件が足される。もう一度入れても増えず、利用者が変えた見本の名前も戻らない。
    @Test func 見本を入れると末尾に足され2回目は増えない() throws {
        let fileURL = temporaryFavoritesFileURL()
        // 見本と同じ店・同じ種類だと行を足さずに個数を書き換えるので、自分で入れた商品は見本に無い店のものにする。
        let existingFavorite = favorite(name: "自分で入れた商品", variantName: nil, quantity: 1, product: .shopify(ShopifyProduct(shopDomain: "own-shop.example", variantID: "1")), reminder: nil)
        try saveFavorites(favorites: [existingFavorite], fileURL: fileURL)
        try insertSampleFavorites(fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [existingFavorite] + sampleFavorites())
        try updateFavorite(id: sampleFavorites()[0].id, name: "名前を変えた見本", quantity: 4, fileURL: fileURL)
        try insertSampleFavorites(fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["自分で入れた商品", "名前を変えた見本", "洗濯用せっけん", "プロテイン"])
    }

    /// 見本を消すと、名前を変えた見本を含む見本の 3 件だけが無くなり、自分で入れたお気に入りは並びも値もそのまま残る。もう一度消しても変わらない。
    @Test func 見本を消すと自分で入れたお気に入りだけが残る() throws {
        let fileURL = temporaryFavoritesFileURL()
        // 見本とも互いとも違う種類にする (同じ店・同じ種類の追加は行を足さない)。
        let firstOwnFavorite = favorite(name: "自分で入れた商品", variantName: nil, quantity: 1, product: .shopify(ShopifyProduct(shopDomain: "own-shop.example", variantID: "1")), reminder: nil)
        let secondOwnFavorite = favorite(name: "後から入れた商品", variantName: nil, quantity: 1, product: .shopify(ShopifyProduct(shopDomain: "own-shop.example", variantID: "2")), reminder: nil)
        try saveFavorites(favorites: [firstOwnFavorite], fileURL: fileURL)
        try insertSampleFavorites(fileURL: fileURL)
        try addFavorite(favorite: secondOwnFavorite, fileURL: fileURL)
        try updateFavorite(id: sampleFavorites()[1].id, name: "名前を変えた見本", quantity: 4, fileURL: fileURL)
        try deleteSampleFavorites(fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [firstOwnFavorite, secondOwnFavorite])
        try deleteSampleFavorites(fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [firstOwnFavorite, secondOwnFavorite])
    }

    /// 見本だけが入っている時に消すと 0 件になり、保存先のファイルが無い時に消しても 0 件のまま。
    @Test func 見本だけの時に消すと0件になる() throws {
        let fileURL = temporaryFavoritesFileURL()
        try deleteSampleFavorites(fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [])
        try insertSampleFavorites(fileURL: fileURL)
        try deleteSampleFavorites(fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [])
    }
}
