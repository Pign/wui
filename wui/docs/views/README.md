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

Repeats a view template for each item in a collection.

```haxe
new ForEach(items:Dynamic, template:Dynamic -> View)
```

```haxe
new ForEach(names, (name) -> new Text(name).padding())
```

Use this to dynamically generate views from an array or state-bound collection.

---

## ConditionalView

Shows or hides content based on a condition.

```haxe
new ConditionalView(condition:Dynamic, thenView:View, ?elseView:View)
```

```haxe
new ConditionalView(
    isLoggedIn,
    new Text("Welcome back!"),
    new Button("Log in")
)
```

When `condition` is a `State<Bool>`, the view swaps automatically when the state changes. The `elseView` is optional -- omit it to show nothing when the condition is false.

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
| `ForEach` | _(dynamic)_ | Collection iteration |
| `ConditionalView` | _(dynamic)_ | Conditional rendering |
