import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
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
        let forbiddenPhrases = ["ワンタップ", "1 タップ", "１タップ", "自動で買", "自動購入", "one tap", "one-tap", "automatically", "auto-buy"]
        for language in appStoreScreenshotLanguages {
            for screen in AppStoreScreenshotScreen.allCases {
                for text in [appStoreScreenshotHeadline(screen: screen, locale: language.locale), appStoreScreenshotSubheadline(screen: screen, locale: language.locale)] {
                    #expect(!forbiddenPhrases.contains { text.localizedCaseInsensitiveContains($0) }, "\(text)")
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

    /// 見本のリマインドは、一覧で「次の知らせは 5 日後」「知らせなし」「そろそろ買う頃」の 3 つの状態を出す。
    @Test func 見本のリマインドは3つの状態を出す() {
        #expect(appStoreScreenshotFavorites(locale: Locale(identifier: "ja"), now: now).map { reminderStatusText(reminder: $0.reminder, now: now, locale: Locale(identifier: "ja")) } == [
            "次の知らせは 5 日後", "知らせなし", "そろそろ買う頃",
        ])
    }

    /// 見本の店は実在しない `.example` のドメインだけにする (実在の店の名前をストアの画像に出さない)。
    @Test func 見本の店はexampleのドメインだけ() {
        for favorite in appStoreScreenshotFavorites(locale: Locale(identifier: "ja"), now: now) {
            #expect(shopDomainText(favorite: favorite).hasSuffix(".example"))
        }
    }
}
