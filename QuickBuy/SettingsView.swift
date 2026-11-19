import SwiftUI

/// 問い合わせを受けるメールアドレス (`documents/PROJECT.md`「守ること」の連絡先)。
let contactMailAddress = "bannzai.app@gmail.com"

/// `docs/` を配信する GitHub Pages の URL (`docs/index.html` の canonical と同じ)。
let publicPagesURL = URL(string: "https://bannzai.github.io/quickbuy/")!

/// 利用規約のページ (`docs/Terms-ja.md`) の URL。
///
/// 拡張子なしの形にしている根拠は実測: 同じ構成 (`main` ブランチの `/docs` を Jekyll でビルドし、`docs/_config.yml` を置き
/// `.nojekyll` を置かない) の公開済みのサイトで、`https://bannzai.github.io/mementomorning/Terms-ja` と
/// `https://bannzai.github.io/mementomorning/PrivacyPolicy-ja` が HTTP 200 (`text/html`) を返した (2026-11-18 に `curl` で確認)。
/// このリポジトリの GitHub Pages は 2026-11-18 時点で未公開のため、この URL 自体が開けることは未確認。
let termsURL = publicPagesURL.appending(path: "Terms-ja")

/// プライバシーポリシーのページ (`docs/PrivacyPolicy-ja.md`) の URL。
let privacyPolicyURL = publicPagesURL.appending(path: "PrivacyPolicy-ja")

/// 問い合わせのメールの作成を開く URL (宛先と件名を入れた `mailto:`) を返す。組み立てられない時は nil。
func contactMailURL() -> URL? {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = contactMailAddress
    components.queryItems = [URLQueryItem(name: "subject", value: "Quick Buy へのお問い合わせ")]
    return components.url
}

/// アプリの Info.plist の中身から、設定画面に出すバージョンの文字列 (例: `1.0.0 (1)`) を返す。
///
/// バージョン (`CFBundleShortVersionString`) かビルド番号 (`CFBundleVersion`) を読めない時は nil。
func appVersionText(infoDictionary: [String: Any]?) -> String? {
    guard let shortVersion = infoDictionary?["CFBundleShortVersionString"] as? String,
          let buildNumber = infoDictionary?["CFBundleVersion"] as? String
    else {
        return nil
    }
    return "\(shortVersion) (\(buildNumber))"
}

/// 設定画面。問い合わせのメールの作成・利用規約・プライバシーポリシーを開く入口と、Firebase に送る記録の説明と、アプリのバージョンを表示する。
struct SettingsView: View {
    /// お気に入りの保存先のファイルの URL。開発者メニュー (DEBUG ビルドだけ) に渡す。
    let favoritesFileURL: URL
    /// この画面を閉じる処理。
    let onFinish: () -> Void

    /// メールの作成と公開ページを開く処理 (既定のメールアプリ・ブラウザで開く)。
    @Environment(\.openURL) private var openURL
    /// メールの作成を開けなかったことを知らせる表示を出している間は true。
    @State private var isMailUnavailable = false
    #if DEBUG
        /// 開発者メニューを出している間は true。
        @State private var isDeveloperMenuPresented = false
    #endif

    /// 問い合わせ・利用規約・プライバシーポリシーの行と、バージョンの行。
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let mailURL = contactMailURL() {
                        Button {
                            openURL(mailURL) { isAccepted in
                                if !isAccepted {
                                    isMailUnavailable = true
                                }
                            }
                        } label: {
                            LabeledContent("お問い合わせ", value: contactMailAddress)
                        }
                    }
                    Link("利用規約", destination: termsURL)
                    Link("プライバシーポリシー", destination: privacyPolicyURL)
                } footer: {
                    // 送る内容の詳細は docs/PrivacyPolicy-ja.md「利用状況の解析と不具合の記録」
                    Text("利用の状況とアプリが落ちた時の記録を Google の Firebase に送ります\n商品や店の名前と購入画面の URL は送りません")
                }
                if let versionText = appVersionText(infoDictionary: Bundle.main.infoDictionary) {
                    Section {
                        LabeledContent("バージョン", value: versionText)
                    }
                }
                #if DEBUG
                    Section {
                        Button("開発者メニュー") {
                            isDeveloperMenuPresented = true
                        }
                    }
                #endif
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: onFinish)
                }
            }
            .alert("メールを開けませんでした", isPresented: $isMailUnavailable) {} message: {
                Text("\(contactMailAddress) へメールでご連絡ください")
            }
        }
        .tint(quickBuyAccentColor)
        #if DEBUG
            .sheet(isPresented: $isDeveloperMenuPresented) {
                DeveloperMenuView(favoritesFileURL: favoritesFileURL) {
                    isDeveloperMenuPresented = false
                }
            }
        #endif
    }
}
