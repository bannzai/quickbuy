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
    /// 店の入口を呼んでいる間は true。
    @State private var isLoading = false
    /// 店の入口を呼べなかった理由の文言。出していない時は nil。
    @State private var errorMessage: String?
    /// 名前の欄の文字列。検索の結果の商品の名前から始まる。
    @State private var name = ""
    /// 選んだ商品バリアントの並び (選んだ順)。
    @State private var selectedVariants: [ShopifyCatalogSelectedVariant] = []
    /// 選んだ商品バリアントの、商品バリアントの ID ごとの個数。
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
                        ForEach(selectedVariants, id: \.variantID) { selectedVariant in
                            VStack(alignment: .leading, spacing: 4) {
                                if hasShopifyCatalogVariantChoices(options: storefrontProduct?.options) {
                                    Text(selectedVariant.title)
                                        .font(.subheadline.weight(.bold))
                                }
                                if let quantity = quantitiesByVariantID[selectedVariant.variantID] {
                                    QuantityStepperRow(quantity: Binding(
                                        get: { quantity },
                                        set: { quantitiesByVariantID[selectedVariant.variantID] = $0 }
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
                            variantCount: hasShopifyCatalogVariantChoices(options: storefrontProduct?.options) ? 2 : 1,
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
    }

    /// 種類の選び方ごとの値の選択と、選んだ値の組の商品バリアントを「お気に入りにする種類」へ足すボタン。
    @ViewBuilder private var variantChoiceSection: some View {
        Section {
            if let storefrontProduct, let variant = storefrontProduct.variants.first {
                ForEach(storefrontProduct.options ?? [], id: \.name) { option in
                    if option.values.count >= 2 {
                        Picker(option.name, selection: selectedLabelBinding(storefrontProduct: storefrontProduct, optionName: option.name)) {
                            ForEach(option.values, id: \.label) { value in
                                Text(value.label).tag(value.label)
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
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }
                if let variantID = shopifyVariantNumericID(variantGID: variant.id) {
                    Button(selectedVariants.contains { $0.variantID == variantID } ? "この種類は選んであります" : "この種類を選ぶ") {
                        selectVariant(ShopifyCatalogSelectedVariant(variantID: variantID, title: variant.title))
                    }
                    .disabled(isLoading || selectedVariants.contains { $0.variantID == variantID })
                    .accessibilityIdentifier("selectVariantButton")
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                Button("もう一度読み込む") {
                    Task {
                        await loadStorefrontProduct(
                            productID: storefrontProduct?.id ?? searchedProduct.variants.first?.id ?? "",
                            selected: storefrontProduct?.selected
                        )
                    }
                }
            }
        } header: {
            Text("種類を選ぶ")
        }
    }

    /// 種類の選び方 `optionName` で今選んでいる値を、選び直すと店の入口を呼び直す値にして返す。
    private func selectedLabelBinding(storefrontProduct: ShopifyCatalogProduct, optionName: String) -> Binding<String> {
        Binding(
            get: { storefrontProduct.selected?.first { $0.name == optionName }?.label ?? "" },
            set: { newLabel in
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
    private func selectVariant(_ selectedVariant: ShopifyCatalogSelectedVariant) {
        selectedVariants.append(selectedVariant)
        quantitiesByVariantID[selectedVariant.variantID] = initialVariantQuantity
        if favoriteIDsByVariantID[selectedVariant.variantID] == nil {
            favoriteIDsByVariantID[selectedVariant.variantID] = UUID()
        }
    }

    /// 店の入口の `get_product` を呼び、返った商品を画面に出す。呼べなかった時は理由を出し、前に出していた商品はそのまま残す。
    private func loadStorefrontProduct(productID: String, selected: [ShopifyCatalogSelectedOption]?) async {
        isLoading = true
        errorMessage = nil
        do {
            storefrontProduct = try await loadShopifyStorefrontProduct(shopDomain: shopDomain, productID: productID, selected: selected, urlSession: urlSession)
            // 種類の選び方が 1 つも無い商品 (商品バリアントが 1 つだけ) は、選ぶ操作を挟まずに選んだ状態にする。
            if let storefrontProduct, !hasShopifyCatalogVariantChoices(options: storefrontProduct.options), selectedVariants.isEmpty,
               let variant = storefrontProduct.variants.first, let variantID = shopifyVariantNumericID(variantGID: variant.id)
            {
                selectVariant(ShopifyCatalogSelectedVariant(variantID: variantID, title: variant.title))
            }
        } catch {
            // `loadShopifyStorefrontProduct` が投げるのは `ShopifyCatalogError` だけ。それ以外が来た時は失敗の扱いにする。
            errorMessage = shopifyCatalogErrorMessage(error: error as? ShopifyCatalogError ?? .failed)
        }
        isLoading = false
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
