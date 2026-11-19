import Foundation
import Testing
@testable import QuickBuy

/// 文字列カタログから言語を指定して文言を引けるかを確かめる (仕組みの確認用の一時的なテスト)。
struct LocalizationTests {
    /// アプリの bundle の言語ごとの lproj の URL。
    private func lprojURL(languageCode: String) throws -> URL {
        try #require(Bundle.main.url(forResource: languageCode, withExtension: "lproj"))
    }

    /// アプリの bundle の言語ごとの lproj の Bundle。
    private func lprojBundle(languageCode: String) throws -> Bundle {
        try #require(Bundle(url: lprojURL(languageCode: languageCode)))
    }

    /// 日本語の lproj から日本語の文言 (単数・複数・埋め込み) を引ける。
    @Test func japaneseBundleLookup() throws {
        let japaneseBundle = try lprojBundle(languageCode: "ja")
        #expect(String(localized: "カートイン", bundle: japaneseBundle) == "カートイン")
        #expect(String(localized: "\(2) 種類をお気に入りに追加", bundle: japaneseBundle) == "2 種類をお気に入りに追加")
    }

    /// locale だけを日本語にすると日本語が選ばれるか (環境は en-US)。
    @Test func japaneseLocaleOnly() {
        #expect(String(localized: "カートイン", locale: Locale(identifier: "ja")) == "カートイン")
        var resource = LocalizedStringResource("カートイン")
        resource.locale = Locale(identifier: "ja")
        #expect(String(localized: resource) == "カートイン")
    }

    /// LocalizedStringResource の bundle に lproj の URL を入れると、その言語が選ばれるか。
    @Test func resourceBundleAtLprojURL() throws {
        #expect(String(localized: LocalizedStringResource("カートイン", bundle: .atURL(try lprojURL(languageCode: "ja")))) == "カートイン")
        #expect(String(localized: LocalizedStringResource("\(2) 種類をお気に入りに追加", bundle: .atURL(try lprojURL(languageCode: "en")))) == "Add 2 Variants to Favorites")
    }

    /// LocalizedStringResource の locale を変えると、その言語が選ばれるか。
    @Test func resourceLocaleJapanese() {
        var resource = LocalizedStringResource("\(1) 種類をお気に入りに追加")
        resource.locale = Locale(identifier: "ja")
        #expect(String(localized: resource) == "1 種類をお気に入りに追加")
    }

    /// String(localized:bundle:locale:) の bundle に lproj を渡すと、複数形の規則が locale で決まるか。
    @Test func englishBundleWithJapaneseLocalePlural() throws {
        #expect(String(localized: "\(1) 種類をお気に入りに追加", bundle: try lprojBundle(languageCode: "en"), locale: Locale(identifier: "en")) == "Add 1 Variant to Favorites")
    }
}
