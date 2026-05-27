# State Management

wui uses a reactive state system. You declare state variables with `@:state`, and the framework automatically regenerates UI when state changes. Under the hood, state updates flow directly through C++ — there is no cross-language bridge.

All state types live in `wui.state.*`.

---

## State\<T\>

The core reactive container. Holds a value and notifies subscribers when it changes.

```haxe
var count = new State<Int>(0, "count");

// Read
trace(count.value);    // 0
trace(count.get());    // 0  (alias)

// Write (notifies all subscribers)
count.value = 5;
count.set(10);         // alias for count.value = 10

// Subscribe to changes
count.subscribe((newValue) -> trace("count is now: " + newValue));
```

### Constructor

```haxe
new State<T>(initial:T, stateName:String)
```

- `initial` — the starting value.
- `stateName` — a unique string name used in the global registry and for code generation.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `value` | `T` (get/set) | Current value. Setting it notifies all subscribers. |
| `name` | `String` | The registered state name. |

### Methods

| Method | Description |
|--------|-------------|
| `get():T` | Read the current value. Alias for `.value`. |
| `set(v:T):Void` | Set a new value and notify subscribers. Alias for `.value = v`. |
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
| `State.setByName(name, value)` | Set a state's value by name (string-based, Haxe-side only). |

> **Note** — to read or write the *C++ side* state (the `s_<name>` static the UI is bound to), use [`wui.state.StateBridge`](#statebridge) instead. `State.setByName` only updates the Haxe-side `_registry`, not the running UI.

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
4. **Propagates the declared default to the C++ static** via a `@:wuiInitial` meta — `MainWindow.cpp` initializes `static T s_<name> = <default>` directly at static init time (no need to seed via `main()` or `body()`).

Supported default expression literals: `Int`, `Float`, `Bool`, `String`. Other expressions fall back to the per-type zero value (`0`, `0.0`, `false`, `L""`).

You then use `count.value`, `count.inc(1)`, etc. in your `body()`.

---

## StateAction

Declarative state mutations. Passed to `Button` and other interactive controls to describe what happens on interaction. The UIBuilder macro translates these directly into C++/WinRT code — no runtime enum dispatch, no per-action object.

```haxe
new Button("Add",    null, count.inc(1))
new Button("Reset",  null, count.setTo(0))
new Button("Toggle", null, isDark.tog())
```

### All actions

| Action | Description | Example |
|--------|-------------|---------|
| `Increment(state, amount)` | Add `amount` to a numeric state. | `count.inc(1)` |
| `Decrement(state, amount)` | Subtract `amount` from a numeric state. | `count.dec(1)` |
| `SetValue(state, value)` | Set state to a specific value. | `count.setTo(0)` or `StateAction.SetValue(count, 42)` |
| `Toggle(state)` | Flip a boolean state. | `isDark.tog()` or `StateAction.Toggle(isDark)` |
| `Custom(callback)` | Execute an arbitrary Haxe callback — see below. | `Custom(MyApp.startLogin)` |
| `Sequence(actions)` | Execute multiple actions in order. | `Sequence([loginStatus.setTo("…"), Custom(work)])` |
| `Append(state, value)` | *(planned)* Append to an array state. | — |
| `Remove(state, value)` | *(planned)* Remove from an array state. | — |
| `Animated(action, curve)` | *(planned)* Wrap an action with animation. | — |

> Append, Remove and Animated are declared in the enum but the codegen isn't wired yet. Use `Custom` to emulate them for now.

### `Custom` — calling into Haxe

`Custom` lets a click handler invoke arbitrary Haxe code. The macro auto-generates a wrapper in a synthesized `wui.generated.Callbacks` class and the C++ click handler calls it directly — **no manual `@:expose`, no string-based lookup**.

Two forms:

#### Static function reference

```haxe
class MyApp extends wui.App {
    public static function startLogin():Void {
        // do work, set state, spawn threads…
    }

    override function body():View
        return new Button("Login", null, StateAction.Custom(MyApp.startLogin));
}
```

#### Anonymous lambda

```haxe
new Button("Login", null, StateAction.Custom(() -> {
    wui.state.StateBridge.setString("loginStatus", "Loading…");
    sys.thread.Thread.create(() -> doAsyncWork());
}))
```

The lambda body is lifted into a static wrapper in `wui.generated.Callbacks` via `Context.storeTypedExpr`. Captures of *local variables* are not supported (the static lift loses the closure scope). To pass data into the lambda's body, either:

- Reference module-level statics / class statics (visible to the lifted body), or
- Read state via `wui.state.StateBridge.getX(name)`.

> See [#threading-caveat](#threading-caveat) before passing data into worker threads.

### `Sequence` — chaining actions

`Sequence` runs all its inner actions on click. Useful for "set a status string, then start a worker":

```haxe
new Button("Connecter", null, StateAction.Sequence([
    StateAction.SetValue(loginStatus, "Démarrage…"),
    StateAction.Custom(MyApp.startLogin),
]))
```

Inner actions can be any other `StateAction`, including another `Sequence`.

---

## StateBridge — read/write `@:state` by name

For Haxe code that needs to touch state outside of `body()` — typically a `Custom` click handler or a `Thread.create` worker — use `wui.state.StateBridge`. It's a stable Haxe API that dispatches by field name to the C++ side.

```haxe
import wui.state.StateBridge;

// Inside a Custom lambda, a worker thread, or anywhere with cpp target:
StateBridge.setString("loginStatus", "Démarrage…");
StateBridge.setInt("count", 42);
StateBridge.setBool("isDark", true);
StateBridge.setFloat("progress", 0.42);

var url:String  = StateBridge.getString("serverUrl");
var n:Int       = StateBridge.getInt("count");
var dark:Bool   = StateBridge.getBool("isDark");
var p:Float     = StateBridge.getFloat("progress");
```

Under the hood, `UIBuilder` emits `extern "C" clw_state_{set,get}_{string,int,double,bool}(name, ...)` dispatch functions in `MainWindow.cpp`. The dispatch matches the wstring `name` against each `@:state` field and routes to `s_<name>` directly, then calls `notify_<name>()` so the bound UI controls update.

Unknown names are silently ignored on `set` and return type defaults on `get`.

### Threading caveat

`Sys.println`, `haxe.Http`, and `StateBridge` all work fine on a `sys.thread.Thread.create` worker. But **passing data through a closure capture or a Haxe class static into the worker comes back as garbage** on hxcpp 4.3 — you'll see a single character + NUL truncation. Use `sys.thread.Deque<T>` or `sys.thread.Mutex` to synchronize:

```haxe
static var _q:sys.thread.Deque<String> = new sys.thread.Deque<String>();

public static function startLogin():Void {
    var server = StateBridge.getString("serverUrl");
    _q.add(server);
    sys.thread.Thread.create(_runWorker);
}

static function _runWorker():Void {
    var server = _q.pop(true);
    // server is intact here
}
```

A proper fix in hxcpp/wui is tracked separately.

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
.opacity(opacityState)     // Reactive — updates when state changes
```

This is used internally by the modifier system to support both patterns.

---

## How state updates flow

```mermaid
sequenceDiagram
    participant User
    participant Button as Button (C++/WinRT)
    participant Action as StateAction
    participant Static as s_count
    participant Listener as Listener lambda
    participant DQ as DispatcherQueue
    participant UI as TextBlock (C++/WinRT)

    User->>Button: Click
    Button->>Action: Execute (e.g. Increment)
    Action->>Static: s_count += 1; notify_count();
    Static->>Listener: fire
    Listener->>DQ: TryEnqueue([ctrl]() { ctrl.Text(…) })
    DQ->>UI: ctrl.Text(newValue) (next frame)
    Note over UI: Defer is required —<br/>updating Text synchronously<br/>from a click handler crashes<br/>the XAML compositor.
```

Because both hxcpp and C++/WinRT compile to native C++, listeners are direct C++ lambdas that capture WinUI control handles. No serialization, no JSON, no cross-process communication. The `TryEnqueue` defer is necessary to keep WinUI happy across re-entrant UI updates.

---

## Full example: counter app

```haxe
class Counter extends wui.App {
    @:state var count:Int = 0;

    static function main() {}

    override function appName():String return "Counter";

    override function body():View {
        return new VStack([
            new Text("Counter").font(Title),
            new Text("Count: " + count)
                .font(TitleLarge)
                .foregroundColor(AccentColor),
            new HStack([
                new Button("-", null, count.dec(1)),
                new Button("Reset", null, count.setTo(0)),
                new Button("+", null, count.inc(1))
            ]).spacing(8)
        ]).horizontalAlignment(Center);
    }
}
```

## Full example: login flow with a worker thread

```haxe
import wui.View;
import wui.ui.*;
import wui.state.StateAction;
import wui.state.StateBridge;

class App extends wui.App {
    @:state var serverUrl:String = "https://mail.example.com";
    @:state var userCode:String = "";
    @:state var loginStatus:String = "Pas encore connecté";

    static var _q:sys.thread.Deque<String> = new sys.thread.Deque<String>();

    static function main() {}

    public static function startLogin():Void {
        var server = StateBridge.getString("serverUrl");
        _q.add(server);
        StateBridge.setString("loginStatus", "Démarrage…");
        sys.thread.Thread.create(_runWorker);
    }

    static function _runWorker():Void {
        var server = _q.pop(true);
        try {
            // … requestDeviceCode, poll, etc. — all on this thread
            StateBridge.setString("userCode", "ABC-123");
            StateBridge.setString("loginStatus", "Connecté !");
        } catch (e:Dynamic) {
            StateBridge.setString("loginStatus", "Erreur : " + Std.string(e));
        }
    }

    override function appName():String return "Login";

    override function body():View {
        return new VStack([
            new TextBox("https://…", serverUrl),
            new Text("Code utilisateur : " + userCode),
            new Text(loginStatus),
            new Button("Se connecter", null, StateAction.Custom(App.startLogin)),
        ]);
    }
}
```
