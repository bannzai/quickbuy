import Foundation
import Testing
@testable import QuickBuy

/// お問い合わせのフォームの、送信できるかの判定と、Firestore に書く文書の形 (issue #100) を確かめる。
struct ContactInquiryTests {
    /// リポジトリのルートからの相対パスで指したファイルの中身を返す。
    private func repositoryFileText(relativePath: String) throws -> String {
        try String(
            contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: relativePath),
            encoding: .utf8
        )
    }

    /// 問い合わせを JSON にした時のキーと値を返す。Firestore に書く時と同じ Codable の実装で、文書のキーと値を確かめるため。
    private func encodedObject(inquiry: ContactInquiry) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(inquiry)) as? [String: Any])
    }

    // MARK: - 送信できるかの判定

    /// 内容とメールアドレスが入っていれば送信できる。前後の空白と改行は数えない。
    @Test func 内容とメールアドレスが入っていれば送信できる() {
        #expect(isContactFormSubmittable(content: "カートインが開かない", emailAddress: "user@example.com"))
        #expect(isContactFormSubmittable(content: "  \n開かない\n ", emailAddress: " user@example.com\n"))
    }

    /// 内容かメールアドレスが空か、空白と改行だけの時は送信できない。
    @Test(arguments: [
        ("", "user@example.com"),
        (" \n ", "user@example.com"),
        ("開かない", ""),
        ("開かない", "  "),
    ])
    func 内容かメールアドレスが空なら送信できない(content: String, emailAddress: String) {
        #expect(!isContactFormSubmittable(content: content, emailAddress: emailAddress))
    }

    /// メールアドレスは `@` を 1 つだけ含み、その前後に文字がある時だけ送信できる。
    @Test(arguments: [
        ("a@b", true),
        ("user.name+tag@example.co.jp", true),
        ("userexample.com", false),
        ("@example.com", false),
        ("user@", false),
        ("user@@example.com", false),
        ("a@b@c", false),
    ])
    func メールアドレスの形(emailAddress: String, isSubmittable: Bool) {
        #expect(isContactFormSubmittable(content: "開かない", emailAddress: emailAddress) == isSubmittable)
    }

    /// 内容は上限の文字数ちょうどまで送信でき、1 文字超えると送信できない。日本語の文字も 1 文字と数える。
    @Test func 内容は上限の文字数まで送信できる() {
        #expect(isContactFormSubmittable(content: String(repeating: "あ", count: 10_000), emailAddress: "user@example.com"))
        #expect(!isContactFormSubmittable(content: String(repeating: "あ", count: 10_001), emailAddress: "user@example.com"))
    }

    /// メールアドレスは上限の文字数ちょうどまで送信でき、1 文字超えると送信できない。
    @Test func メールアドレスは上限の文字数まで送信できる() {
        let domain = "@example.com"
        #expect(isContactFormSubmittable(content: "開かない", emailAddress: String(repeating: "a", count: 254 - domain.count) + domain))
        #expect(!isContactFormSubmittable(content: "開かない", emailAddress: String(repeating: "a", count: 255 - domain.count) + domain))
    }

    /// アプリの上限は、セキュリティルールが拒む上限と同じ値にする (片方だけ変えると、アプリで送れるのにルールが拒む)。
    @Test func 上限はセキュリティルールと同じ() throws {
        let rules = try repositoryFileText(relativePath: "firebase/firestore.rules")
        #expect(contactInquiryContentMaxLength == 10_000)
        #expect(rules.contains("request.resource.data.content.size() <= \(contactInquiryContentMaxLength)"))
        #expect(contactInquiryEmailAddressMaxLength == 254)
        #expect(rules.contains("request.resource.data.emailAddress.size() <= \(contactInquiryEmailAddressMaxLength)"))
    }

    // MARK: - 文書の形

    /// 文書のキーと値は、セキュリティルールが許すキーと、Functions が読むキーと同じ名前になる。
    @Test func 文書のキーと値() throws {
        let object = try encodedObject(
            inquiry: ContactInquiry(inquiryType: .feedback, content: "要望", emailAddress: "user@example.com", userID: "uid-1", appVersion: "1.0.0 (15)", test: true)
        )
        #expect(Set(object.keys) == ["inquiryType", "content", "emailAddress", "userID", "appVersion", "test"])
        #expect(object["inquiryType"] as? String == "feedback")
        #expect(object["content"] as? String == "要望")
        #expect(object["emailAddress"] as? String == "user@example.com")
        #expect(object["userID"] as? String == "uid-1")
        #expect(object["appVersion"] as? String == "1.0.0 (15)")
        #expect(object["test"] as? Bool == true)
        #expect(
            try repositoryFileText(relativePath: "firebase/firestore.rules")
                .contains("hasOnly(['inquiryType', 'content', 'emailAddress', 'userID', 'appVersion', 'test', 'createdDateTime'])")
        )
    }

    /// バージョンを読めない時は、文書に `appVersion` のキーを書かない (null を書かない)。
    @Test func バージョンが無い時はキーを書かない() throws {
        let object = try encodedObject(
            inquiry: ContactInquiry(inquiryType: .bug, content: "開かない", emailAddress: "user@example.com", userID: "uid-1", appVersion: nil, test: false)
        )
        #expect(!object.keys.contains("appVersion"))
        #expect(object["test"] as? Bool == false)
    }

    /// 種別の値は 3 つで、セキュリティルールが許す種別の並びと同じ。
    @Test func 種別の値はセキュリティルールと同じ() throws {
        #expect(ContactInquiryType.allCases.map(\.rawValue) == ["bug", "feedback", "other"])
        #expect(try repositoryFileText(relativePath: "firebase/firestore.rules").contains("in ['bug', 'feedback', 'other']"))
    }

    /// 文書を書くコレクションの名前は、セキュリティルールと Functions が見るパスと同じ。
    @Test func コレクションの名前はセキュリティルールとFunctionsと同じ() throws {
        #expect(contactInquiriesCollectionPath == "contactInquiries")
        #expect(try repositoryFileText(relativePath: "firebase/firestore.rules").contains("match /contactInquiries/{contactInquiryID}"))
        #expect(try repositoryFileText(relativePath: "firebase/functions/src/notifyContactInquiry.ts").contains("document: \"contactInquiries/{contactInquiryID}\""))
    }
}
