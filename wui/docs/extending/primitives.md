# Binding a native control as a WUI primitive

WUI ships ~14 primitives that map 1-to-1 onto WinUI 3 controls (`Text` →
`TextBlock`, `Button` → `Button`, `Slider` → `Slider`, …). When you need
something WinUI 3 exposes that the framework doesn't (a `Pivot`, a
`PersonPicture`, a custom `MapControl`…), you don't have to fork — you can
**add a primitive** that the framework treats exactly like its own.

The contract is two static methods on a class extending `wui.View`. Once
they're registered, the new primitive is reachable as `new MyPrimitive(…)`
from any `body()`.

This guide assumes you've read [Views](README.md) and have a feel for the
analyze → emit pipeline. If not, [the architecture overview](../architecture.md)
covers the macro phases first.

---

## The contract — `wuiAnalyze` + `wuiEmit`

Every primitive lives in `wui.ui.*` and looks like this (simplified) :

```haxe
package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

@:wuiPrimitive
class Hyperlink extends View {
    public function new(text:String, url:String) {
        super("Hyperlink");
        properties.set("text", text);
        properties.set("url", url);
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var props:Map<String, Dynamic> = new Map();
        if (args.length > 0) props.set("text", ctx.extractString(args[0]));
        if (args.length > 1) props.set("url",  ctx.extractString(args[1]));
        return { viewType: "Hyperlink", children: [], modifiers: [], properties: props };
    }

    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("link");
        ctx.lines.push('winrt_controls::HyperlinkButton $varName;');
        var text = node.properties.get("text");
        if (text != null) {
            var escaped = ctx.escapeWideString(Std.string(text));
            ctx.lines.push('$varName.Content(winrt::box_value(L"$escaped"));');
        }
        var url = node.properties.get("url");
        if (url != null) {
            var escaped = ctx.escapeWideString(Std.string(url));
            ctx.lines.push('$varName.NavigateUri(winrt::Windows::Foundation::Uri(L"$escaped"));');
        }
        ctx.applyModifiers(varName, "HyperlinkButton", node.modifiers);
        return varName;
    }
    #end
}
```

Two responsibilities :

- **`wuiAnalyze(args, ctx)`** runs at macro typing time. Receives the
  constructor's typed arguments and returns a `ViewNode` — a serialisable
  description of what should be emitted. `wui.macros.UIBuilder.ViewNode` is
  a plain typedef :

  ```haxe
  typedef ViewNode = {
      viewType:String,                       // dispatch key on the emit side
      children:Array<ViewNode>,
      modifiers:Array<ModifierData>,
      properties:Map<String, Dynamic>,
  };
  ```

- **`wuiEmit(node, ctx)`** runs at code-generation time. Receives the
  `ViewNode` your analyze produced and writes the C++/WinRT statements that
  construct the matching control. Returns the C++ variable name it created
  — the caller (UIBuilder) uses that to append the widget to its parent.

The class itself is just runtime stubs : it carries the `viewType` string
and a properties bag. At runtime nothing actually instantiates `Hyperlink`
— the macro pipeline replaces `new Hyperlink(…)` with the C++ from
`wuiEmit`.

---

## `AnalyzeCtx` — what's in scope at analyze

`wui.macros.PrimitiveCtx.AnalyzeCtx` bundles helpers your `wuiAnalyze` needs.
You don't have to import them from UIBuilder yourself — the framework
passes them in :

| Field | Returns | Notes |
|---|---|---|
| `ctx.recurseChild(expr)` | `ViewNode` | Recurse into a single child `View` expression. Used by widgets that take a single View arg (`ScrollViewer`, `Show`). |
| `ctx.recurseChildren(expr)` | `Array<ViewNode>` | Expects a `TArrayDecl` of View exprs. Used by stacks. |
| `ctx.extractString(expr)` | `String` | Static string / int / float literal extraction. Returns `"..."` (sentinel) when the expression isn't a static literal. |
| `ctx.extractFloat(expr)` | `Null<Float>` | Numeric literal ; `null` when not a literal. |
| `ctx.extractStateBoundText(expr)` | `Null<{text, boundState, format}>` | Detects state-bound text expressions (`"Count: " + count`). Use it when your primitive's main argument is a text that should auto-bind to a `@:state` field. |
| `ctx.extractStateRef(expr)` | `String` | Resolves a `@:state` field reference to its bridge key name. Use it for two-way binding control args. |
| `ctx.extractStateAction(expr)` | `String` | Compiles a `StateAction` value to the C++ snippet that executes it. Use it for click / change handlers. |
| `ctx.defaultNode()` | `ViewNode` | Empty placeholder. Return it when your primitive received malformed args and you'd rather degrade than abort the build. |

Anything more exotic — walking modifier chains, detecting lambda bodies,
typing decisions — you do yourself with `haxe.macro.Type` and
`haxe.macro.TypedExprTools`. The ctx is meant to be ergonomic, not
exhaustive.

---

## `EmitCtx` — what's in scope at emit

`wui.macros.PrimitiveCtx.EmitCtx` :

| Field | Type | Notes |
|---|---|---|
| `ctx.lines` | `Array<String>` | The line buffer. Push your C++ statements directly. Indentation is the caller's problem ; don't worry about it. |
| `ctx.depth` | `Int` | Tree depth, in case you want to format. Rarely useful. |
| `ctx.nextVar(prefix)` | `String -> String` | Allocate a unique C++ variable name. Always use it — colliding with another widget's local is the easiest way to break a build. |
| `ctx.emitChild(node)` | `ViewNode -> String` | Recursively emit a child `ViewNode`, return its var name. |
| `ctx.applyModifiers(varName, controlType, mods)` | `String -> String -> Array<ModifierData> -> Void` | Apply the View's modifier chain (`padding`, `width`, `font`, …) to the just-emitted control. The `controlType` tells the modifier engine which subset of modifiers makes sense (a `Padding` modifier on a `TextBlock` is honoured ; a `Font` modifier on a `Border` is silently dropped). |
| `ctx.pushStateBinding(b)` | `{stateName, controlVar, format} -> Void` | Register a binding so the change-listener for `stateName` will re-apply `format` to `controlVar` on every notification. Use it whenever your primitive shows a state value (the binding is what makes it reactive). |
| `ctx.cppId(name)` | `String -> String` | Sanitise a bridge key into a C++ identifier (`"settings.darkMode"` → `"settings_darkMode"`). Composite Observable keys carry dots that aren't legal C++ identifiers ; this turns them into underscores. |
| `ctx.escapeWideString(s)` | `String -> String` | Escape a Haxe string for inclusion inside `L"..."`. Use it for every literal you emit — don't roll your own. |
| `ctx.stateFields` | `Array<{name, type, initial}>` | Read-only view of every primitive `@:state` field collected from the App. Useful for auto-binding heuristics (e.g. "if a Text's literal matches a state's initial, bind it"). |

---

## Registration

The framework discovers primitives explicitly — they live in a registry
that `WinUIGenerator.register()` populates. Add two lines for your new
primitive :

```haxe
// In wui/macros/WinUIGenerator.hx, inside register():
registerPrimitive("wui.ui.Hyperlink", wui.ui.Hyperlink.wuiAnalyze);
UIBuilder.registerEmitter("Hyperlink", wui.ui.Hyperlink.wuiEmit);
```

- `registerPrimitive(fqClassName, analyzeFn)` — keyed by Haxe class FQ name,
  matched against the `new <X>(...)` expression the user wrote.
- `registerEmitter(viewType, emitFn)` — keyed by the `viewType` string your
  `wuiAnalyze` puts in the returned `ViewNode`. Multiple primitive classes
  can share an emitter (HStack and VStack both produce `"StackPanel"`
  ViewNodes ; one emitter handles both, reading the orientation from
  properties).

The `@:wuiPrimitive` meta on the class isn't strictly required for the
manual registration above — it's reserved for the auto-discovery pass that
will eventually scan all classes tagged with it and register them
automatically. Until that lands, the two manual lines are what wire your
primitive in.

For a primitive that lives in user-app code (not in the WUI lib), the
registration goes into a `--macro` call you add to `build.hxml` :

```
--macro MyApp.registerPrimitives()
```

Where `registerPrimitives` does the same two calls.

---

## Walkthrough — adding `Hyperlink`

End-to-end : making `new Hyperlink(label, url)` produce a clickable navigation
link.

### 1. The WinUI 3 control

`winrt::Microsoft::UI::Xaml::Controls::HyperlinkButton`. Two properties we
care about :

- `Content(IInspectable)` — the text. We'll wrap a `winrt::hstring` in
  `box_value`.
- `NavigateUri(Uri)` — the link target.

Both supported out of the box ; no extra package import.

### 2. The Haxe class

`src/wui/ui/Hyperlink.hx` :

```haxe
package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

@:wuiPrimitive
class Hyperlink extends View {
    public function new(text:String, url:String) {
        super("Hyperlink");
        properties.set("text", text);
        properties.set("url", url);
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var props:Map<String, Dynamic> = new Map();
        if (args.length > 0) props.set("text", ctx.extractString(args[0]));
        if (args.length > 1) props.set("url",  ctx.extractString(args[1]));
        return { viewType: "Hyperlink", children: [], modifiers: [], properties: props };
    }

    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("link");
        ctx.lines.push('winrt_controls::HyperlinkButton $varName;');
        var text = node.properties.get("text");
        if (text != null) {
            var escaped = ctx.escapeWideString(Std.string(text));
            ctx.lines.push('$varName.Content(winrt::box_value(L"$escaped"));');
        }
        var url = node.properties.get("url");
        if (url != null) {
            var escaped = ctx.escapeWideString(Std.string(url));
            ctx.lines.push('$varName.NavigateUri(winrt::Windows::Foundation::Uri(L"$escaped"));');
        }
        ctx.applyModifiers(varName, "HyperlinkButton", node.modifiers);
        return varName;
    }
    #end
}
```

The `#if macro` guards everything macro-only — at runtime the primitive is
just a `View` with a properties bag, never actually constructed.

### 3. The registration

Two lines in `WinUIGenerator.register()` :

```haxe
registerPrimitive("wui.ui.Hyperlink", wui.ui.Hyperlink.wuiAnalyze);
UIBuilder.registerEmitter("Hyperlink", wui.ui.Hyperlink.wuiEmit);
```

### 4. Use it

```haxe
override function body():View {
    return new VStack([
        new Text("Need help ?"),
        new Hyperlink("Read the docs", "https://example.com/docs"),
    ]);
}
```

The generated `MainWindow.cpp` will contain :

```cpp
winrt_controls::HyperlinkButton link_3;
link_3.Content(winrt::box_value(L"Read the docs"));
link_3.NavigateUri(winrt::Windows::Foundation::Uri(L"https://example.com/docs"));
panel_0.Children().Append(link_3);
```

That's the whole loop.

---

## Patterns

### Children-bearing primitives

If your primitive wraps a single View (like `ScrollViewer`, `Show`), pull
the child via `ctx.recurseChild` in analyze, then emit it via `ctx.emitChild`
in emit :

```haxe
public static function wuiAnalyze(args, ctx):ViewNode {
    var children = args.length > 0 ? [ctx.recurseChild(args[0])] : [];
    return { viewType: "MyWrapper", children: children, modifiers: [], properties: new Map() };
}

public static function wuiEmit(node, ctx):String {
    var varName = ctx.nextVar("wrap");
    ctx.lines.push('winrt_controls::ContentControl $varName;');
    if (node.children.length > 0) {
        var childVar = ctx.emitChild(node.children[0]);
        ctx.lines.push('$varName.Content($childVar);');
    }
    ctx.applyModifiers(varName, "ContentControl", node.modifiers);
    return varName;
}
```

For an array of children (like a stack), use `ctx.recurseChildren(args[0])`
which expects a `TArrayDecl`.

### State-bound primitives

If your primitive shows a `@:state` value, use
`ctx.extractStateBoundText(arg)` to detect the binding. It returns a
record with `text` (the initial string), `boundState` (the bridge key
name), and `format` (the C++ format string the change listener should
run) :

```haxe
public static function wuiAnalyze(args, ctx):ViewNode {
    var props:Map<String, Dynamic> = new Map();
    var bound = args.length > 0 ? ctx.extractStateBoundText(args[0]) : null;
    if (bound != null) {
        props.set("text", bound.text);
        props.set("boundState", bound.boundState);
        props.set("boundFormat", bound.format);
    } else {
        props.set("text", args.length > 0 ? ctx.extractString(args[0]) : "");
    }
    return { viewType: "MyLabel", children: [], modifiers: [], properties: props };
}

public static function wuiEmit(node, ctx):String {
    var varName = ctx.nextVar("lbl");
    ctx.lines.push('winrt_controls::TextBlock $varName;');
    var boundState = node.properties.get("boundState");
    if (boundState != null) {
        var format = StringTools.replace(Std.string(node.properties.get("boundFormat")), "CTRL", varName);
        ctx.lines.push(format);
        ctx.pushStateBinding({ stateName: Std.string(boundState), controlVar: varName, format: format });
    } else {
        var escaped = ctx.escapeWideString(Std.string(node.properties.get("text")));
        ctx.lines.push('$varName.Text(L"$escaped");');
    }
    ctx.applyModifiers(varName, "TextBlock", node.modifiers);
    return varName;
}
```

The `pushStateBinding` registers your control with the runtime binding
system : every time the bridge fires `notify_<stateName>()`, the format
string runs against `varName`, reading the latest `s_<stateName>` value.

### Two-way binding (like `TextBox`)

Use `ctx.extractStateRef(arg)` to pull the `@:state` field name, then emit
both directions :

```haxe
var boundState = node.properties.get("boundState");
if (boundState != null) {
    var stateName = Std.string(boundState);
    var id = ctx.cppId(stateName);
    // Initial value
    ctx.lines.push('$varName.Text(winrt::hstring(s_$id));');
    // Control → state
    ctx.lines.push('$varName.TextChanged([](auto const& sender, auto const&) {');
    ctx.lines.push('    auto h = sender.as<winrt_controls::TextBox>().Text();');
    ctx.lines.push('    s_$id = std::wstring(h.c_str(), h.size());');
    ctx.lines.push('    notify_$id();');
    ctx.lines.push('});');
    // State → control (via the binding listener)
    ctx.pushStateBinding({
        stateName: stateName,
        controlVar: varName,
        format: 'if ($varName.Text() != winrt::hstring(s_$id)) $varName.Text(winrt::hstring(s_$id));'
    });
}
```

The guard in the State → control format avoids the obvious reentrance
loop : setting `Text(...)` fires `TextChanged` fires `notify_` fires the
listener fires `Text(...)`…

### Click handlers

For an action-bearing primitive (like `Button`), use
`ctx.extractStateAction(actionArg)` at analyze time. It returns a
pre-compiled C++ snippet (or `null` if the arg isn't a recognised
`StateAction`). Store it in properties and wire the event in emit :

```haxe
public static function wuiAnalyze(args, ctx):ViewNode {
    var props = new Map();
    if (args.length > 0) props.set("label", ctx.extractString(args[0]));
    if (args.length > 1) {
        var actionCode = ctx.extractStateAction(args[1]);
        if (actionCode != null) props.set("onClick", actionCode);
    }
    return { viewType: "MyButton", children: [], modifiers: [], properties: props };
}

public static function wuiEmit(node, ctx):String {
    var varName = ctx.nextVar("btn");
    ctx.lines.push('winrt_controls::Button $varName;');
    var onClick = node.properties.get("onClick");
    if (onClick != null) {
        ctx.lines.push('$varName.Click([](auto const&, auto const&) {');
        ctx.lines.push('    ${Std.string(onClick)}');
        ctx.lines.push('});');
    }
    ctx.applyModifiers(varName, "Button", node.modifiers);
    return varName;
}
```

The action compilation already covers `Increment` / `SetValue` / `Toggle` /
`Custom` and chains of those via `Sequence` — you get the full state-action
vocabulary on your primitive for free.

---

## Constraints and gotchas

- **The runtime stub matters.** Your `wuiAnalyze` only runs at compile time
  ; if a user happens to call `new MyPrimitive(…)` from non-`body()` Haxe
  code (e.g. inside a `Custom` lambda), the runtime constructor runs. Keep
  it cheap and correct so the resulting `View` instance has the right
  `viewType` and properties — they're not used by the macro pipeline but
  may be inspected by user code.
- **`controlType` in `applyModifiers` matters.** A `Font` modifier on a
  `Border` is silently dropped because Border has no FontFamily property.
  If a modifier "doesn't apply", check that the second arg to
  `ctx.applyModifiers` matches what the modifier engine expects for that
  modifier (see `UIBuilder.applyModifiers` for the dispatch table).
- **Don't push raw user input into `lines`.** Always run it through
  `ctx.escapeWideString` before wrapping in `L"..."`. A literal that
  contains a `"` or a `\` breaks the build at best, opens a code-injection
  hole at worst.
- **The viewType key is namespaced by you.** Pick something that doesn't
  collide with framework primitives (`StackPanel`, `Grid`, `TextBlock`,
  `Button`, …). When in doubt, prefix with your app's short identifier
  (`MyAppCard` rather than `Card`).

---

## What about user composition versus new primitives ?

If you're wrapping existing widgets with custom defaults (a `Title` that's
a `Text` with a fixed font and colour), use a **user component** instead
of a new primitive : see [Creating reusable views](../views/components.md).
Components inline at compile time and don't need any registration.

The primitive route is for **new widget types** — controls WinUI 3 offers
that wui doesn't surface yet, or custom-drawn controls you want to expose
to the rest of the app under a clean Haxe API. If the answer to "could this
be built by composing existing widgets ?" is yes, prefer the component
route.
