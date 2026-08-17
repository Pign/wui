# Component Mapping: sui (SwiftUI) to wui (WinUI 3)

This table maps concepts from [sui](https://github.com/lapavoiserie/sui) (Haxe-to-SwiftUI for macOS/iOS) to their wui equivalents (Haxe-to-WinUI 3 for Windows).

## Views

| sui (SwiftUI) | wui (WinUI 3) | Notes |
|----------------|----------------|-------|
| `Text` -> `SwiftUI.Text` | `Text` -> `TextBlock` | Same API. wui uses `TextBlock` (WinUI's read-only text control). |
| `Button` -> `SwiftUI.Button` | `Button` -> `Button` | Both accept a label and action. wui adds optional `icon` parameter. |
| `VStack` -> `VStack` | `VStack` -> `StackPanel` (Vertical) | Identical API. Different native control. |
| `HStack` -> `HStack` | `HStack` -> `Grid` (columns) | Identical API. A Grid, not a StackPanel: a panel hands each child the size it asks for and distributes nothing, so a `Spacer` in it came out zero wide. Each child gets a column, `Auto` for content and `*` for a spacer. |
| `ZStack` -> `ZStack` | `ZStack` -> `Grid` (overlapping) | WinUI has no ZStack; wui uses a Grid with children in the same cell. |
| `Spacer` -> `Spacer` | `Spacer` -> `Border` (a starred column) | Same concept. An empty Border, tagged so the `HStack` around it gives its column the leftover width. In a `VStack` it takes none: a StackPanel cannot distribute height, and saying so beats a spacer that works in one direction only. |
| `TextField` -> `TextField` | `TextBox` -> `TextBox` | Named `TextBox` to match WinUI naming. |
| `Toggle` -> `Toggle` | `ToggleSwitch` -> `ToggleSwitch` | Named `ToggleSwitch` to match WinUI naming. |
| `Slider` -> `Slider` | `Slider` -> `Slider` | Same API. |
| `Image` -> `Image` | `Image` -> `Image` | Both accept a source string. |
| `ScrollView` -> `ScrollView` | `ScrollViewer` -> `ScrollViewer` | Named to match WinUI. |
| `List` -> `List` | `ListView` -> `ListView` | Named to match WinUI. |
| `Picker` -> `Picker` | `ComboBox` -> `ComboBox` | WinUI equivalent of a dropdown picker. |
| -- | `CheckBox` -> `CheckBox` | WinUI-specific. SwiftUI uses Toggle with a checkbox style. |
| `ProgressView` -> `ProgressView` | `ProgressRing` -> `ProgressRing` | WinUI uses a ring by default. |
| `NavigationStack` -> `NavigationStack` | `NavigationView` -> `NavigationView` | A few top-level sections, in `Top` mode by default so it reads the way tabs read elsewhere. It owns its selection in a shared cell, as sui's renderer does — so an app that says nothing about selection still gets working tabs. One navigation bar per application. |
| -- | `ContentDialog` -> `ContentDialog` | WinUI-specific modal dialog. SwiftUI uses `.alert()` / `.sheet()`. |
| `TabView` -> `TabView` | `TabView` -> `TabView` | Document tabs: each carries a close button and the strip offers a "+". Right for things a user opens and closes. **`mui.ui.TabView` maps to `NavigationView` instead**, because the sections of an app can be neither closed nor added. |
| -- | `SelectorBar` -> `SelectorBar` | wui-specific segmented selector: not which section of the app you are in, but which of several views of one page. No `mui` equivalent, and not looking for one. |
| -- | `TabViewItem` -> `TabViewItem` | A `TabView` holds items, not contents. Built by `TabView`'s constructor; you rarely write one. |
| -- | `Border` -> `Border` | WinUI has neither separator nor spacer, and both **are** a border. |
| `DisclosureGroup` -> `DisclosureGroup` | `Expander` -> `Expander` | WinUI equivalent of collapsible sections. |
| -- | `InfoBar` -> `InfoBar` | WinUI-specific notification bar. No direct SwiftUI equivalent. |
| `ForEach` -> `ForEach` | `ForEach` | Same API. |
| -- | `ConditionalView` | wui-specific. In sui/SwiftUI, use `if/else` in view builders. |

## Modifiers

| sui (SwiftUI) | wui (WinUI 3) | Notes |
|----------------|----------------|-------|
| `.padding()` | `.padding()` | Same API. Both default to system standard. |
| -- | `.margin()` | WinUI-specific. SwiftUI handles margins differently. |
| `.frame()` | `.frame()` | Same parameters: width, height, min/max variants. |
| -- | `.width()` / `.height()` | Convenience shortcuts (also available in sui). |
| -- | `.horizontalAlignment()` | WinUI uses explicit alignment enums. SwiftUI uses `.frame(alignment:)`. |
| -- | `.verticalAlignment()` | Same as above. |
| `.spacing()` | `.spacing()` | Both set stack spacing. |
| `.font()` | `.font()` | Both use a type-ramp enum. Values differ to match platform guidelines. |
| `.fontSize()` | `.fontSize()` | Same API. |
| `.bold()` | `.bold()` | Same API. |
| `.italic()` | `.italic()` | Same API. |
| `.foregroundColor()` | `.foregroundColor()` | Same API. Color enums differ. |
| `.background()` | `.background()` | Same API. |
| `.opacity()` | `.opacity()` | Same API. |
| `.cornerRadius()` | `.cornerRadius()` | Same API. |
| -- | `.borderBrush()` | WinUI-specific. SwiftUI uses `.overlay()` or `.border()`. |
| -- | `.borderThickness()` | WinUI-specific. |
| `.disabled()` | `.disabled()` | Same API. |
| -- | `.visible()` | WinUI-specific. SwiftUI uses conditional views or `.opacity(0)`. |
| -- | `.toolTip()` | WinUI-specific. SwiftUI uses `.help()` on macOS. |
| `.onAppear()` | `.onLoaded()` | Same concept, different name to match WinUI lifecycle. |

## Font styles

| sui (SwiftUI) | wui (WinUI 3) | Size |
|----------------|----------------|------|
| `Caption` / `.caption` | `Caption` | 12px |
| `Body` / `.body` | `Body` | 14px |
| `Headline` / `.headline` | `BodyStrong` | 14px semibold |
| `Title3` / `.title3` | `Subtitle` | 20px semibold |
| `Title` / `.title` | `Title` | 28px semibold |
| `LargeTitle` / `.largeTitle` | `TitleLarge` | 40px semibold |
| -- | `Display` | 68px semibold (WinUI-specific) |

## Colors

| sui (SwiftUI) | wui (WinUI 3) |
|----------------|----------------|
| `.accentColor` | `AccentColor` |
| `.primary` | `Black` / `White` (theme-dependent) |
| `.red` | `Red` |
| `.green` | `Green` |
| `.blue` | `Blue` |
| `.clear` | `Transparent` |
| `Color(red:green:blue:)` | `Rgb(r, g, b)` |
| `Color(red:green:blue:opacity:)` | `Argb(a, r, g, b)` |
| -- | `AccentColorLight1`, `Light2`, `Dark1`, `Dark2` (WinUI-specific) |
| -- | `Hex("#RRGGBB")` |

## State

| sui (SwiftUI) | wui (WinUI 3) | Notes |
|----------------|----------------|-------|
| `@:state` / `State<T>` | `@:state` / `State<T>` | Same API. |
| `StateAction` | `StateAction` | Same enum variants. |
| `Binding<T>` | `Binding<T>` | Same API. `Binding.fromState()` in both. |
| `Observable` | `Observable` | Same concept. |
| `StateOr<T>` | `StateOr<T>` | Same API. |

## Architecture

| Concept | sui | wui |
|---------|-----|-----|
| Target platform | macOS / iOS | Windows 10/11 |
| Native UI toolkit | SwiftUI | WinUI 3 (C++/WinRT) |
| Haxe target | hxcpp -> C++ | hxcpp -> C++ |
| Native language | Swift (via generated code) | C++/WinRT (via generated code) |
| Bridge | None (compile-time) | None (compile-time) |
| Build system | Xcode / xcodebuild | MSBuild / .vcxproj |
| Package manager | Swift Package Manager | NuGet |
| CLI tool | `sui init/build/run` | `wui init/build/run` |
| Config file | `sui.json` | `wui.json` |
| Deployment | .app bundle | Self-contained .exe |

## Porting an app from sui to wui

1. Replace imports: `sui.ui.*` becomes `wui.ui.*`, `sui.App` becomes `wui.App`.
2. Rename platform-specific views: `TextField` -> `TextBox`, `Toggle` -> `ToggleSwitch`, `ScrollView` -> `ScrollViewer`, `List` -> `ListView`, `Picker` -> `ComboBox`, `ProgressView` -> `ProgressRing`, `DisclosureGroup` -> `Expander`.
3. Rename font styles: `Headline` -> `BodyStrong`, `Title3` -> `Subtitle`, `LargeTitle` -> `TitleLarge`.
4. Replace `.onAppear()` with `.onLoaded()`.
5. Add `.margin()` where needed (SwiftUI handles margins implicitly).
6. Replace `sui.json` with `wui.json`.
7. Replace `build.hxml` to use `-lib wui` instead of `-lib sui`.

State management (`@:state`, `StateAction`, `Binding`) is identical and requires no changes.
