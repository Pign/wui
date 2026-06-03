# Views

Every UI element in wui is a `View`. Views map directly to WinUI 3 C++/WinRT controls. You compose them into a tree inside your `body()` method, chain modifiers to style them, and wui's macros generate the corresponding native code.

All view classes live in `wui.ui.*`.

---

## Text

Displays read-only text. Maps to **WinUI `TextBlock`**.

```haxe
new Text(content:Dynamic)
```

```haxe
new Text("Hello World")
    .font(TitleLarge)
    .foregroundColor(AccentColor)
```

The `content` parameter accepts a string literal or a state-bound expression. When bound to a `State<String>`, the text updates automatically.

---

## Button

A clickable button. Maps to **WinUI `Button`**.

```haxe
new Button(label:String, ?icon:Dynamic, ?action:StateAction)
```

```haxe
// Simple button
new Button("Click me")

// Button with a state action
new Button("Increment", null, count.inc(1))

// Button with a callback
new Button("Submit").onClick(() -> doSomething())
```

The third parameter accepts any `StateAction` -- see [State](../state/README.md) for the full list. Use `.onClick()` when you need a custom callback instead.

---

## VStack

Vertical stack layout. Maps to **WinUI `StackPanel`** with `Orientation::Vertical`.

```haxe
new VStack(children:Array<View>, ?spacing:Float)
```

```haxe
new VStack([
    new Text("Top"),
    new Text("Middle"),
    new Text("Bottom")
]).spacing(8)
```

Children are laid out top to bottom. Use the `spacing` parameter or `.spacing()` modifier to add uniform gaps.

---

## HStack

Horizontal stack layout. Maps to **WinUI `StackPanel`** with `Orientation::Horizontal`.

```haxe
new HStack(children:Array<View>, ?spacing:Float)
```

```haxe
new HStack([
    new Button("Cancel"),
    new Spacer(),
    new Button("OK")
]).spacing(8)
```

Children are laid out left to right.

---

## ZStack

Overlapping layout. Maps to **WinUI `Grid`** with all children placed in the same cell.

```haxe
new ZStack(children:Array<View>)
```

```haxe
new ZStack([
    new Image("assets/background.png"),
    new Text("Overlay text")
        .foregroundColor(White)
])
```

Later children render on top of earlier ones.

---

## Spacer

A flexible spacer that expands to fill available space. Pushes siblings apart in stacks.

```haxe
new Spacer(?minSize:Float)
```

```haxe
new VStack([
    new Text("Top"),
    new Spacer(),       // fills the gap
    new Text("Bottom")
])

new Spacer(20)          // at least 20px
```

Implemented as a stretching `Border` element. In a VStack it grows vertically; in an HStack, horizontally.

---

## TextBox

Text input field. Maps to **WinUI `TextBox`**.

```haxe
new TextBox(?placeholder:String, ?binding:Dynamic)
```

```haxe
// Simple text field
new TextBox("Enter your name...")
    .width(200)

// Two-way bound to state
var name = new State<String>("", "name");
new TextBox("Enter name", Binding.fromState(name))
```

Pass a `Binding<String>` to get two-way data binding -- the TextBox reads from and writes to the bound state.

---

## ToggleSwitch

A toggle switch control. Maps to **WinUI `ToggleSwitch`**.

```haxe
new ToggleSwitch(?label:String, ?binding:Dynamic)
```

```haxe
new ToggleSwitch("Dark Mode", Binding.fromState(isDarkMode))
```

The label appears as the switch header. Bind to a `State<Bool>` for two-way updates.

---

## Slider

A slider for numeric ranges. Maps to **WinUI `Slider`**.

```haxe
new Slider(min:Float, max:Float, ?binding:Dynamic, ?step:Float)
```

```haxe
new Slider(0, 100, Binding.fromState(volume))
new Slider(0, 1, Binding.fromState(opacity), 0.1)
```

The `step` parameter sets the tick frequency.

---

## Image

Displays an image. Maps to **WinUI `Image`** with a `BitmapImage` source.

```haxe
new Image(source:String)
```

```haxe
new Image("assets/logo.png")
    .frame(200, 200)
    .cornerRadius(8)
```

The `source` is a URI -- local path or `ms-appx:///` URI.

---

## ScrollViewer

A scrollable container. Maps to **WinUI `ScrollViewer`**.

```haxe
new ScrollViewer(content:View)
```

```haxe
new ScrollViewer(
    new VStack(longListOfItems)
)
```

Wraps a single child view and enables vertical/horizontal scrolling.

---

## ListView

A scrollable list of data items. Maps to **WinUI `ListView`**.

```haxe
new ListView(items:Dynamic, ?itemTemplate:Dynamic -> View)
```

```haxe
new ListView(todos, (todo) -> new HStack([
    new CheckBox(null, Binding.fromState(todo.completed)),
    new Text(todo.title)
]))
```

Pass a collection and a template function. The template receives each item and returns a `View`.

---

## ComboBox

A dropdown picker. Maps to **WinUI `ComboBox`**.

```haxe
new ComboBox(options:Array<String>, ?binding:Dynamic)
```

```haxe
new ComboBox(
    ["Small", "Medium", "Large"],
    Binding.fromState(selectedSize)
)
```

---

## CheckBox

A checkbox control. Maps to **WinUI `CheckBox`**.

```haxe
new CheckBox(?label:String, ?binding:Dynamic)
```

```haxe
new CheckBox("Accept terms", Binding.fromState(accepted))
new CheckBox("Remember me")
```

---

## ProgressRing

A circular progress indicator. Maps to **WinUI `ProgressRing`**.

```haxe
new ProgressRing(?value:Float)
```

```haxe
new ProgressRing()      // indeterminate spinner
new ProgressRing(0.75)  // 75% determinate progress
```

Omit the value for an indeterminate spinner. Pass `0.0`--`1.0` for determinate progress.

---

## NavigationView

Navigation container with a sidebar. Maps to **WinUI `NavigationView`**.

```haxe
new NavigationView(items:Array<NavigationItem>)
```

```haxe
new NavigationView([
    { label: "Home", icon: "Home", content: homeView },
    { label: "Settings", content: settingsView }
])
```

Each `NavigationItem` is a typedef:

```haxe
typedef NavigationItem = {
    label:String,
    ?icon:String,
    content:View
};
```

---

## ContentDialog

A modal dialog. Maps to **WinUI `ContentDialog`**.

```haxe
new ContentDialog(title:String, content:Dynamic, ?primaryButton:String, ?secondaryButton:String, ?closeButton:String)
```

```haxe
new ContentDialog(
    "Confirm Delete",
    "This action cannot be undone.",
    "Delete",
    "Cancel"
)
```

---

## TabView

A tabbed interface. Maps to **WinUI `TabView`**.

```haxe
new TabView(tabs:Array<TabItem>)
```

```haxe
new TabView([
    { label: "Document 1", content: editor1 },
    { label: "Document 2", icon: "Document", content: editor2 }
])
```

Each `TabItem` is a typedef:

```haxe
typedef TabItem = {
    label:String,
    ?icon:String,
    content:View
};
```

---

## Expander

An expandable/collapsible section. Maps to **WinUI `Expander`**.

```haxe
new Expander(header:String, content:View, ?isExpanded:Bool)
```

```haxe
new Expander("Advanced Options", new VStack([
    new ToggleSwitch("Enable logging"),
    new Slider(0, 100)
]), true)
```

Set `isExpanded` to `true` to start expanded.

---

## InfoBar

An information notification bar. Maps to **WinUI `InfoBar`**.

```haxe
new InfoBar(title:String, ?message:String, ?severity:InfoBarSeverity)
```

```haxe
new InfoBar("Update available", "Version 2.0 is ready.", Informational)
new InfoBar("Error", "Connection failed.", Error)
```

Severity values: `Informational`, `Success`, `Warning`, `Error`.

---

## ForEach

Repeats a view template for each item in a collection. Bound to a
[`@:state` Immutable](../state/immutable.md) field — the codegen subscribes
to the field's `<name>__v` trigger and rebuilds the row panel on every
replacement of the underlying list.

```haxe
new ForEach(items:Dynamic, template:Item -> View)
```

```haxe
@:state var todos:ImmutableList<Todo> = ImmutableList.empty();

new ForEach(todos, (todo:Todo) -> new VStack([
    new Text(todo.label).font(BodyStrong),
    new Text(todo.meta).foregroundColor(brand.muted()),
]))
```

What the macro guarantees :

- The `items` argument must be a `@:state` field whose type implements
  `wui.state.Immutable` (typically an `ImmutableList<T>`). Anything else
  fails analysis with a warning pointing at the call.
- The `template` lambda must be a single expression returning either an
  `HStack` / `VStack` (MVP) or a [user component](components.md) — in the
  component case the macro inlines the component's `body()` and applies
  the same rules below.
- Each row child must be `new Text(<literal>)` or
  `new Text(<lambdaParam>.<field>)`. Modifier chains on those Texts
  (`.font(...)`, `.foregroundColor(...)`, `.bold()`, …) are honoured — the
  ForEach analyzer walks the call chain and applies each modifier to the
  per-row `TextBlock`.

The generated code emits a vertical StackPanel, a `std::function<void()>`
rebuild closure that pulls the current row count and each per-field value
through `wui.generated.ForEachAccessor` (Haxe-side), and a listener on
`s_<items>__v_listeners` that re-runs the closure via
`DispatcherQueue.TryEnqueue` (same re-entrance pattern as other state
bindings).

### Row interaction

Row-tap handlers go through the generic [`.onTap(StateAction)`](#interaction)
modifier on the row View — same modifier you'd use on any other widget.
The per-row index isn't exposed to the template lambda yet, so the action's
target has to be something the row can derive from its own data (e.g.
`StateAction.SetValue(detailId, todo.id)` reads the row's id at codegen
time). Surfacing the index to the lambda is a tracked follow-up.

> **Known gap** — modifiers stacked on the template root (`(item) ->
> new MyRow(...).onTap(...)`) don't propagate to the row container yet
> in the current ForEach implementation. For now, attach `.onTap` on a
> wrapping primitive inside the template, or wait for the propagation
> pass.

The full background — Immutable triggers, accessor codegen, why the list
never crosses the bridge — is in [Immutable state](../state/immutable.md).

---

## Interaction

The `.onTap(action:StateAction)` modifier is inherited by every View —
primitives and user components alike. It fires a `StateAction` when the
user clicks or taps anywhere inside the view's bounds. The action vocabulary
is identical to `Button`'s :

```haxe
new MyComponent(...)
    .onTap(selectedIdx.setTo(3))                       // method-form action
    .onTap(StateAction.Toggle(isExpanded))             // enum constructor
    .onTap(StateAction.Custom(MyApp.handleTap))        // static fn ref
    .onTap(StateAction.Custom(() -> {                  // anonymous lambda
        wui.state.StateBridge.setString("status", "tapped");
        sys.thread.Thread.create(doWork);
    }))
    .onTap(StateAction.Sequence([                      // chain
        StateAction.SetValue(loadingFlag, true),
        StateAction.Custom(MyApp.fetchDetail),
    ]));
```

Under the hood : the modifier analyzer compiles the `StateAction` to a C++
snippet (same path used for `Button.action`), and `applyModifiers` wraps it
in a `Tapped` event handler attached to the resulting WinRT control. `Tapped`
is on `UIElement`, so the modifier composes with any primitive — including
`Button` (its `Click` and the `Tapped` from `.onTap` both fire on a mouse
click, the user can pick either route).

---

## Show

Visibility gate keyed on a `@:state Bool`. Both branches are emitted into
the XAML tree at compile time ; only the `Visibility` property flips
between `Visible` and `Collapsed` at runtime — no rebuild.

```haxe
new Show(when:Dynamic, child:View)
```

```haxe
@:state var isConnected:Bool = false;
@:state var isLoginShown:Bool = true;

new VStack([
    new Show(isLoginShown,  new LoginScreen(...)),
    new Show(isConnected,   new MainScreen(...)),
])
```

The `when` argument is a `@:state Bool` field reference. Maps to a WinUI
`ContentControl` whose `Visibility` is bound to the state.

Use it for screen-level routing (login → app) and conditional sub-sections
where the inner tree is static. For content that depends on which item in
a list is selected, use a per-row [`Effect.run`](../state/README.md#effect)
instead.

Negation isn't supported directly — `new Show(!isConnected, ...)` won't
analyse. Declare a companion `@:state` and flip both flags together
(typical pattern for two-screen apps).

---

## Summary table

| wui class | WinUI 3 control | Purpose |
|-----------|-----------------|---------|
| `Text` | `TextBlock` | Display text |
| `Button` | `Button` | Clickable action |
| `VStack` | `StackPanel` (Vertical) | Vertical layout |
| `HStack` | `StackPanel` (Horizontal) | Horizontal layout |
| `ZStack` | `Grid` (overlapping) | Layered layout |
| `Spacer` | `Border` (stretch) | Flexible space |
| `TextBox` | `TextBox` | Text input |
| `ToggleSwitch` | `ToggleSwitch` | Boolean toggle |
| `Slider` | `Slider` | Numeric range |
| `Image` | `Image` | Display image |
| `ScrollViewer` | `ScrollViewer` | Scrollable container |
| `ListView` | `ListView` | Data list |
| `ComboBox` | `ComboBox` | Dropdown picker |
| `CheckBox` | `CheckBox` | Boolean checkbox |
| `ProgressRing` | `ProgressRing` | Progress indicator |
| `NavigationView` | `NavigationView` | Sidebar navigation |
| `ContentDialog` | `ContentDialog` | Modal dialog |
| `TabView` | `TabView` | Tabbed interface |
| `Expander` | `Expander` | Collapsible section |
| `InfoBar` | `InfoBar` | Notification bar |
| `ForEach` | `StackPanel` + dynamic rows | Reactive collection iteration |
| `Show` | `ContentControl` | Visibility gate on a `@:state Bool` |
