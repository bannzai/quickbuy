import Foundation
import Testing
@testable import QuickBuy

/// 設定画面が開くリンク先 (問い合わせのメール・利用規約・プライバシーポリシー) と、バージョンの表示を確かめる。
struct SettingsTests {
    /// リポジトリのルートからの相対パスで指したファイルの URL を返す。
    private func repositoryFileURL(relativePath: String) -> URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: relativePath)
    }

    // MARK: - 問い合わせのメール

    /// 宛先は `documents/PROJECT.md` に書いた連絡先で、件名が入った `mailto:` になる。
    @Test func 問い合わせのメールは連絡先を宛先にして件名を入れる() throws {
        #expect(
            try String(contentsOf: repositoryFileURL(relativePath: "documents/PROJECT.md"), encoding: .utf8)
                .contains("連絡先のメールアドレスは bannzai.app@gmail.com\n")
        )
        let components = try #require(URLComponents(url: #require(contactMailURL()), resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == "bannzai.app@gmail.com")
        #expect(components.queryItems == [URLQueryItem(name: "subject", value: "Quick Buy へのお問い合わせ")])
    }

    // MARK: - 利用規約・プライバシーポリシー

    /// リンク先は GitHub Pages の拡張子なしの URL で、紹介ページ (`docs/index.html`) の canonical と同じ場所の下にある。
    @Test func 利用規約とプライバシーポリシーは公開ページのURLを指す() throws {
        #expect(termsURL.absoluteString == "https://bannzai.github.io/quickbuy/Terms-ja")
        #expect(privacyPolicyURL.absoluteString == "https://bannzai.github.io/quickbuy/PrivacyPolicy-ja")
        #expect(
            try String(contentsOf: repositoryFileURL(relativePath: "docs/index.html"), encoding: .utf8)
                .contains("<link rel=\"canonical\" href=\"https://bannzai.github.io/quickbuy/\">")
        )
    }

    /// リンク先のページの元になる Markdown が `docs/` にある (ファイルの名前を変えるとリンクが切れるため)。
    @Test(arguments: [termsURL, privacyPolicyURL])
    func リンク先のページの元のファイルがある(pageURL: URL) {
        #expect(
            FileManager.default.fileExists(
                atPath: repositoryFileURL(relativePath: "docs/\(pageURL.lastPathComponent).md").path(percentEncoded: false)
            )
        )
    }

    // MARK: - バージョン

    /// バージョンとビルド番号の両方を読めた時は `バージョン (ビルド番号)` の形にする。
    @Test func バージョンとビルド番号を1つの文字列にする() {
        #expect(appVersionText(infoDictionary: ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "45"]) == "1.2.3 (45)")
    }

    /// バージョンかビルド番号のどちらかが無い時・文字列でない時・Info.plist 自体を読めない時は、表示する文字列を作らない。
    @Test func バージョンを読めない時は文字列を作らない() {
        #expect(appVersionText(infoDictionary: ["CFBundleShortVersionString": "1.2.3"]) == nil)
        #expect(appVersionText(infoDictionary: ["CFBundleVersion": "45"]) == nil)
        #expect(appVersionText(infoDictionary: ["CFBundleShortVersionString": 123, "CFBundleVersion": "45"]) == nil)
        #expect(appVersionText(infoDictionary: [:]) == nil)
        #expect(appVersionText(infoDictionary: nil) == nil)
    }
}
