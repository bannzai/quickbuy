import SwiftUI
import UserNotifications

/// アプリの最初の画面。お気に入りの保存先を開ければ一覧を、開けなければその旨を表示する。
struct ContentView: View {
    /// お気に入りの一覧、または保存先を開けないことの表示。
    var body: some View {
        if let favoritesFileURL = sharedFavoritesFileURL() {
            FavoritesListView(favoritesFileURL: favoritesFileURL)
        } else {
            FavoritesStoreUnavailableView()
        }
    }
}

/// お気に入りの一覧の画面。保存した並びで表示し、「カートイン」で「購入画面を開きますか？」の確認を出して、確認の「開く」で店の購入画面を開く。
/// 追加・名前と個数の変更・並べ替え・削除・設定画面の入口を持つ。
struct FavoritesListView: View {
    /// お気に入りの保存先のファイルの URL。
    let favoritesFileURL: URL

    /// 店の購入画面を開く処理 (既定のブラウザで開く)。
    @Environment(\.openURL) private var openURL
    /// アプリが前面にあるか。共有メニューの拡張で足したお気に入りを、アプリへ戻った時に読み直すために見る。
    @Environment(\.scenePhase) private var scenePhase
    /// 表示しているお気に入りの並び (保存先から読んだもの)。
    @State private var favorites: [Favorite] = []
    /// 保存先のファイルを読めなかった時は true。
    @State private var isLoadFailed = false
    /// 保存に失敗したことを知らせる表示を出している間は true。
    @State private var isSaveFailed = false
    /// 編集の画面で開いているお気に入り (開いた時点の保存済みの値)。開いていない時は nil。
    @State private var editingFavorite: Favorite?
    /// お気に入りの追加の画面を出している間は true。
    @State private var isAddingFavorite = false
    /// 設定画面を出している間は true。
    @State private var isSettingsPresented = false
    /// 「カートイン」を押して出している確認が指すお気に入りの識別子と、確認を出した (同じ行で押し直した時は出し直した) 時刻。出していない時は nil。
    /// 持つのは識別子だけで、購入画面の URL は「開く」を押した時に保存済みのお気に入りから組み立てる (documents/adr/0003)。
    @State private var cartInConfirmation: (favoriteID: UUID, shownAt: Date)?

    /// 一覧と、追加・編集・設定の画面への入口。
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("お気に入り")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isSettingsPresented = true
                        } label: {
                            Label("設定", systemImage: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isAddingFavorite = true
                        } label: {
                            Label("お気に入りを追加", systemImage: "plus")
                        }
                    }
                }
        }
        .tint(quickBuyAccentColor)
        .onAppear(perform: reload)
        .task(id: cartInConfirmation?.shownAt) {
            guard cartInConfirmation != nil else {
                return
            }
            do {
                try await Task.sleep(for: .seconds(cartInConfirmationSeconds))
            } catch {
                // 別の行の「カートイン」か「開く」で、この確認の待ちが取り消された。
                return
            }
            cartInConfirmation = nil
        }
        .onOpenURL { tapURL in
            // 購入画面を開けない時 (お気に入りが消されている・購入画面の URL を組み立てられない等) は、この一覧をそのまま見せる。
            // 確認の「開く」と同じ経路で、リマインドの数え直しと通知の予約のし直しを行う。
            save {
                if let tappedPurchaseURL = try tappedFavoritePurchaseURL(tapURL: tapURL, now: .now, fileURL: favoritesFileURL) {
                    openURL(tappedPurchaseURL)
                }
            }
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .active {
                reload()
            }
        }
        // アプリが前面に来るたびに、通知が許可されているのに予約の無いリマインド (通知を拒否していた間に保存したもの) を予約する。
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                return
            }
            await restoreMissingReminderNotifications(fileURL: favoritesFileURL, center: .current(), now: .now)
            reload()
        }
        .sheet(item: $editingFavorite, onDismiss: reload) { favorite in
            EditFavoriteView(favorite: favorite, favoritesFileURL: favoritesFileURL) {
                editingFavorite = nil
            }
        }
        .sheet(isPresented: $isAddingFavorite, onDismiss: reload) {
            AddFavoriteView(initialText: "", favoritesFileURL: favoritesFileURL, urlSession: .shared) {
                isAddingFavorite = false
            }
        }
        .sheet(isPresented: $isSettingsPresented, onDismiss: reload) {
            SettingsView(favoritesFileURL: favoritesFileURL) {
                isSettingsPresented = false
            }
        }
        .alert("保存できませんでした", isPresented: $isSaveFailed) {}
    }

    /// お気に入りの並び。読めなかった時と 1 件も無い時は、その旨の表示。
    @ViewBuilder private var content: some View {
        if isLoadFailed {
            ContentUnavailableView("お気に入りを読み込めません", systemImage: "exclamationmark.triangle")
        } else if favorites.isEmpty {
            ContentUnavailableView(
                "お気に入りはまだありません",
                systemImage: "cart",
                description: Text("右上の + から商品ページの URL を入れると\nここに並びます")
            )
        } else {
            List {
                Section {
                    ForEach(favorites) { favorite in
                        row(favorite: favorite)
                            .listRowSeparator(.hidden)
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 16)
                            )
                            .listRowInsets(EdgeInsets(top: 17, leading: 28, bottom: 17, trailing: 28))
                    }
                    .onMove { sourceIndexes, destinationOffset in
                        // 一覧のドラッグで動かせるのは 1 行ずつなので、渡される位置は 1 つ。
                        guard let sourceIndex = sourceIndexes.first else {
                            return
                        }
                        save {
                            try moveFavorite(
                                id: favorites[sourceIndex].id,
                                destinationIndex: destinationIndexAfterMove(sourceIndex: sourceIndex, destinationOffset: destinationOffset),
                                fileURL: favoritesFileURL
                            )
                        }
                    }
                    .onDelete { deletedIndexes in
                        save {
                            try deleteFavorites(indexes: deletedIndexes, favorites: favorites, fileURL: favoritesFileURL)
                        }
                    }
                } footer: {
                    Text("「カートイン」の後に「開く」を押すと店の購入画面が開きます\n支払いの確定は店の画面で行います")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                cartInConfirmationView
            }
            .animation(.default, value: cartInConfirmation?.shownAt)
        }
    }

    /// 「カートイン」を押した後に画面の下に出す確認。「開く」を押すと、確認が指すお気に入りの購入画面を開く。
    /// 確認が指すお気に入りが保存先から消えた時と、購入画面を開けなくなった時は出さない。
    @ViewBuilder private var cartInConfirmationView: some View {
        if let confirmingFavorite = cartInConfirmationFavorite(favoriteID: cartInConfirmation?.favoriteID, favorites: favorites) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("購入画面を開きますか？")
                        .font(.subheadline.weight(.heavy))
                    Text(cartInConfirmationText(favorite: confirmingFavorite))
                        .font(.caption)
                        .foregroundStyle(cartInConfirmationSecondaryTextColor)
                }
                Spacer(minLength: 0)
                Button {
                    cartInConfirmation = nil
                    save {
                        if let openingURL = try purchaseURLForOpening(favoriteID: confirmingFavorite.id, now: .now, fileURL: favoritesFileURL) {
                            openURL(openingURL)
                        }
                    }
                } label: {
                    Text("開く")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(cartInConfirmationBackgroundColor)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(cartInConfirmationBackgroundColor, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// お気に入り 1 件の行。名前の側を押すと編集の画面が開き、「カートイン」を押すと購入画面を開くかの確認が出る (購入画面はまだ開かない)。
    private func row(favorite: Favorite) -> some View {
        HStack(spacing: 12) {
            Button {
                editingFavorite = favorite
            } label: {
                HStack(spacing: 12) {
                    FavoriteThumbnail(imageURL: favorite.imageURL)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(favorite.name)
                            .font(.subheadline.weight(.bold))
                        if let variantName = favorite.variantName {
                            Text(variantName)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(quickBuyAccentColor)
                        }
                        // 長いドメインでも個数が次の行に送られないよう、ドメインだけを中ほどで省いて 1 行に収める。
                        HStack(spacing: 0) {
                            Text(shopDomainText(favorite: favorite))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(" ・ \(favorite.quantity) 個")
                                .fixedSize()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        // 一覧を開いたまま日数が過ぎた時にも文言が切り替わるよう、1 分ごとに描き直す。
                        // 1 分は、文言の最小の単位 (1 日) に対して遅れが目立たず、描き直しの負荷も小さい間隔。
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            if let reminder = favorite.reminder, isReminderDue(reminder: reminder, now: timeline.date) {
                                Text(reminderStatusText(reminder: reminder, now: timeline.date))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(reminderDueColor)
                            } else {
                                Text(reminderStatusText(reminder: favorite.reminder, now: timeline.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if purchaseURL(favorite: favorite) != nil {
                Button("カートイン") {
                    cartInConfirmation = (favoriteID: favorite.id, shownAt: .now)
                }
                .font(.subheadline.weight(.heavy))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
            }
        }
    }

    /// 保存先からお気に入りを読み直して表示に反映する。
    private func reload() {
        do {
            favorites = try loadFavorites(fileURL: favoritesFileURL)
            isLoadFailed = false
        } catch {
            isLoadFailed = true
        }
    }

    /// 保存の操作を実行し、失敗した時はその旨を知らせる。成否にかかわらず、保存先の今の並びを表示に反映する。
    /// 操作で変わったリマインドに合わせて、通知の予約も取り消す・予約し直す。
    private func save(operation: () throws -> Void) {
        do {
            try performSavingWithReminderNotifications(fileURL: favoritesFileURL, center: .current(), operation: operation)
        } catch {
            isSaveFailed = true
        }
        reload()
    }
}

/// 一覧の行で、リマインドの日数が過ぎたこと (「そろそろ買う頃」) を示す文字の色。
///
/// 画面の見本 (documents/design/mock-2026-11-17/project/Main.dc.html) の「そろそろ買う頃」の色 `#9A3412`。
let reminderDueColor = Color(red: 0x9A / 255, green: 0x34 / 255, blue: 0x12 / 255)

/// 「カートイン」の確認を、利用者が何も押さない時に出しておく秒数。
///
/// 8 秒は、確認の 2 行を読んで「開く」を押すのに足り、押し間違えて放っておいた確認が画面に残り続けない長さとして agent が決めた値 (実測した値ではない)。
/// 消えた後は、同じ行の「カートイン」を押せば同じ確認をまた出せる。
let cartInConfirmationSeconds: Double = 8

/// 「カートイン」の確認の地の色。画面の見本 (documents/design/mock-2026-11-18/project/Favorites.dc.html) の確認の色 `#111318`。「開く」の文字にも使う。
let cartInConfirmationBackgroundColor = Color(red: 0x11 / 255, green: 0x13 / 255, blue: 0x18 / 255)

/// 「カートイン」の確認の 2 行目の文字の色。画面の見本 (documents/design/mock-2026-11-18/project/Favorites.dc.html) の色 `#D5D9E0`。
let cartInConfirmationSecondaryTextColor = Color(red: 0xD5 / 255, green: 0xD9 / 255, blue: 0xE0 / 255)

/// 「カートイン」の確認が指すお気に入りを、表示している並び (保存先から読んだもの) から返す。
///
/// `favoriteID` は最後に「カートイン」を押した行のお気に入りの識別子 (確認を出していない時は nil)。
/// その識別子のお気に入りが並びに無い時 (確認を出した後に削除された等) と、購入画面の URL を組み立てられない時は nil を返す (確認を出さない)。
func cartInConfirmationFavorite(favoriteID: UUID?, favorites: [Favorite]) -> Favorite? {
    favorites.first { $0.id == favoriteID && purchaseURL(favorite: $0) != nil }
}

/// 「カートイン」の確認の 2 行目に出す、何を何個カートに入れて開くかの文を返す。商品バリアントの名前を持つお気に入りでは、名前の後ろに足す。
func cartInConfirmationText(favorite: Favorite) -> String {
    "\([favorite.name, favorite.variantName].compactMap { $0 }.joined(separator: " ")) を \(favorite.quantity) 個カートに入れて開きます"
}

/// 一覧の並べ替え (`onMove`) が渡す移動先を、`moveFavorite(id:destinationIndex:fileURL:)` の `destinationIndex` (移動した後の位置) に直して返す。
///
/// `onMove` の移動先は、移動する前の並びで「この位置の要素の前に差し込む」を表す (末尾の後ろは件数と同じ値)。
/// 元の位置より後ろへ移す時は、移すお気に入り自身が抜ける分だけ 1 つ前にずれる。
func destinationIndexAfterMove(sourceIndex: Int, destinationOffset: Int) -> Int {
    destinationOffset > sourceIndex ? destinationOffset - 1 : destinationOffset
}

/// 一覧の削除 (`onDelete`) が渡す位置 (表示している並び `favorites` の中の位置。複数のこともある) のお気に入りを、保存先から消す。
///
/// 位置を先に識別子へ直してから消す (1 件消すたびに後ろの位置がずれるため、位置のまま順に消すと別のお気に入りを消してしまう)。
func deleteFavorites(indexes: IndexSet, favorites: [Favorite], fileURL: URL) throws {
    for deletedFavoriteID in indexes.map({ favorites[$0].id }) {
        try deleteFavorite(id: deletedFavoriteID, fileURL: fileURL)
    }
}

#Preview {
    ContentView()
}
