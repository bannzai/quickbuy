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
                    content: reminderNotificationContent(favorite: favorite),
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                )
            )
        }
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

        /// 見本のお気に入りを入れる・消すのボタン、見本の商品で追加の画面を開くボタン、リマインドの状態と通知を作るボタン。
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
                }
                .navigationTitle("開発者メニュー")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる", action: onFinish)
                    }
                }
                .alert("操作に失敗しました", isPresented: $isOperationFailed) {}
                .sheet(isPresented: $isAddingSampleProduct) {
                    AddFavoriteView(
                        initialText: sampleProductPageURLText,
                        favoritesFileURL: favoritesFileURL,
                        urlSession: sampleProductURLSession(),
                        onFinish: onFinish
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
