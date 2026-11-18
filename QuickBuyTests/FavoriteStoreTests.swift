import Foundation
import Testing
@testable import QuickBuy

/// お気に入りの型が保存の形 (JSON) と行き来できることと、追加・変更・並べ替え・削除が保存先のファイルに反映されることを確かめる。
/// 型と操作の出典は documents/data-structure/favorite-2026-11-17.html。
struct FavoriteStoreTests {
    /// テストごとに別の、まだ存在しない保存先のファイルの URL を返す (テストどうしが同じファイルを読み書きしないため)。
    private func temporaryFavoritesFileURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "favorites-\(UUID().uuidString).json")
    }

    /// 名前と識別子だけが違う Shopify の商品のお気に入りを返す。
    private func shopifyFavorite(id: UUID, name: String) -> Favorite {
        Favorite(
            id: id,
            name: name,
            imageURL: nil,
            quantity: 1,
            product: .shopify(ShopifyProduct(shopDomain: "example.myshopify.com", variantID: "70881412")),
            reminder: nil
        )
    }

    /// 並びの確認に使う 1 件目 (「洗剤」) の識別子。
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    /// 並びの確認に使う 2 件目 (「電池」) の識別子。
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    /// 並びの確認に使う 3 件目 (「水」) の識別子。
    private let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    /// 「洗剤」「電池」「水」の順で 3 件を保存した保存先のファイルの URL を返す。
    private func fileURLWithThreeFavorites() throws -> URL {
        let fileURL = temporaryFavoritesFileURL()
        try saveFavorites(
            favorites: [
                shopifyFavorite(id: firstID, name: "洗剤"),
                shopifyFavorite(id: secondID, name: "電池"),
                shopifyFavorite(id: thirdID, name: "水"),
            ],
            fileURL: fileURL
        )
        return fileURL
    }

    // MARK: - 保存の形

    /// 全部の値を持つお気に入り (Shopify・画像あり・リマインドあり) と、任意の値が無いお気に入り (Amazon・画像なし・リマインドなし) を
    /// 保存して読み戻すと、並びも値も等しい。日時は秒未満を含む値で確かめる。
    @Test func 保存したお気に入りを読み戻すと等しい() throws {
        let fileURL = temporaryFavoritesFileURL()
        let favorites = [
            Favorite(
                id: firstID,
                name: "洗剤",
                imageURL: URL(string: "https://cdn.example.com/detergent.png"),
                quantity: 2,
                product: .shopify(ShopifyProduct(shopDomain: "example.myshopify.com", variantID: "70881412")),
                reminder: Reminder(intervalDays: 30, countedFrom: Date(timeIntervalSinceReferenceDate: 784_000_000.125))
            ),
            Favorite(
                id: secondID,
                name: "電池",
                imageURL: nil,
                quantity: 1,
                product: .amazon(AmazonProduct(asin: "B00EXAMPLE")),
                reminder: nil
            ),
        ]
        try saveFavorites(favorites: favorites, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == favorites)
    }

    /// 保存済みの端末のファイルの形 (キーの名前、`Product` の case の入れ子、日時が 2001-01-01 00:00:00 UTC からの秒数であること) を固定する。
    /// この JSON を読めなくなる変更は、保存済みのお気に入りを読めなくする。
    @Test func 保存済みのJSONの形を読める() throws {
        let fileURL = temporaryFavoritesFileURL()
        try Data(
            """
            [
              {
                "id": "00000000-0000-0000-0000-000000000001",
                "name": "洗剤",
                "variantName": "つめかえ用 / 2L",
                "imageURL": "https://cdn.example.com/detergent.png",
                "quantity": 2,
                "product": {"shopify": {"_0": {"shopDomain": "example.myshopify.com", "variantID": "70881412"}}},
                "reminder": {"intervalDays": 30, "countedFrom": 86400}
              },
              {
                "id": "00000000-0000-0000-0000-000000000002",
                "name": "電池",
                "quantity": 1,
                "product": {"amazon": {"_0": {"asin": "B00EXAMPLE"}}}
              }
            ]
            """.utf8
        ).write(to: fileURL)
        #expect(
            try loadFavorites(fileURL: fileURL) == [
                Favorite(
                    id: firstID,
                    name: "洗剤",
                    variantName: "つめかえ用 / 2L",
                    imageURL: URL(string: "https://cdn.example.com/detergent.png"),
                    quantity: 2,
                    product: .shopify(ShopifyProduct(shopDomain: "example.myshopify.com", variantID: "70881412")),
                    // 2001-01-02 00:00:00 UTC。
                    reminder: Reminder(intervalDays: 30, countedFrom: Date(timeIntervalSince1970: 978_393_600))
                ),
                Favorite(
                    id: secondID,
                    name: "電池",
                    variantName: nil,
                    imageURL: nil,
                    quantity: 1,
                    product: .amazon(AmazonProduct(asin: "B00EXAMPLE")),
                    reminder: nil
                ),
            ]
        )
    }

    /// 書き出したファイルも、上の「保存済みのJSONの形を読める」と同じ形になる (キーの名前と入れ子、日時の秒数)。
    /// 商品バリアントの名前・画像・リマインドが無いお気に入りは、そのキーを書かない。
    @Test func 保存するJSONの形() throws {
        let fileURL = temporaryFavoritesFileURL()
        try saveFavorites(
            favorites: [
                Favorite(
                    id: firstID,
                    name: "洗剤",
                    variantName: "つめかえ用 / 2L",
                    imageURL: URL(string: "https://cdn.example.com/detergent.png"),
                    quantity: 2,
                    product: .shopify(ShopifyProduct(shopDomain: "example.myshopify.com", variantID: "70881412")),
                    reminder: Reminder(intervalDays: 30, countedFrom: Date(timeIntervalSince1970: 978_393_600))
                ),
                Favorite(
                    id: secondID,
                    name: "電池",
                    variantName: nil,
                    imageURL: nil,
                    quantity: 1,
                    product: .amazon(AmazonProduct(asin: "B00EXAMPLE")),
                    reminder: nil
                ),
            ],
            fileURL: fileURL
        )
        #expect(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? NSArray == [
                [
                    "id": "00000000-0000-0000-0000-000000000001",
                    "name": "洗剤",
                    "variantName": "つめかえ用 / 2L",
                    "imageURL": "https://cdn.example.com/detergent.png",
                    "quantity": 2,
                    "product": ["shopify": ["_0": ["shopDomain": "example.myshopify.com", "variantID": "70881412"]]],
                    "reminder": ["intervalDays": 30, "countedFrom": 86400],
                ] as NSDictionary,
                [
                    "id": "00000000-0000-0000-0000-000000000002",
                    "name": "電池",
                    "quantity": 1,
                    "product": ["amazon": ["_0": ["asin": "B00EXAMPLE"]]],
                ] as NSDictionary,
            ] as NSArray
        )
    }

    // MARK: - 読み出し

    /// 1 件も保存していない (ファイルが無い) 時は、空の並びを返す。
    @Test func ファイルが無い時は空を返す() throws {
        #expect(try loadFavorites(fileURL: temporaryFavoritesFileURL()) == [])
    }

    /// 0 件を保存した時も空の並びを返す (ファイルが無い時との境界)。
    @Test func 空の並びを保存して読み戻せる() throws {
        let fileURL = temporaryFavoritesFileURL()
        try saveFavorites(favorites: [], fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [])
    }

    /// ファイルの中身がお気に入りの並びとして読めない時は、空の並びにせずエラーを投げる。
    @Test(arguments: ["", "{}", "[{\"id\": \"00000000-0000-0000-0000-000000000001\"}]", "こわれた中身"])
    func 読めないファイルはエラーにする(fileText: String) throws {
        let fileURL = temporaryFavoritesFileURL()
        try Data(fileText.utf8).write(to: fileURL)
        #expect(throws: DecodingError.self) {
            try loadFavorites(fileURL: fileURL)
        }
    }

    // MARK: - 保存の検査

    /// 個数が 0 以下のお気に入りが 1 つでもあれば保存せず、前に保存した並びが残る (個数 1 は通る境界)。
    @Test(arguments: [0, -1])
    func 個数が1未満のお気に入りは保存しない(quantity: Int) throws {
        let fileURL = try fileURLWithThreeFavorites()
        #expect(throws: FavoriteStoreError.quantityLessThanOne) {
            try saveFavorites(
                favorites: [
                    shopifyFavorite(id: firstID, name: "洗剤"),
                    Favorite(
                        id: secondID,
                        name: "電池",
                        imageURL: nil,
                        quantity: quantity,
                        product: .amazon(AmazonProduct(asin: "B00EXAMPLE")),
                        reminder: nil
                    ),
                ],
                fileURL: fileURL
            )
        }
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤", "電池", "水"])
    }

    /// リマインドの日数が 0 以下のお気に入りは保存せず、前に保存した並びが残る。
    @Test(arguments: [0, -1])
    func リマインドの日数が1未満のお気に入りは保存しない(intervalDays: Int) throws {
        let fileURL = try fileURLWithThreeFavorites()
        #expect(throws: FavoriteStoreError.reminderIntervalDaysLessThanOne) {
            try saveFavorites(
                favorites: [
                    Favorite(
                        id: firstID,
                        name: "洗剤",
                        imageURL: nil,
                        quantity: 1,
                        product: .amazon(AmazonProduct(asin: "B00EXAMPLE")),
                        reminder: Reminder(intervalDays: intervalDays, countedFrom: Date(timeIntervalSince1970: 0))
                    ),
                ],
                fileURL: fileURL
            )
        }
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤", "電池", "水"])
    }

    /// リマインドの日数が 1 のお気に入りは保存できる (通る境界)。
    @Test func リマインドの日数が1のお気に入りは保存できる() throws {
        let fileURL = temporaryFavoritesFileURL()
        try saveFavorites(
            favorites: [
                Favorite(
                    id: firstID,
                    name: "洗剤",
                    imageURL: nil,
                    quantity: 1,
                    product: .amazon(AmazonProduct(asin: "B00EXAMPLE")),
                    reminder: Reminder(intervalDays: 1, countedFrom: Date(timeIntervalSince1970: 0))
                ),
            ],
            fileURL: fileURL
        )
        #expect(try loadFavorites(fileURL: fileURL).first?.reminder?.intervalDays == 1)
    }

    // MARK: - 追加

    /// 1 件も無い所への追加は 1 件になり、続けて足したお気に入りは並びの末尾に入る。
    @Test func 追加したお気に入りは並びの末尾に入る() throws {
        let fileURL = temporaryFavoritesFileURL()
        try addFavorite(favorite: shopifyFavorite(id: firstID, name: "洗剤"), fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤"])
        try addFavorite(favorite: shopifyFavorite(id: secondID, name: "電池"), fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤", "電池"])
    }

    /// 保存済みの識別子と同じお気に入りの追加は、件数も保存済みの値も変えない。
    @Test func 同じ識別子のお気に入りは二重に足さない() throws {
        let fileURL = try fileURLWithThreeFavorites()
        try addFavorite(favorite: shopifyFavorite(id: secondID, name: "別の名前"), fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤", "電池", "水"])
    }

    /// 個数が 0 のお気に入りは追加されない。
    @Test func 個数が1未満のお気に入りは追加しない() throws {
        let fileURL = try fileURLWithThreeFavorites()
        #expect(throws: FavoriteStoreError.quantityLessThanOne) {
            try addFavorite(
                favorite: Favorite(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                    name: "米",
                    imageURL: nil,
                    quantity: 0,
                    product: .amazon(AmazonProduct(asin: "B00EXAMPLE")),
                    reminder: nil
                ),
                fileURL: fileURL
            )
        }
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤", "電池", "水"])
    }

    // MARK: - 名前と個数の変更

    /// 指定したお気に入りの名前と個数だけが変わり、並び・ほかのお気に入り・商品は変わらない。
    @Test func 名前と個数の変更が保存に反映される() throws {
        let fileURL = try fileURLWithThreeFavorites()
        try updateFavorite(id: secondID, name: "単3電池", quantity: 4, fileURL: fileURL)
        #expect(
            try loadFavorites(fileURL: fileURL) == [
                shopifyFavorite(id: firstID, name: "洗剤"),
                Favorite(
                    id: secondID,
                    name: "単3電池",
                    imageURL: nil,
                    quantity: 4,
                    product: .shopify(ShopifyProduct(shopDomain: "example.myshopify.com", variantID: "70881412")),
                    reminder: nil
                ),
                shopifyFavorite(id: thirdID, name: "水"),
            ]
        )
    }

    /// 個数を 0 以下にする変更は保存されず、名前も元のまま残る。
    @Test(arguments: [0, -1])
    func 個数を1未満にする変更は保存しない(quantity: Int) throws {
        let fileURL = try fileURLWithThreeFavorites()
        #expect(throws: FavoriteStoreError.quantityLessThanOne) {
            try updateFavorite(id: secondID, name: "単3電池", quantity: quantity, fileURL: fileURL)
        }
        #expect(
            try loadFavorites(fileURL: fileURL) == [
                shopifyFavorite(id: firstID, name: "洗剤"),
                shopifyFavorite(id: secondID, name: "電池"),
                shopifyFavorite(id: thirdID, name: "水"),
            ]
        )
    }

    /// 保存されていない識別子の変更はエラーになり、保存済みの並びは変わらない。
    @Test func 無いお気に入りの変更はエラーにする() throws {
        let fileURL = try fileURLWithThreeFavorites()
        #expect(throws: FavoriteStoreError.favoriteNotFound) {
            try updateFavorite(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                name: "米",
                quantity: 1,
                fileURL: fileURL
            )
        }
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤", "電池", "水"])
    }

    // MARK: - 並べ替え

    /// 「洗剤・電池・水」から 1 件を移した後の並び。先頭から末尾、末尾から先頭、隣どうし、同じ位置 (変わらない) を確かめる。
    @Test(arguments: [
        ("00000000-0000-0000-0000-000000000001", 2, ["電池", "水", "洗剤"]),
        ("00000000-0000-0000-0000-000000000003", 0, ["水", "洗剤", "電池"]),
        ("00000000-0000-0000-0000-000000000001", 1, ["電池", "洗剤", "水"]),
        ("00000000-0000-0000-0000-000000000002", 0, ["電池", "洗剤", "水"]),
        ("00000000-0000-0000-0000-000000000002", 1, ["洗剤", "電池", "水"]),
    ])
    func 並べ替えが保存に反映される(idText: String, destinationIndex: Int, expectedNames: [String]) throws {
        let fileURL = try fileURLWithThreeFavorites()
        try moveFavorite(id: UUID(uuidString: idText)!, destinationIndex: destinationIndex, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == expectedNames)
    }

    /// 同じ並べ替えを 2 回呼んでも、1 回呼んだ時と同じ並びになる。
    @Test func 同じ並べ替えを繰り返しても並びは変わらない() throws {
        let fileURL = try fileURLWithThreeFavorites()
        try moveFavorite(id: firstID, destinationIndex: 1, fileURL: fileURL)
        try moveFavorite(id: firstID, destinationIndex: 1, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["電池", "洗剤", "水"])
    }

    /// 移動先が並びの範囲の外 (-1 と件数と同じ 3) ならエラーになり、並びは変わらない (0 と 2 は通る境界で、上の「並べ替えが保存に反映される」で確かめている)。
    @Test(arguments: [-1, 3])
    func 範囲の外への並べ替えはエラーにする(destinationIndex: Int) throws {
        let fileURL = try fileURLWithThreeFavorites()
        #expect(throws: FavoriteStoreError.destinationIndexOutOfRange) {
            try moveFavorite(id: firstID, destinationIndex: destinationIndex, fileURL: fileURL)
        }
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤", "電池", "水"])
    }

    /// 保存されていない識別子の並べ替えはエラーになり、並びは変わらない。
    @Test func 無いお気に入りの並べ替えはエラーにする() throws {
        let fileURL = try fileURLWithThreeFavorites()
        #expect(throws: FavoriteStoreError.favoriteNotFound) {
            try moveFavorite(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                destinationIndex: 0,
                fileURL: fileURL
            )
        }
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤", "電池", "水"])
    }

    // MARK: - 削除

    /// 先頭・中・末尾のどれを削除しても、そのお気に入りだけが消え、残りの並びは保たれる。
    @Test(arguments: [
        ("00000000-0000-0000-0000-000000000001", ["電池", "水"]),
        ("00000000-0000-0000-0000-000000000002", ["洗剤", "水"]),
        ("00000000-0000-0000-0000-000000000003", ["洗剤", "電池"]),
    ])
    func 削除が保存に反映される(idText: String, expectedNames: [String]) throws {
        let fileURL = try fileURLWithThreeFavorites()
        try deleteFavorite(id: UUID(uuidString: idText)!, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == expectedNames)
    }

    /// 保存されていない識別子の削除と、同じ削除の 2 回目は、残りの並びを変えない。
    @Test func 無いお気に入りの削除は並びを変えない() throws {
        let fileURL = try fileURLWithThreeFavorites()
        try deleteFavorite(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤", "電池", "水"])
        try deleteFavorite(id: secondID, fileURL: fileURL)
        try deleteFavorite(id: secondID, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL).map(\.name) == ["洗剤", "水"])
    }

    /// 最後の 1 件を削除すると空の並びになる。
    @Test func 最後の1件を削除すると空になる() throws {
        let fileURL = temporaryFavoritesFileURL()
        try addFavorite(favorite: shopifyFavorite(id: firstID, name: "洗剤"), fileURL: fileURL)
        try deleteFavorite(id: firstID, fileURL: fileURL)
        #expect(try loadFavorites(fileURL: fileURL) == [])
    }
}
