import SwiftUI

/// お気に入りの追加の画面。商品ページの URL を受け取り、店のドメインを目立つ形で見せる確認の画面を経て、利用者が「お気に入りに入れる」を押した時だけ保存する。
///
/// アプリの中 (貼り付け) と共有メニューの拡張の両方がこの画面を使うため、どちらから渡した URL も同じ確認の画面を通る (documents/adr/0003)。
struct AddFavoriteView: View {
    /// 最初から入っている URL の文字列。共有メニューから渡された時はその文字列、アプリの中から開いた時は空文字。
    let initialText: String
    /// お気に入りの保存先のファイルの URL。
    let favoritesFileURL: URL
    /// この画面を閉じる処理。保存した後と、やめた時に呼ぶ。
    let onFinish: () -> Void

    /// 入力欄の URL の文字列。
    @State private var text = ""
    /// 商品の情報を取得している間は true。
    @State private var isLoading = false
    /// 確認の画面に出している登録前のお気に入り。まだ URL を受け取っていない間は nil。
    @State private var favoriteDraft: Favorite?
    /// 入力欄の下に出す、登録できなかった理由の文言。出していない時は nil。
    @State private var errorMessage: String?
    /// 保存に失敗したことを知らせる表示を出している間は true。
    @State private var isSaveFailed = false

    /// URL を受け取る前は入力の画面、受け取った後は確認の画面。
    var body: some View {
        NavigationStack {
            Group {
                if let favoriteDraftBinding = Binding($favoriteDraft) {
                    confirmationForm(favorite: favoriteDraftBinding)
                } else {
                    inputForm
                }
            }
            .navigationTitle("お気に入りに入れる")
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
            await loadDraft()
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
                Text("Shopify の店の商品ページの URL を貼り付けてください")
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
                        await loadDraft()
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

    /// 店のドメイン・名前・個数を確かめる画面。
    private func confirmationForm(favorite: Binding<Favorite>) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("この店の商品です")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(shopDomainText(favorite: favorite.wrappedValue))
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
            Section {
                HStack(spacing: 12) {
                    FavoriteThumbnail(imageURL: favorite.wrappedValue.imageURL)
                    TextField("名前", text: favorite.name, axis: .vertical)
                        .accessibilityIdentifier("favoriteNameField")
                }
                QuantityStepperRow(quantity: favorite.quantity)
            }
            Section {
                Button {
                    finish(choice: .add)
                } label: {
                    Text("お気に入りに入れる")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(favorite.wrappedValue.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("入れただけでは購入されません")
            }
        }
    }

    /// 入力欄の文字列から登録前のお気に入りを作り、確認の画面に進む。作れなかった時は理由を入力欄の下に出す。
    private func loadDraft() async {
        isLoading = true
        errorMessage = nil
        do {
            favoriteDraft = try await loadFavoriteDraft(text: text, id: UUID(), urlSession: .shared)
        } catch {
            // `loadFavoriteDraft` が投げるのは `FavoriteDraftLoadError` だけ。それ以外が来た時は、登録できない扱いにして確認の画面へ進めない。
            errorMessage = favoriteDraftLoadErrorMessage(error: error as? FavoriteDraftLoadError ?? .notRegistrable)
        }
        isLoading = false
    }

    /// 利用者が選んだ操作を保存に反映して画面を閉じる。確認の画面に進む前の「やめる」は、保存するものが無いので閉じるだけ。
    private func finish(choice: FavoriteAdditionChoice) {
        do {
            if let favoriteDraft {
                try finishFavoriteAddition(choice: choice, favorite: favoriteDraft, fileURL: favoritesFileURL)
            }
            onFinish()
        } catch {
            isSaveFailed = true
        }
    }
}

/// アプリと共有メニューの拡張で使う、ボタンと強調の色。
///
/// 画面の見本 (documents/design/mock-2026-11-17/index.html) の「買う」「お気に入りに入れる」と店のドメインの枠の色 `#0F5E6B`。
let quickBuyAccentColor = Color(red: 0x0F / 255, green: 0x5E / 255, blue: 0x6B / 255)

/// 確認の画面で店のドメインを囲む枠の形。
///
/// 角の丸みは、一覧の行のまとまりの角の丸み (iOS 26 の simulator で、丸み 10 の枠の四隅が切れた) より大きくして、枠の四隅が切れないようにしている。
private let shopDomainBoxShape = RoundedRectangle(cornerRadius: 26, style: .continuous)

/// 登録できなかった理由を、入力欄の下に出す文言にして返す。
func favoriteDraftLoadErrorMessage(error: FavoriteDraftLoadError) -> String {
    switch error {
    case .notProductPageURL:
        "この URL は登録できません\nShopify の店の商品ページの URL を入れてください"
    case .temporarilyUnavailable:
        "商品の情報を取得できませんでした\n少し待ってからもう一度お試しください"
    case .notRegistrable:
        "この商品は登録できません\n商品の情報を取得できない店か、商品が見つかりません"
    }
}

/// お気に入りの店のドメインを、画面に出す文字列にして返す。Amazon の商品は `amazon.co.jp` (`AmazonProduct` が指す店)。
func shopDomainText(favorite: Favorite) -> String {
    switch favorite.product {
    case let .shopify(shopifyProduct):
        shopifyProduct.shopDomain
    case .amazon:
        "amazon.co.jp"
    }
}

/// 商品の画像の小さな表示。画像の URL が無い時と読み込めない間は、買い物袋のアイコンを出す。
struct FavoriteThumbnail: View {
    /// 商品の画像の URL。無ければ nil。
    let imageURL: URL?

    /// 角を丸めた正方形の画像。
    var body: some View {
        AsyncImage(url: imageURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Image(systemName: "bag")
                .font(.title2)
                .foregroundStyle(.tint)
        }
        .frame(width: 56, height: 56)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            if quantity > 1 {
                quantity -= 1
            }
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
