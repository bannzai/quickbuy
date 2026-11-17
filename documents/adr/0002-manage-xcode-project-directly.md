# 0002. Xcode プロジェクトを直接管理する

## Status
Accepted (2026-11-17)

## Context
最初の `QuickBuy.xcodeproj` (アプリ・ウィジェット拡張・ユニットテストの 3 ターゲット) は XcodeGen で組み立てた。XcodeGen の入力 `project.yml` と生成物 `project.pbxproj` の両方を Git で持つと、片方だけが更新された時の差異を検出する仕組みがなく、後から再生成した時に設定の不一致やビルドエラーが表面化する。Xcode の GUI で加えた変更も、次の再生成で失われる (同じ問題が起きた先例: https://github.com/bannzai/mementomorning の ADR 0002)。

## Decision
初期作成の後に `project.yml` を削除し、`QuickBuy.xcodeproj` をプロジェクト構成の唯一の正として直接管理する。ターゲット、ファイル、ビルド設定、Scheme、Swift Package の変更には Xcode の GUI を使う。自動化が必要な場合は、プロジェクト構成を `project.pbxproj`、Scheme を `xcshareddata/xcschemes/*.xcscheme` で直接編集する。XcodeGen は使わず、`xcodegen generate` を実行しない。

## Consequences

**良い点:**
- `project.yml` と `project.pbxproj` の二重管理がなく、両者の不一致による遅れたビルド失敗が起きない
- Xcode の GUI で行った変更が後の再生成で失われない

**悪い点 / 引き受けるリスク:**
- `project.pbxproj` の差分は YAML より読みづらいため、変更時に意図しない差分がないかを `git diff -- QuickBuy.xcodeproj` で確認する
- 直接編集で不正な構成を作る可能性があるため、プロジェクト構成の変更後は PR の CI のビルドとテストで確かめる
