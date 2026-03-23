# State Management

wui uses a reactive state system. You declare state variables with `@:state`, and the framework automatically regenerates UI when state changes. Under the hood, state updates flow directly through C++ -- there is no cross-language bridge.

All state types live in `wui.state.*`.

---

## State\<T\>

The core reactive container. Holds a value and notifies subscribers when it changes.

```haxe
var count = new State<Int>(0, "count");

// Read
trace(count.value);    // 0

// Write (notifies all subscribers)
count.value = 5;

// Subscribe to changes
count.subscribe((newValue) -> trace("count is now: " + newValue));
```

### Constructor

```haxe
new State<T>(initial:T, stateName:String)
```

- `initial` -- the starting value.
- `stateName` -- a unique string name used in the global registry and for code generation.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `value` | `T` (get/set) | Current value. Setting it notifies all subscribers. |
| `name` | `String` | The registered state name. |

### Methods

| Method | Description |
|--------|-------------|
| `subscribe(fn:T -> Void)` | Register a listener called on every value change. |
| `unsubscribe(fn:T -> Void)` | Remove a previously registered listener. |
| `inc(amount)` | Returns a `StateAction.Increment` for this state. |
| `dec(amount)` | Returns a `StateAction.Decrement` for this state. |
| `setTo(val)` | Returns a `StateAction.SetValue` for this state. |
| `tog()` | Returns a `StateAction.Toggle` for this state. |
| `appendAction(val)` | Returns a `StateAction.Append` for this state. |

### Static helpers

| Method | Description |
|--------|-------------|
| `State.getByName(name)` | Look up a state instance by its registered name. |
| `State.setByName(name, value)` | Set a state's value by name (string-based). |

---

## @:state macro

The `@:state` metadata on a field is the recommended way to declare state in an `App` or `ViewComponent`. The `StateMacro` transforms it at compile time.

```haxe
class MyApp extends wui.App {
    @:state var count:Int = 0;
    @:state var name:String = "World";
    @:state var isDark:Bool = false;
}
```

This compiles to:

```haxe
var count:State<Int>;   // initialized in constructor as new State<Int>(0, "count")
var name:State<String>; // initialized as new State<String>("World", "name")
var isDark:State<Bool>; // initialized as new State<Bool>(false, "isDark")
```

The macro:

1. Changes the field type from `T` to `State<T>`.
2. Injects `new State<T>(initialValue, "fieldName")` into the constructor.
3. Creates a constructor if one does not exist.

You then use `count.value`, `count.inc(1)`, etc. in your `body()`.

---

## StateAction

Declarative state mutations. Passed to `Button` and other interactive controls to describe what happens on interaction. The UIBuilder macro translates these directly into C++/WinRT code.

```haxe
new Button("Add", null, count.inc(1))
new Button("Reset", null, count.setTo(0))
new Button("Toggle Dark", null, isDark.tog())
```

### All actions

| Action | Description | Example |
|--------|-------------|---------|
| `Increment(state, amount)` | Add `amount` to a numeric state. | `count.inc(1)` |
| `Decrement(state, amount)` | Subtract `amount` from a numeric state. | `count.dec(1)` |
| `SetValue(state, value)` | Set state to a specific value. | `count.setTo(0)` |
| `Toggle(state)` | Flip a boolean state. | `isDark.tog()` |
| `Append(state, value)` | Append a value to an array state. | `items.appendAction(newItem)` |
| `Remove(state, value)` | Remove a value from an array state. | `Remove(items, item)` |
| `Custom(callback)` | Execute an arbitrary callback. | `Custom(() -> doWork())` |
| `Animated(action, curve)` | Wrap an action with animation. | `Animated(count.inc(1), EaseOut)` |
| `Sequence(actions)` | Execute multiple actions in order. | `Sequence([count.inc(1), msg.setTo("Done")])` |

### AnimationCurve

Used with the `Animated` action:

| Value | Description |
|-------|-------------|
| `Default` | System default easing |
| `Linear` | Constant speed |
| `EaseIn` | Slow start |
| `EaseOut` | Slow end |
| `EaseInOut` | Slow start and end |
| `Spring` | Spring physics |
| `Bouncy` | Bounce at the end |

---

## Binding\<T\>

Two-way binding between a state and a control that both reads and writes. Used by `TextBox`, `ToggleSwitch`, `Slider`, `ComboBox`, and `CheckBox`.

```haxe
var name = new State<String>("", "name");

// Create a two-way binding
new TextBox("Enter name", Binding.fromState(name))
```

### Constructor

```haxe
new Binding<T>(getter:() -> T, setter:T -> Void)
```

### Factory method

```haxe
Binding.fromState(state:State<T>):Binding<T>
```

Creates a binding that reads from `state.value` and writes back to `state.value`. This is the typical usage.

### Manual binding

For computed or filtered bindings:

```haxe
var binding = new Binding<String>(
    () -> name.value.toUpperCase(),
    (v) -> name.value = v.toLowerCase()
);
```

---

## Observable

Base class for observable data models. Tracks which properties have changed and notifies listeners by property name.

```haxe
class TodoItem extends Observable {
    public var title:String;
    public var completed:Bool;

    public function setTitle(t:String) {
        title = t;
        notifyChanged("title");
    }
}
```

### Methods

| Method | Description |
|--------|-------------|
| `onPropertyChanged(listener:String -> Void)` | Subscribe to property-level change notifications. |
| `notifyChanged(propertyName:String)` | Fire a change notification for the named property. |

Use `Observable` for model objects in `ListView` and `ForEach` templates.

---

## StateOr\<T\>

Union type that lets a modifier accept either a static value or a reactive state.

```haxe
enum StateOr<T> {
    Static(value:T);
    Reactive(state:State<T>);
}
```

```haxe
.opacity(0.5)              // Static value
.opacity(opacityState)     // Reactive -- updates when state changes
```

This is used internally by the modifier system to support both patterns.

---

## How state updates flow

```mermaid
sequenceDiagram
    participant User
    participant Button as Button (C++/WinRT)
    participant Action as StateAction
    participant State as State&lt;T&gt;
    participant Sub as Subscriber lambda
    participant UI as TextBlock (C++/WinRT)

    User->>Button: Click
    Button->>Action: Execute (e.g. Increment)
    Action->>State: set_value(newValue)
    State->>Sub: notify(newValue)
    Sub->>UI: .Text(newValue)
    Note over UI: UI updates instantly<br/>(same C++ process)
```

Because both hxcpp and C++/WinRT compile to native C++, state subscriber lambdas directly call WinUI control APIs. There is no serialization, no JSON, no cross-process communication.

---

## Full example: counter app

```haxe
class Counter extends wui.App {
    @:state var count:Int = 0;

    override function appName():String return "Counter";

    override function body():View {
        return new VStack([
            new Text("Counter")
                .font(Title),
            new Text("0")
                .font(TitleLarge)
                .foregroundColor(AccentColor),
            new HStack([
                new Button("Decrement", null, count.dec(1)),
                new Button("Reset", null, count.setTo(0)),
                new Button("Increment", null, count.inc(1))
            ]).spacing(8)
        ]).horizontalAlignment(Center);
    }
}
```
