import SwiftUI

/// トップページの検索の結果から開く、お気に入りの追加の画面。
///
/// 店のドメイン (`seller.url` のホスト) を目立つ形で見せ、店の入口の `get_product` で種類 (商品バリアント) を選んでもらい、
/// 選んだ種類ごとに個数を決めて、利用者が「お気に入りに追加」を押した時だけ保存する (documents/adr/0003)。
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
    /// 最後に始めた店の入口の呼び出しの識別子。結果を受けた時に、この値と違う (後から別の呼び出しを始めた) 呼び出しの結果は捨てる。
    @State private var latestLoadID = UUID()
    /// 店の入口を呼べなかった理由の文言。出していない時は nil。
    @State private var errorMessage: String?
    /// 名前の欄の文字列。検索の結果の商品の名前から始まる。
    @State private var name = ""
    /// 選んだ商品バリアント (店の入口が返したもの) の並び (選んだ順)。
    @State private var selectedVariants: [ShopifyCatalogVariant] = []
    /// 選んだ商品バリアントの、商品バリアントの ID (`ShopifyCatalogVariant.id`) ごとの個数。
    @State private var quantitiesByVariantID: [String: Int] = [:]
    /// 選んだ商品バリアントをお気に入りにする時の識別子。選んだ時に 1 回だけ作り、保存まで変えない (保存が 2 回動いても二重に保存しない)。
    @State private var favoriteIDsByVariantID: [String: UUID] = [:]
    /// 保存に失敗したことを知らせる表示を出している間は true。
    @State private var isSaveFailed = false

    /// 店のドメイン・名前・種類の選び方・選んだ種類と個数・保存のボタン。
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShopDomainConfirmationBox(shopDomain: shopDomain)
                }
                Section {
                    HStack(spacing: 12) {
                        FavoriteThumbnail(imageURL: shopifyCatalogImageURL(product: searchedProduct, shopDomain: shopDomain))
                        TextField("名前", text: $name, axis: .vertical)
                            .accessibilityIdentifier("favoriteNameField")
                    }
                }
                variantChoiceSection
                if !selectedVariants.isEmpty {
                    Section {
                        ForEach(selectedVariants, id: \.id) { selectedVariant in
                            VStack(alignment: .leading, spacing: 4) {
                                if hasShopifyCatalogVariantChoices(options: storefrontProduct?.options) {
                                    Text(selectedVariant.title)
                                        .font(.subheadline.weight(.bold))
                                }
                                if let quantity = quantitiesByVariantID[selectedVariant.id] {
                                    QuantityStepperRow(quantity: Binding(
                                        get: { quantity },
                                        set: { quantitiesByVariantID[selectedVariant.id] = $0 }
                                    ))
                                }
                            }
                        }
                        .onDelete { deletedIndexes in
                            selectedVariants.remove(atOffsets: deletedIndexes)
                        }
                    } header: {
                        Text("お気に入りにする種類")
                    } footer: {
                        Text("選んだ種類ごとにお気に入りの行が 1 つできます")
                    }
                }
                Section {
                    Button {
                        finish(choice: .add)
                    } label: {
                        Text(favoriteAdditionButtonTitle(
                            hasVariantChoices: hasShopifyCatalogVariantChoices(options: storefrontProduct?.options),
                            selectedVariantCount: selectedVariants.count
                        ))
                        .bold()
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .disabled(!isFavoriteAdditionSavable(name: name, selectedVariantCount: selectedVariants.count))
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

    /// 種類の選び方ごとの値の選択と、選んだ値の組の商品バリアントを「お気に入りにする種類」へ足すボタン。
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
                        HStack(spacing: 6) {
                            if storefrontProductFetchedAt != nil, !isStorefrontPriceExpired, let price = variant.price {
                                Text(shopifyCatalogPriceText(money: price))
                            }
                            if variant.availability?.available == false {
                                Text("在庫なし")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }
                if shopifyVariantNumericID(variantGID: variant.id) != nil {
                    Button(selectedVariants.contains { $0.id == variant.id } ? "この種類は選んであります" : "この種類を選ぶ") {
                        selectVariant(variant: variant)
                    }
                    .disabled(isLoading || selectedVariants.contains { $0.id == variant.id })
                    .accessibilityIdentifier("selectVariantButton")
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                // 読み直す商品は、読み込めた商品か、まだ無ければ検索の結果の商品バリアント。検索の結果は商品バリアントのある商品だけなので、どちらかが必ずある。
                if let reloadProductID = storefrontProduct?.id ?? searchedProduct.variants.first?.id {
                    Button("もう一度読み込む") {
                        Task {
                            await loadStorefrontProduct(productID: reloadProductID, selected: storefrontProduct?.selected)
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

    /// 選んだ商品バリアントを「お気に入りにする種類」の末尾に個数 `initialVariantQuantity` で足す。足した時に識別子を 1 回だけ作る。
    private func selectVariant(variant: ShopifyCatalogVariant) {
        selectedVariants.append(variant)
        quantitiesByVariantID[variant.id] = initialVariantQuantity
        if favoriteIDsByVariantID[variant.id] == nil {
            favoriteIDsByVariantID[variant.id] = UUID()
        }
    }

    /// 店の入口の `get_product` を呼び、返った商品を画面に出す。呼べなかった時は理由を出し、前に出していた商品はそのまま残す。
    /// 呼び出しを重ねた時 (選び直しの最中に価格の期限で読み直した時など) は、最後に始めた呼び出しの結果だけを出す。
    private func loadStorefrontProduct(productID: String, selected: [ShopifyCatalogSelectedOption]?) async {
        let loadID = UUID()
        latestLoadID = loadID
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
                errorMessage = shopifyCatalogErrorMessage(error: error as? ShopifyCatalogError ?? .failed)
            }
        }
        if latestLoadID == loadID {
            isLoading = false
        }
    }

    /// 呼び出し `loadID` が返した商品 `product` を、今の時刻で取得したものとして出す。後から別の呼び出しを始めていた時は何もしない。
    /// 種類の選び方が無い商品は、選ぶ操作を挟まずに選んだ状態にする (`shopifyCatalogAutoSelectedVariant`)。
    private func applyStorefrontProduct(loadID: UUID, product: ShopifyCatalogProduct) {
        guard latestLoadID == loadID else {
            return
        }
        // 最初に読み込んだ商品かは `storefrontProduct` を書き換える前に見る。
        if let autoSelectedVariant = shopifyCatalogAutoSelectedVariant(product: product, isFirstLoadedProduct: storefrontProduct == nil) {
            selectVariant(variant: autoSelectedVariant)
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
                favorites: shopifyCatalogFavorites(
                    shopDomain: shopDomain,
                    name: name,
                    hasVariantChoices: hasShopifyCatalogVariantChoices(options: storefrontProduct?.options),
                    selectedVariants: selectedVariants,
                    quantitiesByVariantID: quantitiesByVariantID,
                    favoriteIDsByVariantID: favoriteIDsByVariantID
                ),
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
