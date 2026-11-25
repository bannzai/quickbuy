import SwiftUI

/// 商品の詳細ページ。トップページの商品のカードを押すと開き、大きい画像・店のドメイン・名前・価格・在庫・種類の選び方・説明文を見せて、「お気に入り追加」から追加の画面へ進める。
///
/// 開いた直後は検索の結果の商品を出し、店の入口の `get_product` が返ったら、店が付けた種類の選び方・説明文・取り直した価格と在庫に替える。
/// 名前・画像・説明文・価格は画面に出すだけで保存しない。価格と在庫は、取得から `shopifyCatalogPriceCacheSeconds` 秒より前の時だけ出し、過ぎたら消して店の入口から読み直す。
/// 名前・画像・説明文・種類の選び方は、取得から `shopifyCatalogContentCacheSeconds` 秒より前の商品のものだけを出し、出せる商品が無くなったら画面を閉じる (Shopify の「Caching limits」)。
/// 購入画面を開く入口は持たない (購入画面は保存済みのお気に入りからだけ開く。documents/adr/0003)。
struct CatalogProductDetailView: View {
    /// 検索の結果で押した商品 (Global Catalog の `search_catalog` が返したもの)。
    let searchedProduct: ShopifyCatalogProduct
    /// 店のドメイン (`shopifyCatalogShopDomain(variant:)` の値)。
    let shopDomain: String
    /// `searchedProduct` を含む検索の結果を取得した時刻。
    let searchFetchedAt: Date
    /// 店の入口を呼ぶ通信。
    let urlSession: URLSession
    /// 「お気に入り追加」を押した時に呼ぶ処理 (追加の画面を開く)。
    let onAddFavorite: () -> Void

    /// アプリが前面にあるか。前面に戻った時に、古くなった値を消して読み直すために見る。
    @Environment(\.scenePhase) private var scenePhase
    /// この画面を閉じる処理。出してよい商品が無くなった時に呼ぶ。
    @Environment(\.dismiss) private var dismiss
    /// 店の入口が返した商品と、取得した時刻。読み込む前と、1 回も読み込めていない時は nil。
    @State private var storefrontProduct: (product: ShopifyCatalogProduct, fetchedAt: Date)?
    /// 値を出してよいかを判定する時刻。商品を出した時・値の期限が来た時・画面が出た時・アプリが前面に戻った時に今の時刻へ進める。
    @State private var checkedAt = Date.now
    /// 店の入口を呼んでいる間は true。
    @State private var isLoading = false
    /// 最後に始めた店の入口の呼び出しの識別子。結果を受けた時に、この値と違う (後から別の呼び出しを始めた) 呼び出しの結果は捨てる。
    @State private var latestLoadID = UUID()
    /// 店の入口を呼べなかった理由の文言。出していない時は nil。
    @State private var errorMessage: String?

    /// 画面に出している価格と在庫を取得した時刻 (店の入口の商品を読み込んだ後はその時刻、前は検索の結果の時刻)。
    private var shownPriceFetchedAt: Date {
        storefrontProduct?.fetchedAt ?? searchFetchedAt
    }

    /// 名前・説明文・種類の選び方・画像を出してよい店の入口の商品。読み込む前と、取得から `shopifyCatalogContentCacheSeconds` 秒を過ぎた時は nil。
    private var freshStorefrontProduct: ShopifyCatalogProduct? {
        storefrontProduct.flatMap { isShopifyCatalogContentFresh(fetchedAt: $0.fetchedAt, now: checkedAt) ? $0.product : nil }
    }

    /// 名前・説明文・画像を出してよい検索の結果の商品。取得から `shopifyCatalogContentCacheSeconds` 秒を過ぎた時は nil。
    private var freshSearchedProduct: ShopifyCatalogProduct? {
        isShopifyCatalogContentFresh(fetchedAt: searchFetchedAt, now: checkedAt) ? searchedProduct : nil
    }

    /// 画像・商品の情報・種類の選び方・説明文と、下に固定した「お気に入り追加」のボタン。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                images
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    if let errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                            Button("もう一度読み込む") {
                                Task {
                                    await loadStorefrontProduct()
                                }
                            }
                        }
                    }
                    if !shopifyCatalogChoiceOptions(options: freshStorefrontProduct?.options).isEmpty {
                        options(choiceOptions: shopifyCatalogChoiceOptions(options: freshStorefrontProduct?.options))
                    }
                    // 説明文は店が付けたものを先に使う。
                    if let descriptionText = shopifyCatalogDetailDescriptionText(products: [freshStorefrontProduct, freshSearchedProduct].compactMap { $0 }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("商品の説明")
                                .font(.headline)
                            Text(descriptionText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("商品の詳細")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: onAddFavorite) {
                Text("お気に入り追加")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("addFavoriteFromDetail")
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        // 画面が出るたびに動く (ほかのタブから戻った時も)。
        .task {
            refreshExpiredValues()
        }
        // 画面を開いたまま価格を出してよい時間を過ぎたら、価格と在庫を消して店の入口から読み直す。
        .task(id: shownPriceFetchedAt) {
            try? await Task.sleep(for: .seconds(shopifyCatalogPriceRemainingSeconds(fetchedAt: shownPriceFetchedAt, now: .now)))
            if !Task.isCancelled {
                refreshExpiredValues()
            }
        }
        // 画面を開いたまま、検索の結果の商品と店の入口の商品のそれぞれの名前・画像・説明文を出してよい時間を過ぎたら、判定をやり直す (期限を過ぎた商品の値を出さなくし、出せる商品が無くなれば画面が閉じる)。
        .task(id: searchFetchedAt) {
            await refreshWhenContentExpires(fetchedAt: searchFetchedAt)
        }
        .task(id: storefrontProduct?.fetchedAt) {
            if let storefrontFetchedAt = storefrontProduct?.fetchedAt {
                await refreshWhenContentExpires(fetchedAt: storefrontFetchedAt)
            }
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .active {
                refreshExpiredValues()
            }
        }
        .onChange(of: checkedAt) {
            if !hasShopifyCatalogDetailFreshContent(searchFetchedAt: searchFetchedAt, storefrontFetchedAt: storefrontProduct?.fetchedAt, now: checkedAt) {
                dismiss()
            }
        }
    }

    /// 商品の画像。複数ある時は横にめくって見る。出せる画像が無い時は下地の色だけを出す。
    private var images: some View {
        Color(uiColor: .quaternarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                TabView {
                    // 画像は検索の結果の商品のものを先に使う (店の入口の商品を読み込んだ時に、出している画像を読み込み直さないため)。
                    ForEach(
                        shopifyCatalogDetailImageURLs(products: [freshSearchedProduct, freshStorefrontProduct].compactMap { $0 }, shopDomain: shopDomain),
                        id: \.self
                    ) { imageURL in
                        CatalogProductImage(imageURL: imageURL, contentMode: .fit)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            .accessibilityIdentifier("productDetailImages")
    }

    /// 店のドメイン・名前と、出してよい間だけの価格・在庫。
    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shopDomain)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
            if let title = shopifyCatalogDetailTitle(searchedProduct: searchedProduct, searchFetchedAt: searchFetchedAt, storefrontProduct: storefrontProduct, now: checkedAt) {
                Text(title)
                    .font(.title3.weight(.bold))
            }
            if let searchedVariant = searchedProduct.variants.first,
               let priceVariant = shopifyCatalogDetailPriceVariant(
                   searchedVariant: searchedVariant,
                   searchFetchedAt: searchFetchedAt,
                   storefrontProduct: storefrontProduct?.product,
                   storefrontFetchedAt: storefrontProduct?.fetchedAt,
                   now: checkedAt
               )
            {
                if let price = priceVariant.price {
                    Text(shopifyCatalogPriceText(money: price))
                        .font(.title2.weight(.heavy))
                }
                if let priceVariantName = shopifyCatalogDetailPriceVariantName(priceVariant: priceVariant, storefrontProduct: storefrontProduct?.product) {
                    Text(priceVariantName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let availability = priceVariant.availability {
                    Text(availability.available ? LocalizedStringKey("在庫あり") : LocalizedStringKey("在庫なし"))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(availability.available ? AnyShapeStyle(quickBuyAccentColor) : AnyShapeStyle(.secondary))
                }
            }
            if isLoading {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    /// 店が付けた種類の選び方 `choiceOptions` (`shopifyCatalogChoiceOptions` の値) ごとの、選べる値の並び (見るだけ。選ぶのは追加の画面)。
    ///
    /// 種類の選び方の名前を太字の見出しにし、値はその下に字下げして「・」を前に付けて並べる (名前と値が別の段だと見分けられるようにするため。https://github.com/bannzai/quickbuy/issues/84 )。
    /// 店が付けた名前と値の文字は書き換えず、「・」は値とは別の文字として置く (読み上げには出さない)。
    private func options(choiceOptions: [ShopifyCatalogOption]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("選べる種類")
                .font(.headline)
            ForEach(choiceOptions, id: \.name) { option in
                VStack(alignment: .leading, spacing: 6) {
                    Text(option.name)
                        .font(.subheadline.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(option.values, id: \.label) { value in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: "・")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(value.label)
                        }
                        .font(.subheadline)
                        .padding(.leading, 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    /// 時刻 `fetchedAt` に取得した商品の名前・画像・説明文を出してよい時間が過ぎるまで待ち、過ぎたら値を出してよいかの判定をやり直す。待つ間に止められた時は何もしない。
    private func refreshWhenContentExpires(fetchedAt: Date) async {
        try? await Task.sleep(for: .seconds(shopifyCatalogContentRemainingSeconds(fetchedAt: fetchedAt, now: .now)))
        if !Task.isCancelled {
            refreshExpiredValues()
        }
    }

    /// 値を出してよいかの判定を今の時刻でやり直し、店の入口の商品をまだ読み込んでいないか、その価格が期限を過ぎていれば、店の入口から読み込む。
    /// 読み込み中と、失敗の文言を出している間は読み込まない (利用者の「もう一度読み込む」を待つ。検索の結果の取り直しと同じ決まり)。
    /// 読み込みは画面が隠れても止めない (ほかのタブへ移った時に、通信の中断を失敗として出さないため)。
    private func refreshExpiredValues() {
        checkedAt = .now
        if shouldRefreshShopifyCatalogSearch(fetchedAt: storefrontProduct?.fetchedAt, isSearching: isLoading, isShowingError: errorMessage != nil, now: checkedAt) {
            // 下の `Task` が動き出す前にこの関数がもう一度呼ばれても、読み込みを重ねて始めないよう、ここで読み込み中にする。
            isLoading = true
            Task {
                await loadStorefrontProduct()
            }
        }
    }

    /// 店の入口の `get_product` を検索の結果の商品バリアントの ID で呼び、返った商品を今の時刻で取得したものとして出す。
    /// 呼べなかった時は理由を出し、前に出していた商品はそのまま残す (期限を過ぎた価格と在庫は出ない)。
    /// 呼び出しを重ねた時は、最後に始めた呼び出しの結果だけを出す。検索の結果の商品に商品バリアントが無い時は何もしない。
    private func loadStorefrontProduct() async {
        guard let searchedVariantID = searchedProduct.variants.first?.id else {
            return
        }
        let loadID = UUID()
        latestLoadID = loadID
        isLoading = true
        errorMessage = nil
        do {
            try await applyLoadResult(
                loadID: loadID,
                result: .success(loadShopifyStorefrontProduct(shopDomain: shopDomain, productID: searchedVariantID, selected: nil, urlSession: urlSession))
            )
        } catch {
            // `loadShopifyStorefrontProduct` が投げるのは `ShopifyCatalogError` だけ。それ以外が来た時は失敗の扱いにする。
            applyLoadResult(loadID: loadID, result: .failure(error as? ShopifyCatalogError ?? .failed))
        }
    }

    /// 呼び出し `loadID` の結果 `result` を画面に反映し、読み込み中を終える (`shopifyCatalogDetailLoaded` の決まり)。後から別の呼び出しを始めていた時は何もしない。
    private func applyLoadResult(loadID: UUID, result: Result<ShopifyCatalogProduct, ShopifyCatalogError>) {
        guard latestLoadID == loadID else {
            return
        }
        let loaded = shopifyCatalogDetailLoaded(previous: storefrontProduct, result: result, now: .now)
        storefrontProduct = loaded.storefrontProduct
        errorMessage = loaded.error.map { shopifyCatalogErrorMessage(error: $0, locale: appTextLocale) }
        checkedAt = .now
        isLoading = false
    }
}
