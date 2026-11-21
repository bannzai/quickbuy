#if DEBUG
    import SwiftUI
    import UserNotifications

    /// 開発者メニューが入れる見本のお気に入り 3 件を返す。
    ///
    /// 店のドメインは実在しない `.example` (RFC 2606 の予約済みのドメイン) にしている。実在の店の名前をリポジトリに入れないため。
    /// 識別子を固定しているので、何度入れても 3 件のままになる。
    /// 商品バリアントの名前を持つもの (1 件目と 3 件目) と持たないもの (2 件目) の両方を含む。
    func sampleFavorites() -> [Favorite] {
        [
            Favorite(
                id: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!,
                name: "コーヒー豆",
                variantName: "200g / 豆のまま",
                imageURL: nil,
                quantity: 2,
                product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
                reminder: nil
            ),
            Favorite(
                id: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA2")!,
                name: "洗濯用せっけん",
                imageURL: nil,
                quantity: 1,
                product: .shopify(ShopifyProduct(shopDomain: "sukoyaka-soap.example", variantID: "70881382")),
                reminder: nil
            ),
            Favorite(
                id: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA3")!,
                name: "プロテイン",
                variantName: "1kg",
                imageURL: nil,
                quantity: 1,
                product: .shopify(ShopifyProduct(shopDomain: "karada-store.example", variantID: "70881999")),
                reminder: nil
            ),
        ]
    }

    /// 見本のお気に入りを、保存済みの並びの末尾に足す。既に入っている見本は足さず、変えない。
    func insertSampleFavorites(fileURL: URL) throws {
        for sampleFavorite in sampleFavorites() {
            try addFavorite(favorite: sampleFavorite, fileURL: fileURL)
        }
    }

    /// 保存済みのお気に入りから、見本のお気に入り (名前や個数を変えたものを含む) だけを消す。利用者が自分で入れたお気に入りと、その並びは変えない。
    func deleteSampleFavorites(fileURL: URL) throws {
        try saveFavorites(
            favorites: loadFavorites(fileURL: fileURL).filter { favorite in !sampleFavorites().contains { $0.id == favorite.id } },
            fileURL: fileURL
        )
    }

    /// リマインドを設定しているお気に入りすべてを、日数がちょうど過ぎた状態にする (日数を数え始めた日時を、`now` から設定した日数だけ前へずらす)。
    ///
    /// 時計を進めないと作れない「そろそろ買う頃」の表示を確かめるために使う。通知の予約は変えない。
    func makeFavoriteRemindersDue(now: Date, fileURL: URL) throws {
        try saveFavorites(
            favorites: loadFavorites(fileURL: fileURL).map { favorite in
                var dueFavorite = favorite
                if let reminder = favorite.reminder {
                    dueFavorite.reminder?.countedFrom = now.addingTimeInterval(-reminderTimeInterval(reminder: reminder))
                }
                return dueFavorite
            },
            fileURL: fileURL
        )
    }

    /// お気に入りのリマインドと同じ内容の通知を 5 秒後に 1 回だけ出す予約をする (通知の見た目と、タップした時の動きを確かめるために使う)。
    ///
    /// 通知の識別子はお気に入りの識別子と別にしているので、そのお気に入りの本物の予約を置き換えない。
    /// 5 秒は、ボタンを押してからホーム画面へ移る操作が間に合う長さ。
    func scheduleReminderNotificationPreview(favorite: Favorite, center: UNUserNotificationCenter) {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            center.add(
                UNNotificationRequest(
                    identifier: "developerMenuReminderPreview",
                    content: reminderNotificationContent(favorite: favorite, locale: appTextLocale),
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                )
            )
        }
    }

    /// 通知の許可の説明の画面を出した記録を消す (説明の画面をもう一度出して確かめるために使う)。記録が無い時は何も変わらない。
    ///
    /// 端末の通知の許可そのものは変えない (アプリから許可を聞かれる前の状態へ戻す手段は無い)。
    func resetNotificationPermissionExplanationPresented(userDefaults: UserDefaults) {
        userDefaults.removeObject(forKey: notificationPermissionExplanationPresentedKey)
    }

    /// 追加の画面の見本に使う商品ページの URL。店のドメインは実在しない `.example` (RFC 2606 の予約済みのドメイン)。
    let sampleProductPageURLText = "https://mori-coffee.example/products/coffee-beans"

    /// 追加の画面の見本に使う、商品バリアントが 3 つある商品の JSON (Shopify の Ajax Product API の応答の形)。
    let sampleProductJSONText = """
    {"title":"コーヒー豆 中煎り","featured_image":null,"variants":[
    {"id":70881412,"title":"200g / 豆のまま","available":true},
    {"id":70881413,"title":"500g / 中挽き","available":true},
    {"id":70881414,"title":"1kg / 豆のまま","available":true}]}
    """

    /// どの URL へのリクエストにも、ネットワークに出ずに `sampleProductJSONText` を HTTP 200 で返す、通信の差し替え。
    ///
    /// 実在しない店の商品で追加の画面を開くために使う (実在の店の名前をリポジトリと動作確認の記録に入れないため)。
    /// class にしているのは、`URLSessionConfiguration.protocolClasses` が `URLProtocol` のサブクラスを求めるため。
    final class SampleProductURLProtocol: URLProtocol {
        /// すべてのリクエストをこの差し替えで受ける。
        override class func canInit(with _: URLRequest) -> Bool {
            true
        }

        /// リクエストを変えずに返す。
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        /// `sampleProductJSONText` を本文にした HTTP 200 の応答を返す。
        override func startLoading() {
            if let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(sampleProductJSONText.utf8))
                client?.urlProtocolDidFinishLoading(self)
            } else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            }
        }

        /// 途中で止めるものが無いため何もしない。
        override func stopLoading() {}
    }

    /// `SampleProductURLProtocol` を通る (ネットワークに出ない) 通信を返す。
    func sampleProductURLSession() -> URLSession {
        let urlSessionConfiguration = URLSessionConfiguration.ephemeral
        urlSessionConfiguration.protocolClasses = [SampleProductURLProtocol.self]
        return URLSession(configuration: urlSessionConfiguration)
    }

    /// 商品の詳細ページの見本に使う店のドメイン。実在しない `.example` (RFC 2606 の予約済みのドメイン)。
    let sampleCatalogShopDomain = "mori-coffee.example"

    /// 商品の詳細ページの見本に使う、検索の結果の形の商品。画像 2 枚と動画 1 本、タグの入った説明文を持ち、売り切れ。
    ///
    /// 画像は Shopify が自分の CDN で配っている見本の画像 (2026-11-21 に `curl -I` でどちらも HTTP 200・`image/png` を確かめた)。実在の店の画像をリポジトリに入れないため。
    func sampleCatalogProduct() -> ShopifyCatalogProduct {
        ShopifyCatalogProduct(
            id: "gid://shopify/p/sample",
            title: "コーヒー豆 中煎り",
            description: ShopifyCatalogDescription(plain: "<p>検索の結果の説明文</p><ul><li>内容量: 200g</li><li>焙煎: 中煎り</li></ul>", html: nil),
            media: [
                ShopifyCatalogMedia(type: "video", url: "https://cdn.shopify.com/videos/c/vp/sample/sample.m3u8"),
                ShopifyCatalogMedia(type: "image", url: "https://cdn.shopify.com/s/files/1/0533/2089/files/placeholder-images-product-1_large.png"),
                ShopifyCatalogMedia(type: "image", url: "https://cdn.shopify.com/s/files/1/0533/2089/files/placeholder-images-image_large.png"),
            ],
            options: nil,
            selected: nil,
            variants: [
                ShopifyCatalogVariant(
                    id: "gid://shopify/ProductVariant/70881412",
                    title: "コーヒー豆 中煎り",
                    price: ShopifyCatalogMoney(amount: 1800, currency: "JPY"),
                    availability: .init(available: false),
                    seller: .init(url: "https://mori-coffee.example")
                ),
            ]
        )
    }

    /// 商品の詳細ページの見本に使う、店の入口の `get_product` の応答の JSON。選べる値が 2 つの選び方と 1 つだけの選び方を持ち、商品バリアントは売り切れ。
    let sampleStorefrontProductJSONText = """
    {"jsonrpc":"2.0","id":1,"result":{"structuredContent":{"product":{
    "id":"gid://shopify/Product/1","title":"コーヒー豆 中煎り","description":{"html":"店の入口の説明文 売り切れの見本です"},
    "media":[{"type":"image","url":"https://cdn.shopify.com/s/files/1/0533/2089/files/placeholder-images-product-1_large.png"}],
    "options":[{"name":"内容量","values":[{"label":"200g"},{"label":"500g"}]},{"name":"挽き方","values":[{"label":"豆のまま"}]}],
    "selected":[{"name":"内容量","label":"200g"},{"name":"挽き方","label":"豆のまま"}],
    "variants":[{"id":"gid://shopify/ProductVariant/70881412","title":"200g / 豆のまま","price":{"amount":1800,"currency":"JPY"},"availability":{"available":false}}]}}}}
    """

    /// どの URL へのリクエストにも、ネットワークに出ずに `sampleStorefrontProductJSONText` を HTTP 200 で返す、通信の差し替え。
    ///
    /// 実在しない店の商品で商品の詳細ページを開くために使う。class にしているのは、`URLSessionConfiguration.protocolClasses` が `URLProtocol` のサブクラスを求めるため。
    class SampleStorefrontProductURLProtocol: URLProtocol {
        /// 返す応答の HTTP の状態・ヘッダー・本文。
        class var sampleResponse: (statusCode: Int, headerFields: [String: String], body: String) {
            (200, [:], sampleStorefrontProductJSONText)
        }

        /// すべてのリクエストをこの差し替えで受ける。
        override class func canInit(with _: URLRequest) -> Bool {
            true
        }

        /// リクエストを変えずに返す。
        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        /// `sampleResponse` の応答を返す。
        override func startLoading() {
            if let url = request.url,
               let response = HTTPURLResponse(
                   url: url,
                   statusCode: type(of: self).sampleResponse.statusCode,
                   httpVersion: "HTTP/1.1",
                   headerFields: type(of: self).sampleResponse.headerFields
               )
            {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(type(of: self).sampleResponse.body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            } else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            }
        }

        /// 途中で止めるものが無いため何もしない。
        override func stopLoading() {}
    }

    /// どの URL へのリクエストにも、ネットワークに出ずに HTTP 429 (`Retry-After: 30`) を返す、通信の差し替え。店の入口を読み込めない時の商品の詳細ページを開くために使う。
    final class SampleStorefrontRateLimitedURLProtocol: SampleStorefrontProductURLProtocol {
        /// HTTP 429 と `Retry-After: 30`、空の本文。
        override class var sampleResponse: (statusCode: Int, headerFields: [String: String], body: String) {
            (429, ["Retry-After": "30"], "")
        }
    }

    /// `protocolClass` (`URLProtocol` のサブクラス) を通る (ネットワークに出ない) 通信を返す。
    func sampleURLSession(protocolClass: AnyClass) -> URLSession {
        let urlSessionConfiguration = URLSessionConfiguration.ephemeral
        urlSessionConfiguration.protocolClasses = [protocolClass]
        return URLSession(configuration: urlSessionConfiguration)
    }

    /// 開発者メニュー (DEBUG ビルドだけ)。画面の操作では作りにくい状態を作る。
    struct DeveloperMenuView: View {
        /// お気に入りの保存先のファイルの URL。
        let favoritesFileURL: URL
        /// この画面を閉じる処理。
        let onFinish: () -> Void

        /// 操作に失敗したことを知らせる表示を出している間は true。
        @State private var isOperationFailed = false
        /// 見本の商品の追加の画面を出している間は true。
        @State private var isAddingSampleProduct = false
        /// 見本の商品の詳細ページを出している間の、店の入口の通信の差し替えと、開いた時刻 (検索の結果を取得した時刻として渡す)。出していない時は nil。
        @State private var sampleProductDetail: (urlSession: URLSession, openedAt: Date)?

        /// 見本のお気に入りを入れる・消すのボタン、見本の商品で追加の画面と商品の詳細ページを開くボタン、リマインドの状態と通知を作るボタン、通知の許可の説明の画面を出した記録を消すボタン。
        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Button("見本のお気に入りを入れる") {
                            finish {
                                try insertSampleFavorites(fileURL: favoritesFileURL)
                            }
                        }
                        Button("種類のある見本の商品を追加の画面で開く") {
                            isAddingSampleProduct = true
                        }
                        Button("見本のお気に入りを消す", role: .destructive) {
                            finish {
                                try performSavingWithReminderNotifications(fileURL: favoritesFileURL, center: .current()) {
                                    try deleteSampleFavorites(fileURL: favoritesFileURL)
                                }
                            }
                        }
                    } header: {
                        Text("お気に入り")
                    }
                    Section {
                        Button("売り切れで画像が 2 枚の見本の商品を開く") {
                            sampleProductDetail = (sampleURLSession(protocolClass: SampleStorefrontProductURLProtocol.self), .now)
                        }
                        Button("店の入口を読み込めない見本の商品を開く") {
                            sampleProductDetail = (sampleURLSession(protocolClass: SampleStorefrontRateLimitedURLProtocol.self), .now)
                        }
                    } header: {
                        Text("商品の詳細ページ")
                    }
                    Section {
                        Button("リマインドの日数が過ぎた状態にする") {
                            finish {
                                try makeFavoriteRemindersDue(now: .now, fileURL: favoritesFileURL)
                            }
                        }
                        Button("先頭のお気に入りの通知を 5 秒後に出す") {
                            finish {
                                guard let firstFavorite = try loadFavorites(fileURL: favoritesFileURL).first else {
                                    throw FavoriteStoreError.favoriteNotFound
                                }
                                scheduleReminderNotificationPreview(favorite: firstFavorite, center: .current())
                            }
                        }
                        Button("保存されていないお気に入りの通知を 5 秒後に出す") {
                            finish {
                                scheduleReminderNotificationPreview(
                                    favorite: Favorite(
                                        id: UUID(),
                                        name: "保存されていないお気に入り",
                                        imageURL: nil,
                                        quantity: 1,
                                        product: .shopify(ShopifyProduct(shopDomain: "mori-coffee.example", variantID: "70881412")),
                                        reminder: nil
                                    ),
                                    center: .current()
                                )
                            }
                        }
                    } header: {
                        Text("リマインド")
                    }
                    Section {
                        Button("説明の画面を出した記録を消す") {
                            finish {
                                resetNotificationPermissionExplanationPresented(userDefaults: .standard)
                            }
                        }
                    } header: {
                        Text("通知の許可の説明")
                    }
                }
                .navigationTitle("開発者メニュー")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる", action: onFinish)
                    }
                }
                .alert("操作に失敗しました", isPresented: $isOperationFailed) {}
                .navigationDestination(isPresented: Binding(get: { sampleProductDetail != nil }, set: { if !$0 { sampleProductDetail = nil } })) {
                    if let sampleProductDetail {
                        // 見本の商品はお気に入りにしないので、「お気に入り追加」は押せることだけを見せて何もしない。
                        CatalogProductDetailView(
                            searchedProduct: sampleCatalogProduct(),
                            shopDomain: sampleCatalogShopDomain,
                            searchFetchedAt: sampleProductDetail.openedAt,
                            urlSession: sampleProductDetail.urlSession,
                            onAddFavorite: {}
                        )
                    }
                }
                .sheet(isPresented: $isAddingSampleProduct) {
                    AddFavoriteView(
                        initialText: sampleProductPageURLText,
                        favoritesFileURL: favoritesFileURL,
                        urlSession: sampleProductURLSession(),
                        onFinish: { isAddingSampleProduct = false }
                    )
                }
            }
            .tint(quickBuyAccentColor)
        }

        /// 操作を実行し、成功したら画面を閉じる。失敗した時は画面を閉じずにその旨を知らせる。
        private func finish(operation: () throws -> Void) {
            do {
                try operation()
                onFinish()
            } catch {
                isOperationFailed = true
            }
        }
    }
#endif
