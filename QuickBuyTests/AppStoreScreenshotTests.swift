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
                    #expect(!["。", "、", ".", ",", "!"].contains { text.hasSuffix($0) }, "\(text)")
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
                for domainText in try recognizedText(screen: screen, locale: language.locale).lowercased().matches(of: #/[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}/#).map(\.output.0) {
                    #expect(domainText.hasSuffix(".example"), "\(language.directoryName) \(screen) \(domainText)")
                }
            }
            // 店のドメインを読めていること (読めない認識では上の確認が何も見ない)。
            #expect(try recognizedText(screen: .search, locale: language.locale).lowercased().contains("mori-coffee.example"), "\(language.directoryName)")
        }
    }

    /// 英語の見本の文字列 (お気に入りの名前・商品バリアントの名前・検索の商品の名前・種類の選び方の名前) に日本語が残らない。
    @Test func 英語の見本の文字列に日本語が残らない() {
        let english = Locale(identifier: "en")
        for text in appStoreScreenshotFavorites(locale: english, now: now).flatMap({ [$0.name, $0.variantName ?? ""] })
            + appStoreScreenshotSearchProducts(locale: english).map(\.title)
            + [appStoreScreenshotShopText(japaneseText: appStoreScreenshotOptionName, locale: english)]
        {
            #expect(!containsJapanese(text: text), "\(text)")
        }
        #expect(appStoreScreenshotSearchProducts(locale: english).map(\.title) == ["Coffee beans", "Dark Roast 200g", "Light Roast 200g", "Decaf 150g"])
        #expect(appStoreScreenshotSearchProducts(locale: Locale(identifier: "ja")).map(\.title) == ["コーヒー豆", "深煎り 200g", "浅煎り 200g", "デカフェ 150g"])
        #expect(appStoreScreenshotShopText(japaneseText: appStoreScreenshotOptionName, locale: english) == "Size")
        // 対応の無い文字列は、言語によらない表記としてそのまま返す。
        #expect(appStoreScreenshotShopText(japaneseText: "1kg", locale: english) == "1kg")
        #expect(appStoreScreenshotShopText(japaneseText: "", locale: english) == "")
    }

    /// 英語のスクリーンショットの画像には日本語の文字が写らず、日本語のスクリーンショットの画像には写る (画面のコードに直に書いた文言も見る)。
    @Test func 英語の画像に日本語の文字が写らない() throws {
        for screen in AppStoreScreenshotScreen.allCases {
            let japaneseLines = try recognizedText(screen: screen, locale: Locale(identifier: "en")).split(separator: "\n").filter { containsJapanese(text: String($0)) }
            #expect(japaneseLines.isEmpty, "\(screen) \(japaneseLines)")
            // 日本語を読めていること (読めない認識では上の確認が何も見ない)。
            #expect(try containsJapanese(text: recognizedText(screen: screen, locale: Locale(identifier: "ja"))), "\(screen)")
        }
    }

    /// 見出しと補足は、切り詰められずに全部の行が画像に写る (2 行の見出しが 1 行に切り詰められると 2 行目が写らない)。
    @Test func 見出しと補足は全部の行が画像に写る() throws {
        for language in appStoreScreenshotLanguages {
            for screen in AppStoreScreenshotScreen.allCases {
                for line in (appStoreScreenshotHeadline(screen: screen, locale: language.locale) + "\n" + appStoreScreenshotSubheadline(screen: screen, locale: language.locale)).split(separator: "\n") {
                    #expect(
                        try comparableText(text: recognizedText(screen: screen, locale: language.locale)).contains(comparableText(text: String(line))),
                        "\(language.directoryName) \(screen) \(line)"
                    )
                }
            }
        }
    }

    /// 1 枚を描いて、写っている文字を Vision の文字の認識 (日本語と英語) で読み、行を改行でつないで返す。描けない時は投げる。
    private func recognizedText(screen: AppStoreScreenshotScreen, locale: Locale) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        // 辞書で直すと、店のドメインや見本の名前が別の語に替わるため切る。
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(data: #require(screenshotPNG(screen: screen, locale: locale))).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// 文字の認識の結果と元の文言を比べるために、文字と数字だけを残して小文字にした文字列を返す (空白・改行・引用符の形の違いで食い違わないようにする)。
    private func comparableText(text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// `text` に日本語の文字 (ひらがな・カタカナ・漢字) があるか。
    private func containsJapanese(text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }
}
