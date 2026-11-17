import Foundation
import Testing
@testable import QuickBuy

/// 商品ページの URL の分解・商品の JSON を取得する URL の組み立て・登録前のお気に入りの作成を確かめる。
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

    // MARK: - 登録前のお気に入り

    /// 登録前のお気に入りの確認に使う識別子。
    private let draftID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!

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

    /// 商品バリアントの指定が無い時は、最初の今買える商品バリアントを選び、個数 1・リマインドなしで作る。名前には商品バリアントの名前が付く。
    @Test func 指定が無い時は最初の買える商品バリアントで作る() {
        #expect(
            favoriteDraft(id: draftID, productPage: productPage(variantID: nil), product: productWithThreeVariants(featuredImage: "//cdn.shopify.com/beans.png"))
                == Favorite(
                    id: draftID,
                    name: "コーヒー豆 200g",
                    imageURL: URL(string: "https://cdn.shopify.com/beans.png"),
                    quantity: 1,
                    product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "102")),
                    reminder: nil
                )
        )
    }

    /// `?variant=` で指定された商品バリアントは、売り切れでも・最後の 1 つでも、そのまま選ぶ。
    @Test(arguments: [("101", "コーヒー豆 100g"), ("103", "コーヒー豆 500g")])
    func 指定された商品バリアントで作る(variantID: String, expectedName: String) {
        let favorite = favoriteDraft(id: draftID, productPage: productPage(variantID: variantID), product: productWithThreeVariants(featuredImage: nil))
        #expect(favorite?.name == expectedName)
        #expect(favorite?.product == .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: variantID)))
    }

    /// 指定された商品バリアントがその商品に無い時は作らない (別の商品バリアントにすり替えない)。
    @Test func 指定された商品バリアントが無い時は作らない() {
        #expect(favoriteDraft(id: draftID, productPage: productPage(variantID: "999"), product: productWithThreeVariants(featuredImage: nil)) == nil)
    }

    /// 商品バリアントが 1 つも無い商品では作らない。
    @Test func 商品バリアントが無い商品では作らない() {
        #expect(
            favoriteDraft(id: draftID, productPage: productPage(variantID: nil), product: ShopifyAjaxProduct(title: "コーヒー豆", featuredImage: nil, variants: [])) == nil
        )
    }

    /// 商品バリアントが 1 つだけの商品は、名前に商品バリアントの名前を付けない。今買えるものが無い時は先頭を選ぶ。
    @Test func 商品バリアントが1つの商品は商品の名前だけにする() {
        let favorite = favoriteDraft(
            id: draftID,
            productPage: productPage(variantID: nil),
            product: ShopifyAjaxProduct(title: "せっけん", featuredImage: nil, variants: [.init(id: 201, title: "Default Title", available: false)])
        )
        #expect(favorite?.name == "せっけん")
        #expect(favorite?.product == .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "201")))
    }

    /// 画像の URL は、`https` (スキームを省いた形を含む) で、ホストが Shopify の CDN か店のドメイン (`mori-coffee.example`) のものだけを入れる。
    /// 無関係なホスト・CDN の名前で始まるだけのホスト・認証情報の位置に CDN の名前を書いた URL・店のドメインのサブドメイン・`http`・ほかのスキーム・空文字・画像なしでは入れない。
    @Test(arguments: [
        ("https://cdn.shopify.com/s/files/beans.png", "https://cdn.shopify.com/s/files/beans.png"),
        ("//cdn.shopify.com/s/files/beans.png", "https://cdn.shopify.com/s/files/beans.png"),
        ("https://CDN.Shopify.com/s/files/beans.png", "https://CDN.Shopify.com/s/files/beans.png"),
        ("https://mori-coffee.example/cdn/shop/beans.png", "https://mori-coffee.example/cdn/shop/beans.png"),
        ("//mori-coffee.example/cdn/shop/beans.png", "https://mori-coffee.example/cdn/shop/beans.png"),
        ("https://tracker.example/beans.png", nil),
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
            favoriteDraft(id: draftID, productPage: productPage(variantID: nil), product: productWithThreeVariants(featuredImage: featuredImage))?.imageURL?.absoluteString
                == expectedImageURLText
        )
    }
}
