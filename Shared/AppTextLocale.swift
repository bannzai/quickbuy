import Foundation

/// bundle が選んだ言語の並び (`Bundle.preferredLocalizations`) から、文言を返す関数に渡す locale を返す。
///
/// 画面の `Text("…")` が文字列カタログから選ぶ言語 (`preferredLocalizations` の先頭) と同じ言語にする。
/// `Locale.current` を使わないのは、カタログに無い言語 (例: フランス語) を端末の言語の先頭にした時に、`Locale.current` はその言語になり、画面の `Text` が選んだ言語と関数の文言の言語が食い違い得るため。
/// 並びが空の時の `fallback` は、bundle が言語を 1 つも持たない場合の値で、文字列カタログを入れた 3 つのターゲット (アプリ・ウィジェット・共有メニューの拡張) では使われない。
func textLocale(preferredLocalizations: [String], fallback: Locale) -> Locale {
    preferredLocalizations.first.map(Locale.init(identifier:)) ?? fallback
}

/// 文言を返す関数 (`cartInButtonTitle(favorite:locale:)` 等) に渡す、画面・ウィジェット・通知の文言の言語。
let appTextLocale = textLocale(preferredLocalizations: Bundle.main.preferredLocalizations, fallback: .current)
