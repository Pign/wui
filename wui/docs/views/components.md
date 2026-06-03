# Creating reusable views — user components

Built-in widgets (`Text`, `VStack`, `Button`, …) are framework primitives.
Their look and behaviour ship with wui. But you don't write a real app from
primitives alone — you build your own components on top : a `Title` with the
brand colour, a `Card`, a labelled form field, a list row.

This guide covers the contract for **user components** — Haxe classes that
extend `wui.View`, override `body()`, and get inlined into the surrounding
tree by the macro pipeline.

---

## The contract

```haxe
package myapp.views;

import wui.View;
import wui.ui.Text;

class Title extends View {
    var text:String;

    public function new(text:String) {
        super("Title");
        this.text = text;
    }

    override function body():View {
        return new Text(text).font(TitleLarge);
    }
}
```

Use it like any primitive :

```haxe
new VStack([
    new Title("Welcome back"),
    new Text("Sign in to continue"),
])
```

That's it. No registration, no metadata. The macro recognises any class
extending `wui.View` that overrides `body()` and inlines the override's
return expression into the surrounding tree at compile time.

The runtime equivalence : `new Title("Welcome back")` emits the **exact same**
C++ as if you'd written `new Text("Welcome back").font(TitleLarge)` directly.

---

## What "inline" means

The component doesn't run at runtime. Its `body()` method is read by the
macro analyzer, and the AST it returns becomes part of the caller's tree.

For each `new MyComponent(arg0, arg1, …)` it finds, the macro :

1. Looks up `MyComponent.body()`'s typed AST.
2. Reads the constructor body to map each parameter to the field it gets
   assigned to (so `this.<field>` references can be substituted).
3. Walks the body return expression and replaces every `this.<field>` with
   the corresponding caller arg.
4. Hands the substituted expression back to its own `analyzeNewExpr` —
   recursively, so a component built from other components composes
   normally.

There's no runtime instance of `Title`. The constructor body runs at compile
time (only its `this.X = paramName` assignments — see [the rule on
constructors](#constructor-rule)) ; the override's body never sees a `this`
in the running app. The whole component vanishes into the emitted XAML
tree.

---

## Constructor rule

The substitution map is built from the constructor body. Today the macro
recognises one shape :

```haxe
public function new(text:String) {
    super("Title");
    this.text = text;     // ← this is what the substitution map sees
}
```

For each `this.<field> = <localParam>` statement, the macro records
`<field> → <localParam>`. When it walks `body()` and finds `this.text`, it
looks up "text" in the map, finds the parameter name, finds its index in
the constructor signature, and pulls the value from the caller's arg list.

**Anything else falls back silently** — a transformed assignment, a
conditional init, a field set from a static, all those keep the original
`this.X` reference in the inlined body. The caller's analyzer then can't
resolve it and the resulting node is empty or a placeholder Border.

If you need to transform a constructor argument, do it inside `body()` :

```haxe
class Greeting extends View {
    var name:String;
    public function new(name:String) {
        super("Greeting");
        this.name = name;          // ✅ plain assignment — substitution works
    }
    override function body():View {
        return new Text("Hello, " + name.toUpperCase());  // transform here
    }
}
```

This isn't a hard limitation of the macro design ; it's an MVP cut-off.
Richer constructor patterns are tracked as a follow-up.

---

## Passing state into components

A component can take a `wui.state.State<T>` reference as a constructor arg
and bind it directly — the substitution preserves the original `@:state`
field expression, so `extractStateRef` (the same machinery the framework
uses for `TextBox`'s two-way binding) resolves the name correctly :

```haxe
class SettingsForm extends View {
    var serverUrl:wui.state.State<String>;
    var statusText:wui.state.State<String>;

    public function new(serverUrl, statusText) {
        super("SettingsForm");
        this.serverUrl = serverUrl;
        this.statusText = statusText;
    }

    override function body():View {
        return new VStack([
            new TextBox("https://…", serverUrl),         // ← bound to @:state
            new Text(statusText).font(Caption),          // ← state-bound text
        ]);
    }
}
```

Used from the App :

```haxe
class MyApp extends wui.App {
    @:state var serverUrl:String = "https://api.example.com";
    @:state var statusText:String = "Idle";

    override function body():View {
        return new SettingsForm(serverUrl, statusText);
    }
}
```

The binding works because :

- The App's `serverUrl` is a `State<String>` after `@:state` macro expansion.
- `new SettingsForm(serverUrl, …)` passes that `State<String>` reference.
- Inside the component, `new TextBox(…, serverUrl)` references the field
  `this.serverUrl` of type `State<String>`.
- Phase 3 substitutes `this.serverUrl` → the original `App.serverUrl`
  expression.
- `TextBox.wuiAnalyze` calls `extractStateRef` on that expression and gets
  the name `"serverUrl"`, which matches the bridge key.

You don't need to flatten everything into the App. You can decompose UI into
components and pass the state slices each one needs.

---

## Components inside `ForEach`

A component can be the template of a `ForEach`. The substitution chain
threads the lambda parameter through :

```haxe
class TodoRow extends View {
    var label:String;
    var meta:String;

    public function new(label:String, meta:String) {
        super("TodoRow");
        this.label = label;
        this.meta = meta;
    }

    override function body():View {
        return new VStack([
            new Text(label).font(BodyStrong).foregroundColor(brand.primary()),
            new Text(meta).foregroundColor(brand.muted()),
        ]);
    }
}

// In the App
new ForEach(todos, (todo:Todo) ->
    new TodoRow(todo.label, todo.id),
    selectedIdx
)
```

What happens at compile time :

1. `ForEach.wuiAnalyze` sees a template body that's a `new TodoRow(…)`
   call — not its expected `HStack` / `VStack`.
2. It tries Phase 3 inlining on `TodoRow` with the lambda's args.
3. The inlined body becomes `new VStack([new Text(todo.label).font(...)...,
   new Text(todo.id).foregroundColor(...)])` — `this.label` was replaced
   by `todo.label` (the lambda's field access on the row item).
4. ForEach proceeds with the inlined body as if you'd written that VStack
   directly in the template.

The component carries the styling. Restyle the row by editing `TodoRow`
and `ForEach` knows nothing about it.

> Modifier chains on Text children inside a ForEach template are handled —
> `font(...)`, `foregroundColor(...)`, `bold()`, etc. propagate through to
> the per-row `TextBlock`. The ForEach analyzer walks the call chain and
> collects modifiers like the general modifier system does for regular
> Views.

---

## What components can and can't do

| You can | You can't (yet) |
|---|---|
| Override `body()` to return a tree of primitives | Have constructor args that aren't directly assigned to a same-named field (no transforms in the ctor) |
| Take any number of constructor args | Declare new `@:state` inside a component — the state must live on the App |
| Take `State<T>` references and bind them via `TextBox`, `Text`, `Slider`, … | Be used inside another component's `effects()` (effects belong to the App) |
| Use other components inside `body()` (composition is recursive) | Capture non-string fields off the row item — accessors emit `String` returns, so `item.isStarred` (Bool) in a `ForEach` closure fails at re-typing. String fields work. |
| Stack modifiers — `.padding(8)`, `.background(...)`, `.onTap(StateAction.Custom(fn))` — at the call site. They apply to the inlined root, on a primitive or inside a `ForEach` template. | |
| Inside a `ForEach` template, receive the row index via the lambda's optional second argument and reference it from a `Custom` closure or typed `(Int) -> Void` static callback. Closures may also reference `item.<field>` — the macro rewrites those as calls into the auto-generated `ForEachAccessor`. | |

The list is short on purpose — Phase 3 deliberately ships the minimum that
unblocks composition. Richer constructor patterns are tracked in the WUI
roadmap.

The list is short on purpose — Phase 3 deliberately ships the minimum that
unblocks composition. Modifier chains on the component, an `effects()` hook
per component, and richer constructor patterns are tracked in the WUI
roadmap.

---

## Why not a separate `Component` base class ?

Components extend `wui.View` directly — same as primitives. There's no
`Component extends View` intermediate. The reason :

- Primitive widgets (`Text`, `Button`, …) extend `View` because they want the
  modifier chain methods (`.padding()`, `.font()`, etc.) inherited.
- User components want the same modifier chain methods — see
  "[modifiers on components](#components-and-modifiers)" below.
- The macro's dispatch is "if the class extends `View` and overrides
  `body()`, treat it as inlineable". Splitting the hierarchy would add a
  layer for zero behavioural gain.

If components ever grow lifecycle hooks distinct from primitives (per-mount
state, async init, …), introducing a `Component` base would make sense. Not
today.

---

## Components and modifiers

`new Title("Hello").padding(16).onTap(StateAction.Custom(fn))` — works the
same as on any primitive. The macro's modifier-chain analyzer walks the
TCall chain on top of `new MyComponent(...)`, treats the underlying
inlined View as the base, and pushes the chained modifiers onto its
modifier list. The emitted C++ applies them to the inlined root control.

```haxe
// All three lines apply to the same TextBlock (the one Title's body
// returns) — Padding around it, brand foreground, a Tapped handler.
new Title("Hello")
    .padding(16)
    .foregroundColor(brand.accent())
    .onTap(StateAction.Custom(MyApp.showAbout))
```

The one exception is **inside a `ForEach` template** : modifiers on the
template root don't reach the per-row container yet. For now, route per-row
interaction through a wrapping primitive instead. The propagation pass is
a tracked follow-up.

---

## Debugging

When a component renders empty or wrong, the most common causes are :

1. **No `override function body()`** — the class extends `View` but has no
   `body()` override, so the macro has nothing to inline. The emitted output
   is `defaultNode()` (an empty placeholder).
2. **Constructor doesn't assign to fields** — `this.label = label` is fine ;
   `this.label = label.toLowerCase()` is not — the substitution map skips
   it and `body()` keeps the original `this.label` reference (unresolved at
   call site).
3. **Field name mismatch** — `var label:String` plus `this.title = label`
   stores in `title`, but `body()` references `label`. The map says
   `title → label` ; `body()`'s `this.label` doesn't appear in the map →
   stays as `this.label` → resolves to nothing at call site.
4. **`override` keyword missing** — Haxe would error with "Field body is
   declared 'override' but doesn't override any field" (the class needs
   `override` since `View.body()` is the virtual it overrides).
5. **The component is used inside `effects()`** — effects don't go through
   the View analyzer ; only `body()` and `titleBar()` do.

The macro's analyzer is deliberately quiet about failures (it falls back to
`defaultNode()`). If a component renders empty when you expect content, the
fastest debug is to inline its body() once at the call site and see if that
renders — it isolates the inlining logic from the rest of the tree.

---

## Naming conventions

By convention :

- Components that wrap an existing primitive with a fixed styling carry the
  primitive's role in the name : `Title`, `SectionHeader`, `BodyText`,
  `Caption`.
- Components that compose multiple primitives carry the screen / module
  name : `SettingsForm`, `TodoRow`, `Sidebar`, `Card`.
- Use a dedicated package — `myapp.views` or `myapp.ui`. Keeps the
  framework `wui.ui.*` separate from your app's components.

Nothing enforces these conventions ; they help when reading code six months
later.
