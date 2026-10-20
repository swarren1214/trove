# Trove

Trove is the sixth Hearth app: a private vault for a household's important documents, tied to
the people and things they belong to, and to where the paper original is kept. SwiftUI, iOS 26
and iPadOS 26. Rules for changing the code are in AGENT.md; the plan is the "Trove —
Implementation Plan" doc, and the screens are the Trove design canvas.

## App icon

`Trove/AppIcon.icon` is the Icon Composer icon (from `~/Developer/app-icons/trove.icon`), and
it's what iOS 26 uses. `Assets.xcassets/AppIcon.appiconset` holds a flat 1024 render as a
fallback. The light and dark renders are also in `hearthkit/Hearth/trove.imageset` (96 pt), for
the splash and the Hearth Apps page in every app. To change the icon, edit it in Icon
Composer, copy it over `Trove/AppIcon.icon`, and re-export the renders.

## First build

1. In `~/Developer/hearthkit`, run `bash sync.sh`. It copies the shared Hearth code and the
   Hearth icons into Trove (and into the other five apps, which pick up the new `.trove` case).
   Trove already has copies of the shared Swift files, so it builds before the sync; the sync
   adds the app icons for the Hearth Apps page and the splash.
2. Open `Trove.xcodeproj`. Xcode resolves RevenueCat (the only package).
3. Signing & Capabilities: the team is set (BH8R3BX5WF). In the developer portal, create the App
   ID `com.stephenwarren.trove` with iCloud (container `iCloud.com.stephenwarren.hearth`), Push
   Notifications, Sign in with Apple and the App Group `group.com.stephenwarren.hearth`.
4. RevenueCat: add Trove to the Hearth project, create `trove_plus` (monthly and yearly) and put
   the public key in `AppConfig.revenueCatAPIKey`. Until then, paid features stay locked and
   everything else works.
6. CloudKit: run once against Development, add a document with a scan and a place, then deploy
   the schema (record types `VaultAsset`, `VaultDocument`, `VaultPlace`, `VaultScan`).

## How it's built

| Folder | What's there |
| --- | --- |
| `App/` | `TroveApp` (launch, the root, the lock and privacy covers, the scene delegate for household invitations), `RootTabView`, `AppRouter` (tabs, paths, the Add sheet), `AppConfig` |
| `Models/` | `TroveAsset`, `TroveDocument`, `TroveScan`, `TrovePlace`, `TroveState`; `DocumentType` (symbols, numbers, lead times, renewal notes); `Attention` (what needs a look) |
| `Services/` | `TroveStore` (the vault, a `HearthZoneParticipant`), `TroveSharing`, `TroveFiles` (state and scans on the device), `Reminders`, `AppLock`, `TroveExport` (PDFs) |
| `Services/Capture/` | `DocumentCamera` (VisionKit), `DocumentReader` (license barcodes, passport lines, Vision text, the on-device model) |
| `Services/Hearth/` | Copies of HearthKit. Never edit them here |
| `DesignSystem/` | Brand colors, the color header, cards, the top bar, sheet buttons, menu icons |
| `Features/` | Home, Assets, Documents, People, Originals, Capture (Add Document), Search, Profile, Onboarding |

### Data

The vault is one JSON state per family on the device (Application Support/Trove), plus each
scan as a JPEG, mirrored to the `Trove` zone in the Hearth container. Every asset, document and
place is one record whose content is encrypted JSON; every scan is a record with the image as an
asset. The newest `updatedAt` wins. A document belongs to a household person (their Hearth id),
an asset, or the household, and points at a place for its original.

### Reading a document

`DocumentReader.read` tries, in order: the PDF417 barcode on a license or ID (AAMVA fields), a
passport's machine-readable lines (checked with their check digit), then Vision's text with the
on-device model filling in the type, name, number, issuer and dates. On devices without Apple
Intelligence, the first two still work and the person picks the type. What's read only fills
empty fields, and the person checks it before saving. Every page is saved as captured.

### Reminders

Local notifications, scheduled on each device from the synced vault: at the start of each
document's lead time (`DocumentType.defaultLeadDays`, or the document's own), a week before,
and on the day; and a yearly check on each place. The 50 soonest are scheduled.

## What's not here yet

- Widgets (Needs Attention), the vehicle render on an asset (needs an image API), and the
  iPad-specific layouts beyond the adaptive grids.
- Contributing `SecureValue` and the reminder scheduler to HearthKit, once another app needs them.
- Trove isn't on the Hearth Apps page yet (`HearthAppInfo.order`); add it with its TestFlight link.
