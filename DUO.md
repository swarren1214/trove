# Trove on iPhone Duo

Trove has no Duo design yet, so this is the optimization pass plus one fit: the document list
beside the selected document in Search › Browse. Nothing is committed; review with `git diff`.
(The four `trove.imageset` PNG changes in `git status` were there before this work.)

## What changed

- `App/TroveApp.swift`: `.hearthDuoPose()` on the scene root (after the environment, outside the
  tab view), so every screen can read `\.hearthDuoPose`.
- `DesignSystem/Toolbar.swift`: `troveToolbar` puts its group at `.primaryAction` instead of
  `.topBarTrailing`, so the system can move it to the outer display's trailing rail. Same place
  as before on other iPhones and iPad. New `overColorHeader:` option (default true): when false,
  action icons use the text color instead of white (used by the document pane, which sits under a
  plain list bar).
- `DesignSystem/Components.swift`:
  - `TroveScreen` has `ownsBar:` (default true). When false it draws only the header and cards
    and leaves the navigation title and bar alone. Behavior with the default is unchanged.
  - New `EvenGrid`: a `LazyVGrid` with 2, 4 or 6 columns from the width it has
    (`HearthEvenColumns`), so a fold never cuts through a card.
- `Features/Home/HomeView.swift`, `Features/Assets/AssetsView.swift`: the asset tile grids use
  `EvenGrid(minimumCellWidth: 150)` instead of an adaptive grid (which could give 3 or 5 columns).
- `Features/Documents/DocumentDetailView.swift`: the scan thumbnail grid uses `EvenGrid`. New
  `inPane:` (default false): as a pane it shows a large title in the content, doesn't take over the
  bar, hides the profile avatar (the list's screen has none either), and stays put after a delete
  (the list picks the next document).
- `Features/Search/SearchView.swift`: Search › Browse › a group (`GroupDocumentsView`). With
  regular width and either landscape or a fold, the list and the selected document show side by
  side in `HearthFoldSplit`. Tapping a row selects it (highlighted) instead of pushing. Otherwise
  rows push as before. The selection is `@State` on the list screen, so it survives rotating,
  folding and unfolding.

Checked already, left alone:
- All sheet toolbars already use `SheetCancelButton`/`SheetDoneButton` in `.cancellationAction`/
  `.confirmationAction`. Screen toolbar buttons already have a title and symbol
  (`Button("Edit", systemImage: "pencil")`, `Menu("More", systemImage: "ellipsis")`).
- `ScanViewer`'s Close is already `.cancellationAction` with title and symbol.
- `TabView` is the standard one, so the tab bar moves to the rail by itself.
- No `UIScreen.main.bounds`. `DeviceName` reads the idiom only for the word "iPhone"/"iPad" in a
  sentence, not for layout. `PresentView` reads the scene's screen only for brightness.
- `ReadingView`'s 320/340 pt caps and `LockView`/`PrivacyNote` max widths are readable-width caps
  that work at any width, not phone-width assumptions.

## How each pose behaves now

- Standard (other iPhones, iPad, Duo inner portrait / Open tall): same as before, except asset and
  scan grids are always an even number of columns. On iPad landscape, Search › Browse shows list
  and document side by side.
- Outer (closed or tent): compact width. The tab bar and each screen's actions (+ avatar) move to
  the trailing rail. Browse pushes as on any iPhone.
- Open wide (inner landscape): regular width. Search › Browse shows the list on the left and the
  selected document on the right. Grids get 4 or 6 columns.
- Book (folded, fold vertical): Browse shows list and document in equal pages, nothing in the fold.
- Laptop (folded, fold horizontal): Browse shows the list on the top half and the document on the
  bottom half (Apple's split arrangement stacks them).

## Testing in the iPhone Duo simulator

1. Build on the iPhone Duo simulator (iOS 27.1). Add a few documents of one group (say two IDs and
   a passport) and two or three assets.
2. Closed: check the tab bar and the + / avatar sit on the trailing rail on Home, Assets, People,
   Originals, a document, an asset and a place. Check sheets still show the round X and checkmark.
3. Open tall: Home and Assets grids should show 2 columns; a document's scans 2.
4. Open wide: Search › Browse › Identity. The list is on the left, the first document on the right.
   Tap another row: the right side changes, the row highlights. Edit from the bar edits the
   document on the right. Delete it from Edit: the next one shows.
5. Fold to Book and to Laptop with Browse open: equal panes, nothing under the fold, the same
   document still selected. Unfold and rotate to portrait: back to a plain list, and tapping pushes.
6. Repeat 4 on an iPad in landscape and in Split View (narrow Split View should push).

## Skipped, and why

- A two-level split on Home, People, Assets and Originals: they're card screens inside a
  `TroveScreen` scroll view with pushes through the router's paths. Splitting them means
  reworking `AppRouter` navigation, which the brief said not to do wholesale.
- A glance board: not wanted for Trove.
- `PresentView`'s floating Done button: a deliberate full-screen immersive view, kept as is.
- Text action buttons inside cards ("Scan", "Rescan", "Still There", "Choose", "Scan the New
  One", "See all"): these are in-content controls, not toolbar items, so the rail rule doesn't apply.

## Ideas for a Trove Duo design (not built)

- Present in Book pose: the scan on one page, the facts (masked number, dates) on the other, so
  you can hand over the scan side at a counter while keeping the number.
- Laptop pose on a document: scans on the top half, Present / Share / Export controls on the
  flat half (`HearthFoldOverlay`).
- Open wide on People: the person switcher as a list on the left, their essentials on the right.
- Originals open wide: places on the left, what's in the selected place on the right.
- Add Document while folded: camera preview on top, the read fields below to check before saving.

## Please confirm

1. Moving `troveToolbar` from `.topBarTrailing` to `.primaryAction`. On iOS 26 iPhone and iPad
   both are the top trailing corner, so it should look the same; please glance at Home on iPad.
2. In the Browse split, the document pane hides the profile avatar and uses text-colored icons
   (the bar there is the plain Search list bar, not the blue header). OK?
3. The split only appears in Search › Browse. Want it on People or Originals next (needs a router
   change)?
4. `EvenGrid` caps at 6 columns; the old adaptive grids had no cap. Fine for iPad full width?

## Review (overnight)

Checked every changed .swift file against the codebase and HearthDuo.swift: symbol names,
argument labels, initializers, ViewBuilder rules, toolbar placements, banned APIs (none used),
AGENT.md rules (menus, app color, sheet buttons, alerts). Syntax check: 0 errors.

What checked out:
- `SearchView.swift` ~128–163: `let roomy` and `if roomy, let selected = … ?? documents.first`
  inside the GeometryReader closure are valid in a view builder. `listRowBackground(isSelected ?
  Color(.tertiarySystemFill) : nil)` infers `Color?`, which the modifier accepts.
  `accessibilityAddTraits(isSelected ? .isSelected : [])` infers `AccessibilityTraits`. Selection
  is `@State` above both layouts, so it survives pose changes. `.refreshable` on the
  GeometryReader still reaches the List and the pane.
- `Components.swift` ~70–92: `TroveScreen.body` as if/else is fine (implicit view builder);
  `ownsBar` is constant per screen, so no identity flips. All 9 existing `TroveScreen(` calls
  still match the init (new parameter has a default).
- `Components.swift` ~343+: `EvenGrid`'s memberwise init works from other files; the private
  `@State width` has a default, so it's left out of the init and doesn't make it private (same
  pattern as the app's `Card`). Call sites `EvenGrid(minimumCellWidth:)` and
  `EvenGrid(minimumCellWidth:spacing:)` match. Column counts on iPhone and iPad full width are
  the same as the old adaptive grids (2 and 4).
- `Toolbar.swift`: `.primaryAction` is the trailing end on iOS 26 iPhone/iPad.

Fixed:
- `Features/Documents/DocumentDetailView.swift:14,30-34,26,76`: in the Browse split, the pane's
  Edit icon was set to the text color everywhere. When the panes are side by side (iPad
  landscape, Open wide, Book) the pane's blue header runs up under the trailing end of the bar,
  so a black icon there sat on blue. Now it stays white unless the pose is Laptop (pane stacked
  below the list, bar over the plain list).

Remaining risks and questions:
- On iOS 27.1, whether Apple's split arrangement lets the pane's header run under the bar is
  unconfirmed; check Edit's icon contrast in Open wide and Book in the simulator.
- iPad landscape side by side with iOS 26 (fallback split): the pane's header is under the bar's
  trailing end, so white icons are right; check in Light Mode.
- Same as above: the bar title in the split is the group name ("Identity") in the text color over
  the list pane; fine, but the blue header only covers the right half of the bar.
