# View Modifiers

Every `View` in wui supports a chainable modifier API. Modifiers describe layout, typography, color, shape, interaction, and lifecycle properties. During compilation, the macro system translates each modifier into the corresponding C++/WinRT property setter.

Modifiers are defined in `wui.modifiers.ViewModifier`.

## Chaining

Modifiers return `this`, so you can chain them:

```haxe
new Text("Hello")
    .font(Title)
    .bold()
    .foregroundColor(AccentColor)
    .padding(16)
    .margin(8)
    .opacity(0.9)
```

Order does not matter -- all modifiers in the chain are applied to the same control.

---

## Layout Modifiers

### padding

Adds uniform padding (WinUI `Padding` as a `Thickness`).

```haxe
.padding()         // default 12px
.padding(16)       // 16px on all sides
```

### margin

Adds uniform margin (WinUI `Margin` as a `Thickness`).

```haxe
.margin()          // default 12px
.margin(8)         // 8px on all sides
```

### frame

Sets explicit dimensions and min/max constraints.

```haxe
.frame(200, 100)                          // width=200, height=100
.frame(null, null, 100, 400, 50, 300)     // minW, maxW, minH, maxH
```

Signature: `frame(?width, ?height, ?minWidth, ?maxWidth, ?minHeight, ?maxHeight)`. Pass `null` for values you want to leave unset.

Generated C++/WinRT: `Width()`, `Height()`, `MinWidth()`, `MaxWidth()`, `MinHeight()`, `MaxHeight()`.

### width / height

Set a single dimension.

```haxe
.width(300)
.height(50)
```

### horizontalAlignment

```haxe
.horizontalAlignment(Center)
```

Values (`HorizontalAlign` enum):

| Value | WinUI mapping |
|-------|--------------|
| `Left` | `HorizontalAlignment::Left` |
| `Center` | `HorizontalAlignment::Center` |
| `Right` | `HorizontalAlignment::Right` |
| `Stretch` | `HorizontalAlignment::Stretch` |

### verticalAlignment

```haxe
.verticalAlignment(Top)
```

Values (`VerticalAlign` enum):

| Value | WinUI mapping |
|-------|--------------|
| `Top` | `VerticalAlignment::Top` |
| `Center` | `VerticalAlignment::Center` |
| `Bottom` | `VerticalAlignment::Bottom` |
| `Stretch` | `VerticalAlignment::Stretch` |

### spacing

Sets the spacing between children of a stack panel.

```haxe
new VStack([...]).spacing(12)
```

Only applies to `VStack` and `HStack`. Generated C++/WinRT: `StackPanel::Spacing()`.

---

## Typography Modifiers

These modifiers apply to `Text` (`TextBlock`) views. Using them on non-text views is a no-op.

### font

Apply a predefined WinUI 3 type ramp style.

```haxe
.font(Title)
```

`FontStyle` enum values:

| Value | Font size | Weight |
|-------|-----------|--------|
| `Caption` | 12px | Normal |
| `Body` | 14px | Normal |
| `BodyStrong` | 14px | SemiBold (600) |
| `Subtitle` | 20px | SemiBold (600) |
| `Title` | 28px | SemiBold (600) |
| `TitleLarge` | 40px | SemiBold (600) |
| `Display` | 68px | SemiBold (600) |

These match the WinUI 3 typography guidelines.

### fontSize

Set an explicit font size in pixels.

```haxe
.fontSize(18)
```

### bold

Set font weight to Bold (700).

```haxe
.bold()
```

### italic

Set font style to Italic.

```haxe
.italic()
```

---

## Color Modifiers

### foregroundColor

Set the text/foreground color. Applies to `Text` views.

```haxe
.foregroundColor(AccentColor)
.foregroundColor(Red)
.foregroundColor(Rgb(30, 144, 255))
.foregroundColor(Hex("#1E90FF"))
```

### background

Set the background brush.

```haxe
.background(Blue)
.background(Argb(128, 255, 0, 0))   // semi-transparent red
.background(Transparent)
```

### opacity

Set the element opacity (0.0 = invisible, 1.0 = fully opaque).

```haxe
.opacity(0.5)
```

### ColorValue enum

The `ColorValue` enum supports named colors, system accent colors, and custom values:

**Named colors:**

| Value | Color |
|-------|-------|
| `Black` | #000000 |
| `White` | #FFFFFF |
| `Red` | #FF0000 |
| `Green` | #008000 |
| `Blue` | #0000FF |
| `Yellow` | #FFFF00 |
| `Orange` | #FFA500 |
| `Purple` | #800080 |
| `Gray` | #808080 |
| `Transparent` | transparent |

**System accent colors:**

| Value | Description |
|-------|-------------|
| `AccentColor` | User's chosen Windows accent color |
| `AccentColorLight1` | Light variant 1 |
| `AccentColorLight2` | Light variant 2 |
| `AccentColorDark1` | Dark variant 1 |
| `AccentColorDark2` | Dark variant 2 |

**Custom colors:**

```haxe
Rgb(r:Int, g:Int, b:Int)              // 0-255 per channel
Argb(a:Int, r:Int, g:Int, b:Int)      // alpha + RGB
Hex(hex:String)                        // "#RRGGBB" or "#AARRGGBB"
```

---

## Shape / Border Modifiers

### cornerRadius

Round the corners of a control.

```haxe
.cornerRadius(8)
```

Generated C++/WinRT: `CornerRadius` with uniform value on all four corners.

### borderBrush

Set the border color.

```haxe
.borderBrush(Gray)
.borderBrush(Rgb(200, 200, 200))
```

### borderThickness

Set the border width.

```haxe
.borderThickness(2)
```

Combine with `borderBrush` and `cornerRadius` for styled containers:

```haxe
new VStack([...])
    .borderBrush(Gray)
    .borderThickness(1)
    .cornerRadius(8)
    .padding(16)
```

---

## Interaction Modifiers

### disabled

Disable a control so it cannot receive input.

```haxe
.disabled()          // disabled
.disabled(true)      // disabled
.disabled(false)     // enabled
```

Generated C++/WinRT: `IsEnabled(!isDisabled)`.

### visible

Set the visibility of a control.

```haxe
.visible()           // visible (default)
.visible(true)       // visible
.visible(false)      // collapsed (hidden and does not take space)
```

Generated C++/WinRT: `Visibility::Collapsed` when false.

### toolTip

Attach a tooltip that appears on hover.

```haxe
.toolTip("Click to submit")
```

Generated C++/WinRT: `ToolTipService::SetToolTip(...)`.

---

## Lifecycle Modifiers

### onLoaded

Run a callback when the control has been loaded into the visual tree.

```haxe
.onLoaded(() -> trace("View is ready"))
```

---

## Full example

```haxe
override function body():View {
    return new VStack([
        new Text("Settings")
            .font(Title)
            .foregroundColor(AccentColor)
            .padding(16),

        new VStack([
            new ToggleSwitch("Notifications"),
            new ToggleSwitch("Dark Mode"),
            new Slider(0, 100)
                .width(200)
                .toolTip("Volume")
        ])
        .spacing(12)
        .padding(16)
        .background(Rgb(245, 245, 245))
        .cornerRadius(8)
        .margin(16)
    ]).horizontalAlignment(Center);
}
```
