import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
import Vision
@testable import QuickBuy

/// App Store のスクリーンショットを描いて、App Store が受け付ける形 (1320 x 2868 px・透明の無い PNG) になることと、文言の決まりを確かめる。
///
/// 環境変数 `QUICKBUY_SCREENSHOT_DIR` があれば、描いた画像をその下の `<言語>/<番号>_<画面>.png` に書き出す
/// (`.github/workflows/store-screenshots.yml` が `TEST_RUNNER_QUICKBUY_SCREENSHOT_DIR` で渡す。`TEST_RUNNER_` を付けた環境変数は、付けない名前でテストの実行に渡る)。
@MainActor
struct AppStoreScreenshotTests {
    /// スクリーンショットに出す日時。見本のリマインドの残りの日数がこの日時から決まる。
    ///
    /// 実行した日時で絵が変わらないように固定する。値そのものに意味は無く、リマインドは `appStoreScreenshotFavorites(locale:now:)` が `now` からの日数で作るため、どの日時でも同じ絵になる。
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// 1 枚を描いて、透明の無い PNG にして返す。描けない時は nil。
    ///
    /// `ImageRenderer` の画像は透明を持つことがあり、App Store Connect は透明を持つスクリーンショットを受け付けないため、透明の無い色の形で描き直す。
    private func screenshotPNG(screen: AppStoreScreenshotScreen, locale: Locale) -> Data? {
        let renderer = ImageRenderer(content: AppStoreScreenshotPage(screen: screen, locale: locale, now: now))
        renderer.scale = appStoreScreenshotScale
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage,
              let context = CGContext(
                  data: nil,
                  width: cgImage.width,
                  height: cgImage.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let data = NSMutableData()
        guard let opaqueImage = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else {
            return nil
        }
        CGImageDestinationAddImage(destination, opaqueImage, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// 全部の言語の全部の画面が 1320 x 2868 px の透明の無い PNG になる。書き出し先があれば書き出す。
    @Test func スクリーンショットはAppStoreが受け付ける大きさの透明の無いPNGになる() throws {
        // 書き出し先は 10 枚とも同じなので、ループの外で 1 回だけ環境変数を読む (式に畳むと 1 枚ごとに読み直す)。
        let outputDirectoryURL = ProcessInfo.processInfo.environment["QUICKBUY_SCREENSHOT_DIR"].map { URL(filePath: $0) }
        for language in appStoreScreenshotLanguages {
            for screen in AppStoreScreenshotScreen.allCases {
                let png = try #require(screenshotPNG(screen: screen, locale: language.locale))
                let image = try #require(CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
                #expect(image.width == 1320, "\(language.directoryName) \(screen)")
                #expect(image.height == 2868, "\(language.directoryName) \(screen)")
                #expect([CGImageAlphaInfo.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo), "\(language.directoryName) \(screen)")
                if let outputDirectoryURL {
                    let languageDirectoryURL = outputDirectoryURL.appending(path: language.directoryName)
                    try FileManager.default.createDirectory(at: languageDirectoryURL, withIntermediateDirectories: true)
                    try png.write(to: languageDirectoryURL.appending(path: appStoreScreenshotFileName(screen: screen)))
                }
            }
        }
    }

    /// ファイル名は並びの順の番号から始まり、deliver が名前の順に並べた時にストアの並びと同じ順になる。
    @Test func ファイル名は並びの順の番号から始まる() {
        #expect(AppStoreScreenshotScreen.allCases.map { appStoreScreenshotFileName(screen: $0) } == [
            "01_widget.png", "02_confirmation.png", "03_search.png", "04_addFavorite.png", "05_reminder.png",
        ])
    }

    /// 見出しと補足は、確認してから購入画面が開くことと食い違う言い方をせず、末尾に句読点を付けない。
    @Test func 見出しと補足はワンタップや自動の購入を書かず末尾に句読点を付けない() {
        for language in appStoreScreenshotLanguages {
            for screen in AppStoreScreenshotScreen.allCases {
                for text in [appStoreScreenshotHeadline(screen: screen, locale: language.locale), appStoreScreenshotSubheadline(screen: screen, locale: language.locale)] {
                    #expect(!["ワンタップ", "1 タップ", "１タップ", "自動で買", "自動購入", "one tap", "one-tap", "automatically", "auto-buy"].contains { text.localizedCaseInsensitiveContains($0) }, "\(text)")
                    #expect(!["。", "、", "，", "！", ".", ",", "!"].contains { text.hasSuffix($0) }, "\(text)")
                    #expect(!text.contains("、"), "\(text)")
                }
            }
        }
    }

    /// 日本語のスクリーンショットは日本語、英語のスクリーンショットは英語の見出しと見本の名前になる。
    @Test func 見出しと見本の名前は言語ごとに切り替わる() {
        #expect(appStoreScreenshotHeadline(screen: .confirmation, locale: Locale(identifier: "ja")) == "確認に答えると\n購入画面が開く")
        #expect(appStoreScreenshotHeadline(screen: .confirmation, locale: Locale(identifier: "en")) == "Confirm and\nyour checkout opens")
        #expect(appStoreScreenshotFavorites(locale: Locale(identifier: "ja"), now: now).map(\.name) == ["コーヒー豆", "洗濯用せっけん", "プロテイン"])
        #expect(appStoreScreenshotFavorites(locale: Locale(identifier: "en"), now: now).map(\.name) == ["Coffee beans", "Laundry soap", "Protein"])
        #expect(appStoreScreenshotFavorites(locale: Locale(identifier: "en"), now: now).map(\.variantName) == ["200g / Whole bean", nil, "1kg"])
        #expect(appStoreScreenshotFavorites(locale: Locale(identifier: "ja"), now: now).map(\.variantName) == ["200g / 豆のまま", nil, "1kg"])
        #expect(appStoreScreenshotFavorites(locale: Locale(identifier: "de"), now: now).map(\.name) == ["Kaffeebohnen", "Waschseife", "Protein"])
        #expect(appStoreScreenshotFavorites(locale: Locale(identifier: "de"), now: now).map(\.variantName) == ["200g / Ganze Bohnen", nil, "1kg"])
        #expect(appStoreScreenshotFavorites(locale: Locale(identifier: "ko"), now: now).map(\.name) == ["원두", "세탁 비누", "프로틴"])
        // 日本語のほかの言語は、どの言語も見出しと見本のお気に入りの名前が日本語と違う (訳を入れ忘れた言語が日本語の画像にならない)。
        for language in appStoreScreenshotLanguages where language.directoryName != "ja" {
            #expect(appStoreScreenshotHeadline(screen: .widget, locale: language.locale) != appStoreScreenshotHeadline(screen: .widget, locale: Locale(identifier: "ja")), "\(language.directoryName)")
            #expect(appStoreScreenshotFavorites(locale: language.locale, now: now).map(\.name) != appStoreScreenshotFavorites(locale: Locale(identifier: "ja"), now: now).map(\.name), "\(language.directoryName)")
        }
    }

    /// スクリーンショットの言語は、App Store Connect の言語の 9 つで、fastlane/metadata のディレクトリと同じ名前になる。
    @Test func スクリーンショットの言語は9つ() {
        #expect(appStoreScreenshotLanguages.map(\.directoryName) == ["ja", "en-US", "es-ES", "fr-FR", "de-DE", "pt-BR", "ko", "zh-Hans", "zh-Hant"])
    }

    /// 見本のリマインドは、一覧で残りの日数・知らせなし・買う頃の 3 つの状態を 1 件ずつ出す。
    @Test func 見本のリマインドは3つの状態を出す() {
        #expect(appStoreScreenshotFavorites(locale: Locale(identifier: "ja"), now: now).map { reminderStatusText(reminder: $0.reminder, now: now, locale: Locale(identifier: "ja")) } == [
            "次の知らせは 5 日後", "知らせなし", "そろそろ買う頃",
        ])
    }

    /// 見本の店は実在しない `.example` のドメインだけにする (実在の店の名前をストアの画像に出さない)。お気に入りの店と、検索の画面に並べる商品の店の両方を見る。
    @Test func 見本の店はexampleのドメインだけ() {
        for language in appStoreScreenshotLanguages {
            for favorite in appStoreScreenshotFavorites(locale: language.locale, now: now) {
                #expect(shopDomainText(favorite: favorite).hasSuffix(".example"))
            }
            // 店のドメインか価格を読めない商品は検索の画面の行が空になるため、4 件とも両方を読めることも確かめる。
            #expect(appStoreScreenshotSearchProducts(locale: language.locale).map { $0.variants.first.flatMap { shopifyCatalogShopDomain(variant: $0) } } == [
                "mori-coffee.example", "mori-coffee.example", "hoshi-roast.example", "hoshi-roast.example",
            ])
            #expect(appStoreScreenshotSearchProducts(locale: language.locale).map { $0.variants.first?.price.map { shopifyCatalogPriceText(money: $0) } } == [
                "¥1,480", "¥1,280", "¥1,350", "¥1,200",
            ])
        }
    }

    /// 画像に写った店のドメインの形の文字列は、どれも `.example` で終わる (画面のコードに直に書いた店のドメインも見つける)。
    @Test func 画像に写る店のドメインはexampleだけ() throws {
        for language in appStoreScreenshotLanguages {
            for screen in AppStoreScreenshotScreen.allCases {
                for domainText in try recognizedText(screen: screen, language: language).lowercased().matches(of: #/[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}/#).map(\.output.0) {
                    #expect(domainText.hasSuffix(".example"), "\(language.directoryName) \(screen) \(domainText)")
                }
            }
            // 店のドメインを読めていること (読めない認識では上の確認が何も見ない)。
            #expect(try recognizedText(screen: .search, language: language).lowercased().contains("mori-coffee.example"), "\(language.directoryName)")
        }
    }

    /// 日本語のほかの言語の見本の文字列 (お気に入りの名前・商品バリアントの名前・検索の商品の名前・種類の選び方の名前・編集のボタン) に仮名が残らず、中国語のほかは漢字も残らない。
    @Test func 日本語のほかの言語の見本の文字列に日本語が残らない() {
        for language in appStoreScreenshotLanguages where language.directoryName != "ja" {
            for text in appStoreScreenshotFavorites(locale: language.locale, now: now).flatMap({ [$0.name, $0.variantName ?? ""] })
                + appStoreScreenshotSearchProducts(locale: language.locale).map(\.title)
                + [appStoreScreenshotOptionName(locale: language.locale), appStoreScreenshotEditButtonTitle(locale: language.locale)]
            {
                #expect(!containsKana(text: text), "\(language.directoryName) \(text)")
                if language.locale.language.languageCode != .chinese {
                    #expect(!containsJapanese(text: text), "\(language.directoryName) \(text)")
                }
            }
        }
        #expect(appStoreScreenshotSearchProducts(locale: Locale(identifier: "en")).map(\.title) == ["Coffee beans", "Dark Roast 200g", "Light Roast 200g", "Decaf 150g"])
        #expect(appStoreScreenshotSearchProducts(locale: Locale(identifier: "ja")).map(\.title) == ["コーヒー豆", "深煎り 200g", "浅煎り 200g", "デカフェ 150g"])
        #expect(appStoreScreenshotOptionName(locale: Locale(identifier: "en")) == "Size")
        #expect(appStoreScreenshotOptionName(locale: Locale(identifier: "ja")) == "内容量")
    }

    /// ラテン文字の言語 (英語・スペイン語・フランス語・ドイツ語・ポルトガル語) のスクリーンショットの画像には日本語の文字が写らず、日本語のスクリーンショットの画像には写る (画面のコードに直に書いた文言も見る)。
    ///
    /// 韓国語と中国語の画像は、日本語の文字の認識で読むとハングルと漢字を日本語の文字と見分けられないため、この画像の確認から外す。
    /// 2 つの言語の文言に日本語が残っていないことは、文字列カタログの検査 (translate-app-xcstrings skill の `check` の「原文の言語の文字の残り」) と、テスト「日本語のほかの言語の見本の文字列に日本語が残らない」で確かめる。
    @Test func ラテン文字の言語の画像に日本語の文字が写らない() throws {
        let japaneseRecognitionLanguages = ["ja-JP", "en-US"]
        for language in appStoreScreenshotLanguages where ![.japanese, .korean, .chinese].contains(language.locale.language.languageCode) {
            for screen in AppStoreScreenshotScreen.allCases {
                let japaneseLines = try recognizedText(screen: screen, locale: language.locale, recognitionLanguages: japaneseRecognitionLanguages)
                    .split(separator: "\n")
                    .filter { containsRecognizedJapanese(text: String($0)) }
                #expect(japaneseLines.isEmpty, "\(language.directoryName) \(screen) \(japaneseLines)")
            }
        }
        for screen in AppStoreScreenshotScreen.allCases {
            // 日本語を読めていること (読めない認識では上の確認が何も見ない)。
            #expect(try containsRecognizedJapanese(text: recognizedText(screen: screen, locale: Locale(identifier: "ja"), recognitionLanguages: japaneseRecognitionLanguages)), "\(screen)")
        }
    }

    /// 一覧の画面の「編集」は iOS の `EditButton` の文言で文字列カタログに無いため、言語ごとの文言が画像に写ることを確かめる (2 文字の「編集」は、テスト「ラテン文字の言語の画像に日本語の文字が写らない」では見つからない)。
    @Test func 編集のボタンは言語ごとの文言で画像に写る() throws {
        for language in appStoreScreenshotLanguages {
            let text = try recognizedText(screen: .confirmation, language: language)
            #expect(comparableText(text: text).contains(comparableText(text: appStoreScreenshotEditButtonTitle(locale: language.locale))), "\(language.directoryName) \(text)")
            if language.directoryName != "ja" {
                #expect(!text.contains("編集"), "\(language.directoryName) \(text)")
            }
        }
    }

    /// 追加の画面には、見本のお気に入りの種類の値 (「200g」) が種類の選び方・商品バリアントの名前の 2 か所に、検索の先頭の商品の価格 (「¥1,480」) が 1 か所に写る。
    @Test func 追加の画面に種類の値と価格が写る() throws {
        for language in appStoreScreenshotLanguages {
            let text = try comparableText(text: recognizedText(screen: .addFavorite, language: language))
            #expect(text.components(separatedBy: "200g").count - 1 == 2, "\(language.directoryName) \(text)")
            #expect(text.components(separatedBy: "1480").count - 1 == 1, "\(language.directoryName) \(text)")
        }
    }

    /// 地・壁紙・一覧の地の色は、PR #60 で目視して決めた色 (`#E6F2EC`・`#0A3D2E`) と、iOS の明るい外観の `systemGroupedBackground` (`#F2F2F7`) から、見分けが付かない範囲にある。
    @Test func 地と壁紙の色は決めた色から離れない() {
        for (color, red, green, blue) in [
            (appStoreScreenshotBackgroundColor, 0xE6, 0xF2, 0xEC),
            (appStoreScreenshotWallpaperColor, 0x0A, 0x3D, 0x2E),
            (appStoreScreenshotGroupedBackgroundColor, 0xF2, 0xF2, 0xF7),
        ] {
            var components: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0, 0, 0)
            UIColor(color).getRed(&components.red, green: &components.green, blue: &components.blue, alpha: nil)
            // 0.02 (255 段階の 5 段階) は、並べて見ても色の差が分からなかった範囲 (run 44918156487 の画像と PR #60 の画像の目視)。
            #expect(abs(components.red - CGFloat(red) / 255) < 0.02, "\(red) \(components)")
            #expect(abs(components.green - CGFloat(green) / 255) < 0.02, "\(green) \(components)")
            #expect(abs(components.blue - CGFloat(blue) / 255) < 0.02, "\(blue) \(components)")
        }
    }

    /// 見出しと補足は、切り詰められずに全部の行が画像に写る (2 行の見出しが 1 行に切り詰められると 2 行目が写らない)。
    @Test func 見出しと補足は全部の行が画像に写る() throws {
        for language in appStoreScreenshotLanguages {
            for screen in AppStoreScreenshotScreen.allCases {
                for line in (appStoreScreenshotHeadline(screen: screen, locale: language.locale) + "\n" + appStoreScreenshotSubheadline(screen: screen, locale: language.locale)).split(separator: "\n") {
                    #expect(
                        try comparableText(text: recognizedText(screen: screen, language: language, regionOfInterest: headingRegion)).contains(comparableText(text: String(line))),
                        "\(language.directoryName) \(screen) \(line)"
                    )
                }
            }
        }
    }

    /// 画像のうち見出しと補足が写る範囲 (Vision の `regionOfInterest` の形。左下が原点で、幅と高さを 1 とした割合)。
    ///
    /// 上から 2 割にするのは、端末の枠が上から 21.6% の所から始まり (run 44918156487 が描いた 10 枚で、2 行の見出しの時の枠の上の端は 2000 分の 432)、補足の下の端がそれより上にあるため。
    /// 端末の中の文言を読まないために区切る (日本語の追加の画面は、補足と同じ「追加しただけでは購入されません」がフォームの下にも写る)。
    private let headingRegion = CGRect(x: 0, y: 0.8, width: 1, height: 0.2)

    /// `language` の言語の 1 枚を描いて、`regionOfInterest` の範囲に写っている文字を Vision の文字の認識 (その言語と英語) で読み、行を改行でつないで返す。描けない時は投げる。
    ///
    /// 英語を足すのは、どの言語の画像にも英語の文字 (店のドメイン・「Quick Buy」) が写るため。
    private func recognizedText(
        screen: AppStoreScreenshotScreen,
        language: AppStoreScreenshotLanguage,
        // 範囲を渡さない呼び出しは画像の全体を読む (Vision の `regionOfInterest` の既定の値と同じ)。
        regionOfInterest: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) throws -> String {
        try recognizedText(
            screen: screen,
            locale: language.locale,
            recognitionLanguages: language.textRecognitionLanguage == "en-US" ? ["en-US"] : [language.textRecognitionLanguage, "en-US"],
            regionOfInterest: regionOfInterest
        )
    }

    /// `locale` の言語の 1 枚を描いて、`regionOfInterest` の範囲に写っている文字を Vision の文字の認識 (`recognitionLanguages` の言語) で読み、行を改行でつないで返す。描けない時は投げる。
    private func recognizedText(
        screen: AppStoreScreenshotScreen,
        locale: Locale,
        recognitionLanguages: [String],
        // 範囲を渡さない呼び出しは画像の全体を読む (Vision の `regionOfInterest` の既定の値と同じ)。
        regionOfInterest: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) throws -> String {
        let request = VNRecognizeTextRequest()
        request.regionOfInterest = regionOfInterest
        request.recognitionLevel = .accurate
        request.recognitionLanguages = recognitionLanguages
        // 辞書で直すと、店のドメインや見本の名前が別の語に替わるため切る。
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(data: #require(screenshotPNG(screen: screen, locale: locale))).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// 文字の認識の結果と元の文言を比べるために、文字と数字だけを残し、小文字にしてアクセント記号を外した文字列を返す (空白・改行・引用符の形の違いと、「é」を「e」と読むような認識の違いで食い違わないようにする)。
    private func comparableText(text: String) -> String {
        String(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// 文字の認識の結果 `text` に、日本語の文字 (ひらがな・カタカナ・長音・漢字) が 3 文字以上続く所があるか。
    ///
    /// 2 文字以下の日本語と中点「・」を数えないのは、文字の認識の誤読のため。英語の画像の区切り「·」(U+00B7) が「・」と読まれ、文字でない図形が、画像の配置によって「リ-山」(2026-11-21 の run 44917190742) とも「ニー1」(同日の run 44919217821) とも読まれた。
    /// 認識の確からしさでは分けられない (同日の run 44920334035 の実測で、誤読の「リ-山」も、日本語の画像の本物の「200g/豆のまま」も 0.3 だった)。
    /// そのため、英語の画像に 2 文字以下で残った日本語 (「個数」「開く」) はこの関数では見つからない。
    /// 図形の誤読は画面の配置を変えると変わり、3 文字の続き (「ニー山」。同日の run 44926464236 で、一覧の画面の「Edit」を別の文言にした時) になることがある。
    /// 画面を変えた後にテスト「英語の画像に日本語の文字が写らない」が落ちたら、失敗の文に出る行が画面の文言か図形の誤読かを画像で見分ける。
    private func containsRecognizedJapanese(text: String) -> Bool {
        text.contains(#/[\u{3041}-\u{3096}\u{30A1}-\u{30FA}\u{30FC}\u{4E00}-\u{9FFF}]{3,}/#)
    }

    /// `text` に仮名 (ひらがな・カタカナ) があるか。
    private func containsKana(text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    /// `text` に日本語の文字 (ひらがな・カタカナ・漢字) があるか。
    private func containsJapanese(text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }
}
