# Bundled text face provenance

Ashfall ships exactly one external asset: a text font for Traditional Chinese.
Geometry, icons and all other artwork stay procedural MathArt output. No external
icon set, texture, sprite sheet or art font is allowed.

## NotoSansCJKtc-Regular.otf

- Upstream: https://github.com/notofonts/noto-cjk
- Pinned commit: `165c01b46ea533872e002e0785ff17e44f6d97d8`
- Path in that commit: `Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf`
- Downloaded with:
  `curl -sSL --retry 3 -o assets/fonts/NotoSansCJKtc-Regular.otf https://raw.githubusercontent.com/notofonts/noto-cjk/165c01b46ea533872e002e0785ff17e44f6d97d8/Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf`
- Observed size: 16,435,884 bytes (same as the pinned upstream blob)
- Observed SHA-256: `dce08bd4fd91aa8aa76ed8fea4b694c2dfb8550f67871e326843212ddbeb88b4`
- Font version string: `Version 2.004;hotconv 1.0.118;makeotfexe 2.5.65603`
- Internal copyright notice, verbatim from name ID 0 of the font's name table:
  `© 2014-2021 Adobe (http://www.adobe.com/).`
- Internal trademark notice: `Noto is a trademark of Google Inc.`
- Internal license description: the SIL OFL 1.1 statement pointing at
  `http://scripts.sil.org/OFL`.

Only the Regular weight is used. Subsetting is not performed, so the bundled
file stays byte-identical to the pinned upstream object above; the hash is the
check. `scripts/systems/math_art.gd` loads it through `MathArt.ui_font()`, which
emits an error if the asset is missing instead of pretending the fallback face
covers Chinese.

## OFL.txt

- Upstream: same repository, same commit, root `LICENSE`
- Downloaded with:
  `curl -sSL --retry 3 -o assets/fonts/OFL.txt https://raw.githubusercontent.com/notofonts/noto-cjk/165c01b46ea533872e002e0785ff17e44f6d97d8/LICENSE`
- Observed size: 4,301 bytes, 92 lines
- Observed SHA-256: `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`
- Content: the unmodified SIL Open Font License 1.1 body. It names no
  Reserved Font Name and carries no copyright line; the copyright and license
  notices that OFL condition 2 asks to preserve travel inside the font's own
  name table (quoted above), not in this file.

## Licence summary

Noto Sans CJK is distributed under the SIL Open Font License, Version 1.1. The
licence permits bundling and redistribution with software, including commercial
products, provided the copyright and licence notices travel with the font; the
notice is embedded in the font's name table and repeated verbatim above, and
`OFL.txt` is the licence text. No modification or subsetting is performed, so
the reserved-name and derivative clauses are not triggered; the font name is
never used to imply endorsement.
