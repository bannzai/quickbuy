import Foundation
import Testing
@testable import QuickBuy

/// アプリ・ウィジェット拡張・共有メニューの拡張のどのターゲットにも、お気に入りの保存先と同じ App Group の設定が入っていることを確かめる。
///
/// CI は署名なし (`CODE_SIGNING_ALLOWED=NO`) でビルドするため、実行時に共有する領域を開いて確かめることができない。
/// そのため、リポジトリにある設定のファイル (entitlements と `project.pbxproj`) を、このテストのファイルの場所からたどって読む。
struct AppGroupEntitlementsTests {
    /// リポジトリのルートからの相対パスで指したファイルの URL を返す。
    private func repositoryFileURL(relativePath: String) -> URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: relativePath)
    }

    /// どのターゲットの entitlements も、`favoritesAppGroupIdentifier` の 1 つだけを App Group として持つ。
    @Test(arguments: [
        "QuickBuy/QuickBuy.entitlements",
        "QuickBuyWidget/QuickBuyWidget.entitlements",
        "QuickBuyShare/QuickBuyShare.entitlements",
    ])
    func entitlementsがお気に入りの保存先と同じAppGroupを持つ(relativePath: String) throws {
        #expect(favoritesAppGroupIdentifier == "group.com.bannzai.QuickBuy")
        #expect(
            try (
                PropertyListSerialization.propertyList(
                    from: Data(contentsOf: repositoryFileURL(relativePath: relativePath)),
                    format: nil
                ) as? [String: [String]]
            )?["com.apple.security.application-groups"] == [favoritesAppGroupIdentifier]
        )
    }

    /// どのターゲットの Debug と Release のビルド設定も、それぞれの entitlements のファイルを指している (ターゲットごとに 2 か所)。
    @Test(arguments: [
        "CODE_SIGN_ENTITLEMENTS = QuickBuy/QuickBuy.entitlements;",
        "CODE_SIGN_ENTITLEMENTS = QuickBuyWidget/QuickBuyWidget.entitlements;",
        "CODE_SIGN_ENTITLEMENTS = QuickBuyShare/QuickBuyShare.entitlements;",
    ])
    func ビルド設定がentitlementsを指している(buildSettingLine: String) throws {
        #expect(
            try String(contentsOf: repositoryFileURL(relativePath: "QuickBuy.xcodeproj/project.pbxproj"), encoding: .utf8)
                .components(separatedBy: buildSettingLine).count == 3
        )
    }
}
