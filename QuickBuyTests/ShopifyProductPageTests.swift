import Foundation
import os
import Testing
@testable import QuickBuy

/// 商品ページの URL の分解・商品の JSON を取得する URL の組み立て・確認の画面で選ぶ商品バリアント・選んだ商品バリアントから作るお気に入りを確かめる。
/// 形式の出典は `shopifyProductPage(text:)` と `ShopifyAjaxProduct` の document コメント。
struct ShopifyProductPageTests {
    // MARK: - 商品ページの URL の分解

    /// 通す形ごとに、店のドメイン・言語の部分・商品のハンドル・商品バリアントの ID が取り出せる。
    @Test(arguments: [
        (
            "https://mori-coffee.example/products/coffee-beans-200g",
            ShopifyProductPage(shopDomain: "mori-coffee.example", localePathComponent: nil, percentEncodedProductHandle: "coffee-beans-200g", variantID: nil)
        ),
        (
            "https://mori-coffee.example/products/coffee-beans-200g/",
            ShopifyProductPage(shopDomain: "mori-coffee.example", localePathComponent: nil, percentEncodedProductHandle: "coffee-beans-200g", variantID: nil)
        ),
        (
            "https://mori-coffee.example/products/coffee-beans-200g?variant=70881412",
            ShopifyProductPage(shopDomain: "mori-coffee.example", localePathComponent: nil, percentEncodedProductHandle: "coffee-beans-200g", variantID: "70881412")
        ),
        (
            "https://mori-coffee.example/products/coffee-beans-200g?utm_source=mail&variant=70881412#reviews",
            ShopifyProductPage(shopDomain: "mori-coffee.example", localePathComponent: nil, percentEncodedProductHandle: "coffee-beans-200g", variantID: "70881412")
        ),
        (
            "https://mori-coffee.example/ja/products/coffee-beans-200g",
            ShopifyProductPage(shopDomain: "mori-coffee.example", localePathComponent: "ja", percentEncodedProductHandle: "coffee-beans-200g", variantID: nil)
        ),
        (
            "https://mori-coffee.example/en-ca/collections/beans/products/coffee-beans-200g",
            ShopifyProductPage(shopDomain: "mori-coffee.example", localePathComponent: "en-ca", percentEncodedProductHandle: "coffee-beans-200g", variantID: nil)
        ),
        (
            "https://mori-coffee.example/collections/beans/products/coffee-beans-200g",
            ShopifyProductPage(shopDomain: "mori-coffee.example", localePathComponent: nil, percentEncodedProductHandle: "coffee-beans-200g", variantID: nil)
        ),
        (
            "HTTPS://Mori-Coffee.Example/products/coffee-beans-200g",
            ShopifyProductPage(shopDomain: "mori-coffee.example", localePathComponent: nil, percentEncodedProductHandle: "coffee-beans-200g", variantID: nil)
        ),
        (
            "https://mori-coffee.example/products/%E7%8F%88%E7%90%B2",
            ShopifyProductPage(shopDomain: "mori-coffee.example", localePathComponent: nil, percentEncodedProductHandle: "%E7%8F%88%E7%90%B2", variantID: nil)
        ),
    ])
    func 商品ページのURLを分解できる(text: String, expectedProductPage: ShopifyProductPage) {
        #expect(shopifyProductPage(text: text) == expectedProductPage)
    }

    /// 通す形に似ているが、スキーム・認証情報・ポート・店のドメイン・パス・商品バリアントの ID のどれかが決まった形でない入力は分解しない。
    @Test(arguments: [
        "",
        "mori-coffee.example/products/coffee-beans-200g",
        "http://mori-coffee.example/products/coffee-beans-200g",
        "shopify://mori-coffee.example/products/coffee-beans-200g",
        "https://mori-coffee.example@evil.example/products/coffee-beans-200g",
        "https://user:password@mori-coffee.example/products/coffee-beans-200g",
        "https://mori-coffee.example:8443/products/coffee-beans-200g",
        "https://192.0.2.1/products/coffee-beans-200g",
        "https://localhost/products/coffee-beans-200g",
        "https://mori-coffee.example",
        "https://mori-coffee.example/",
        "https://mori-coffee.example/products",
        "https://mori-coffee.example/products/",
        "https://mori-coffee.example/products//",
        "https://mori-coffee.example//products/coffee-beans-200g",
        "https://mori-coffee.example/products/coffee-beans-200g/reviews",
        "https://mori-coffee.example/pages/products/coffee-beans-200g",
        "https://mori-coffee.example/collections/products/coffee-beans-200g",
        "https://mori-coffee.example/ja/en/products/coffee-beans-200g",
        "https://mori-coffee.example/cart/70881412:1",
        "https://www.amazon.co.jp/dp/B00EXAMPLE",
        "https://mori-coffee.example/products/coffee-beans-200g?variant=",
        "https://mori-coffee.example/products/coffee-beans-200g?variant=70881412:9",
        "https://mori-coffee.example/products/coffee-beans-200g?variant=abc",
        "https://mori-coffee.example/products/coffee beans",
        "https://mori-coffee.example/products/珈琲",
        "https://mori-coffee.example/products/coffee-beans-200g\nhttps://evil.example/products/x",
        " https://mori-coffee.example/products/coffee-beans-200g",
    ])
    func 形の違う入力は分解しない(text: String) {
        #expect(shopifyProductPage(text: text) == nil)
    }

    // MARK: - 商品の JSON を取得する URL

    /// 言語の部分が無い商品ページは `/products/{商品のハンドル}.js`、ある商品ページは `/{言語}/products/{商品のハンドル}.js` を取得する。コレクションの部分と商品バリアントの ID は URL に入らない。
    @Test(arguments: [
        ("https://mori-coffee.example/products/coffee-beans-200g?variant=70881412", "https://mori-coffee.example/products/coffee-beans-200g.js"),
        ("https://mori-coffee.example/ja/collections/beans/products/coffee-beans-200g", "https://mori-coffee.example/ja/products/coffee-beans-200g.js"),
        ("https://mori-coffee.example/products/%E7%8F%88%E7%90%B2", "https://mori-coffee.example/products/%E7%8F%88%E7%90%B2.js"),
    ])
    func 商品のJSONを取得するURLを組み立てる(text: String, expectedURLText: String) throws {
        #expect(try shopifyAjaxProductURL(productPage: #require(shopifyProductPage(text: text)))?.absoluteString == expectedURLText)
    }

    // MARK: - 商品の JSON の読み取り

    /// 公式ドキュメントの応答の例と同じ形 (バリアントの `id` が数値・画像がスキームを省いた形・使わないキーを含む) の JSON を読める。
    @Test func 商品のJSONを読める() throws {
        #expect(
            try JSONDecoder().decode(
                ShopifyAjaxProduct.self,
                from: Data(
                    """
                    {"id":329678821,"title":"Red Rain Coat","handle":"red-rain-coat","price":12900,
                     "variants":[{"id":794864229,"title":"Small","available":true,"price":12900},
                                 {"id":794864233,"title":"Medium","available":false,"price":12900}],
                     "featured_image":"//cdn.shopify.com/s/files/1/0040/7092/products/red-rain-coat.jpeg?v=1402604893",
                     "url":"/products/red-rain-coat"}
                    """.utf8
                )
            ) == ShopifyAjaxProduct(
                title: "Red Rain Coat",
                featuredImage: "//cdn.shopify.com/s/files/1/0040/7092/products/red-rain-coat.jpeg?v=1402604893",
                variants: [
                    .init(id: 794_864_229, title: "Small", available: true),
                    .init(id: 794_864_233, title: "Medium", available: false),
                ]
            )
        )
    }

    /// 画像の無い商品 (`featured_image` が null) も読める。
    @Test func 画像の無い商品のJSONを読める() throws {
        #expect(
            try JSONDecoder().decode(
                ShopifyAjaxProduct.self,
                from: Data(#"{"title":"Soap","featured_image":null,"variants":[{"id":1,"title":"Default Title","available":true}]}"#.utf8)
            ) == ShopifyAjaxProduct(title: "Soap", featuredImage: nil, variants: [.init(id: 1, title: "Default Title", available: true)])
        )
    }

    // MARK: - 確認の画面で選ぶ商品バリアント

    /// 作るお気に入りの確認に使う 1 つ目の識別子。
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    /// 作るお気に入りの確認に使う 2 つ目の識別子。
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    /// 店のドメインが `mori-coffee.example` の商品ページ (商品バリアントの ID は引数のとおり) を返す。
    private func productPage(variantID: String?) -> ShopifyProductPage {
        ShopifyProductPage(shopDomain: "mori-coffee.example", localePathComponent: nil, percentEncodedProductHandle: "coffee-beans", variantID: variantID)
    }

    /// 「100g」(売り切れ)・「200g」(買える)・「500g」(買える) の 3 つの商品バリアントを持つ商品を返す。
    private func productWithThreeVariants(featuredImage: String?) -> ShopifyAjaxProduct {
        ShopifyAjaxProduct(
            title: "コーヒー豆",
            featuredImage: featuredImage,
            variants: [
                .init(id: 101, title: "100g", available: false),
                .init(id: 102, title: "200g", available: true),
                .init(id: 103, title: "500g", available: true),
            ]
        )
    }

    /// 商品バリアントが「Default Title」(売り切れ) の 1 つだけの商品を返す。
    private func productWithOneVariant() -> ShopifyAjaxProduct {
        ShopifyAjaxProduct(title: "せっけん", featuredImage: nil, variants: [.init(id: 201, title: "Default Title", available: false)])
    }

    /// 商品バリアントが 2 つ以上ある商品は、`?variant=` が無ければどれも選んでいない状態から始まる (最初の買える商品バリアントを勝手に選ばない)。
    @Test func 複数ある商品は指定が無ければ未選択から始まる() {
        #expect(initialVariantQuantities(productPage: productPage(variantID: nil), product: productWithThreeVariants(featuredImage: nil)) == [:])
    }

    /// `?variant=` で指定された商品バリアントは、売り切れ (先頭) でも・最後の 1 つでも、それだけを個数 1 で選んだ状態から始まる。
    @Test(arguments: [("101", 101), ("103", 103)] as [(String, UInt64)])
    func 指定された商品バリアントだけを選んだ状態から始まる(variantIDText: String, expectedVariantID: UInt64) {
        #expect(
            initialVariantQuantities(productPage: productPage(variantID: variantIDText), product: productWithThreeVariants(featuredImage: nil))
                == [expectedVariantID: 1]
        )
    }

    /// 商品バリアントが 1 つだけの商品は、指定が無くても・その 1 つを指定しても、売り切れでも、その 1 つを個数 1 で選んだ状態から始まる。
    @Test(arguments: [nil, "201"] as [String?])
    func 商品バリアントが1つの商品はその1つを選んだ状態から始まる(variantIDText: String?) {
        #expect(initialVariantQuantities(productPage: productPage(variantID: variantIDText), product: productWithOneVariant()) == [201: 1])
    }

    /// 指定された商品バリアントがその商品に無い時 (複数ある商品でも 1 つだけの商品でも) は、確認の画面に進めない (別の商品バリアントにすり替えない)。
    @Test func 指定された商品バリアントが無い時は進めない() {
        #expect(initialVariantQuantities(productPage: productPage(variantID: "999"), product: productWithThreeVariants(featuredImage: nil)) == nil)
        #expect(initialVariantQuantities(productPage: productPage(variantID: "999"), product: productWithOneVariant()) == nil)
    }

    /// 商品バリアントが 1 つも無い商品では、確認の画面に進めない。
    @Test func 商品バリアントが無い商品では進めない() {
        #expect(
            initialVariantQuantities(
                productPage: productPage(variantID: nil),
                product: ShopifyAjaxProduct(title: "コーヒー豆", featuredImage: nil, variants: [])
            ) == nil
        )
    }

    /// 選んでいない商品バリアントの行を押すと個数 1 で選ばれ、選んである行を押すと選ぶのをやめる。ほかの商品バリアントの個数は変わらない。
    @Test(arguments: [
        ([:], [102: 1]),
        ([103: 2], [102: 1, 103: 2]),
        ([102: 3, 103: 2], [103: 2]),
        ([102: 3], [:]),
    ] as [([UInt64: Int], [UInt64: Int])])
    func 商品バリアントの行を押すと選ぶ選ばないが替わる(quantitiesByVariantID: [UInt64: Int], expectedQuantitiesByVariantID: [UInt64: Int]) {
        #expect(toggledVariantQuantities(quantitiesByVariantID: quantitiesByVariantID, variantID: 102) == expectedQuantitiesByVariantID)
    }

    // MARK: - 選んだ商品バリアントから作るお気に入り

    /// 3 つのうち「500g」を 1 個・「100g」を 2 個選ぶと、商品の並び順 (100g・500g) で 2 件でき、それぞれが選んだ個数・商品バリアントの名前・商品バリアントの ID を持つ。
    /// 名前はどちらも確認の画面の名前、選んでいない「200g」のお気に入りはできない。
    @Test func 選んだ商品バリアントごとに1件ずつお気に入りを作る() {
        // 識別子を作る処理が呼ばれるたびに、先頭から 1 つずつ渡す。
        let remainingIDs = OSAllocatedUnfairLock(initialState: [firstID, secondID])
        #expect(
            selectedVariantFavorites(
                productPage: productPage(variantID: nil),
                product: productWithThreeVariants(featuredImage: "//cdn.shopify.com/beans.png"),
                name: "いつもの豆",
                quantitiesByVariantID: [103: 1, 101: 2],
                makeID: { remainingIDs.withLock { $0.removeFirst() } }
            ) == [
                Favorite(
                    id: firstID,
                    name: "いつもの豆",
                    variantName: "100g",
                    imageURL: URL(string: "https://cdn.shopify.com/beans.png"),
                    quantity: 2,
                    product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "101")),
                    reminder: nil
                ),
                Favorite(
                    id: secondID,
                    name: "いつもの豆",
                    variantName: "500g",
                    imageURL: URL(string: "https://cdn.shopify.com/beans.png"),
                    quantity: 1,
                    product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "103")),
                    reminder: nil
                ),
            ]
        )
    }

    /// 1 つも選んでいない時は、お気に入りを 1 件も作らない。
    @Test func 選んでいない時はお気に入りを作らない() {
        #expect(
            selectedVariantFavorites(
                productPage: productPage(variantID: nil),
                product: productWithThreeVariants(featuredImage: nil),
                name: "いつもの豆",
                quantitiesByVariantID: [:],
                makeID: { firstID }
            ) == []
        )
    }

    /// 商品バリアントが 1 つだけの商品のお気に入りは、商品バリアントの名前を持たない (`Default Title` を入れない)。個数は決めた値になる。
    @Test func 商品バリアントが1つの商品は商品バリアントの名前を持たない() {
        #expect(
            selectedVariantFavorites(
                productPage: productPage(variantID: nil),
                product: productWithOneVariant(),
                name: "せっけん",
                quantitiesByVariantID: [201: 3],
                makeID: { firstID }
            ) == [
                Favorite(
                    id: firstID,
                    name: "せっけん",
                    variantName: nil,
                    imageURL: nil,
                    quantity: 3,
                    product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "201")),
                    reminder: nil
                ),
            ]
        )
    }

    /// 画像の URL は、`https` (スキームを省いた形を含む) で、ホストが Shopify の CDN か店のドメイン (`mori-coffee.example`) のものだけを入れる。
    /// ホストの大文字と小文字は区別しない。
    /// 無関係なホスト (スキームを省いた形を含む)・CDN の名前で始まるだけのホスト・末尾にドットの付いたホスト・認証情報の位置に CDN の名前を書いた URL・パスワードだけを含む URL・ポートを含む URL・店のドメインのサブドメイン・`http`・ほかのスキーム・空文字・画像なしでは入れない。
    @Test(arguments: [
        ("https://cdn.shopify.com/s/files/beans.png", "https://cdn.shopify.com/s/files/beans.png"),
        ("//cdn.shopify.com/s/files/beans.png", "https://cdn.shopify.com/s/files/beans.png"),
        ("https://CDN.Shopify.com/s/files/beans.png", "https://CDN.Shopify.com/s/files/beans.png"),
        ("https://mori-coffee.example/cdn/shop/beans.png", "https://mori-coffee.example/cdn/shop/beans.png"),
        ("//mori-coffee.example/cdn/shop/beans.png", "https://mori-coffee.example/cdn/shop/beans.png"),
        ("https://Mori-Coffee.Example/cdn/shop/beans.png", "https://Mori-Coffee.Example/cdn/shop/beans.png"),
        ("https://tracker.example/beans.png", nil),
        ("//tracker.example/beans.png", nil),
        ("https://cdn.shopify.com:8443/s/files/beans.png", nil),
        ("https://mori-coffee.example:8443/cdn/shop/beans.png", nil),
        ("https://:password@cdn.shopify.com/s/files/beans.png", nil),
        ("https://cdn.shopify.com./s/files/beans.png", nil),
        ("https://cdn.shopify.com.tracker.example/beans.png", nil),
        ("https://cdn.shopify.com@tracker.example/beans.png", nil),
        ("https://sub.mori-coffee.example/beans.png", nil),
        ("http://cdn.shopify.com/s/files/beans.png", nil),
        ("", nil),
        ("file:///etc/hosts", nil),
        (nil, nil),
    ] as [(String?, String?)])
    func 画像のURLはhttpsで店のドメインかShopifyのCDNのものだけを入れる(featuredImage: String?, expectedImageURLText: String?) {
        #expect(
            selectedVariantFavorites(
                productPage: productPage(variantID: nil),
                product: productWithThreeVariants(featuredImage: featuredImage),
                name: "コーヒー豆",
                quantitiesByVariantID: [102: 1],
                makeID: { firstID }
            ).map { $0.imageURL?.absoluteString } == [expectedImageURLText]
        )
    }

    // MARK: - 保存するボタンの文言

    /// 商品バリアントが複数ある商品で 1 つ以上選んでいる時だけ、選んだ数を入れる。1 つも選んでいない時と、1 つだけの商品では数を入れない。
    @Test(arguments: [
        (3, 2, "2 種類をお気に入りに追加"),
        (3, 1, "1 種類をお気に入りに追加"),
        (2, 2, "2 種類をお気に入りに追加"),
        (3, 0, "お気に入りに追加"),
        (1, 1, "お気に入りに追加"),
    ])
    func 保存するボタンは選んだ種類の数を出す(variantCount: Int, selectedVariantCount: Int, expectedTitle: String) {
        #expect(favoriteAdditionButtonTitle(variantCount: variantCount, selectedVariantCount: selectedVariantCount) == expectedTitle)
    }
}
