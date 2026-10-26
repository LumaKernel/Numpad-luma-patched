# NumpadLuma

yeonfish6040/Numpad のフォーク。main ブランチが上流のコピー、luma-patched ブランチにパッチを載せる。

## Versioning

- タグ形式: `v{upstream-ver}-luma.{luma-ver}`
  - 例: `v0.0.4-luma.1`, `v0.0.4-luma.2`, `v0.0.5-luma.3`
- `upstream-ver`: VERSION ファイルの値と一致させる。上流のバージョンに追従。
- `luma-ver`: 整数1個。通しでカウントアップし続ける（upstream ver が変わってもリセットしない）。
- VERSION ファイルには upstream ver のみ書く（`0.0.4` など）。luma ver はタグでのみ管理。

## Release

- `v*-luma.*` タグを push すると GitHub Actions がビルド・リリースを作成する。
- 署名・公証は Secrets (CERT_P12_BASE64, SIGN_IDENTITY, NOTARY_*) が設定されている場合のみ。
- 成果物: `NumpadLuma-{upstream-ver}-luma.{luma-ver}-universal.dmg` + SHA256SUMS

## Build

```sh
bash scripts/build-app.sh          # ローカルビルド (ad-hoc署名)
UNIVERSAL=1 bash scripts/build-app.sh  # universal ビルド
bash scripts/build-dmg.sh          # DMG作成 (署名はSIGN_IDENTITY環境変数)
```

## Localization

en/ja/ko の3言語。文字列は `Sources/TrackpadCore/Resources/{lang}.lproj/Localizable.strings` に追加する。
