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

For mutations in click handlers, just write the typed setter directly inside the closure :

```haxe
new Button("+",     null, () -> count.value++)
new Button("Reset", null, () -> count.value = 0)
new Button("Dark",  null, () -> isDark.value = !isDark.value)
```

No more `count.inc(1)` shortcuts — closures are the single, uniform vocabulary.

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

You then use `count.value` (read or assign) anywhere `body()` produces — inside a `.onTap(() -> { … })` closure for mutations, or inline (`new Text("Count: " + count)`) for display, where the framework macro resolves the state-bound binding.

### Type rule

`@:state` is intentionally restrictive. The macro enforces — at compile time, with `Context.error` pointing at the offending field — that the field type is one of:

1. A primitive: `String`, `Int`, `Float`, `Bool`
2. A class extending [`wui.state.Observable`](#observable) — for composite state with field-level reactivity
3. A class implementing [`wui.state.Immutable`](immutable.md) — for value-replacement composites (`ImmutableList<T>` and friends)

Anything else (a `typedef`, plain `Array<T>`, a `Map`, a class with none of the markers) is rejected at compile time:

```
@:state var items:Array<Thing> = [];
                ^^^^^^^^^^^^^
@:state var items:T — type must be a primitive (String/Int/Float/Bool),
extend wui.state.Observable, or implement wui.state.Immutable.
```

The rule keeps the bridge layer honest: every reactive cell either lives in C++ as a primitive, is a primitive decomposed from an Observable's fields, or has a small `Int` trigger paired with a Haxe-side payload (Immutable). The framework never marshals opaque Haxe objects across language boundaries.

Planned but not yet eligible: nullary enums (will be stored as `int` via the index).

---

## Observable

Composite reactive state. An `Observable` subclass is a Haxe-side container for one or more `@:state` fields whose individual cells participate in the reactive bridge under a dotted scope.

```haxe
class Settings extends wui.state.Observable {
    @:state public var darkMode:Bool = false;
    @:state public var fontSize:Int = 14;
}

class MyApp extends wui.App {
    @:state var settings:Settings = new Settings();
}
```

The macro expands `settings` into two bridge entries — `"settings.darkMode"` and `"settings.fontSize"` — exactly as if the user had written:

```haxe
@:state var settings_darkMode:Bool = false;
@:state var settings_fontSize:Int = 14;
```

…but with three things you get for free that flattening by hand doesn't:

- Composite reads in `body()` resolve to the same dotted key.
  `new Text("Size: " + settings.fontSize.value)` subscribes the
  TextBlock to the `"settings.fontSize"` listener list.
- `Settings` stays a real Haxe type. You can give it methods, helpers,
  or non-`@:state` caches without polluting the App.
- The dotted scope is recursive (planned). `Settings` containing a
  `@:state var network:Network` where `Network extends Observable`
  produces keys like `"settings.network.host"`.

### Codegen contract

| Concern | App-level @:state | Observable @:state |
|---------|-------------------|--------------------|
| Field type after macro | `var x:State<T>` | `var x:State<T>` |
| Bridge key | `"x"` | `"<scope>.x"` |
| State<T> constructed in | `new()` | `_attach(scope)` |
| C++ symbol | `s_x` | `s_<scope>_x` (dots → underscores via `cppId`) |

`Observable._attach(scope)` is called by the enclosing App (or parent
Observable) immediately after construction. The base implementation
just stores `_scope`; subclasses get an auto-generated override that
also instantiates each `State<T>` with the scope-prefixed name.

You don't call `_attach` yourself. The macro injects the call as part
of the constructor codegen on whichever class declares
`@:state var x:MyObservable`.

### Bridge key vs C++ identifier

Composite keys carry dots in the wstring the bridge dispatch compares
against:

```cpp
if (n == L"settings.darkMode") { /* ... */ }
```

but C++ identifiers can't have dots, so the matching static / notify /
listener symbols sanitise to underscores:

```cpp
static bool s_settings_darkMode = false;
static void notify_settings_darkMode() { /* ... */ }
static std::vector<...> s_settings_darkMode_listeners;
```

The split is invisible to user code — `StateBridge.setBool("settings.darkMode", true)` works exactly like its primitive counterpart.

### Phase-1 limitations

What works today:

- Single-level Observable composition: `@:state var settings:Settings`
  with primitive fields on Settings.
- Body-level bindings via `new Text(... settings.fontSize.value ...)`
  with composite key resolution.
- Live initial render: a Text widget bound to a composite Observable
  field shows the C++ initial value at construction, not a generic "0".

Not yet wired:

- Nested Observable in Observable. `Settings.network:Network` where
  Network extends Observable is rejected with a clear error pointing
  at the field. Recursion will land in a follow-up — the runtime
  primitives already support it; only the macro's scope propagation
  needs the recursive walk.
- `.value` rewrite for composite reads inside `effects()` /
  `.onTap(() -> { … })` closures. `settings.fontSize.value` in a lifted
  closure currently reads the stale Haxe-side `State<Int>._value`
  instead of going through `StateBridge`. Primitive `@:state` reads
  (`searchQuery.value`) still work through the existing rewrite.
- Composite refs in `Effect.run` deps (`[settings.darkMode]`). Pass the
  composite key as a string for now (`["settings.darkMode"]`).

> **Observable is for field-level reactivity over a known set of fields.**
> For a reactive *collection* (list, set, map) or for a value type you
> replace wholesale (snapshot, record, config), reach for
> [`wui.state.Immutable`](immutable.md) instead. The Observable path's
> "decompose into per-field bridge entries" model has no answer for "the
> shape itself changes".

---

## Immutable

The third eligible shape — value-replacement reactivity. The payload lives
Haxe-side (a regular reference in `State<T>._value`), and only a small
`Int` trigger crosses the bridge to wake up subscribers like
[`ForEach`](../views/README.md#foreach). The included citizen is
`ImmutableList<T>` ; you can implement the marker on your own value types.

```haxe
@:state var todos:ImmutableList<Todo> = ImmutableList.empty();

// Mutate via the immutable API ; State<T>.set_value bumps the bridge
// trigger, the ForEach subscribed to it rebuilds.
todos.value = todos.value.cons(newTodo);
```

The full guide — payload semantics, ForEach wiring, custom Immutable types,
the `set_value` Reflect detour on hxcpp — is in
[Immutable state](immutable.md). The TL;DR :

| | Primitive | Observable | Immutable |
|---|---|---|---|
| Bridge entries | one per field | one per nested primitive (dotted key) | one trigger `Int` per field (`<name>__v`) |
| Payload lives | C++ | C++ (decomposed) | Haxe |
| When to reach for it | scalar reactive value | grouped scalar fields | reactive collection or whole-value replacement |

---

## StateAction — a closure type

`StateAction` is just `typedef StateAction = () -> Void`. The third arg of `Button`, the arg of `.onTap(...)`, and similar tap-handler slots all accept a closure (or a static fn ref that coerces to one). There is no enum of variants ; there is no method-form shortcut on `State<T>`. There is one uniform vocabulary :

```haxe
new Button("Login",   null, MyApp.startLogin)              // static fn ref
new Button("+",       null, () -> count.value++)           // closure
new Button("Reset",   null, () -> count.value = 0)         // closure
new Button("Connect", null, () -> {                        // multi-statement
    wui.state.StateBridge.setString("loginStatus", "Loading…");
    sys.thread.Thread.create(() -> doAsyncWork());
})
```

### Static fn refs vs closures

| Shape | When | What the macro does |
|---|---|---|
| `MyApp.handler`        | The work is a real function elsewhere | Emit a zero-arg wrapper on `wui.generated.Callbacks` that calls the target ; the C++ click handler invokes the wrapper |
| `() -> { … }` (no captures) | Inline body, references only statics + StateBridge | Lift the body via `Context.storeTypedExpr` into the same Callbacks class. **`body()` never runs at runtime**, so the lambda has no enclosing scope — `this.X` and `body()`-locals aren't reachable. Module statics, other class statics, and StateBridge are fine. |
| `() -> { … }` (with captures, inside a `ForEach` row) | Closure references the row `idx`, item fields, or row-lambda locals | Generate a `(idx:Int) -> () -> Void` *builder* that materialises `item` (cast from `State.getByName("<state>").value.get(idx)`) and the row-lambda locals, then returns the closure. hxcpp handles the captures at runtime. The closure is stored in a GC-rooted `Callbacks._handlers` array ; the C++ Tapped handler captures only the `Int` index and dispatches via `Callbacks.runHandler(_hi)`. |

The third row is what makes runtime closures with captures work — see the [ForEach row taps section in views/README.md](../views/README.md) for the full pattern.

For state mutations that used to read `count.inc(1)` etc., just write the typed setter directly inside the closure :

```haxe
() -> count.value++          // increment
() -> count.value--          // decrement
() -> count.value = 0        // set
() -> isDark.value = !isDark.value   // toggle
```

`count` is a typed `State<Int>` (after `@:state` macro expansion). The typed setter call goes through `set_value` cleanly — no Dynamic dispatch, no Reflect roundtrip.

For "set A then start B" chains, just do both statements in the same closure :

```haxe
new Button("Connecter", null, () -> {
    StateBridge.setString("loginStatus", "Démarrage…");
    MyApp.startLogin();
})
```

> See [#threading-caveat](#threading-caveat) before passing data into worker threads.

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

### Threading notes

`Sys.println`, `haxe.Http`, and `StateBridge` all work fine on a `sys.thread.Thread.create` worker.

Passing Haxe heap objects across the thread boundary works the same way it does in any other hxcpp program. The infamous "Haxe String comes out as garbage on a worker" symptom was traced to a bridge-side bug (`::String(const char*, int)` was storing the buffer pointer without copying — fixed by routing through `hx::NewGCBytes`). If you see anything that resembles that pattern in a new bridge you're writing — first read works, second read mangled, GC pressure makes it worse — it's almost certainly the same root cause ; check the C++ side for a freed source buffer.

The conservative pattern, if you don't need to share live Haxe state between threads, is to **let the worker read state through `StateBridge.getX(...)`** rather than capturing a Haxe value into the closure :

```haxe
public static function startWork():Void {
    StateBridge.setString("status", "Démarrage…");
    sys.thread.Thread.create(_runWorker);
}

static function _runWorker():Void {
    // Worker reads the server URL through the bridge — no captured
    // Haxe object, just a wstring lookup.
    var server = StateBridge.getString("serverUrl");
    // … network IO, then StateBridge.setString to publish results.
}
```

It's not required, just predictable.

### Lambda capture limitations summary

| Pattern | Captures work? |
| --- | --- |
| Closure built and called on the same thread, in a normal runtime function | ✅ |
| Closure passed to `Thread.create` | ✅ (hxcpp GC-tracks captured locals) |
| `.onTap(() -> { … })` outside a `ForEach` row | ❌ — `body()` is compile-time only ; the lifted lambda has no closure scope. Reach for module statics + `StateBridge`. |
| `.onTap(() -> { … })` inside a `ForEach` row | ✅ — `idx`, `item.<field>`, and row-lambda locals capture cleanly. The macro routes through a per-row builder + GC-rooted handler store. |

---

## Effect

Reactive side-effects for everything that lives *outside* the View tree — window title, taskbar progress, native notifications, file watchers. The same mental model as React's `useEffect`: a lambda runs once at startup and then again every time one of its declared deps changes.

```haxe
import wui.Effect;
import wui.Window;

class MyApp extends wui.App {
    @:state var unreadCount:Int = 0;

    override function effects():Void {
        Effect.run(() -> {
            var n = StateBridge.getInt("unreadCount");
            Window.setTitle('Unread ($n) — MyApp');
        }, [unreadCount]);
    }
}
```

### Where effects live: `effects():Void`

Override the `effects()` virtual on your `App` subclass. The macro walks its body at compile time, lifts every `Effect.run` lambda into `wui.generated.Callbacks`, and emits matching listener subscriptions in `MainWindow.cpp`. The method itself is never invoked at runtime — same pattern as `body()`.

`effects()` runs in instance context, so `@:state` fields are addressable as typed refs (`unreadCount`, not `"unreadCount"`). Typos become compile errors and rename refactors carry through.

### Deps: typed refs or string literals

```haxe
Effect.run(fn, [unreadCount, currentFolder])     // typed @:state field refs (preferred)
Effect.run(fn, ["unreadCount", "currentFolder"]) // string literals (escape hatch)
```

Use refs from `effects()`. The string form stays available for the rare case where you call `Effect.run` from `static main()` (no instance context, so refs aren't in scope).

### Lifecycle

| Phase | What happens |
|-------|--------------|
| Compile | Macro lifts each lambda into `Callbacks_obj.wui_eff_<N>()`, records `{wrapperName, deps[]}`. |
| Runtime, `BuildUI()` | Each effect runs once (initial invocation, matches React `useEffect(fn, [deps])` first call). |
| Runtime, on state change | The C++ `notify_<dep>()` iterates `s_<dep>_listeners`; the effect wrapper re-runs via `DispatcherQueue.TryEnqueue` (same re-entrance protection as view bindings). |

### Reading state inside the effect body

The lambda is **lifted to a static C++ wrapper** — same constraint as a non-ForEach `.onTap(() -> { … })` closure. It has no enclosing runtime scope, so:

- Use `StateBridge.get{String,Int,Float,Bool}("name")` to read the *current* value. The Haxe-side `State<T>.value` is stale; only the C++ `s_<name>` is the source of truth.
- Static helpers, module-level functions, and other class statics work normally.

### Empty deps — "run once, never re-run"

```haxe
Effect.run(() -> initializeAnalytics(), []);
```

No subscriptions are registered. The effect fires exactly once at startup. Matches React's `useEffect(fn, [])` semantics.

### Constraints

- The deps argument must be an **inline array literal**. `var deps = [...]; Effect.run(fn, deps);` won't be picked up — the macro only inspects the literal.
- Each ref-form dep must resolve to a `@:state` field on the App; mismatches surface as compile-time warnings.
- `Effect.run` calls inside conditionals or loops in `effects()` are extracted unconditionally (the macro flattens them). Use `if`/`return` inside the *lambda body*, not around the `Effect.run` call.

### Cleanup

There is no cleanup phase yet — the lifted lambdas live for the application lifetime. For a single-Window desktop app this is fine; if you grow into multi-window scenarios with conditional effects, file a Plane issue.

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
                new Button("-", null, () -> count.value--),
                new Button("Reset", null, () -> count.value = 0),
                new Button("+", null, () -> count.value++)
            ]).spacing(8)
        ]).horizontalAlignment(Center);
    }
}
```

## Full example: login flow with a worker thread

```haxe
import wui.View;
import wui.ui.*;
import wui.state.StateBridge;

class App extends wui.App {
    @:state var serverUrl:String = "https://api.example.com";
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
            new Button("Se connecter", null, App.startLogin),
        ]);
    }
}
```
