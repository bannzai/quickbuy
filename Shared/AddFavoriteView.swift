import SwiftUI

/// お気に入りの追加の画面。商品ページの URL を受け取り、店のドメインを目立つ形で見せる確認の画面で、Shopify の店の商品は種類 (商品バリアント) と個数を選んでもらい、
/// Amazon の商品は名前を付けてもらい、利用者が「お気に入りに追加」を押した時だけ保存する。
///
/// アプリの中 (貼り付け) と共有メニューの拡張の両方がこの画面を使うため、どちらから渡した URL も同じ確認の画面を通る (documents/adr/0003)。
struct AddFavoriteView: View {
    /// 最初から入っている URL の文字列。共有メニューから渡された時はその文字列、アプリの中から開いた時は空文字。
    let initialText: String
    /// お気に入りの保存先のファイルの URL。
    let favoritesFileURL: URL
    /// 商品の情報を取得する通信。
    let urlSession: URLSession
    /// この画面を閉じる処理。保存した後と、やめた時に呼ぶ。
    let onFinish: () -> Void

    /// 入力欄の URL の文字列。
    @State private var text = ""
    /// 商品の情報を取得している間は true。
    @State private var isLoading = false
    /// 確認の画面に出している Shopify の店の商品 (商品ページの URL から取り出した値と、店から取得した商品の JSON)。まだ URL を受け取っていない間と、Amazon の商品の時は nil。
    @State private var loadedProduct: (productPage: ShopifyProductPage, product: ShopifyAjaxProduct)?
    /// 確認の画面に出している Amazon の商品の ASIN と、お気に入りにする時の識別子 (ASIN を受け取った時に 1 回だけ作り、保存まで変えない)。まだ URL を受け取っていない間と、Shopify の店の商品の時は nil。
    @State private var loadedAmazonProduct: (asin: String, favoriteID: UUID)?
    /// 確認の画面の名前の欄の文字列。Shopify の店の商品は、商品の情報を取得した時に商品の名前を入れる。Amazon の商品は空のまま出す (Amazon のページから名前を読み取らない)。
    @State private var name = ""
    /// 確認の画面で選んである商品バリアントの、商品バリアントの ID ごとの個数。選んでいない商品バリアントは入らない。
    @State private var quantitiesByVariantID: [UInt64: Int] = [:]
    /// 確認の画面の商品の商品バリアントをお気に入りにする時の識別子。商品の情報を取得した時に 1 回だけ作り、保存まで変えない。
    @State private var favoriteIDsByVariantID: [UInt64: UUID] = [:]
    /// 商品の情報を取得した時に保存済みだったお気に入り。選んだ種類の個数を保存済みの個数から始めるために読む (読めなかった時は空)。
    @State private var savedFavorites: [Favorite] = []
    /// 入力欄の下に出す、登録できなかった理由の文言。出していない時は nil。
    @State private var errorMessage: String?
    /// 保存に失敗したことを知らせる表示を出している間は true。
    @State private var isSaveFailed = false

    /// URL を受け取る前は入力の画面、受け取った後は店ごとの確認の画面。
    var body: some View {
        NavigationStack {
            Group {
                if let loadedProduct {
                    confirmationForm(productPage: loadedProduct.productPage, product: loadedProduct.product)
                } else if let loadedAmazonProduct {
                    amazonConfirmationForm(asin: loadedAmazonProduct.asin)
                } else {
                    inputForm
                }
            }
            .navigationTitle("お気に入りに追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") {
                        finish(choice: .cancel)
                    }
                }
            }
            .alert("保存できませんでした", isPresented: $isSaveFailed) {}
        }
        .tint(quickBuyAccentColor)
        .task {
            guard !initialText.isEmpty else {
                return
            }
            text = initialText
            await loadAddition()
        }
    }

    /// 商品ページの URL を入れる画面。
    private var inputForm: some View {
        Form {
            Section {
                TextField("https://", text: $text, axis: .vertical)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("productPageURLField")
                PasteButton(payloadType: String.self) { pastedTexts in
                    if let pastedText = pastedTexts.first {
                        text = pastedText
                    }
                }
            } header: {
                Text("商品ページの URL")
            } footer: {
                // 訳した文言を String で渡すのは、LocalizedStringKey で渡すと www.amazon.co.jp が押せるリンクになり、確認の画面を通さずに Amazon を開けてしまうため (2026-11-19 に simtunnel で、リンクとして表示されることを確かめた)。
                Text(String(localized: LocalizedStringResource("Shopify の店か Amazon (www.amazon.co.jp) の商品ページの URL を貼り付けてください", locale: appTextLocale)))
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task {
                        await loadAddition()
                    }
                } label: {
                    HStack {
                        Text("次へ")
                        if isLoading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(text.isEmpty || isLoading)
            }
        }
    }

    /// 店のドメインと名前を確かめ、種類 (商品バリアント) と個数を選ぶ画面。
    ///
    /// 商品バリアントが 2 つ以上ある商品では商品バリアントを並べ、選んだものにだけ個数の行を出す。1 つだけの商品では、選ぶ操作を挟まず個数の行だけを出す。
    private func confirmationForm(productPage: ShopifyProductPage, product: ShopifyAjaxProduct) -> some View {
        Form {
            Section {
                ShopDomainBox(shopDomain: productPage.shopDomain)
            }
            Section {
                HStack(spacing: 12) {
                    FavoriteThumbnail(imageURL: product.featuredImage.flatMap { shopifyProductImageURL(text: $0, shopDomain: productPage.shopDomain) })
                    TextField("名前", text: $name, axis: .vertical)
                        .accessibilityIdentifier("favoriteNameField")
                }
                if product.variants.count == 1, let variant = product.variants.first, let quantity = quantitiesByVariantID[variant.id] {
                    QuantityStepperRow(quantity: quantityBinding(variantID: variant.id, quantity: quantity))
                }
            }
            if product.variants.count >= 2 {
                Section {
                    ForEach(product.variants, id: \.id) { variant in
                        Button {
                            quantitiesByVariantID = variantQuantitiesStartingFromSaved(
                                quantitiesByVariantID: toggledVariantQuantities(quantitiesByVariantID: quantitiesByVariantID, variantID: variant.id),
                                selectedVariantIDs: [variant.id],
                                shopDomain: productPage.shopDomain,
                                savedFavorites: savedFavorites
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: quantitiesByVariantID[variant.id] == nil ? "square" : "checkmark.square.fill")
                                    .font(.title3)
                                    .foregroundStyle(quantitiesByVariantID[variant.id] == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                                Text(variant.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(quantitiesByVariantID[variant.id] == nil ? [] : .isSelected)
                        .accessibilityIdentifier("variantRow-\(variant.id)")
                        if let quantity = quantitiesByVariantID[variant.id] {
                            QuantityStepperRow(quantity: quantityBinding(variantID: variant.id, quantity: quantity))
                        }
                    }
                } header: {
                    Text("種類と個数を選ぶ")
                } footer: {
                    Text("選んだ種類ごとにお気に入りの行が 1 つできます")
                }
            }
            Section {
                Button {
                    finish(choice: .add)
                } label: {
                    Text(favoriteAdditionButtonTitle(hasVariantChoices: hasShopifyAjaxVariantChoices(product: product), selectedVariantCount: quantitiesByVariantID.count, locale: appTextLocale))
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(!isFavoriteAdditionSavable(name: name, selectedVariantCount: quantitiesByVariantID.count))
                .accessibilityIdentifier("addFavoritesButton")
            } footer: {
                Text("追加しただけでは購入されません")
            }
        }
    }

    /// Amazon の商品の、ドメイン (`amazonHost`) と ASIN を確かめ、名前を付ける画面。
    ///
    /// 名前の欄は空で出し、画像は出さない (Amazon のページから名前と画像を読み取らない)。個数の欄は出さない (個数は利用者が Amazon の画面で選ぶ。`amazonFavorite(asin:name:id:)`)。
    private func amazonConfirmationForm(asin: String) -> some View {
        Form {
            Section {
                ShopDomainBox(shopDomain: amazonHost)
            }
            Section {
                TextField("名前 (一覧で見分けられる名前)", text: $name, axis: .vertical)
                    .accessibilityIdentifier("favoriteNameField")
                LabeledContent("ASIN", value: asin)
                    .accessibilityIdentifier("amazonASIN")
            } footer: {
                Text("Amazon の商品ページが開きます\n商品は Amazon の画面でカートに入れてください")
            }
            Section {
                Button {
                    finish(choice: .add)
                } label: {
                    Text("お気に入りに追加")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(!isFavoriteNameSavable(name: name))
                .accessibilityIdentifier("addFavoritesButton")
            } footer: {
                Text("追加しただけでは購入されません")
            }
        }
    }

    /// 選んである商品バリアントの個数を、個数の行が読み書きするための値にして返す。`quantity` はその商品バリアントの今の個数。
    private func quantityBinding(variantID: UInt64, quantity: Int) -> Binding<Int> {
        Binding(get: { quantity }, set: { quantitiesByVariantID[variantID] = $0 })
    }

    /// 入力欄の文字列から商品の情報を取得し、確認の画面に進む。取得できなかった時は理由を入力欄の下に出す。
    private func loadAddition() async {
        isLoading = true
        errorMessage = nil
        do {
            if let asin = try await loadAmazonASIN(text: text, urlSession: urlSession) {
                name = ""
                loadedAmazonProduct = (asin, UUID())
                isLoading = false
                return
            }
            let favoriteAddition = try await loadFavoriteAddition(text: text, urlSession: urlSession)
            name = favoriteAddition.product.title
            savedFavorites = favoriteAdditionSavedFavorites(fileURL: favoritesFileURL)
            quantitiesByVariantID = variantQuantitiesStartingFromSaved(
                quantitiesByVariantID: favoriteAddition.quantitiesByVariantID,
                selectedVariantIDs: Array(favoriteAddition.quantitiesByVariantID.keys),
                shopDomain: favoriteAddition.productPage.shopDomain,
                savedFavorites: savedFavorites
            )
            favoriteIDsByVariantID = makeFavoriteIDsByVariantID(product: favoriteAddition.product, makeID: { UUID() })
            loadedProduct = (favoriteAddition.productPage, favoriteAddition.product)
        } catch {
            // `loadAmazonASIN` と `loadFavoriteAddition` が投げるのは `FavoriteAdditionLoadError` だけ。それ以外が来た時は、登録できない扱いにして確認の画面へ進めない。
            errorMessage = favoriteAdditionLoadErrorMessage(error: error as? FavoriteAdditionLoadError ?? .notRegistrable, locale: appTextLocale)
        }
        isLoading = false
    }

    /// 利用者が選んだ操作を保存に反映して画面を閉じる。確認の画面に進む前の「やめる」は、保存するものが無いので閉じるだけ。
    private func finish(choice: FavoriteAdditionChoice) {
        do {
            if let loadedProduct {
                try finishFavoriteAddition(
                    choice: choice,
                    favorites: selectedVariantFavorites(
                        productPage: loadedProduct.productPage,
                        product: loadedProduct.product,
                        name: name,
                        quantitiesByVariantID: quantitiesByVariantID,
                        favoriteIDsByVariantID: favoriteIDsByVariantID
                    ),
                    fileURL: favoritesFileURL
                )
            } else if let loadedAmazonProduct {
                try finishFavoriteAddition(
                    choice: choice,
                    favorites: [amazonFavorite(asin: loadedAmazonProduct.asin, name: name, id: loadedAmazonProduct.favoriteID)],
                    fileURL: favoritesFileURL
                )
            }
            onFinish()
        } catch {
            isSaveFailed = true
        }
    }
}

/// 確認の画面の、店のドメインを目立つ形で見せる枠。利用者がいつも買っている店かを確かめるために出す (documents/adr/0003)。
///
/// 商品ページの URL からの追加の画面と、トップページの検索の結果からの追加の画面 (`CatalogAddFavoriteView`) が使う。
struct ShopDomainBox: View {
    /// 見せる店のドメイン。
    let shopDomain: String

    /// 「この店の商品です」・ドメイン・確かめる案内を縦に並べ、強調の色の枠で囲む。
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("この店の商品です")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(shopDomain)
                .font(.title2.bold())
                .accessibilityIdentifier("shopDomain")
            Text("いつも買っている店か確かめてください")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: shopDomainBoxShape)
        .overlay(shopDomainBoxShape.strokeBorder(.tint, lineWidth: 2))
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

/// 確認の画面で店のドメインを囲む枠の形。
///
/// 角の丸みは、一覧の行のまとまりの角の丸み (iOS 26 の simulator で、丸み 10 の枠の四隅が切れた) より大きくして、枠の四隅が切れないようにしている。
private let shopDomainBoxShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

/// お気に入りの名前として保存できるかを返す。空文字と、空白・改行だけの名前は保存できない (一覧で見分けられないため)。
func isFavoriteNameSavable(name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// 確認の画面の保存するボタンを押せるかを返す。名前が保存できて (`isFavoriteNameSavable(name:)`)、商品バリアントを 1 つ以上選んでいる時だけ押せる。
func isFavoriteAdditionSavable(name: String, selectedVariantCount: Int) -> Bool {
    isFavoriteNameSavable(name: name) && selectedVariantCount >= 1
}

/// 個数を 1 つ減らした値を返す。1 より小さくはならない (`Favorite.quantity` は 1 以上)。
func decrementedQuantity(quantity: Int) -> Int {
    max(quantity - 1, 1)
}

/// 共有メニューから渡された項目のうち、最初に読めた URL (絶対 URL の文字列) を返す。URL の項目が 1 つも無ければ、最初に読めた文字列を返す。どちらも無い・読めない時は nil を返す。
///
/// URL を文字列より優先するのは、受け取りたいのが商品ページの URL で、URL と文字列 (説明文など) の両方の項目が渡された時に文字列の側を登録の入力にしないため。
func sharedText(itemProviders: [NSItemProvider]) async -> String? {
    for itemProvider in itemProviders where itemProvider.canLoadObject(ofClass: URL.self) {
        if let url = await withCheckedContinuation({ continuation in
            _ = itemProvider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }) {
            return url.absoluteString
        }
    }
    for itemProvider in itemProviders where itemProvider.canLoadObject(ofClass: String.self) {
        if let text = await withCheckedContinuation({ continuation in
            _ = itemProvider.loadObject(ofClass: String.self) { text, _ in continuation.resume(returning: text) }
        }) {
            return text
        }
    }
    return nil
}

/// 登録できなかった理由を、入力欄の下に出す文言にして `locale` の言語で返す。
func favoriteAdditionLoadErrorMessage(error: FavoriteAdditionLoadError, locale: Locale) -> String {
    switch error {
    case .notProductPageURL:
        String(localized: LocalizedStringResource("この URL は登録できません\nShopify の店か Amazon の商品ページの URL を入れてください", locale: locale))
    case .notAmazonProductPageURL:
        String(localized: LocalizedStringResource("この Amazon の URL は登録できません\nAmazon のアプリかサイトの商品ページで共有から Quick Buy を選んでください", locale: locale))
    case .temporarilyUnavailable:
        String(localized: LocalizedStringResource("商品の情報を取得できませんでした\n少し待ってからもう一度お試しください", locale: locale))
    case .notRegistrable:
        String(localized: LocalizedStringResource("この商品は登録できません\n商品の情報を取得できない店か\n商品が見つかりません", locale: locale))
    }
}

/// お気に入りの店のドメインを、画面に出す文字列にして返す。Amazon の商品は `amazonHost` (追加の確認の画面で見せたドメインと同じ表記)。
func shopDomainText(favorite: Favorite) -> String {
    switch favorite.product {
    case let .shopify(shopifyProduct):
        shopifyProduct.shopDomain
    case .amazon:
        amazonHost
    }
}

/// 商品の画像の読み込みの途中で別の URL へ転送された時に、転送先へ進んでよいかを返す。
///
/// 進んでよいのは、転送先が `shopifyProductImageURL(text:shopDomain:)` の条件 (`https`・認証情報とポートなし) を満たし、
/// ホストが最初に読み込もうとした URL のホストか `shopifyCDNHost` の時だけ。保存する時に確かめたホストの外へ、転送で通信させない。
func isAllowedProductImageRedirect(originalURL: URL?, redirectedURL: URL?) -> Bool {
    guard let originalHost = originalURL?.host?.lowercased(), let redirectedURL else {
        return false
    }
    return shopifyProductImageURL(text: redirectedURL.absoluteString, shopDomain: originalHost) != nil
}

/// 商品の画像を読み込む通信で、転送先を確かめる delegate。
///
/// class にしているのは、`URLSessionTaskDelegate` が `NSObject` を継承した型を求めるため。
final class ProductImageRedirectGuard: NSObject, URLSessionTaskDelegate {
    /// 転送先へ進んでよい時は転送先へのリクエストを、進まない時は nil (転送に従わない) を返す。
    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        isAllowedProductImageRedirect(originalURL: task.originalRequest?.url, redirectedURL: request.url) ? request : nil
    }
}

/// 商品の画像を読み込む通信。転送先を `ProductImageRedirectGuard` で確かめる。
let productImageURLSession = URLSession(configuration: .default, delegate: ProductImageRedirectGuard(), delegateQueue: nil)

/// 商品の画像を読み込んで返す。通信に失敗した時・HTTP 200 以外の時 (従わなかった転送の応答を含む)・画像として読めない時は nil を返す。
func loadProductImage(url: URL, urlSession: URLSession) async -> UIImage? {
    guard let (imageData, response) = try? await urlSession.data(from: url),
          (response as? HTTPURLResponse)?.statusCode == 200
    else {
        return nil
    }
    return UIImage(data: imageData)
}

/// 商品の画像の小さな表示。画像の URL が無い時と読み込めない間は、買い物袋のアイコンを出す。
struct FavoriteThumbnail: View {
    /// 商品の画像の URL。無ければ nil。
    let imageURL: URL?

    /// 読み込んだ画像。読み込む前と読み込めなかった時は nil。
    @State private var image: UIImage?

    /// 角を丸めた正方形の画像。
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "bag")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 56, height: 56)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: imageURL) {
            guard let imageURL else {
                image = nil
                return
            }
            image = await loadProductImage(url: imageURL, urlSession: productImageURLSession)
        }
    }
}

/// 個数を 1 ずつ増やす・減らす行。個数は 1 より小さくならない (`Favorite.quantity` は 1 以上)。
struct QuantityStepperRow: View {
    /// 1 回に買う個数。
    @Binding var quantity: Int

    /// 「個数」の見出し・今の個数・増減のボタン。
    var body: some View {
        Stepper {
            HStack {
                Text("個数")
                Spacer()
                Text("\(quantity) 個")
                    .accessibilityIdentifier("favoriteQuantity")
            }
        } onIncrement: {
            quantity += 1
        } onDecrement: {
            quantity = decrementedQuantity(quantity: quantity)
        }
    }
}

/// アプリとウィジェット拡張が共有する領域を開けず、お気に入りを読み書きできない時の表示。
struct FavoritesStoreUnavailableView: View {
    /// 警告のアイコンと、保存先を開けないことの文言。
    var body: some View {
        ContentUnavailableView("お気に入りの保存先を開けません", systemImage: "exclamationmark.triangle")
    }
}
