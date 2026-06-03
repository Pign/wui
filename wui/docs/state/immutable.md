# Immutable state — value-replacement reactivity

The third `@:state` shape, alongside [primitives](README.md#state-macro) and
[Observable](README.md#observable). Use it for **value types you replace
wholesale** instead of mutating in place — lists, records, configuration
snapshots — where field-level granularity (the Observable model) doesn't fit.

The classic case is a list rendered by [`ForEach`](../views/README.md#foreach) :
when a new item arrives, you don't patch one field of the list, you replace
the list with a longer one. Field-level decomposition has no answer for that.
Immutable does.

---

## The marker — `wui.state.Immutable`

An empty interface. Anything that implements it can sit behind a `@:state`
field :

```haxe
interface Immutable {}
```

The framework ships one citizen :

- `wui.state.ImmutableList<T>` — append/setAt/removeAt/update, all
  copy-on-write.

You can implement the marker on your own value types (typically `@:final`
records with `withX` builders), see [Custom Immutable types](#custom-immutable-types)
below.

---

## How it works

A primitive `@:state` lives entirely on the C++ side — the `s_<name>` static
is the source of truth, the Haxe `State<T>` wrapper is a typed handle the
macro uses at compile time.

Immutable inverts that : the **payload lives Haxe-side** (a regular reference
in `State<T>._value`), and only a small **trigger** crosses the bridge — a
companion `Int` named `<field>__v` that bumps on every replacement.

```
┌──────────────── Haxe ─────────────┐  ┌──── C++ / WinUI ────┐
│ State<ImmutableList<T>>           │  │ static int s_items__v
│   _value:  [a, b, c, …]           │  │ static vector<…> s_items__v_listeners
│   _versionKey: "items__v"         │  └──────────▲──────────┘
│                                   │             │ bump + notify
│ items.value = items.cons(newItem) ├─────────────┘
└───────────────────────────────────┘
```

When you reassign the list :

1. `State<T>.set_value` stores the new reference Haxe-side.
2. `_versionKey != null`, so it also bumps the bridge counter via
   `StateBridge.setInt("items__v", ++_version)`.
3. The C++ `s_items__v` static increments and `notify_items__v()` runs every
   listener.
4. A `ForEach` subscribed to `items__v` clears its panel and rebuilds the rows
   from the **current Haxe-side list**, accessed through the auto-generated
   `wui.generated.ForEachAccessor` module.

The trigger is just an `Int`. The actual data never gets marshalled.

---

## `ImmutableList<T>` — the included citizen

Copy-on-write list with the operations you'd expect :

```haxe
import wui.state.ImmutableList;

var list:ImmutableList<Int> = ImmutableList.empty();

list = list.cons(1);            // [1]
list = list.cons(2);            // [1, 2]
list = list.cons(3);            // [1, 2, 3]
list = list.setAt(0, 42);       // [42, 2, 3]
list = list.removeAt(1);        // [42, 3]
list = list.update(0, n -> n*2);// [84, 3]

trace(list.length);             // 2
trace(list.get(0));             // 84

for (n in list) trace(n);       // iteration
```

| Method | Returns | Notes |
|---|---|---|
| `ImmutableList.empty<T>()` | `ImmutableList<T>` | Brand-new empty list — no shared singleton; don't rely on identity. |
| `ImmutableList.fromArray<T>(arr)` | `ImmutableList<T>` | Copies the source array. Caller can keep mutating their `Array<T>`. |
| `cons(item)` | `ImmutableList<T>` | Append at tail. The name is a functional nod — semantically it's `snoc`/push. |
| `setAt(i, item)` | `ImmutableList<T>` | Replace at `i`. Out-of-range follows `Array<T>` semantics ; check `length` first. |
| `removeAt(i)` | `ImmutableList<T>` | Drop at `i`. Returns `this` (same identity) when `i` is out of range. |
| `update(i, fn)` | `ImmutableList<T>` | Functional update : `items.update(0, x -> x.withFlag(true))`. |
| `length` | `Int` | Read-only. |
| `get(i)` | `T` | Random access. |
| `iterator()` | `Iterator<T>` | `for ... in` support. |
| `toArray()` | `Array<T>` | Snapshot copy — mutating it doesn't affect the list. |

Internally it wraps an `Array<T>` and `.copy()`s on every mutation. **No
structural sharing yet** — a real persistent vector (HAMT or finger tree)
would land later if list sizes start hurting. For low-thousands lists the
naive copy is fine.

---

## Declaring an Immutable `@:state`

Same syntax as primitive `@:state`, with an Immutable type :

```haxe
typedef Todo = { id:String, label:String, done:Bool };

class TodoApp extends wui.App {
    @:state var todos:ImmutableList<Todo> = ImmutableList.empty();
}
```

The macro :

1. Wraps the field as `State<ImmutableList<Todo>>` (same as primitives).
2. Synthesises a companion `@:state var todos__v:Int = 0` (the bridge
   trigger).
3. Wires the `State<T>` constructor with `versionKey = "todos__v"` so every
   `set_value` bumps the bridge.
4. Adds `new ThisClass()` at the top of `static main()` — Immutable `@:state`
   needs the Haxe-side wrapper to actually exist at runtime, and it can't be
   created in `static __init__` (boot order races against `State._registry`'s
   own init). The macro handles this for you ; if you didn't have a `main()`,
   it synthesises one.

The C++ side gets one extra static — `static int s_todos__v = 0` — and
nothing else for `todos`. No marshalling of the list itself.

---

## Updating the list

The mechanic is symmetric to Observable : assign through the `State<T>` and
the bridge fires.

### From a static / worker thread

```haxe
static function pushTodos(items:Array<Todo>):Void {
    var listState:Dynamic = wui.state.State.getByName("todos");
    if (listState == null) return;
    Reflect.callMethod(
        listState,
        Reflect.field(listState, "set_value"),
        [wui.state.ImmutableList.fromArray(items)]
    );
}
```

Two things to notice :

- `State.getByName("todos")` — same registry used by `StateBridge` for
  primitives, but here we reach the typed `State<T>` wrapper instead of the
  C++ static.
- `Reflect.callMethod(..., "set_value", [newList])` rather than
  `listState.value = newList`. hxcpp's `__SetField("value", X, paccDynamic)`
  on `State<T>` falls through to the parent's lookup (the property setter
  only matches `paccAlways`), so the Dynamic assignment never reaches
  `set_value` and surfaces as `invalid field:value`. Reflect-calling the
  method directly bypasses the property dispatch.

A typed cast also works and looks cleaner :

```haxe
var s:wui.state.State<wui.state.ImmutableList<Todo>> = cast listState;
s.value = ImmutableList.fromArray(items);  // typed access goes through set_value
```

---

## Rendering with `ForEach`

This is where Immutable pays off. `ForEach` subscribes to the synthetic
`<state>__v` trigger and rebuilds its panel on every bump.

```haxe
@:state var todos:ImmutableList<Todo> = ImmutableList.empty();
@:state var selectedIdx:Int = -1;

override function body():View {
    return new ForEach(
        todos,
        (todo:Todo) -> new VStack([
            new Text(todo.label),
            new Text(todo.id).foregroundColor(brand.muted()),
        ]),
        selectedIdx,
    );
}
```

See the [ForEach guide](../views/README.md#foreach) for the row template and
tap-select wiring details. The bit that matters here :

- The `todos` reference passed to `ForEach` is resolved by name (`"todos"`)
  at codegen time. ForEach asks the bridge for `todos__v`, not for the list.
- Each row template is a `(item) -> View` function. Inside it, `todo.label`
  and `todo.id` get extracted as field accesses, and codegen emits per-field
  accessor methods on `wui.generated.ForEachAccessor` that pull from
  `State.getByName("todos").value.get(i).<field>` at runtime.
- On every `s_todos__v_listeners` notification, the rebuild closure clears
  the panel and re-emits one row per `todos.value.get(i)`.

The template never sees the list itself — only the per-row item. The list is
read once per rebuild via the accessor, on the UI thread.

---

## Custom Immutable types

The marker is intentionally bare so user value types can opt in :

```haxe
@:final class Note implements wui.state.Immutable {
    public final id:String;
    public final title:String;
    public final body:String;
    public final pinned:Bool;

    public function new(id, title, body, pinned) {
        this.id = id; this.title = title; this.body = body; this.pinned = pinned;
    }

    public function withPinned(v:Bool):Note
        return new Note(id, title, body, v);
}

class NotesApp extends wui.App {
    @:state var current:Note = new Note("0", "", "", false);
}
```

Same rules : the macro pairs `current` with a synthetic `current__v` trigger,
and `current = current.withPinned(true)` bumps the bridge.

The fields are `final` by convention — Immutable means "replace, don't
mutate", and `final` enforces that at the type level.

`@:record`-style auto-`withX` generation is a planned follow-up to remove the
boilerplate ; you can write the builders by hand for now.

---

## Where Observable vs Immutable fit

A quick decision chart :

| You want… | Choose |
|---|---|
| A single primitive field (`String`, `Int`, `Float`, `Bool`) | `@:state var x:T` |
| A grouped bag of primitive fields where each one is independently bound | Observable subclass with `@:state` fields |
| A reactive collection (list, set, map) | Immutable — typically `ImmutableList<T>` |
| A value type that's logically "one thing" you replace as a whole (snapshot, record, config) | Immutable — implement the marker on your record |
| A field-level reactive composite that *also* contains an Immutable child | (Future) — nest the Immutable inside an Observable. Phase-1 Observable doesn't allow this yet ; flatten by hand for now. |

---

## Constraints

- Initial value is required on an Immutable `@:state` field. The macro can't
  invent a default `new MyImmutable()` — pass `ImmutableList.empty()` or your
  own zero-value factory.
- Immutable `@:state` inside an Observable is rejected at compile time
  (mirrors the "Observable inside Observable" rule — flatten or wait for
  nested support).
- The companion `<name>__v` is reserved and may collide if you have a real
  `@:state` named that. Choose a different field name in the rare case it
  does.
- The trigger is monotonically increasing. If you bump 2³¹ times in one
  session you'll overflow ; come back when you've found a use case that
  reaches that.
