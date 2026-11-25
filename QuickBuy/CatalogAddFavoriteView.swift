import SwiftUI

/// トップページの検索の結果から開く、お気に入りの追加の画面。
///
/// 店のドメイン (`seller.url` のホスト) を目立つ形で見せ、店の入口の `get_product` で種類 (商品バリアント) を選んでもらい、
/// そのすぐ下で個数を決めて、利用者が保存するボタンを押した時だけ保存する (documents/adr/0003)。
/// 今選んでいる値の組の種類が、そのまま保存する種類になる。同じ店・同じ種類のお気に入りが保存済みの時は、個数を保存済みの個数から始め、
/// ボタンを押すと行を足さずにその個数を書き換える (https://github.com/bannzai/quickbuy/issues/84 )。
struct CatalogAddFavoriteView: View {
    /// 検索の結果で押した商品 (Global Catalog の `search_catalog` が返したもの)。
    let searchedProduct: ShopifyCatalogProduct
    /// 店のドメイン (`shopifyCatalogShopDomain(variant:)` の値)。
    let shopDomain: String
    /// お気に入りの保存先のファイルの URL。
    let favoritesFileURL: URL
    /// 店の入口を呼ぶ通信。
    let urlSession: URLSession
    /// この画面を閉じる処理。保存した後と、やめた時に呼ぶ。
    let onFinish: () -> Void

    /// 店の入口が返した、今選んでいる値の組の商品 (種類の選び方と 1 件の商品バリアント)。読み込む前と読み込めなかった時は nil。
    @State private var storefrontProduct: ShopifyCatalogProduct?
    /// `storefrontProduct` を取得した時刻。まだ取得していない時は nil (価格を出さない)。
    @State private var storefrontProductFetchedAt: Date?
    /// `storefrontProduct` の価格を出してよい時間を過ぎた後、読み直すまでの間は true (価格を出さない)。
    @State private var isStorefrontPriceExpired = false
    /// 店の入口を呼んでいる間は true。
    @State private var isLoading = false
    /// 最後に始めた店の入口の呼び出しの商品の ID と値の組 (`selected` は値の組を指定しない最初の呼び出しでは nil)。
    /// 「もう一度読み込む」は、失敗した呼び出しと同じ要求をやり直すためにこの値を使う (前に出せた商品の値の組ではなく、利用者が選び直した値の組を読む)。
    @State private var latestLoadRequest: (productID: String, selected: [ShopifyCatalogSelectedOption]?)?
    /// 最後に始めた店の入口の呼び出しの識別子。結果を受けた時に、この値と違う (後から別の呼び出しを始めた) 呼び出しの結果は捨てる。
    @State private var latestLoadID = UUID()
    /// 店の入口を呼べなかった理由の文言。出していない時は nil。
    @State private var errorMessage: String?
    /// 名前の欄の文字列。検索の結果の商品の名前から始まる。
    @State private var name = ""
    /// 今選んでいる値の組の種類をお気に入りにする時の個数。種類が替わるたびに `shopifyCatalogAdditionQuantity` の値から始まる。
    @State private var quantity = initialVariantQuantity
    /// この画面を開いた時に保存済みだったお気に入り。選んでいる種類が保存済みかを見分けるために読む (読めなかった時は空で、保存の時に失敗を知らせる)。
    @State private var savedFavorites: [Favorite] = []
    /// 足すお気に入りの識別子。画面を開いた時に 1 回だけ作り、保存まで変えない (保存が 2 回動いても二重に保存しない)。
    @State private var favoriteID = UUID()
    /// 保存に失敗したことを知らせる表示を出している間は true。
    @State private var isSaveFailed = false

    /// 店のドメイン・名前・種類の選び方と個数・保存のボタン。
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShopDomainBox(shopDomain: shopDomain)
                }
                Section {
                    HStack(spacing: 12) {
                        FavoriteThumbnail(imageURL: shopifyCatalogImageURL(product: searchedProduct, shopDomain: shopDomain))
                        TextField("名前", text: $name, axis: .vertical)
                            .accessibilityIdentifier("favoriteNameField")
                    }
                }
                variantChoiceSection
                Section {
                    Button {
                        finish(choice: .add)
                    } label: {
                        Text(shopifyCatalogAdditionButtonTitle(
                            isSaved: shopifyCatalogSavedFavorite(savedFavorites: savedFavorites, shopDomain: shopDomain, variant: storefrontProduct?.variants.first) != nil,
                            locale: appTextLocale
                        ))
                        .bold()
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .disabled(!isShopifyCatalogAdditionSavable(name: name, shopDomain: shopDomain, variant: storefrontProduct?.variants.first, isLoading: isLoading))
                    .accessibilityIdentifier("addFavoritesButton")
                } footer: {
                    // 定期購入が必須の商品は検索に出るが、応答から見分けられないため、ここで 1 行だけ伝える (issue #34)。
                    Text("追加しただけでは購入されません\n定期購入だけの商品は購入画面を開けず店のトップページが開きます")
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
            name = searchedProduct.title
            // 読めない時は保存済みを見分けられないので、どの種類も保存済みでない扱いで出す。保存先が壊れている時は、ボタンを押した時の保存が失敗して知らせる。
            savedFavorites = (try? loadFavorites(fileURL: favoritesFileURL)) ?? []
            if let searchedVariantID = searchedProduct.variants.first?.id {
                await loadStorefrontProduct(productID: searchedVariantID, selected: nil)
            }
        }
        // 画面を開いたまま価格を出してよい時間を過ぎたら、価格を消して同じ値の組で読み直す (Shopify の「Caching limits」)。
        .task(id: storefrontProductFetchedAt) {
            guard let storefrontProductFetchedAt else {
                return
            }
            try? await Task.sleep(for: .seconds(shopifyCatalogPriceRemainingSeconds(fetchedAt: storefrontProductFetchedAt, now: .now)))
            guard !Task.isCancelled else {
                return
            }
            // task の id (`storefrontProductFetchedAt`) を書き換えるとこの task が取り消されて読み直しも止まるため、id とは別の値で価格を消す。
            isStorefrontPriceExpired = true
            // 選び直しの読み込みの最中なら、その結果が新しい価格を出すので、前の値の組で読み直さない。
            if !isLoading, let storefrontProduct {
                await loadStorefrontProduct(productID: storefrontProduct.id, selected: storefrontProduct.selected)
            }
        }
    }

    /// 種類の選び方ごとの値の選択と、選んだ値の組の商品バリアントの名前・価格・在庫と、その個数の増減。
    @ViewBuilder private var variantChoiceSection: some View {
        Section {
            if let storefrontProduct, let variant = storefrontProduct.variants.first {
                ForEach(storefrontProduct.options ?? [], id: \.name) { option in
                    if option.values.count >= 2 {
                        Picker(option.name, selection: selectedLabelBinding(storefrontProduct: storefrontProduct, optionName: option.name)) {
                            ForEach(option.values, id: \.label) { value in
                                Text(value.label).tag(Optional(value.label))
                            }
                        }
                        .disabled(isLoading)
                    }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(variant.title)
                            .font(.subheadline)
                        // 価格と在庫は Shopify の「Caching limits」で同じ 10 分の上限があるため、どちらも期限の間だけ出す。
                        if storefrontProductFetchedAt != nil, !isStorefrontPriceExpired {
                            HStack(spacing: 6) {
                                if let price = variant.price {
                                    Text(shopifyCatalogPriceText(money: price))
                                }
                                if variant.availability?.available == false {
                                    Text("在庫なし")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }
                if shopifyCatalogShopifyProduct(shopDomain: shopDomain, variant: variant) != nil {
                    QuantityStepperRow(quantity: $quantity)
                        .disabled(isLoading)
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                // 失敗した呼び出しと同じ商品と値の組でやり直す。失敗の文言は呼び出しを始めた後にだけ出るので、要求は必ずある。
                if let latestLoadRequest {
                    Button("もう一度読み込む") {
                        Task {
                            await loadStorefrontProduct(productID: latestLoadRequest.productID, selected: latestLoadRequest.selected)
                        }
                    }
                }
            }
        } header: {
            Text("種類を選ぶ")
        }
    }

    /// 種類の選び方 `optionName` で今選んでいる値 (店が返さなかった時は nil で、どれも選ばれていない表示) を、選び直すと店の入口を呼び直す値にして返す。
    private func selectedLabelBinding(storefrontProduct: ShopifyCatalogProduct, optionName: String) -> Binding<String?> {
        Binding(
            get: { storefrontProduct.selected?.first { $0.name == optionName }?.label },
            set: { newLabel in
                guard let newLabel else {
                    return
                }
                Task {
                    await loadStorefrontProduct(
                        productID: storefrontProduct.id,
                        selected: reselectedOptions(selected: storefrontProduct.selected ?? [], optionName: optionName, label: newLabel)
                    )
                }
            }
        )
    }

    /// 店の入口の `get_product` を呼び、返った商品を画面に出す。呼べなかった時は理由を出し、前に出していた商品はそのまま残す。
    /// 呼び出しを重ねた時 (選び直しの最中に価格の期限で読み直した時など) は、最後に始めた呼び出しの結果だけを出す。
    private func loadStorefrontProduct(productID: String, selected: [ShopifyCatalogSelectedOption]?) async {
        let loadID = UUID()
        latestLoadID = loadID
        latestLoadRequest = (productID, selected)
        isLoading = true
        errorMessage = nil
        do {
            try await applyStorefrontProduct(
                loadID: loadID,
                product: loadShopifyStorefrontProduct(shopDomain: shopDomain, productID: productID, selected: selected, urlSession: urlSession)
            )
        } catch {
            if latestLoadID == loadID {
                // `loadShopifyStorefrontProduct` が投げるのは `ShopifyCatalogError` だけ。それ以外が来た時は失敗の扱いにする。
                errorMessage = shopifyCatalogErrorMessage(error: error as? ShopifyCatalogError ?? .failed, locale: appTextLocale)
            }
        }
        if latestLoadID == loadID {
            isLoading = false
        }
    }

    /// 呼び出し `loadID` が返した商品 `product` を、今の時刻で取得したものとして出す。後から別の呼び出しを始めていた時は何もしない。
    /// 返った商品バリアントが前に出していたものと違う時は、個数をその種類の始まりの値にする (`shopifyCatalogAdditionQuantity`)。
    private func applyStorefrontProduct(loadID: UUID, product: ShopifyCatalogProduct) {
        guard latestLoadID == loadID else {
            return
        }
        // 前に出していた商品バリアントは `storefrontProduct` を書き換える前に見る。`loadShopifyStorefrontProduct` は商品バリアントが 1 件以上ある商品だけを返す。
        if let loadedVariant = product.variants.first {
            quantity = shopifyCatalogAdditionQuantity(
                shownVariantID: storefrontProduct?.variants.first?.id,
                quantity: quantity,
                loadedVariant: loadedVariant,
                shopDomain: shopDomain,
                savedFavorites: savedFavorites
            )
        }
        storefrontProduct = product
        storefrontProductFetchedAt = .now
        isStorefrontPriceExpired = false
    }

    /// 利用者が選んだ操作を保存に反映して画面を閉じる。
    private func finish(choice: FavoriteAdditionChoice) {
        do {
            try finishFavoriteAddition(
                choice: choice,
                favorites: [storefrontProduct?.variants.first.flatMap {
                    shopifyCatalogFavorite(
                        shopDomain: shopDomain,
                        name: name,
                        hasVariantChoices: hasShopifyCatalogVariantChoices(options: storefrontProduct?.options),
                        variant: $0,
                        quantity: quantity,
                        favoriteID: favoriteID
                    )
                }].compactMap { $0 },
                fileURL: favoritesFileURL
            )
            onFinish()
        } catch {
            isSaveFailed = true
        }
    }
}

/// 種類の選び方 `optionName` の値を `label` に替えた、値の組を返す。`selected` に `optionName` が無い時は末尾に足す。ほかの選び方の値は変えない。
func reselectedOptions(selected: [ShopifyCatalogSelectedOption], optionName: String, label: String) -> [ShopifyCatalogSelectedOption] {
    selected.contains { $0.name == optionName }
        ? selected.map { $0.name == optionName ? ShopifyCatalogSelectedOption(name: optionName, label: label) : $0 }
        : selected + [ShopifyCatalogSelectedOption(name: optionName, label: label)]
}
