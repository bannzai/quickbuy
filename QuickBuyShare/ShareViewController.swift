import SwiftUI
import UIKit

/// 共有メニューから Quick Buy を選んだ時に表示される画面。渡された URL を、アプリの中と同じお気に入りの追加の画面 (`AddFavoriteView`) に渡す。
///
/// 拡張からアプリ本体を開かず、拡張の中で確認の画面を出して、アプリとウィジェット拡張が共有する領域へ保存する。
final class ShareViewController: UIViewController {
    /// 共有された URL の文字列を取り出し、お気に入りの追加の画面を載せる。
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            // 共有された項目から URL も文字列も取り出せなかった時は、空の入力欄から始める (利用者が URL を貼り付けられる)。
            await embedAddFavoriteView(
                initialText: sharedText(itemProviders: (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }) ?? ""
            )
        }
    }

    /// お気に入りの追加の画面を、この画面いっぱいに載せる。保存先を開けない時は、その旨の表示を載せる。
    private func embedAddFavoriteView(initialText: String) {
        let hostingController = UIHostingController(
            rootView: ShareRootView(initialText: initialText) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }
}

/// 共有メニューの拡張の中身。お気に入りの保存先を開ければ追加の画面を、開けなければその旨を表示する。
struct ShareRootView: View {
    /// 共有された URL の文字列。取り出せなかった時は空文字 (追加の画面は入力から始まる)。
    let initialText: String
    /// 共有メニューの拡張を閉じる処理。
    let onFinish: () -> Void

    /// お気に入りの追加の画面、または保存先を開けないことの表示。
    var body: some View {
        if let favoritesFileURL = sharedFavoritesFileURL() {
            AddFavoriteView(initialText: initialText, favoritesFileURL: favoritesFileURL, onFinish: onFinish)
        } else {
            FavoritesStoreUnavailableView()
        }
    }
}
