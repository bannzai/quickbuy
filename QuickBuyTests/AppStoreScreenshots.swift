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

/// スクリーンショットを作る言語と、fastlane の `screenshots/` の下のディレクトリの名前の組。
///
/// ディレクトリの名前は fastlane deliver の言語の名前 (https://docs.fastlane.tools/actions/deliver/ の「Available Language Codes」の `ja`・`en-US`)。
let appStoreScreenshotLanguages: [(directoryName: String, locale: Locale)] = [
    ("ja", Locale(identifier: "ja")),
    ("en-US", Locale(identifier: "en")),
]

/// 1 枚のファイル名を返す。deliver は名前の順に並べるため、先頭に並びの番号を付ける。
func appStoreScreenshotFileName(screen: AppStoreScreenshotScreen) -> String {
    String(format: "%02d_%@.png", AppStoreScreenshotScreen.allCases.firstIndex(of: screen)! + 1, "\(screen)")
}

/// `locale` が日本語か。スクリーンショットの見出しと見本の商品の名前を選ぶのに使う。
private func isJapanese(locale: Locale) -> Bool {
    locale.language.languageCode == .japanese
}

/// 1 枚の上に大きく出す見出しを `locale` の言語で返す。
///
/// 紹介ページ (docs/index.html) と documents/PROJECT.md「体験の流れ」に合わせる。確認に答えてから購入画面が開くこと、支払いは本人が店の画面で行うことと食い違う言い方 (「ワンタップ」「自動で買う」) をしない。
/// 短い文言のため句読点を使わず改行で区切る (~/.claude/rules/coding-rules-general-user-facing-short-copy-punctuation.md)。
func appStoreScreenshotHeadline(screen: AppStoreScreenshotScreen, locale: Locale) -> String {
    switch (screen, isJapanese(locale: locale)) {
    case (.widget, true): "いつもの商品を\nホーム画面から買い直す"
    case (.widget, false): "Rebuy your usual items\nfrom the Home Screen"
    case (.confirmation, true): "確認に答えると\n購入画面が開く"
    case (.confirmation, false): "Confirm and\nyour checkout opens"
    case (.search, true): "買い直す物を\n店の商品から探す"
    case (.search, false): "Find the things\nyou buy again"
    case (.addFavorite, true): "種類と個数を選んで\nお気に入りに"
    case (.addFavorite, false): "Pick the variant\nand quantity"
    case (.reminder, true): "買う頃になったら\n通知で知らせる"
    case (.reminder, false): "Get a reminder\nwhen it's time to rebuy"
    }
}

/// 見出しの下に出す補足を `locale` の言語で返す。句読点の扱いは `appStoreScreenshotHeadline(screen:locale:)` と同じ。
func appStoreScreenshotSubheadline(screen: AppStoreScreenshotScreen, locale: Locale) -> String {
    switch (screen, isJapanese(locale: locale)) {
    case (.widget, true): "確認の通知から店の購入画面へ"
    case (.widget, false): "A confirmation opens the store's checkout"
    case (.confirmation, true): "支払いの確定は毎回あなたが店の画面で"
    case (.confirmation, false): "You confirm payment in the store every time"
    case (.search, true): "Shopify の店と Amazon の商品に対応"
    case (.search, false): "Works with Shopify stores and Amazon"
    case (.addFavorite, true): "追加しただけでは購入されません"
    case (.addFavorite, false): "Adding doesn't buy anything"
    case (.reminder, true): "お気に入りごとに日数を決められます"
    case (.reminder, false): "Set the number of days for each favorite"
    }
}

/// スクリーンショットに写す見本のお気に入りを返す。開発者メニューの見本 (`sampleFavorites()`) に、`now` から見て状態の違うリマインドを付けたもの。
///
/// 英語のスクリーンショットでは、名前と商品バリアントの名前を英語にする (見本の名前は日本語だけのため)。
func appStoreScreenshotFavorites(locale: Locale, now: Date) -> [Favorite] {
    // 見本の名前と商品バリアントの名前の英語。店が決める値なので文字列カタログには入れず、スクリーンショットだけで使う。
    let englishNames = ["コーヒー豆": "Coffee beans", "洗濯用せっけん": "Laundry soap", "プロテイン": "Protein", "200g / 豆のまま": "200g / Whole bean"]
    return zip(sampleFavorites(), [
        // 2 日前に数え始めた 7 日ごとのリマインド。一覧で「次の知らせは 5 日後」を出す。
        Reminder(intervalDays: 7, countedFrom: now.addingTimeInterval(-2 * reminderDaySeconds)),
        nil,
        // 30 日前に数え始めた 30 日ごとのリマインド。一覧で「そろそろ買う頃」を出す。
        Reminder(intervalDays: 30, countedFrom: now.addingTimeInterval(-30 * reminderDaySeconds)),
    ] as [Reminder?]).map { favorite, reminder in
        var screenshotFavorite = favorite
        if !isJapanese(locale: locale) {
            screenshotFavorite.name = englishNames[favorite.name] ?? favorite.name
            screenshotFavorite.variantName = favorite.variantName.map { englishNames[$0] ?? $0 }
        }
        screenshotFavorite.reminder = reminder
        return screenshotFavorite
    }
}

/// 文字列カタログの文言を `locale` の言語で返す。
private func localized(key: String.LocalizationValue, locale: Locale) -> String {
    String(localized: LocalizedStringResource(key, locale: locale))
}

/// スクリーンショットの地の色。強調の色 `quickBuyAccentColor` (#0B6E4F) を薄くした `#E6F2EC`。
private let appStoreScreenshotBackgroundColor = Color(red: 0xE6 / 255, green: 0xF2 / 255, blue: 0xEC / 255)

/// ホーム画面とロック画面の壁紙の色。強調の色 `quickBuyAccentColor` (#0B6E4F) を暗くした `#0A3D2E`。白いウィジェットと通知を目立たせるため。
private let appStoreScreenshotWallpaperColor = Color(red: 0x0A / 255, green: 0x3D / 255, blue: 0x2E / 255)

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
            AppStoreScreenshotAddFavoriteScreen(favorite: appStoreScreenshotFavorites(locale: locale, now: now)[0], locale: locale)
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

/// 一覧やフォームの画面の地の色。`Color(uiColor: .systemGroupedBackground)` の明るい外観の色 `#F2F2F7`。
private let appStoreScreenshotGroupedBackgroundColor = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)

/// 「カートイン」のボタンの見た目 (強調の色の地に白い太字、角の丸み 10)。アプリの一覧 (QuickBuy/ContentView.swift) とウィジェット (QuickBuyWidget/FavoritesWidget.swift) のボタンに合わせる。
private struct AppStoreScreenshotCartInButton: View {
    /// ボタンが指すお気に入り。
    let favorite: Favorite
    /// 文言の言語。
    let locale: Locale

    /// 「カートイン」(Amazon の商品は「Amazon で開く」)。
    var body: some View {
        Text(cartInButtonTitle(favorite: favorite, locale: locale))
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

    /// 壁紙・確認の通知・ほかのアプリのアイコン・ウィジェット。
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
                    AppStoreScreenshotCartInButton(favorite: favorite, locale: locale)
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

    /// 上のボタン・見出し・一覧・補足・確認・タブ。
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppStoreScreenshotStatusBar(color: .black)
            HStack(spacing: 18) {
                Image(systemName: "gearshape")
                // `EditButton` の文言 (iOS が言語ごとに出す「編集」/「Edit」)。
                Text(verbatim: isJapanese(locale: locale) ? "編集" : "Edit")
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
            Text(localized(key: "「カートイン」の後に「開く」を押すと店の購入画面が開きます\nAmazon の商品は商品ページが開きます\n支払いの確定は店の画面で行います", locale: locale))
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

    /// お気に入り 1 件の行。白い角丸の地に、画像・名前・種類・店と個数・リマインドの状態・「カートイン」。
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
            AppStoreScreenshotCartInButton(favorite: favorite, locale: locale)
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    /// 先頭のお気に入りの「カートイン」を押した後に画面の下に出る確認 (見出し・説明・「開く」)。
    private var confirmation: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cartInConfirmationTitle(favorite: favorites[0], locale: locale)).font(.system(size: 15, weight: .heavy))
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

/// 画面の下端のタブ (「ホーム」と「お気に入り」。QuickBuy/ContentView.swift の `TabView` と同じ名前とアイコン)。
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

    /// 見出し・検索窓・検索語の並び・結果の見出しと商品の 2 列の並び・タブ。
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
                ForEach(searchResults(), id: \.name) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(quickBuyAccentColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 104)
                            .background(appStoreScreenshotBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
                        Text(verbatim: result.shopDomain).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Text(result.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Text(verbatim: result.price).font(.system(size: 14))
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

    /// 検索の結果に並べる見本の商品の名前・店のドメイン・価格。店のドメインは実在しない `.example` (RFC 2606 の予約済みのドメイン) にし、価格も見本の値。
    private func searchResults() -> [(name: String, shopDomain: String, price: String)] {
        isJapanese(locale: locale)
            ? [("いつものブレンド", "mori-coffee.example", "¥1,480"), ("深煎り 200g", "mori-coffee.example", "¥1,280"), ("浅煎り 200g", "hoshi-roast.example", "¥1,350"), ("デカフェ 150g", "hoshi-roast.example", "¥1,200")]
            : [("House Blend", "mori-coffee.example", "¥1,480"), ("Dark Roast 200g", "mori-coffee.example", "¥1,280"), ("Light Roast 200g", "hoshi-roast.example", "¥1,350"), ("Decaf 150g", "hoshi-roast.example", "¥1,200")]
    }
}

/// 検索の結果から開く、種類と個数を選んでお気に入りに追加する画面 (QuickBuy/CatalogAddFavoriteView.swift と同じ並びと文言)。
private struct AppStoreScreenshotAddFavoriteScreen: View {
    /// 追加するお気に入り (名前・商品バリアントの名前・個数・店を出す)。
    let favorite: Favorite
    /// 文言の言語。
    let locale: Locale

    /// 上の「やめる」と見出し・店のドメイン・名前・種類の選び方・選んだ種類と個数・追加のボタン。
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
                        Text(verbatim: isJapanese(locale: locale) ? "内容量" : "Size").font(.system(size: 15))
                        Spacer()
                        Text(verbatim: "200g").font(.system(size: 15)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(height: 40)
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(favorite.variantName ?? "").font(.system(size: 14))
                        Text(verbatim: "¥1,480").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(height: 46)
                    Divider()
                    Text(localized(key: "この種類は選んであります", locale: locale))
                        .font(.system(size: 15))
                        .foregroundStyle(Color.gray)
                        .frame(height: 40)
                }
            }
            section(headerKey: "お気に入りにする種類") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(favorite.variantName ?? "").font(.system(size: 14, weight: .bold))
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
                }
                .padding(.vertical, 8)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(favoriteAdditionButtonTitle(hasVariantChoices: true, selectedVariantCount: 1, locale: locale))
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

    /// 壁紙・時刻・通知。
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
