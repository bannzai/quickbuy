import SwiftUI
@testable import QuickBuy

/// App Store に載せるスクリーンショットの 1 枚が写す画面。並びの順がストアに並ぶ順。
///
/// ストアの検索結果では先頭の数枚だけが見えるため、ほかの買い物アプリに無い入口 (ウィジェット) と、確認してから購入画面を開く流れを先に置く。
enum AppStoreScreenshotScreen: CaseIterable {
    /// ホーム画面のウィジェットと、「カートイン」で届く確認の通知。
    case widget
    /// アプリのお気に入りの一覧と、「カートイン」の後の確認。
    case confirmation
    /// ホームの商品の検索。
    case search
    /// 種類と個数を選んでお気に入りに追加する画面。
    case addFavorite
    /// リマインドの通知。
    case reminder
}

/// スクリーンショットの 1 枚の論理の大きさ (pt)。`appStoreScreenshotScale` 倍で、App Store の iPhone 6.9 インチの 1320 x 2868 px になる。
///
/// 大きさの出典: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications の iPhone 6.9" Display の「1320 x 2868 pixels (portrait)」。
/// アプリは iPhone だけに対応する (`TARGETED_DEVICE_FAMILY = 1`) ため、iPad の大きさは作らない。
let appStoreScreenshotSize = CGSize(width: 440, height: 956)

/// スクリーンショットを描く倍率。`appStoreScreenshotSize` と掛けて 1320 x 2868 px にするための値。
let appStoreScreenshotScale: CGFloat = 3

/// App Store のスクリーンショットを作る 1 つの言語と、その言語の画像に出す文字列のうち文字列カタログに無いもの。
///
/// 見出し・補足はストアの画像だけの文言で、見本の名前・種類の選び方の名前は店が決める値のため、どちらも文字列カタログに入れず、言語ごとにここに並べる。
struct AppStoreScreenshotLanguage {
    /// fastlane の `screenshots/` の下のディレクトリの名前。fastlane deliver の言語の名前 (https://docs.fastlane.tools/actions/deliver/ の「Available Language Codes」) で、`fastlane/metadata/` のディレクトリの名前と同じ。
    let directoryName: String
    /// 文言の言語。文字列カタログの言語 (`QuickBuy.xcodeproj` の `knownRegions`) のどれか。
    let locale: Locale
    /// テストが画像の文字を Vision で読む時に渡す言語 (`VNRecognizeTextRequest.recognitionLanguages` の値)。
    let textRecognitionLanguage: String
    /// 画面ごとの、1 枚の上に大きく出す見出し。
    let headlines: [AppStoreScreenshotScreen: String]
    /// 画面ごとの、見出しの下に出す補足。
    let subheadlines: [AppStoreScreenshotScreen: String]
    /// `sampleFavorites()` の並びの位置ごとの、お気に入りの名前と、商品バリアントの名前のうちこの言語に替える部分。nil は `sampleFavorites()` の値 (日本語) をそのまま出す。
    ///
    /// 日本語の名前から引く表にせず並びの位置で対応させるのは、日本語の名前を `sampleFavorites()` とこの表の 2 か所に書かないため。
    /// 商品バリアントの名前は Shopify が種類の値を「 / 」でつないで作るため、`variantNameParts` は「 / 」で分けた部分の位置 (0 から) ごとに訳を持つ。
    /// 位置の無い部分 (「200g」「1kg」) は言語によらない表記なので、`sampleFavorites()` の値をそのまま出す。
    /// 並びが `sampleFavorites()` と食い違った時は、テスト「見出しと見本の名前は言語ごとに切り替わる」が見つける。
    let favoriteTexts: [(name: String, variantNameParts: [Int: String])]?
    /// 検索の画面 (`.search`) の 2 件目から 4 件目の商品の名前。1 件目は見本のお気に入りの先頭と同じ名前にする。
    let searchProductTitles: [String]
    /// 追加の画面 (`.addFavorite`) の「種類を選ぶ」に出す、種類の選び方の名前の見本。
    let optionName: String
    /// 一覧の画面の `EditButton` の文言 (iOS が言語ごとに出す文言で、文字列カタログに無い)。
    let editButtonTitle: String
}

/// スクリーンショットを作る言語。並びは `.github/workflows/store-screenshots.yml` が枚数を確かめる言語の一覧と同じ。
///
/// 見出しと補足は、紹介ページ (docs/index.html) と documents/PROJECT.md「体験の流れ」に合わせた日本語を基準に訳す。
/// 確認に答えてから購入画面が開くこと、支払いは本人が店の画面で行うことと食い違う言い方 (「ワンタップ」「自動で買う」) をしない。
/// 短い文言のため句読点を使わず改行で区切る (~/.claude/rules/coding-rules-general-user-facing-short-copy-punctuation.md)。
/// 見本の商品の名前と種類の値は、その言語の店が付けそうな名前として agent が決めた。
let appStoreScreenshotLanguages: [AppStoreScreenshotLanguage] = [
    AppStoreScreenshotLanguage(
        directoryName: "ja",
        locale: Locale(identifier: "ja"),
        textRecognitionLanguage: "ja-JP",
        headlines: [
            .widget: "いつもの商品を\nホーム画面から買い直す",
            .confirmation: "確認に答えると\n購入画面が開く",
            .search: "買い直す物を\n店の商品から探す",
            .addFavorite: "種類と個数を選んで\nお気に入りに",
            .reminder: "買う頃になったら\n通知で知らせる",
        ],
        subheadlines: [
            .widget: "確認の通知から店の購入画面へ",
            .confirmation: "支払いの確定は毎回あなたが店の画面で",
            .search: "Shopify の店の商品に対応",
            .addFavorite: "追加しただけでは購入されません",
            .reminder: "お気に入りごとに日数を決められます",
        ],
        favoriteTexts: nil,
        searchProductTitles: ["深煎り 200g", "浅煎り 200g", "デカフェ 150g"],
        optionName: "内容量",
        editButtonTitle: "編集"
    ),
    AppStoreScreenshotLanguage(
        directoryName: "en-US",
        locale: Locale(identifier: "en"),
        textRecognitionLanguage: "en-US",
        headlines: [
            .widget: "Rebuy your usual items\nfrom the Home Screen",
            .confirmation: "Confirm and\nyour checkout opens",
            .search: "Find the things\nyou buy again",
            .addFavorite: "Pick the variant\nand quantity",
            .reminder: "Get a reminder\nwhen it's time to rebuy",
        ],
        subheadlines: [
            .widget: "A confirmation opens the store's checkout",
            .confirmation: "You confirm payment in the store every time",
            .search: "Works with Shopify stores",
            .addFavorite: "Adding doesn't buy anything",
            .reminder: "Set the number of days for each favorite",
        ],
        favoriteTexts: [("Coffee beans", [1: "Whole bean"]), ("Laundry soap", [:]), ("Protein", [:])],
        searchProductTitles: ["Dark Roast 200g", "Light Roast 200g", "Decaf 150g"],
        optionName: "Size",
        editButtonTitle: "Edit"
    ),
    AppStoreScreenshotLanguage(
        directoryName: "es-ES",
        locale: Locale(identifier: "es"),
        textRecognitionLanguage: "es-ES",
        headlines: [
            .widget: "Recompra lo de siempre\ndesde el inicio",
            .confirmation: "Al confirmar se abre\nel pago de la tienda",
            .search: "Busca lo que\nvuelves a comprar",
            .addFavorite: "Elige la variante\ncon su cantidad",
            .reminder: "Te avisa cuando toca\nvolver a comprar",
        ],
        subheadlines: [
            .widget: "De la notificación al pago de la tienda",
            .confirmation: "Siempre confirmas tú el pago en la tienda",
            .search: "Compatible con tiendas Shopify",
            .addFavorite: "Añadir no realiza ninguna compra",
            .reminder: "Elige los días de cada favorito",
        ],
        favoriteTexts: [("Café en grano", [1: "Grano entero"]), ("Jabón para ropa", [:]), ("Proteína", [:])],
        searchProductTitles: ["Tueste oscuro 200g", "Tueste claro 200g", "Descafeinado 150g"],
        optionName: "Contenido",
        editButtonTitle: "Editar"
    ),
    AppStoreScreenshotLanguage(
        directoryName: "fr-FR",
        locale: Locale(identifier: "fr"),
        textRecognitionLanguage: "fr-FR",
        headlines: [
            .widget: "Rachetez l'habituel\ndepuis l'écran d'accueil",
            .confirmation: "Confirmez et\nle paiement s'ouvre",
            .search: "Trouvez ce que\nvous rachetez",
            .addFavorite: "Choisissez la variante\net la quantité",
            .reminder: "Un rappel quand il est\ntemps de racheter",
        ],
        subheadlines: [
            .widget: "De la notification au paiement de la boutique",
            .confirmation: "Vous validez toujours le paiement en boutique",
            .search: "Compatible avec les boutiques Shopify",
            .addFavorite: "Ajouter ne déclenche aucun achat",
            .reminder: "Choisissez le nombre de jours par favori",
        ],
        favoriteTexts: [("Café en grains", [1: "Grains entiers"]), ("Savon à lessive", [:]), ("Protéines", [:])],
        searchProductTitles: ["Café corsé 200g", "Café doux 200g", "Décaféiné 150g"],
        optionName: "Contenance",
        editButtonTitle: "Modifier"
    ),
    AppStoreScreenshotLanguage(
        directoryName: "de-DE",
        locale: Locale(identifier: "de"),
        textRecognitionLanguage: "de-DE",
        headlines: [
            .widget: "Nachkaufen direkt\nvom Home-Bildschirm",
            .confirmation: "Bestätigen und\ndie Kasse öffnet sich",
            .search: "Produkte zum\nNachkaufen finden",
            .addFavorite: "Variante und\nMenge wählen",
            .reminder: "Rechtzeitig an den\nNachkauf erinnert",
        ],
        subheadlines: [
            .widget: "Von der Mitteilung zur Kasse des Shops",
            .confirmation: "Die Zahlung bestätigst du immer im Shop",
            .search: "Für Produkte aus Shopify-Shops",
            .addFavorite: "Hinzufügen kauft noch nichts",
            .reminder: "Tage für jeden Favoriten festlegen",
        ],
        favoriteTexts: [("Kaffee", [1: "Ganze Bohnen"]), ("Waschseife", [:]), ("Protein", [:])],
        searchProductTitles: ["Dunkle Röstung 200g", "Helle Röstung 200g", "Entkoffeiniert 150g"],
        optionName: "Inhalt",
        editButtonTitle: "Bearbeiten"
    ),
    AppStoreScreenshotLanguage(
        directoryName: "pt-BR",
        locale: Locale(identifier: "pt-BR"),
        textRecognitionLanguage: "pt-BR",
        headlines: [
            .widget: "Recompre o de sempre\nna Tela de Início",
            .confirmation: "Confirme e o pagamento\nda loja se abre",
            .search: "Encontre o que\nvocê compra de novo",
            .addFavorite: "Escolha a variante\ne a quantidade",
            .reminder: "Um aviso na hora\nde comprar de novo",
        ],
        subheadlines: [
            .widget: "Da notificação ao pagamento da loja",
            .confirmation: "Você sempre confirma o pagamento na loja",
            .search: "Funciona com lojas Shopify",
            .addFavorite: "Adicionar não faz nenhuma compra",
            .reminder: "Defina os dias de cada favorito",
        ],
        favoriteTexts: [("Café", [1: "Grãos inteiros"]), ("Sabão em pó", [:]), ("Proteína", [:])],
        searchProductTitles: ["Torra escura 200g", "Torra clara 200g", "Descafeinado 150g"],
        optionName: "Conteúdo",
        editButtonTitle: "Editar"
    ),
    AppStoreScreenshotLanguage(
        directoryName: "ko",
        locale: Locale(identifier: "ko"),
        textRecognitionLanguage: "ko-KR",
        headlines: [
            .widget: "늘 사던 상품을\n홈 화면에서 다시 구매",
            .confirmation: "확인하면\n결제 화면이 열림",
            .search: "다시 살 상품을\n스토어에서 찾기",
            .addFavorite: "옵션과 수량을 골라\n즐겨찾기에",
            .reminder: "살 때가 되면\n알림으로 안내",
        ],
        subheadlines: [
            .widget: "확인 알림에서 스토어 결제 화면으로",
            .confirmation: "결제 확정은 매번 스토어 화면에서 직접",
            .search: "Shopify 스토어 상품 지원",
            .addFavorite: "추가만으로는 구매되지 않습니다",
            .reminder: "즐겨찾기마다 일수를 정할 수 있습니다",
        ],
        favoriteTexts: [("원두", [1: "홀빈"]), ("세탁 비누", [:]), ("프로틴", [:])],
        searchProductTitles: ["다크 로스트 200g", "라이트 로스트 200g", "디카페인 150g"],
        optionName: "용량",
        editButtonTitle: "편집"
    ),
    AppStoreScreenshotLanguage(
        directoryName: "zh-Hans",
        locale: Locale(identifier: "zh-Hans"),
        textRecognitionLanguage: "zh-Hans",
        headlines: [
            .widget: "常买的商品\n在主屏幕上再次购买",
            .confirmation: "确认之后\n打开结账页面",
            .search: "在店铺商品中\n查找要回购的商品",
            .addFavorite: "选好款式和数量\n加入收藏",
            .reminder: "该买的时候\n用通知提醒你",
        ],
        subheadlines: [
            .widget: "从确认通知进入店铺的结账页面",
            .confirmation: "每次都由你在店铺页面确认付款",
            .search: "支持 Shopify 店铺的商品",
            .addFavorite: "仅添加不会购买",
            .reminder: "可为每个收藏设置天数",
        ],
        favoriteTexts: [("咖啡豆", [1: "整豆"]), ("洗衣皂", [:]), ("蛋白粉", [:])],
        searchProductTitles: ["深烘 200g", "浅烘 200g", "低因 150g"],
        optionName: "净含量",
        editButtonTitle: "编辑"
    ),
    AppStoreScreenshotLanguage(
        directoryName: "zh-Hant",
        locale: Locale(identifier: "zh-Hant"),
        textRecognitionLanguage: "zh-Hant",
        headlines: [
            .widget: "常買的商品\n在主畫面上再次購買",
            .confirmation: "確認之後\n開啟結帳頁面",
            .search: "在商店商品中\n尋找要回購的商品",
            .addFavorite: "選好款式和數量\n加入收藏",
            .reminder: "該買的時候\n用通知提醒你",
        ],
        subheadlines: [
            .widget: "從確認通知前往商店的結帳頁面",
            .confirmation: "每次都由你在商店頁面確認付款",
            .search: "支援 Shopify 商店的商品",
            .addFavorite: "僅加入不會購買",
            .reminder: "可為每個收藏設定天數",
        ],
        favoriteTexts: [("咖啡豆", [1: "原豆"]), ("洗衣皂", [:]), ("蛋白粉", [:])],
        searchProductTitles: ["深焙 200g", "淺焙 200g", "低因 150g"],
        optionName: "容量",
        editButtonTitle: "編輯"
    ),
]

/// 1 枚のファイル名を返す。deliver は名前の順に並べるため、先頭に並びの番号を付ける。
func appStoreScreenshotFileName(screen: AppStoreScreenshotScreen) -> String {
    String(format: "%02d_%@.png", AppStoreScreenshotScreen.allCases.firstIndex(of: screen)! + 1, "\(screen)")
}

/// `locale` のスクリーンショットの言語を返す。`appStoreScreenshotLanguages` に無い locale を渡すのは呼び出しの誤りのため、止める。
private func appStoreScreenshotLanguage(locale: Locale) -> AppStoreScreenshotLanguage {
    appStoreScreenshotLanguages.first { $0.locale == locale }!
}

/// 1 枚の上に大きく出す見出しを `locale` の言語で返す。
func appStoreScreenshotHeadline(screen: AppStoreScreenshotScreen, locale: Locale) -> String {
    appStoreScreenshotLanguage(locale: locale).headlines[screen]!
}

/// 見出しの下に出す補足を `locale` の言語で返す。
func appStoreScreenshotSubheadline(screen: AppStoreScreenshotScreen, locale: Locale) -> String {
    appStoreScreenshotLanguage(locale: locale).subheadlines[screen]!
}

/// スクリーンショットに写す見本のお気に入りを返す。開発者メニューの見本 (`sampleFavorites()`) の名前と商品バリアントの名前を `locale` の言語にし、`now` から見て状態の違うリマインドを付けたもの。
func appStoreScreenshotFavorites(locale: Locale, now: Date) -> [Favorite] {
    sampleFavorites().enumerated().map { favoriteIndex, favorite in
        var screenshotFavorite = favorite
        if let favoriteText = appStoreScreenshotLanguage(locale: locale).favoriteTexts?[favoriteIndex] {
            screenshotFavorite.name = favoriteText.name
            screenshotFavorite.variantName = favorite.variantName.map { japaneseVariantName in
                japaneseVariantName.components(separatedBy: " / ").enumerated().map { partIndex, japanesePart in
                    favoriteText.variantNameParts[partIndex] ?? japanesePart
                }.joined(separator: " / ")
            }
        }
        screenshotFavorite.reminder = ([
            // 2 日前に数え始めた 7 日ごとのリマインド。一覧で「次の知らせは 5 日後」を出す。
            Reminder(intervalDays: 7, countedFrom: now.addingTimeInterval(-2 * reminderDaySeconds)),
            nil,
            // 30 日前に数え始めた 30 日ごとのリマインド。一覧で「そろそろ買う頃」を出す。
            Reminder(intervalDays: 30, countedFrom: now.addingTimeInterval(-30 * reminderDaySeconds)),
        ] as [Reminder?])[favoriteIndex]
        return screenshotFavorite
    }
}

/// 追加の画面 (`.addFavorite`) の「種類を選ぶ」に出す、種類の選び方の名前の見本を `locale` の言語で返す。店が決める値で、選べる値は見本のお気に入りの商品バリアントの名前の先頭の部分 (「200g」)。
func appStoreScreenshotOptionName(locale: Locale) -> String {
    appStoreScreenshotLanguage(locale: locale).optionName
}

/// 一覧の画面の `EditButton` の文言を `locale` の言語で返す。
func appStoreScreenshotEditButtonTitle(locale: Locale) -> String {
    appStoreScreenshotLanguage(locale: locale).editButtonTitle
}

/// 検索の画面 (`.search`) に並べる見本の商品を、Global Catalog の検索の結果の形で `locale` の言語にして返す。
///
/// 先頭は見本のお気に入りの先頭と同じ名前と店の商品で、追加の画面 (`.addFavorite`) はこの商品の価格を出す (検索の結果から追加の画面を開く流れに合わせる)。
/// 店のドメインは実在しない `.example` (RFC 2606 の予約済みのドメイン)。価格は、200g 前後のコーヒー豆として不自然でない値として agent が決めた見本の値。
func appStoreScreenshotSearchProducts(locale: Locale) -> [ShopifyCatalogProduct] {
    zip(
        [appStoreScreenshotFavorites(locale: locale, now: .now)[0].name] + appStoreScreenshotLanguage(locale: locale).searchProductTitles,
        [
            (shopDomainText(favorite: sampleFavorites()[0]), 1480),
            (shopDomainText(favorite: sampleFavorites()[0]), 1280),
            ("hoshi-roast.example", 1350),
            ("hoshi-roast.example", 1200),
        ] as [(shopDomain: String, priceAmount: Int)]
    ).map { title, sampleShop in
        ShopifyCatalogProduct(
            id: "gid://shopify/p/\(title)",
            title: title,
            description: nil,
            media: nil,
            options: nil,
            selected: nil,
            variants: [
                ShopifyCatalogVariant(
                    id: "gid://shopify/ProductVariant/\(sampleShop.priceAmount)",
                    title: title,
                    price: ShopifyCatalogMoney(amount: sampleShop.priceAmount, currency: "JPY"),
                    availability: nil,
                    seller: ShopifyCatalogVariant.Seller(url: "https://\(sampleShop.shopDomain)")
                ),
            ]
        )
    }
}

/// 強調の色 `quickBuyAccentColor` を、白 (`white` が 1) か黒 (`white` が 0) へ `fraction` の割合だけ寄せた色を返す。
///
/// スクリーンショットの地と壁紙を強調の色と同じ色味にするため、色の値を別に持たず強調の色から作る。
private func appStoreScreenshotAccentColor(white: CGFloat, fraction: CGFloat) -> Color {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    UIColor(quickBuyAccentColor).getRed(&red, green: &green, blue: &blue, alpha: nil)
    return Color(
        red: Double(red + (white - red) * fraction),
        green: Double(green + (white - green) * fraction),
        blue: Double(blue + (white - blue) * fraction)
    )
}

/// 文字列カタログの文言を `locale` の言語で返す。
private func localized(key: String.LocalizationValue, locale: Locale) -> String {
    String(localized: LocalizedStringResource(key, locale: locale))
}

/// スクリーンショットの地の色。強調の色と同じ色味の、ごく薄い色にして、見出しの強調の色を目立たせる。
///
/// 0.9 は、白い行や通知と見分けが付く範囲で最も薄くした割合 (PR #60 で目視して決めた地の色 `#E6F2EC` とほぼ同じ色になる)。
let appStoreScreenshotBackgroundColor = appStoreScreenshotAccentColor(white: 1, fraction: 0.9)

/// ホーム画面とロック画面の壁紙の色。強調の色と同じ色味の暗い色にして、白いウィジェットと通知を目立たせる。
///
/// 0.45 は、ウィジェットの中の強調の色のボタンより暗くなる割合 (PR #60 で目視して決めた壁紙の色 `#0A3D2E` とほぼ同じ色になる)。
let appStoreScreenshotWallpaperColor = appStoreScreenshotAccentColor(white: 0, fraction: 0.45)

/// `sampleFavorites()` の並びの位置ごとに、商品の画像の代わりに出す SF Symbols の名前。
private let appStoreScreenshotFavoriteSymbols = ["cup.and.saucer.fill", "bubbles.and.sparkles.fill", "dumbbell.fill"]

/// App Store のスクリーンショットの 1 枚。上に見出しと補足、下に端末の枠と画面を描く。
struct AppStoreScreenshotPage: View {
    /// 写す画面。
    let screen: AppStoreScreenshotScreen
    /// 文言の言語。
    let locale: Locale
    /// 画面に出す日時。リマインドの残りの日数の計算に使う。
    let now: Date

    /// 1 枚の全体。
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text(appStoreScreenshotHeadline(screen: screen, locale: locale))
                    .font(.system(size: 33, weight: .heavy))
                    .foregroundStyle(quickBuyAccentColor)
                Text(appStoreScreenshotSubheadline(screen: screen, locale: locale))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(white: 0.3))
            }
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            // 縦に必要な分だけ広げる。付けないと `ImageRenderer` が 2 行の見出しを 1 行に切り詰める (2026-11-20 に PR #60 の CI で描いた画像で確かめた)。
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 32)
            AppStoreScreenshotDevice(screen: screen, locale: locale, now: now)
        }
        .frame(width: appStoreScreenshotSize.width, height: appStoreScreenshotSize.height, alignment: .top)
        .background(appStoreScreenshotBackgroundColor)
        .clipped()
        .environment(\.locale, locale)
        .environment(\.colorScheme, .light)
    }
}

/// 端末の枠と、その中の画面。
private struct AppStoreScreenshotDevice: View {
    /// 写す画面。
    let screen: AppStoreScreenshotScreen
    /// 文言の言語。
    let locale: Locale
    /// 画面に出す日時。
    let now: Date

    /// 枠と画面。
    var body: some View {
        content
            .frame(width: 350, height: 710, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 46))
            .padding(10)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 56))
    }

    /// 枠の中に出す画面。
    @ViewBuilder private var content: some View {
        switch screen {
        case .widget:
            AppStoreScreenshotWidgetScreen(favorites: appStoreScreenshotFavorites(locale: locale, now: now), locale: locale)
        case .confirmation:
            AppStoreScreenshotFavoritesScreen(favorites: appStoreScreenshotFavorites(locale: locale, now: now), locale: locale, now: now)
        case .search:
            AppStoreScreenshotSearchScreen(locale: locale)
        case .addFavorite:
            AppStoreScreenshotAddFavoriteScreen(
                favorite: appStoreScreenshotFavorites(locale: locale, now: now)[0],
                searchedProduct: appStoreScreenshotSearchProducts(locale: locale)[0],
                locale: locale
            )
        case .reminder:
            AppStoreScreenshotReminderScreen(favorite: appStoreScreenshotFavorites(locale: locale, now: now)[2], locale: locale)
        }
    }
}

/// 画面の上端の時刻と電池の帯。
private struct AppStoreScreenshotStatusBar: View {
    /// 文字の色。
    let color: Color

    /// 時刻と電池の帯。
    var body: some View {
        HStack {
            Text(verbatim: "9:41").font(.system(size: 15, weight: .semibold))
            Spacer()
            Image(systemName: "battery.100").font(.system(size: 15))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 30)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

/// 商品の画像の代わりに出す、角を丸めた正方形の図形。見本の商品に実在の商品の画像を使わないため。
private struct AppStoreScreenshotThumbnail: View {
    /// 図形の中に出す SF Symbols の名前。
    let systemName: String
    /// 一辺の長さ (pt)。
    let size: CGFloat

    /// 図形。
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42))
            .foregroundStyle(quickBuyAccentColor)
            .frame(width: size, height: size)
            .background(appStoreScreenshotBackgroundColor, in: RoundedRectangle(cornerRadius: size * 0.22))
    }
}

/// 通知の 1 件 (アプリのアイコン・アプリ名・見出し・本文)。ウィジェットの確認の通知とリマインドの通知で使う。
private struct AppStoreScreenshotNotification: View {
    /// 通知の見出し。
    let title: String
    /// 通知の本文。
    let message: String

    /// 角を丸めた白の地に並べた通知。
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cart.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(quickBuyAccentColor, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Quick Buy").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 15, weight: .bold))
                Text(message).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.black)
        .padding(12)
        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 22))
    }
}

/// 一覧やフォームの画面の地の色。アプリが使う `Color(uiColor: .systemGroupedBackground)` の明るい外観の色 (スクリーンショットは描く環境の外観によらず明るい外観で描くため、明るい外観に固定して取り出す)。
let appStoreScreenshotGroupedBackgroundColor = Color(uiColor: UIColor.systemGroupedBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))

/// 「カートイン」のボタン。アプリの一覧 (QuickBuy/ContentView.swift) とウィジェット (QuickBuyWidget/FavoritesWidget.swift) のボタンの見た目に合わせる。
private struct AppStoreScreenshotCartInButton: View {
    /// 文言の言語。
    let locale: Locale

    /// 「カートイン」。
    var body: some View {
        Text(cartInButtonTitle(locale: locale))
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(quickBuyAccentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// ホーム画面のウィジェット (大) と、上から届いた「カートイン」の確認の通知。
private struct AppStoreScreenshotWidgetScreen: View {
    /// ウィジェットに並べるお気に入り。
    let favorites: [Favorite]
    /// 文言の言語。
    let locale: Locale

    /// ホーム画面の全体。
    var body: some View {
        VStack(spacing: 18) {
            AppStoreScreenshotStatusBar(color: .white)
            if let content = cartInConfirmationNotificationContent(favorite: favorites[0], locale: locale) {
                AppStoreScreenshotNotification(title: content.title, message: content.body)
                    .padding(.horizontal, 12)
            }
            iconRow
            widget
                .padding(.horizontal, 18)
            iconRow
            iconRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appStoreScreenshotWallpaperColor)
    }

    /// ほかのアプリのアイコンの代わりの、中身の無い角丸の正方形の 1 列。
    private var iconRow: some View {
        HStack(spacing: 22) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.18)).frame(width: 60, height: 60)
            }
        }
    }

    /// お気に入りの行を並べたウィジェット (QuickBuyWidget/FavoritesWidget.swift の大サイズの行と同じ並びと文言。左は買い物袋のアイコン)。
    private var widget: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized(key: "Quick Buy のお気に入り", locale: locale))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(quickBuyAccentColor)
            ForEach(favorites) { favorite in
                HStack(spacing: 10) {
                    AppStoreScreenshotThumbnail(systemName: "bag", size: 48)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(favorite.name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                        Text(favoriteWidgetRowCaption(favorite: favorite, locale: locale))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    AppStoreScreenshotCartInButton(locale: locale)
                }
            }
        }
        .foregroundStyle(.black)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
}

/// アプリのお気に入りの一覧と、先頭のお気に入りの「カートイン」を押した後の確認 (QuickBuy/ContentView.swift の `FavoritesListView` と同じ並びと文言)。
private struct AppStoreScreenshotFavoritesScreen: View {
    /// 一覧に並べるお気に入り。
    let favorites: [Favorite]
    /// 文言の言語。
    let locale: Locale
    /// リマインドの状態を数える日時。
    let now: Date

    /// お気に入りのタブの全体。
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppStoreScreenshotStatusBar(color: .black)
            HStack(spacing: 18) {
                Image(systemName: "gearshape")
                Text(verbatim: appStoreScreenshotEditButtonTitle(locale: locale))
                Spacer()
                Image(systemName: "plus")
            }
            .font(.system(size: 17))
            .foregroundStyle(quickBuyAccentColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            Text(localized(key: "お気に入り", locale: locale))
                .font(.system(size: 30, weight: .bold))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            VStack(spacing: 10) {
                ForEach(Array(favorites.enumerated()), id: \.element.id) { index, favorite in
                    row(favorite: favorite, systemName: appStoreScreenshotFavoriteSymbols[index])
                }
            }
            .padding(.horizontal, 16)
            Text(localized(key: "「カートイン」の後に「開く」を押すと店の購入画面が開きます\n支払いの確定は店の画面で行います", locale: locale))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            Spacer(minLength: 0)
            confirmation
            AppStoreScreenshotTabBar(locale: locale, selectedTabTitleKey: "お気に入り")
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appStoreScreenshotGroupedBackgroundColor)
    }

    /// お気に入り 1 件の行。`systemName` は商品の画像の代わりに出す SF Symbols の名前。
    private func row(favorite: Favorite, systemName: String) -> some View {
        HStack(spacing: 12) {
            AppStoreScreenshotThumbnail(systemName: systemName, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(favorite.name).font(.system(size: 15, weight: .bold))
                if let variantName = favorite.variantName {
                    Text(variantName).font(.system(size: 13, weight: .bold)).foregroundStyle(quickBuyAccentColor).lineLimit(1).minimumScaleFactor(0.7)
                }
                // アプリの一覧と同じく、長いドメインは中ほどで省き、個数は省かない。
                HStack(spacing: 0) {
                    Text(verbatim: shopDomainText(favorite: favorite))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(localized(key: " ・ \(favorite.quantity) 個", locale: locale))
                        .fixedSize()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                Text(reminderStatusText(reminder: favorite.reminder, now: now, locale: locale))
                    .font(.system(size: 12, weight: favorite.reminder.map { isReminderDue(reminder: $0, now: now) } == true ? .bold : .regular))
                    .foregroundStyle(favorite.reminder.map { isReminderDue(reminder: $0, now: now) } == true ? reminderDueColor : .secondary)
                    // アプリの一覧と同じく、行数を限らず折り返す (縮めると英語の「Next reminder in 5 days」が省かれた)。
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            AppStoreScreenshotCartInButton(locale: locale)
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    /// 先頭のお気に入りの「カートイン」を押した後に画面の下に出る確認。
    private var confirmation: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cartInConfirmationTitle(locale: locale)).font(.system(size: 15, weight: .heavy))
                Text(cartInConfirmationText(favorite: favorites[0], locale: locale))
                    .font(.system(size: 12))
                    .foregroundStyle(cartInConfirmationSecondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(localized(key: "開く", locale: locale))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(cartInConfirmationBackgroundColor)
                .fixedSize()
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(cartInConfirmationBackgroundColor, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// 画面の下端のタブ。QuickBuy/ContentView.swift の `TabView` と同じ名前とアイコンにする。
private struct AppStoreScreenshotTabBar: View {
    /// 文言の言語。
    let locale: Locale
    /// 選んでいるタブの文字列カタログのキー。
    let selectedTabTitleKey: String

    /// 2 つのタブ。
    var body: some View {
        HStack {
            ForEach([("ホーム", "magnifyingglass"), ("お気に入り", "star.fill")], id: \.0) { titleKey, systemName in
                VStack(spacing: 3) {
                    Image(systemName: systemName).font(.system(size: 20))
                    Text(localized(key: String.LocalizationValue(titleKey), locale: locale)).font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(titleKey == selectedTabTitleKey ? quickBuyAccentColor : Color.gray)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(Color(white: 0.98))
    }
}

/// トップページの商品の検索の結果 (QuickBuy/HomeView.swift と同じ並びと文言。検索語を入れた後なので上の案内は出ていない)。
private struct AppStoreScreenshotSearchScreen: View {
    /// 文言の言語。
    let locale: Locale

    /// ホームのタブの全体。
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppStoreScreenshotStatusBar(color: .black)
            Text(verbatim: "Quick Buy")
                .font(.system(size: 30, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(homeSuggestedSearchQueries(locale: locale)[0]).font(.system(size: 16))
                Spacer()
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color(white: 0.89), in: RoundedRectangle(cornerRadius: 11))
            .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 8) {
                Text(localized(key: "買い直す物から探す", locale: locale)).font(.system(size: 16, weight: .semibold))
                HStack(spacing: 8) {
                    ForEach(homeSuggestedSearchQueries(locale: locale), id: \.self) { query in
                        Text(query)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(quickBuyAccentColor)
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(quickBuyAccentColor.opacity(0.14), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            // 横に流れる検索語の並びは、画面の右端で切れる。
            .frame(width: 350, alignment: .leading)
            .clipped()
            Text(localized(key: "「\(homeSuggestedSearchQueries(locale: locale)[0])」の検索結果", locale: locale))
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(appStoreScreenshotSearchProducts(locale: locale), id: \.id) { product in
                    VStack(alignment: .leading, spacing: 5) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(quickBuyAccentColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 104)
                            .background(appStoreScreenshotBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
                        // 店のドメインと価格は、アプリの検索の結果 (QuickBuy/HomeView.swift) と同じ関数で商品から作る。見本の商品はどれも両方を持つ (テスト「見本の店はexampleのドメインだけ」が確かめる)。
                        if let variant = product.variants.first, let shopDomain = shopifyCatalogShopDomain(variant: variant), let price = variant.price {
                            Text(verbatim: shopDomain).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            Text(product.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                            Text(verbatim: shopifyCatalogPriceText(money: price)).font(.system(size: 14))
                        }
                        Text(localized(key: "お気に入り追加", locale: locale))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(quickBuyAccentColor, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appStoreScreenshotGroupedBackgroundColor)
        .overlay(alignment: .bottom) {
            AppStoreScreenshotTabBar(locale: locale, selectedTabTitleKey: "ホーム")
        }
    }
}

/// 検索の結果から開く、種類と個数を選んでお気に入りに追加する画面 (QuickBuy/CatalogAddFavoriteView.swift と同じ並びと文言)。
private struct AppStoreScreenshotAddFavoriteScreen: View {
    /// 追加するお気に入り (名前・商品バリアントの名前・個数・店を出す)。種類を選ぶ画面を写すため、商品バリアントの名前を持つものを渡す (持たない時は画像を描くテストが落ちる)。
    let favorite: Favorite
    /// 検索の結果で押した商品 (価格を出す)。
    let searchedProduct: ShopifyCatalogProduct
    /// 文言の言語。
    let locale: Locale

    /// お気に入りに追加する画面の全体。
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppStoreScreenshotStatusBar(color: .black)
            ZStack {
                Text(localized(key: "お気に入りに追加", locale: locale)).font(.system(size: 16, weight: .semibold))
                HStack {
                    Text(localized(key: "やめる", locale: locale)).font(.system(size: 16)).foregroundStyle(quickBuyAccentColor)
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            VStack(alignment: .leading, spacing: 5) {
                Text(localized(key: "この店の商品です", locale: locale)).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(verbatim: shopDomainText(favorite: favorite)).font(.system(size: 21, weight: .bold))
                Text(localized(key: "いつも買っている店か確かめてください", locale: locale)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(quickBuyAccentColor, lineWidth: 2))
            .padding(.horizontal, 16)
            HStack(spacing: 12) {
                AppStoreScreenshotThumbnail(systemName: appStoreScreenshotFavoriteSymbols[0], size: 52)
                Text(favorite.name).font(.system(size: 16))
                Spacer()
            }
            .padding(10)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            section(headerKey: "種類を選ぶ") {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(verbatim: appStoreScreenshotOptionName(locale: locale)).font(.system(size: 15))
                        Spacer()
                        Text(verbatim: favorite.variantName!.components(separatedBy: " / ")[0]).font(.system(size: 15)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(height: 40)
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(favorite.variantName!).font(.system(size: 14))
                        if let price = searchedProduct.variants.first?.price {
                            Text(verbatim: shopifyCatalogPriceText(money: price)).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 46)
                    Divider()
                    HStack {
                        Text(localized(key: "個数", locale: locale)).font(.system(size: 15))
                        Spacer()
                        Text(localized(key: "\(favorite.quantity) 個", locale: locale)).font(.system(size: 15))
                        // `Stepper` の増減のボタン。
                        HStack(spacing: 14) {
                            Image(systemName: "minus")
                            Divider().frame(height: 16)
                            Image(systemName: "plus")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Color(white: 0.92), in: Capsule())
                    }
                    .frame(height: 46)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(shopifyCatalogAdditionButtonTitle(isSaved: false, locale: locale))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(quickBuyAccentColor, in: RoundedRectangle(cornerRadius: 12))
                Text(localized(key: "追加しただけでは購入されません\n定期購入だけの商品は購入画面を開けず店のトップページが開きます", locale: locale))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appStoreScreenshotGroupedBackgroundColor)
    }

    /// フォームの 1 つのまとまり。小さい見出し (文字列カタログのキー `headerKey` の文言) の下に、白い角丸の地で `content` を出す。
    private func section(headerKey: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(localized(key: String.LocalizationValue(headerKey), locale: locale))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
    }
}

/// ロック画面に届いたリマインドの通知。
private struct AppStoreScreenshotReminderScreen: View {
    /// リマインドの日数が過ぎたお気に入り。
    let favorite: Favorite
    /// 文言の言語。
    let locale: Locale

    /// ロック画面の全体。
    var body: some View {
        VStack(spacing: 0) {
            AppStoreScreenshotStatusBar(color: .white)
            Text(verbatim: "9:41")
                .font(.system(size: 88, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 20)
                .padding(.bottom, 60)
            AppStoreScreenshotNotification(
                title: reminderNotificationContent(favorite: favorite, locale: locale).title,
                message: reminderNotificationContent(favorite: favorite, locale: locale).body
            )
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(appStoreScreenshotWallpaperColor)
    }
}
