package wui;

/**
 * Window-level translucent material applied via
 * `Microsoft.UI.Xaml.Window.SystemBackdrop`. Picked up by
 * `WinUIGenerator` from the `App.backdrop():Backdrop` override and
 * emitted into the generated `App::OnLaunched` body.
 *
 * - `Mica` is the Windows 11 default — a wallpaper-tinted opaque
 *   surface, low CPU cost, expected on long-lived windows (mail,
 *   browser, settings).
 * - `MicaAlt` is the higher-contrast variant — slightly darker tint
 *   that reads better behind dense text or charts.
 * - `Acrylic` is the heavier blur with noise — Windows 11 task pane
 *   feel. Costlier; use on transient surfaces (flyouts, sidebars).
 * - `None` disables the backdrop and falls back to the system theme's
 *   opaque page background. Pick this when you set a solid
 *   `Background` modifier on the root view yourself.
 *
 * Note: a `.background(...)` modifier on the root content covers the
 * backdrop in that region — Mica/Acrylic only show through transparent
 * areas of the visual tree.
 */
enum Backdrop {
    None;
    Mica;
    MicaAlt;
    Acrylic;
}
