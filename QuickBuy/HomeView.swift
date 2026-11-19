import SwiftUI

/// トップページの、検索の前に並べる買い直す物の検索語。押すとその語で検索する。
///
/// 日用品・食品のうち、同じ物を定期的に買い直す物として agent が選んだ語 (issue #34。documents/DIRECTION.md「決めたこと」)。
let homeSuggestedSearchQueries = ["コーヒー豆", "紅茶", "シャンプー", "洗濯洗剤", "プロテイン", "ドッグフード"]

/// トップページを開いた時に、検索の前に結果を並べておく決まった検索語。
///
/// 検索語の並び (`homeSuggestedSearchQueries`) の先頭と同じ語。人気の順を返す API が無いため、見出しは「人気の商品」でなく、この語の検索の結果だと分かる言葉にする (issue #34)。
let homeFeaturedSearchQuery = "コーヒー豆"

/// トップページ。検索窓・買い直す物の検索語・画像つきの商品の並びを見せ、商品の「お気に入り追加」から追加の画面を開く。
///
/// 検索の前は `homeFeaturedSearchQuery` の検索の結果を並べる。商品の名前・画像・価格は画面に出すだけで保存しない。
/// 価格を取得してから `shopifyCatalogPriceCacheSeconds` 秒たった結果は、画面が出た時に取り直す (Shopify の「Caching limits」)。
struct HomeView: View {
    /// お気に入りの保存先のファイルの URL。
    let favoritesFileURL: URL

    /// アプリが前面にあるか。前面に戻った時に、古くなった価格を取り直すために見る。
    @Environment(\.scenePhase) private var scenePhase
    /// 検索窓の文字列。
    @State private var searchText = ""
    /// 並べている商品の検索語。
    @State private var shownQuery = homeFeaturedSearchQuery
    /// 並べている商品と、取得した時刻。まだ取得していない時と取得できなかった時は nil。
    @State private var searchResult: (products: [ShopifyCatalogProduct], fetchedAt: Date)?
    /// 検索している間は true。
    @State private var isSearching = false
    /// 最後に始めた検索の識別子。結果を受けた時に、この値と違う (後から別の検索を始めた) 検索の結果は捨てる。
    @State private var latestSearchID = UUID()
    /// 検索できなかった理由の文言。出していない時は nil。
    @State private var errorMessage: String?
    /// 追加の画面を開いている商品と店のドメイン。開いていない時は nil。
    @State private var addingProduct: AddingProduct?

    /// 追加の画面を開いている商品。
    struct AddingProduct: Identifiable {
        /// 検索の結果の商品。
        let product: ShopifyCatalogProduct
        /// 店のドメイン。
        let shopDomain: String

        /// 商品の ID と店のドメイン (同じ商品を別の店が売る時に別の画面として扱うため)。
        var id: String { "\(shopDomain) \(product.id)" }
    }

    /// 検索窓・案内・検索語・商品の並び。
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if searchText.isEmpty && shownQuery == homeFeaturedSearchQuery {
                        guideBanner
                    }
                    suggestedQueries
                    results
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Quick Buy")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "商品を検索")
            .onSubmit(of: .search) {
                search(query: searchText)
            }
        }
        .tint(quickBuyAccentColor)
        .onAppear(perform: refreshIfPriceExpired)
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .active {
                refreshIfPriceExpired()
            }
        }
        // 画面を開いたまま (追加の画面を重ねている間を含む) 価格を出してよい時間を過ぎたら、同じ検索語で取り直す。
        .task(id: searchResult?.fetchedAt) {
            guard let fetchedAt = searchResult?.fetchedAt else {
                return
            }
            try? await Task.sleep(for: .seconds(shopifyCatalogPriceRemainingSeconds(fetchedAt: fetchedAt, now: .now)))
            if !Task.isCancelled {
                refreshIfPriceExpired()
            }
        }
        // 足したお気に入りの読み直しと通知の許可の説明は、お気に入りのタブを開いた時に一覧の画面が行う。
        .sheet(item: $addingProduct) { addingProduct in
            CatalogAddFavoriteView(
                searchedProduct: addingProduct.product,
                shopDomain: addingProduct.shopDomain,
                favoritesFileURL: favoritesFileURL,
                urlSession: .shared
            ) {
                self.addingProduct = nil
            }
        }
    }

    /// アプリの使い方を 2 行で伝える案内。
    private var guideBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("いつもの商品を 1 タップで")
                .font(.headline)
            Text("お気に入りに入れるとホーム画面のウィジェットから買い直せます")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(quickBuyAccentColor, in: RoundedRectangle(cornerRadius: 16))
    }

    /// 買い直す物の検索語の並び。押すとその語で検索する。
    private var suggestedQueries: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("買い直す物から探す")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(homeSuggestedSearchQueries, id: \.self) { query in
                        Button(query) {
                            searchText = query
                            search(query: query)
                        }
                        .font(.subheadline.weight(.bold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
        }
    }

    /// 検索の結果の見出しと商品の 2 列の並び。検索している間・失敗した時・0 件の時はその旨。
    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("「\(shownQuery)」の検索結果")
                .font(.headline)
            if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Text("お気に入りの + から商品ページの URL を入れても追加できます")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("もう一度検索する") {
                        search(query: shownQuery)
                    }
                }
            } else if let searchResult {
                if searchResult.products.isEmpty {
                    Text("商品が見つかりませんでした")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Array(searchResult.products.enumerated()), id: \.offset) { _, product in
                            if let variant = product.variants.first, let shopDomain = shopifyCatalogShopDomain(variant: variant) {
                                productCard(product: product, variant: variant, shopDomain: shopDomain)
                            }
                        }
                    }
                }
            }
            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 商品 1 件のカード。画像・店のドメイン・名前・価格と「お気に入り追加」のボタン。
    private func productCard(product: ShopifyCatalogProduct, variant: ShopifyCatalogVariant, shopDomain: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(uiColor: .quaternarySystemFill)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let imageURL = shopifyCatalogImageURL(product: product, shopDomain: shopDomain) {
                        CatalogProductImage(imageURL: imageURL)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(shopDomain)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(product.title)
                .font(.subheadline.weight(.bold))
                .lineLimit(2, reservesSpace: true)
            if let price = variant.price {
                Text(shopifyCatalogPriceText(money: price))
                    .font(.subheadline)
            }
            Button {
                addingProduct = AddingProduct(product: product, shopDomain: shopDomain)
            } label: {
                Text("お気に入り追加")
                    .font(.footnote.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("addFavoriteFromSearch")
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    /// 並べている結果の価格を取得してから `shopifyCatalogPriceCacheSeconds` 秒たっていれば、同じ検索語で取り直す。まだ取得していなければ取得する。
    private func refreshIfPriceExpired() {
        guard !isSearching else {
            return
        }
        if let searchResult, isShopifyCatalogPriceFresh(fetchedAt: searchResult.fetchedAt, now: .now) {
            return
        }
        search(query: shownQuery)
    }

    /// 検索語 (前後の空白と改行は除く) で Global Catalog を検索し、結果を並べる。空の検索語では何もしない。
    /// 検索できなかった時は、前の結果を消して理由を出す (古い価格を残さないため)。
    private func search(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return
        }
        let searchID = UUID()
        latestSearchID = searchID
        shownQuery = trimmedQuery
        isSearching = true
        errorMessage = nil
        searchResult = nil
        Task {
            do {
                let products = try await searchShopifyCatalog(query: trimmedQuery, endpointURL: shopifyGlobalCatalogEndpointURL, urlSession: .shared)
                // 結果を待つ間に検索し直した時 (同じ語を含む) は、前の検索の結果で上書きしない。
                guard latestSearchID == searchID else {
                    return
                }
                searchResult = (products, .now)
            } catch {
                guard latestSearchID == searchID else {
                    return
                }
                // `searchShopifyCatalog` が投げるのは `ShopifyCatalogError` だけ。それ以外が来た時は失敗の扱いにする。
                errorMessage = shopifyCatalogErrorMessage(error: error as? ShopifyCatalogError ?? .failed)
            }
            isSearching = false
        }
    }
}

/// 検索の結果の商品の画像。読み込めない間は何も出さない (下地の色が見える)。
///
/// 画像は画面に出すだけで保存しない。読み込みは、転送先を確かめる `productImageURLSession` で行う。
struct CatalogProductImage: View {
    /// 画像の URL (`shopifyCatalogImageURL(product:shopDomain:)` を通ったもの)。
    let imageURL: URL

    /// 読み込んだ画像。読み込む前と読み込めなかった時は nil。
    @State private var image: UIImage?

    /// 枠いっぱいに切り抜いた画像。
    var body: some View {
        // 読み込む前は中身が空で、空の `Group` には `task` が動かないため、透明な下地に重ねる。
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .task(id: imageURL) {
                image = await loadProductImage(url: imageURL, urlSession: productImageURLSession)
            }
    }
}
