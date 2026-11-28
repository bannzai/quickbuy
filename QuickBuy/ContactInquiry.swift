import Foundation

/// 問い合わせの種別。Firestore の `contactInquiries` の文書の `inquiryType` に rawValue をそのまま保存する。
///
/// 値の並びは `firebase/firestore.rules` と `firebase/functions/src/contactInquiry.ts` の種別の並びと同じにする。
enum ContactInquiryType: String, CaseIterable, Codable, Identifiable {
    /// 不具合の報告。
    case bug
    /// 意見・要望。
    case feedback
    /// そのほか。
    case other

    /// `ForEach` で並べる時の識別子。
    var id: Self { self }

    /// フォームの種別の選択肢に出す名前。
    var title: LocalizedStringResource {
        switch self {
        case .bug: "バグ・不具合"
        case .feedback: "ご意見・ご要望"
        case .other: "その他"
        }
    }
}

/// 設定の画面のお問い合わせのフォームから運営者に送る 1 件の問い合わせ。Firestore の `contactInquiries/{自動の ID}` の文書のうち、送った時刻を除く中身。
///
/// 送った時刻 `createdDateTime` は、書き込む時にサーバーの時刻で足す (`sendContactInquiry(inquiryType:content:emailAddress:)`)。
/// 文書を受け取る側は、作成だけを許すセキュリティルール (`firebase/firestore.rules`) と、Slack に通知する Functions (`firebase/functions/src/contactInquiry.ts`)。
struct ContactInquiry: Codable, Equatable {
    /// 問い合わせの種別。
    var inquiryType: ContactInquiryType
    /// 利用者が書いた内容。前後の空白と改行を除いた値。
    var content: String
    /// 返信先のメールアドレス。運営者が問い合わせに返信する時にだけ使う。前後の空白と改行を除いた値。
    var emailAddress: String
    /// 送った人の Firebase Auth の匿名の uid。セキュリティルールが、送った人本人の uid に限る。
    var userID: String
    /// 送ったアプリのバージョン (`appVersionText(infoDictionary:)` の形。例: `1.0.0 (15)`)。読めない時は nil で、文書にキーを書かない。
    var appVersion: String?
    /// DEBUG ビルドから送った時に true。Functions が Slack の通知をテスト用のチャンネル (`#test-notification`) に送る。
    var test: Bool
}

/// 問い合わせの内容の文字数 (Unicode のスカラー値の数) の上限。`firebase/firestore.rules` の `content.size()` の上限と同じ値にする。
///
/// 10,000 は agent の決めた値。不具合の説明を長く書いても収まり、内容をそのまま載せる Slack の投稿の文字数の上限 (40,000。https://docs.slack.dev/reference/methods/chat.postMessage の `text` の説明) を、ほかの行を足しても超えない
let contactInquiryContentMaxLength = 10_000

/// 返信先のメールアドレスの文字数の上限。`firebase/firestore.rules` の `emailAddress.size()` の上限と同じ値にする。
///
/// 254 はメールアドレスの長さの上限 (RFC 5321 の経路の上限 256 から両端の `<` `>` を除いた値)。
let contactInquiryEmailAddressMaxLength = 254

/// フォームの入力の前後の空白と改行を除いた値を返す。送る値と、送信できるかの判定の両方で使う。
func trimmedContactFormText(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// フォームの入力で送信できるかを返す。
///
/// 前後の空白と改行を除いた内容とメールアドレスが空でなく、上限の文字数以内で、メールアドレスが `@` を 1 つだけ含みその前後に文字がある時に true。
/// メールアドレスが実在するか・受け取れるかは確かめない (確かめる手段がアプリに無いため。フォームの説明文で、返信を受け取れるアドレスを入れるよう頼む)。
func isContactFormSubmittable(content: String, emailAddress: String) -> Bool {
    let content = trimmedContactFormText(content)
    let emailAddress = trimmedContactFormText(emailAddress)
    guard !content.isEmpty, content.unicodeScalars.count <= contactInquiryContentMaxLength,
          emailAddress.unicodeScalars.count <= contactInquiryEmailAddressMaxLength
    else {
        return false
    }
    let emailAddressParts = emailAddress.split(separator: "@", omittingEmptySubsequences: false)
    return emailAddressParts.count == 2 && emailAddressParts.allSatisfy { !$0.isEmpty }
}
