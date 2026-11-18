#if DEBUG
    import SwiftUI

    /// 開発者メニューが入れる見本のお気に入り 3 件を返す。
    ///
    /// 店のドメインは実在しない `.example` (RFC 2606 の予約済みのドメイン) にしている。実在の店の名前をリポジトリに入れないため。
    /// 識別子を固定しているので、何度入れても 3 件のままになる。
    func sampleFavorites() -> [Favorite] {
        [
            Favorite(
                id: UUID(uuidString: "5A3B1EAA-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!,
                name: "コーヒー豆 200g",
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
                name: "プロテイン 1kg",
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

    /// 開発者メニュー (DEBUG ビルドだけ)。画面の操作では作りにくい状態を作る。
    struct DeveloperMenuView: View {
        /// お気に入りの保存先のファイルの URL。
        let favoritesFileURL: URL
        /// この画面を閉じる処理。
        let onFinish: () -> Void

        /// 操作に失敗したことを知らせる表示を出している間は true。
        @State private var isOperationFailed = false

        /// 見本のお気に入りを入れる・消すのボタン。
        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Button("見本のお気に入りを入れる") {
                            finish {
                                try insertSampleFavorites(fileURL: favoritesFileURL)
                            }
                        }
                        Button("見本のお気に入りを消す", role: .destructive) {
                            finish {
                                try deleteSampleFavorites(fileURL: favoritesFileURL)
                            }
                        }
                    } header: {
                        Text("お気に入り")
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
