import Foundation

/// Shopify の店の商品ページの URL から取り出した、店のドメインと商品の指し方。
struct ShopifyProductPage: Equatable {
    /// 店のドメイン (小文字)。`isHostName(text:)` を通った値。
    let shopDomain: String
    /// URL のパスの先頭にあった言語の部分 (例: `ja`・`en-ca`)。無ければ nil。
    let localePathComponent: String?
    /// 商品のハンドル。URL のパスにあった percent-encoding のままの文字列 (例: `red-rain-coat`・`%E6%97%A5%E6%9C%AC`)。
    let percentEncodedProductHandle: String
    /// `?variant=` で指された商品バリアントの ID。数字だけの文字列。指定が無ければ nil。
    let variantID: String?
}

/// 文字列が Shopify の店の商品ページの URL の形なら、店のドメインと商品の指し方に分解して返す。形が違えば nil を返す。
///
/// 通す形は `https://{店のドメイン}[/{言語}][/collections/{コレクション}]/products/{商品のハンドル}[/][?variant={商品バリアントの ID}]`。
/// 形式の出典: 商品ページのパス `/products/{handle}` は https://shopify.dev/docs/api/ajax/reference/product の応答の例の `"url": "/products/red-rain-coat"`、
/// 言語の部分は同ページの `GET /{locale}/products/{product-handle}.js`、
/// `/collections/{コレクション}/products/…` は https://shopify.dev/docs/api/liquid/filters/within の出力の例 `/collections/sale-potions/products/draught-of-immortality`、
/// `?variant=` は https://shopify.dev/docs/api/liquid/objects/product の `url` の例 `/products/gorgeous-wooden-computer?variant=1234567890`。
/// 商品のハンドルは ASCII に限らない (https://shopify.dev/changelog/certain-properties-are-changing-to-support-a-full-utf-8-character-set ) ため、percent-encoding された文字列のまま受け取る。
///
/// nil を返す入力: 印字できる ASCII 以外の文字 (空白・改行・タブ・percent-encoding していない日本語) を含む文字列、`https` 以外のスキーム、
/// 認証情報 (`user@`)・ポートを含む URL、ホスト名の形でない店のドメイン (`isHostName(text:)`)、上の形でないパス (Amazon の商品ページ `/dp/{ASIN}` を含む)、
/// 数字だけでない `variant`。どの店かは見ない (店のドメインは、確認の画面で利用者が確かめる。documents/adr/0003)。
func shopifyProductPage(text: String) -> ShopifyProductPage? {
    guard text.utf8.allSatisfy({ (0x21 ... 0x7E).contains($0) }),
          let urlComponents = URLComponents(string: text, encodingInvalidCharacters: false),
          urlComponents.scheme?.lowercased() == "https",
          urlComponents.user == nil,
          urlComponents.password == nil,
          urlComponents.port == nil,
          let shopDomain = urlComponents.host?.lowercased(),
          isHostName(text: shopDomain),
          let percentEncodedProductHandle = productHandle(percentEncodedPath: urlComponents.percentEncodedPath)
    else {
        return nil
    }
    let variantQueryItem = urlComponents.queryItems?.first { $0.name == "variant" }
    guard variantQueryItem.map({ isASCIIDigits(text: $0.value ?? "") }) != false else {
        return nil
    }
    return ShopifyProductPage(
        shopDomain: shopDomain,
        localePathComponent: localePathComponent(percentEncodedPath: urlComponents.percentEncodedPath),
        percentEncodedProductHandle: percentEncodedProductHandle,
        variantID: variantQueryItem?.value
    )
}

/// URL のパスを `/` で区切った部分の並びを返す。先頭の `/` と、末尾に 1 つだけある `/` は部分に数えない。
///
/// `/` が続く所 (`//products/x`) は空の部分として残す (呼び出し側が形の違うパスとして弾けるようにするため)。
private func pathComponents(percentEncodedPath: String) -> [Substring] {
    let components = percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
    return Array(components.last == "" ? components.dropLast() : components)
}

/// 言語の部分の形 (英字 2〜3 文字。続けて `-` と英数字 2〜4 文字があってもよい。例: `ja`・`en-ca`・`zh-TW`) なら true を返す。
private func isLocalePathComponent(text: Substring) -> Bool {
    let subtags = text.split(separator: "-", omittingEmptySubsequences: false)
    guard let languageSubtag = subtags.first, subtags.count <= 2 else {
        return false
    }
    return (2 ... 3).contains(languageSubtag.count)
        && languageSubtag.allSatisfy { $0.isASCII && $0.isLetter }
        && subtags.dropFirst().allSatisfy { (2 ... 4).contains($0.count) && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }
}

/// 商品ページのパスなら、`products` の前にある部分の並び (言語・`collections`・コレクションの名前) を返す。商品ページのパスでなければ nil を返す。
private func productPagePrefixComponents(percentEncodedPath: String) -> [Substring]? {
    let components = pathComponents(percentEncodedPath: percentEncodedPath)
    guard components.count >= 2,
          components.allSatisfy({ !$0.isEmpty }),
          components[components.count - 2] == "products"
    else {
        return nil
    }
    let prefixComponents = components.dropLast(2)
    let componentsAfterLocale = prefixComponents.first.map(isLocalePathComponent(text:)) == true ? prefixComponents.dropFirst() : prefixComponents
    guard componentsAfterLocale.isEmpty || (componentsAfterLocale.count == 2 && componentsAfterLocale.first == "collections") else {
        return nil
    }
    return Array(prefixComponents)
}

/// 商品ページのパスから商品のハンドル (percent-encoding のまま) を返す。商品ページのパスでなければ nil を返す。
private func productHandle(percentEncodedPath: String) -> String? {
    productPagePrefixComponents(percentEncodedPath: percentEncodedPath) == nil
        ? nil
        : pathComponents(percentEncodedPath: percentEncodedPath).last.map(String.init)
}

/// 商品ページのパスの先頭に言語の部分があれば返す。無い時と商品ページのパスでない時は nil を返す。
private func localePathComponent(percentEncodedPath: String) -> String? {
    productPagePrefixComponents(percentEncodedPath: percentEncodedPath)?.first
        .flatMap { isLocalePathComponent(text: $0) ? String($0) : nil }
}

/// 商品の名前・画像・商品バリアントを取得する URL (Shopify の Ajax Product API) を組み立てて返す。
///
/// 形式の出典: https://shopify.dev/docs/api/ajax/reference/product の `GET /{locale}/products/{product-handle}.js`。
/// URL に入るのは、`shopifyProductPage(text:)` が取り出した店のドメイン・言語の部分・商品のハンドルだけ。
func shopifyAjaxProductURL(productPage: ShopifyProductPage) -> URL? {
    URL(
        string: "https://\(productPage.shopDomain)\(productPage.localePathComponent.map { "/\($0)" } ?? "")/products/\(productPage.percentEncodedProductHandle).js"
    )
}

/// Shopify の Ajax Product API が返す商品の JSON のうち、お気に入りの登録に使う部分。
///
/// キーと値の形の出典: https://shopify.dev/docs/api/ajax/reference/product の応答の例。
struct ShopifyAjaxProduct: Decodable, Equatable {
    /// 商品の名前。
    let title: String
    /// 商品の画像の URL。応答の例ではスキームを省いた形 (`//cdn.shopify.com/…`)。画像が無い商品では値が無い。
    let featuredImage: String?
    /// 商品バリアントの並び。
    let variants: [Variant]

    /// 商品バリアント (色・大きさなどの違いごとの、カートに入れる単位)。
    struct Variant: Decodable, Equatable {
        /// 商品バリアントの ID。応答の例では数値。
        let id: UInt64
        /// 商品バリアントの名前 (例: `Small`)。
        let title: String
        /// 今買えるか (在庫があるか)。
        let available: Bool
    }

    /// JSON のキー (snake_case) とプロパティの対応。
    enum CodingKeys: String, CodingKey {
        case title
        case featuredImage = "featured_image"
        case variants
    }
}

/// 商品バリアントを選んだ時に最初に入れる個数。
///
/// 1 回に買う個数の下限 (`Favorite.quantity` は 1 以上)。確認の画面で利用者が変えられる。
let initialVariantQuantity = 1

/// 確認の画面を開いた時に選んである商品バリアントと個数を、商品バリアントの ID ごとの個数で返す。選んでいない商品バリアントは入らない。
///
/// URL に `?variant=` があれば、その ID の商品バリアントだけを選んだ状態にする (売り切れでも選ぶ)。
/// `?variant=` が無く、商品バリアントが 1 つだけの商品は、その 1 つを選んだ状態にする (選ぶ操作を挟まないため)。
/// `?variant=` が無く、商品バリアントが 2 つ以上ある商品は、どれも選んでいない状態にする (どれをお気に入りにするかを利用者が選ぶため)。
/// `?variant=` の ID が商品バリアントの並びに無い時 (別の商品バリアントにすり替えない) と、商品バリアントが 1 つも無い時は nil を返す。
func initialVariantQuantities(productPage: ShopifyProductPage, product: ShopifyAjaxProduct) -> [UInt64: Int]? {
    if let variantID = productPage.variantID {
        return product.variants.first { String($0.id) == variantID }.map { [$0.id: initialVariantQuantity] }
    }
    guard let firstVariant = product.variants.first else {
        return nil
    }
    return product.variants.count == 1 ? [firstVariant.id: initialVariantQuantity] : [:]
}

/// 商品バリアントの行を押した後の、選んである商品バリアントと個数を返す。
///
/// 選んでいなかった商品バリアントは個数 `initialVariantQuantity` で選び、選んであった商品バリアントは選ぶのをやめる (決めた個数は残さない)。ほかの商品バリアントは変えない。
func toggledVariantQuantities(quantitiesByVariantID: [UInt64: Int], variantID: UInt64) -> [UInt64: Int] {
    var toggledQuantitiesByVariantID = quantitiesByVariantID
    toggledQuantitiesByVariantID[variantID] = quantitiesByVariantID[variantID] == nil ? initialVariantQuantity : nil
    return toggledQuantitiesByVariantID
}

/// 確認の画面で選んだ商品バリアントごとに 1 件ずつ、保存するお気に入りを作って返す。保存はしない。
///
/// 並びは商品の商品バリアントの並び順で、`quantitiesByVariantID` に無い商品バリアントのお気に入りは作らない (1 つも選んでいなければ空の配列)。
/// 名前はどれも `name` (確認の画面で利用者が確かめた商品の名前)、個数は `quantitiesByVariantID` の値にする。
/// 商品バリアントの名前は、商品バリアントが 2 つ以上ある商品でだけ入れる (1 つだけの商品では、Shopify が付けた `Default Title` を見分けに使わないため nil)。
/// 画像の URL は、`https` で、ホストが店のドメインか Shopify の CDN のものだけを入れる (`shopifyProductImageURL(text:shopDomain:)`)。
/// 識別子は `favoriteIDsByVariantID` の、その商品バリアントの値にする。同じ引数で何度呼んでも同じ識別子のお気に入りを返すので、同じ追加が 2 回保存に渡っても増えない。
/// `favoriteIDsByVariantID` に無い商品バリアントのお気に入りは作らない。
func selectedVariantFavorites(
    productPage: ShopifyProductPage,
    product: ShopifyAjaxProduct,
    name: String,
    quantitiesByVariantID: [UInt64: Int],
    favoriteIDsByVariantID: [UInt64: UUID]
) -> [Favorite] {
    product.variants.compactMap { variant in
        guard let quantity = quantitiesByVariantID[variant.id], let favoriteID = favoriteIDsByVariantID[variant.id] else {
            return nil
        }
        return Favorite(
            id: favoriteID,
            name: name,
            variantName: product.variants.count >= 2 ? variant.title : nil,
            imageURL: product.featuredImage.flatMap { shopifyProductImageURL(text: $0, shopDomain: productPage.shopDomain) },
            quantity: quantity,
            product: .shopify(ShopifyProduct(shopDomain: productPage.shopDomain, variantID: String(variant.id))),
            reminder: nil
        )
    }
}

/// 商品の商品バリアントごとに、お気に入りにする時の識別子を 1 つずつ作って、商品バリアントの ID ごとに返す。
///
/// 確認の画面を開いた時に 1 回だけ呼び、保存までその値を使う (保存の操作が 2 回動いても同じ識別子になり、二重に保存されない)。
/// 識別子は、商品バリアントの並び順に `makeID` を 1 回ずつ呼んで得る。同じ ID の商品バリアントが並びに複数ある時は、最初のものの識別子を使う。
func makeFavoriteIDsByVariantID(product: ShopifyAjaxProduct, makeID: () -> UUID) -> [UInt64: UUID] {
    Dictionary(product.variants.map { ($0.id, makeID()) }, uniquingKeysWith: { firstID, _ in firstID })
}

/// 商品の JSON の商品が、種類を選ぶ商品 (商品バリアントが 2 つ以上ある商品) かを返す。
func hasShopifyAjaxVariantChoices(product: ShopifyAjaxProduct) -> Bool {
    product.variants.count >= 2
}

/// 確認の画面の、保存するボタンの文言を `locale` の言語で返す。
///
/// 種類を選ぶ商品 (`hasVariantChoices`。商品バリアントが 2 つ以上ある商品) で 1 つ以上選んでいる時は、選んだ数を入れる (例: `2 種類をお気に入りに追加`)。
/// 種類を選ばない商品と、1 つも選んでいない時は `お気に入りに追加`。
func favoriteAdditionButtonTitle(hasVariantChoices: Bool, selectedVariantCount: Int, locale: Locale) -> String {
    hasVariantChoices && selectedVariantCount >= 1
        ? String(localized: LocalizedStringResource("\(selectedVariantCount) 種類をお気に入りに追加", locale: locale))
        : String(localized: LocalizedStringResource("お気に入りに追加", locale: locale))
}

/// Shopify が商品の画像を配信する CDN のホスト。
///
/// 出典: https://shopify.dev/docs/api/ajax/reference/product の応答の例の `featured_image` (`//cdn.shopify.com/s/files/…`)。
/// 2026-11-17 に実在の Shopify の店 2 つの `/products.json` を取得した時も、5 つの商品の画像のホストはすべてこの値だった。
let shopifyCDNHost = "cdn.shopify.com"

/// 商品の JSON が返した画像の URL の文字列を、アプリが読み込んでよい URL にして返す。読み込まない URL では nil を返す。
///
/// 返すのは、`https` (スキームを省いた形 `//…` は `https` を補う) で、認証情報 (`user@`) とポートを含まず、ホストが店のドメインか `shopifyCDNHost` の URL だけ (商品ページの URL の検査 `shopifyProductPage(text:)` と同じ条件)。ホストの大文字と小文字は区別しない。
/// 画像は一覧を表示するたびに読み込まれるため、店が JSON で指した無関係なホストへ利用者の端末から通信させない。
func shopifyProductImageURL(text: String, shopDomain: String) -> URL? {
    guard let urlComponents = URLComponents(string: text.hasPrefix("//") ? "https:\(text)" : text),
          urlComponents.scheme?.lowercased() == "https",
          urlComponents.user == nil,
          urlComponents.password == nil,
          urlComponents.port == nil,
          [shopDomain, shopifyCDNHost].contains(urlComponents.host?.lowercased())
    else {
        return nil
    }
    return urlComponents.url
}

/// お気に入りの登録が、確認の画面に進まずに終わった理由。
enum FavoriteAdditionLoadError: Error, Equatable {
    /// 渡された文字列が、Shopify の店の商品ページの URL の形でも、Amazon の URL でもない。
    case notProductPageURL
    /// 渡された文字列が Amazon の URL だが、受け取る形 (www.amazon.co.jp の商品ページの URL か、その短い URL) でない。
    case notAmazonProductPageURL
    /// 通信できなかった、または店が一時的に応答を制限している (HTTP 429)。待てば取得できる可能性がある。
    case temporarilyUnavailable
    /// 商品の情報を取得できない (Shopify の店でない・商品が無い・指定の商品バリアントが無い)。
    case notRegistrable
}

/// 同じ ID の商品バリアントが並びに複数ある商品を、ID ごとに最初の 1 つだけを店の並び順のまま残した商品にして返す。ほかの値は変えない。
///
/// 確認の画面は商品バリアントの ID で行・選択・個数を見分けるため、同じ ID が 2 行あると、選んだ行と違う名前で保存される。
func productWithUniqueVariants(product: ShopifyAjaxProduct) -> ShopifyAjaxProduct {
    ShopifyAjaxProduct(
        title: product.title,
        featuredImage: product.featuredImage,
        variants: product.variants.reduce(into: []) { uniqueVariants, variant in
            if !uniqueVariants.contains(where: { $0.id == variant.id }) {
                uniqueVariants.append(variant)
            }
        }
    )
}

/// 渡された文字列 (前後の空白と改行は除く) から、確認の画面に出す商品と、最初に選んである商品バリアントと個数を返す。保存はしない。
///
/// 返すのは、文字列を `shopifyProductPage(text:)` で分解した値、その店から取得した商品の JSON (`productWithUniqueVariants(product:)` を通したもの)、`initialVariantQuantities(productPage:product:)` の値。
/// 通信するのは、分解できた時の `shopifyAjaxProductURL(productPage:)` の URL への GET の 1 回だけ。
/// 失敗した時は `FavoriteAdditionLoadError` を投げる (HTTP 200 以外・JSON として読めない応答・`initialVariantQuantities(productPage:product:)` が nil の商品は `notRegistrable`、HTTP 429 と通信の失敗は `temporarilyUnavailable`)。
func loadFavoriteAddition(
    text: String,
    urlSession: URLSession
) async throws -> (productPage: ShopifyProductPage, product: ShopifyAjaxProduct, quantitiesByVariantID: [UInt64: Int]) {
    guard let productPage = shopifyProductPage(text: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let ajaxProductURL = shopifyAjaxProductURL(productPage: productPage)
    else {
        throw FavoriteAdditionLoadError.notProductPageURL
    }
    guard let (ajaxProductData, response) = try? await urlSession.data(from: ajaxProductURL) else {
        throw FavoriteAdditionLoadError.temporarilyUnavailable
    }
    guard (response as? HTTPURLResponse)?.statusCode != 429 else {
        throw FavoriteAdditionLoadError.temporarilyUnavailable
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let product = (try? JSONDecoder().decode(ShopifyAjaxProduct.self, from: ajaxProductData)).map(productWithUniqueVariants(product:)),
          let quantitiesByVariantID = initialVariantQuantities(productPage: productPage, product: product)
    else {
        throw FavoriteAdditionLoadError.notRegistrable
    }
    return (productPage, product, quantitiesByVariantID)
}

/// 確認の画面で利用者が選んだ操作。
enum FavoriteAdditionChoice {
    /// 「お気に入りに追加」を押した。
    case add
    /// 「やめる」を押した。
    case cancel
}

/// 確認の画面の操作を保存に反映する。`add` の時だけ、選んだ商品バリアントごとのお気に入りを並びの末尾に足し、`cancel` の時は保存先に何も書かない。
///
/// 確認の画面のお気に入りを保存する経路はこの関数の `add` だけにする (確認の画面を通さずに保存しない。documents/adr/0003)。
func finishFavoriteAddition(choice: FavoriteAdditionChoice, favorites: [Favorite], fileURL: URL) throws {
    switch choice {
    case .add:
        try addFavorites(favorites: favorites, fileURL: fileURL)
    case .cancel:
        break
    }
}
