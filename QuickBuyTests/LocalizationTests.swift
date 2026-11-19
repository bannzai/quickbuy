import Foundation
import Testing
@testable import QuickBuy

/// 文字列カタログから言語を指定して文言を引けるかを確かめる (仕組みの確認用の一時的なテスト)。
struct LocalizationTests {
    /// アプリの bundle の英語の lproj。
    private let englishBundle = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap { Bundle(path: $0) }

    /// テストを動かしている環境の言語の並びを記録する。
    @Test func environmentLanguages() {
        #expect(Locale.preferredLanguages == ["probe"])
        #expect(Bundle.main.preferredLocalizations == ["probe"])
        #expect(Bundle.main.localizations == ["probe"])
    }

    /// 英語の lproj から文言を引ける。
    @Test func englishBundleLookup() throws {
        let englishBundle = try #require(englishBundle)
        #expect(String(localized: "カートイン", bundle: englishBundle) == "Add to Cart")
    }

    /// 英語の lproj から複数形の文言を引ける。
    @Test func englishBundlePlural() throws {
        let englishBundle = try #require(englishBundle)
        #expect(String(localized: "\(1) 種類をお気に入りに追加", bundle: englishBundle) == "Add 1 Variant to Favorites")
        #expect(String(localized: "\(2) 種類をお気に入りに追加", bundle: englishBundle) == "Add 2 Variants to Favorites")
        #expect(String(localized: "\(1) 種類をお気に入りに追加", bundle: englishBundle, locale: Locale(identifier: "en")) == "Add 1 Variant to Favorites")
    }

    /// locale だけで言語が選ばれるか。
    @Test func localeOnlyLookup() {
        #expect(String(localized: "カートイン", locale: Locale(identifier: "en")) == "Add to Cart")
        var resource = LocalizedStringResource("カートイン")
        resource.locale = Locale(identifier: "en")
        #expect(String(localized: resource) == "Add to Cart")
        var pluralResource = LocalizedStringResource("\(1) 種類をお気に入りに追加")
        pluralResource.locale = Locale(identifier: "en")
        #expect(String(localized: pluralResource) == "Add 1 Variant to Favorites")
    }
}
