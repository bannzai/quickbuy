import FirebaseAuth
import FirebaseFirestore
import SwiftUI

/// 問い合わせを保存する Firestore のコレクションの名前。`firebase/firestore.rules` と `firebase/functions/src/notifyContactInquiry.ts` のパスと同じにする。
let contactInquiriesCollectionPath = "contactInquiries"

/// 問い合わせを DEBUG ビルドから送る時に true。文書の `test` に入れ、Functions が通知をテスト用のチャンネルに送る。
#if DEBUG
    let isDebugBuildForContactInquiry = true
#else
    let isDebugBuildForContactInquiry = false
#endif

/// 問い合わせに書く送った人の uid を返す。Firebase Auth にサインインしていなければ匿名でサインインし、その uid を返す。サインインに失敗したら throw する。
///
/// アプリの起動の時ではなく送る時にサインインするのは、問い合わせを送らない利用者の匿名のアカウントを作らないため。
@MainActor
func contactInquiryUserID() async throws -> String {
    if let currentUser = Auth.auth().currentUser {
        return currentUser.uid
    }
    return try await Auth.auth().signInAnonymously().user.uid
}

/// フォームの入力を問い合わせとして Firestore に 1 件書く。書き込みがサーバーに届くまで待ち、届かなければ throw する。
///
/// 送った人の uid は `contactInquiryUserID()` で得る (セキュリティルールが送った人の uid を求めるため)。
/// 冪等でない: 呼ぶたびに文書が 1 つ増える。送信のボタンを押した回数だけ問い合わせを残すのが仕様のため。
@MainActor
func sendContactInquiry(inquiryType: ContactInquiryType, content: String, emailAddress: String) async throws {
    var documentData = try Firestore.Encoder().encode(
        ContactInquiry(
            inquiryType: inquiryType,
            content: trimmedContactFormText(content),
            emailAddress: trimmedContactFormText(emailAddress),
            userID: try await contactInquiryUserID(),
            appVersion: appVersionText(infoDictionary: Bundle.main.infoDictionary),
            test: isDebugBuildForContactInquiry
        )
    )
    documentData["createdDateTime"] = FieldValue.serverTimestamp()
    _ = try await Firestore.firestore().collection(contactInquiriesCollectionPath).addDocument(data: documentData)
}

/// 設定の画面から開くお問い合わせのフォーム。種別・内容・返信先のメールアドレスを入れて運営者に送る。
///
/// 送れた時はお礼の表示の後に設定の画面へ戻り、送れなかった時は入力を残したまま、メールで連絡する宛先を出す。
struct ContactFormView: View {
    /// 設定の画面へ戻る処理。
    @Environment(\.dismiss) private var dismiss
    /// 選んでいる種別。最初は不具合の報告にする (Focus のフォームと同じ。問い合わせの多くは不具合の報告と見込むため)。
    @State private var inquiryType: ContactInquiryType = .bug
    /// 入力中の内容。
    @State private var content = ""
    /// 入力中の返信先のメールアドレス。
    @State private var emailAddress = ""
    /// 送っている間は true。送信のボタンを押せなくし、入力を変えられなくする。
    @State private var isSending = false
    /// 送れたことを知らせる表示を出している間は true。
    @State private var isSent = false
    /// 送れなかったことを知らせる表示を出している間は true。
    @State private var isSendFailed = false

    /// 種別・内容・メールアドレスの入力と、送信のボタン。
    var body: some View {
        Form {
            Section {
                Picker("種別", selection: $inquiryType) {
                    ForEach(ContactInquiryType.allCases) { inquiryType in
                        Text(inquiryType.title).tag(inquiryType)
                    }
                }
            }
            Section {
                TextEditor(text: $content)
                    .frame(minHeight: 160)
                    .accessibilityLabel(Text("内容"))
            } header: {
                Text("内容")
            } footer: {
                Text("不具合の時は\nどの画面で何をした時に何が起きたかを書いてください")
            }
            Section {
                TextField("メールアドレス", text: $emailAddress)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("返信先のメールアドレス")
            } footer: {
                Text("返信は \(contactMailAddress) から届きます\nメールアドレスは返信にだけ使います")
            }
        }
        .disabled(isSending)
        .navigationTitle("お問い合わせ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button("送信") {
                        send()
                    }
                    .disabled(!isContactFormSubmittable(content: content, emailAddress: emailAddress))
                }
            }
        }
        .alert("送信しました", isPresented: $isSent) {
            Button("閉じる") {
                dismiss()
            }
        } message: {
            Text("お問い合わせありがとうございます")
        }
        .alert("送信できませんでした", isPresented: $isSendFailed) {} message: {
            Text("\(contactMailAddress) へメールでご連絡ください")
        }
    }

    /// 入力を問い合わせとして送り、結果の表示を出す。送っている間に呼ばれた時と、送信できない入力の時は何もしない。
    private func send() {
        guard !isSending, isContactFormSubmittable(content: content, emailAddress: emailAddress) else {
            return
        }
        isSending = true
        Task {
            do {
                try await sendContactInquiry(inquiryType: inquiryType, content: content, emailAddress: emailAddress)
                isSent = true
            } catch {
                isSendFailed = true
            }
            isSending = false
        }
    }
}
