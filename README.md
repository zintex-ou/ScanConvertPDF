# PDF Scan & Convert Pro

iOS document scanner / PDF converter. Acquired app, now maintained by Zintex OÜ.

- **Bundle ID:** `com.pdfscan.converter`
- **App Store ID:** `6758149297`
- **Site:** https://pdfscanconvert.site
- **Version at import:** 1.4 (build 1)
- **Min iOS:** 15.0 · **Swift:** 5.0 (language mode) · **Xcode:** 26

## Stack

| Area | Tech |
|---|---|
| UI | UIKit, programmatic Auto Layout (custom tab bar) |
| Storage | Core Data (`CDModel`) + PDFs on disk in `Documents/` |
| Scanning | VisionKit `VNDocumentCameraViewController`, PHPicker, `UIDocumentPicker` |
| Cropping | TOCropViewController 3.1.1 |
| PDF | PDFKit, `WKWebView.createPDF` (web page → PDF) |
| Monetization | Adapty 3.15.3 (paywalls + onboarding), StoreKit 2 fallback |
| Backend | Firebase 12.9 (Analytics, Remote Config) |
| Attribution | AdServices (Apple Search Ads), ATT / IDFA |
| CI | Codemagic (`codemagic.yaml`) |

## Features

Free: scan (VisionKit), camera → crop → PDF, gallery → PDF, file import → PDF,
web page → PDF, folders, move/rename/delete, sort, search.

**Premium-gated:** opening a document for viewing, and sharing.

Not implemented (despite what onboarding claims): OCR, page reorder/merge,
e-signature, scan filters, compression, password protection, iCloud sync.

## Build

```bash
open ScanConvertPDF.xcodeproj
```

SPM dependencies resolve automatically. No CocoaPods (the `pod install` step in
`codemagic.yaml` is a no-op left over from a template).

## CI / signing

`codemagic.yaml` expects a Codemagic **environment variable group** named
`appstore_signing` containing a secure `CERTIFICATE_PRIVATE_KEY`.
The key is **not** stored in this repo — do not re-add it.

The `app_store_connect` integration is still named `"Bhalat Puneey"` (previous
owner's) and needs to be repointed at our App Store Connect API key.

## Known issues

See `AUDIT.md` for the full technical audit (bugs, monetization gaps,
App Store review risks, refactor plan).

Highest priority:

1. StoreKit fallback purchase does not grant premium — user pays, stays locked.
2. Review gating in `RateAppViewController` (ratings ≤ 3 never reach the App Store) — violates Guideline 1.1.7.
3. `showAlert(title: "Web Page", message: "TODO")` in `FolderViewController`.
4. Support email hardcoded to the previous owner's personal address.

## Third-party accounts to migrate

- Apple Developer team `SY7683D43P`
- Adapty (`public_live_F7MwJICF…`)
- Firebase project `pdfscanconvertpro`
- Codemagic App Store Connect integration
- Terms/Privacy currently hosted on telegra.ph — move to own domain
