# Window

Everything that lives *outside* the View tree — title, translucent material, custom title bar — is configured here. Each concern has a declarative initial value (a method override on your `App` subclass) and an imperative runtime API on the `wui.Window` module.

For reactivity, combine `wui.Window` with [`wui.Effect`](state/README.md#effect) to re-apply window state whenever a `@:state` field changes:

```haxe
override function effects():Void {
    Effect.run(() -> {
        var n = StateBridge.getInt("unreadCount");
        Window.setTitle('Unread ($n) — MyApp');
    }, [unreadCount]);
}
```

---

## App overrides

These are the **initial values** baked into `App::OnLaunched` at startup. They're macro-extracted at compile time — only literal returns are read. For dynamic updates, use the runtime API below.

### `appName():String`

The OS-level window title. Shown in:

- The taskbar (hover tooltip / thumbnail label)
- Alt+Tab and Win+Tab switchers
- Task Manager
- The system caption bar (only when `titleBar()` returns `null`)

```haxe
override function appName():String return "MyApp";
```

Defaults to the Haxe class name. The macro reads the literal string off the `return` expression, so anything else falls through to the class name. Compute-then-return-a-variable patterns are intentionally not supported here — use `Window.setTitle()` from `effects()` instead.

### `backdrop():Backdrop`

The Window's translucent material — picks up the wallpaper for that "native Windows 11" feel.

```haxe
import wui.Backdrop;

override function backdrop():Backdrop return Acrylic;
```

`Backdrop` values:

| Value | Effect | Cost | Typical use |
|-------|--------|------|-------------|
| `Mica` *(default)* | Wallpaper-tinted opaque surface | Low | Long-lived windows (editor, settings) |
| `MicaAlt` | Mica with higher contrast (BaseAlt variant) | Low | Dense text/charts that need readable bg |
| `Acrylic` | Heavy blur with noise (task-pane feel) | Higher | Transient surfaces — flyouts, sidebars |
| `None` | Opaque system page background | None | Picked when you set a solid `.background()` on the root yourself |

> A `.background(...)` modifier on the root view *covers* the backdrop in that region. Mica/Acrylic only show through transparent areas of the visual tree.

### `titleBar():View`

Replace the system caption bar with a custom view tree — File Explorer / Edge style. Returning `null` (the default) keeps the standard system title bar showing `appName()`.

```haxe
override function titleBar():View {
    return new HStack([
        new Text("MyApp")
            .font(BodyStrong)
            .foregroundColor(primary()),
        new Spacer(),
        new TextBox("Rechercher…", searchQuery).width(280),
    ]).spacing(12).padding();
}
```

What the codegen does for you when a non-null view is returned:

1. **Calls `Window.ExtendsContentIntoTitleBar(true)`** so the system caption row is removed.
2. **Wraps title bar + body in a 2-row Grid** (title bar = Auto, body = Star) so the title bar element is in the visual tree — `SetTitleBar()` only marks the drag region, it does *not* insert the element.
3. **Adds a minimum right Margin of 145px** on the root so the system caption buttons (min/max/close, drawn at the right edge) don't sit on top of your widgets.
4. **Registers each interactive child as a passthrough region** via `InputNonClientPointerSource.SetRegionRects` on `Loaded` and `SizeChanged`. WinUI 3 1.5 does not reliably forward pointer input from the drag region to nested controls — Tab works but mouse clicks don't focus a `TextBox` otherwise. The framework re-computes bounds whenever layout shifts (DPI change, resize, content reflow).

Interactive widgets tracked for passthrough: `Button`, `TextBox`, `ComboBox`, `Slider`, `ToggleSwitch`, `CheckBox`. Decorative children (`Text`, `Image`, `Spacer`) stay drag-region.

---

## `wui.Window` — imperative API

Calls into extern "C" bridges defined in `App.cpp`. Every call is marshalled onto the UI thread (`runOnUIThread`), so it's safe to invoke from a worker thread (e.g. a long-poll loop or a JSON-RPC handler).

```haxe
import wui.Window;
import wui.Backdrop;

Window.setTitle("Some computed value");
Window.setBackdrop(Acrylic);
```

| Method | Effect |
|--------|--------|
| `setTitle(value:String):Void` | Update the OS window title. Visible everywhere `appName()` is. |
| `setBackdrop(value:Backdrop):Void` | Swap the Window's translucent material at runtime. Same `Backdrop` enum as the override. |

These work whether or not you ship the matching App override. The override seeds the initial state; the imperative API mutates afterwards.

---

## Composition with Effect

The `wui.Effect.run(fn, deps)` primitive is the bridge from `@:state` reactivity to imperative window APIs. The lambda runs once at startup and then again every time a dep changes:

```haxe
class MyApp extends wui.App {
    @:state var unreadCount:Int = 0;
    @:state var currentSection:String = "Home";

    override function appName():String return "MyApp";

    override function effects():Void {
        Effect.run(() -> {
            var section = StateBridge.getString("currentSection");
            var n = StateBridge.getInt("unreadCount");
            Window.setTitle(n > 0
                ? '$section ($n) — MyApp'
                : '$section — MyApp');
        }, [unreadCount, currentSection]);
    }
}
```

The deps are typed refs (`[unreadCount, currentSection]`) rather than strings — typos become compile errors and rename refactors carry through. See [Effect](state/README.md#effect) for the full reference.

---

## Pitfalls

- **Setting a solid `.background()` on the root view defeats Mica.** The backdrop only shows through transparent regions. Either drop the background or set `backdrop():Backdrop return None;` to be explicit.
- **`appName()` with a non-literal return falls back to the class name.** The macro only reads string literals. If you need a computed title, override `appName()` to a sensible default and call `Window.setTitle(computed)` from `effects()`.
- **Caption buttons sit at the right edge regardless of `titleBar()`.** They're drawn by the system, not by us, and the right ~138px of the title bar is reserved. Codegen enforces this by padding the title bar root with a minimum right Margin of 145px — your `.frame()`/`.width()` constraints still apply on the remaining region.
- **`Window.setBackdrop(None)` does not restore the *previous* opaque page background colour** — it sets `SystemBackdrop(nullptr)`, after which the window falls back to the framework default (usually `ApplicationPageBackgroundThemeBrush`). If you need a specific colour, set it via `.background()` on the root view.
