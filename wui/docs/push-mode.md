# Push mode

An app marked `@:nui` does not have its `body()` read at compile time. It runs,
describes itself as [`nui` nodes](https://lapavoiserie.github.io/nui/#/push-mode),
and a reconciler tells the WinUI side what changed. This page is about that
side — what a node becomes, where its children go, and how a control answers
back.

## What a node becomes

`wui.nui.Vocabulary` reads the `@:winuiType` and `@:winrt` annotations off
`wui.ui.*` and the generated `WuiNodes.cpp` is emitted from them. A control in
the vocabulary is a node type the sink can build; anything else is **refused at
compile time** by `wui.macros.PushCoverage`, which names the type and the file
to annotate.

That refusal is deliberate. A type the sink does not know could be drawn as
`?TabView` on screen — which is the right answer for a tree arriving as *data*,
and the wrong one for a `body()` written here and compiled for a known backend.
A knowable defect belongs in the build, not in a screenshot.

**A node reports its class name**, not its WinRT type. `wui.ui.Text` is the
documented exception, stated in its own source. `VStack` and `HStack` both used
to report `"StackPanel"`, and since every generated branch is keyed on the name
a node reports, the two collapsed onto one branch that could only carry one
orientation: every stack in the tree came out horizontal, and a screenful of
rows landed on a single line.

## Where children go

`wui_node_insert` receives a parent, a child and an index. WinRT has **four**
places a parent can keep a child, and which one applies depends on the parent:

| Parent | Children go to | Index |
|---|---|---|
| `Panel` (StackPanel, Grid) | `Children` | honoured |
| `TabView` | `TabItems` | honoured |
| `NavigationView` | `MenuItems` for a `NavigationViewItem`, `Content` for anything else | pane only |
| `SelectorBar` | `Items` | honoured |
| `Border` | `Child` | nothing to order |
| `ContentControl` | `Content` | nothing to order |

Handling only `Panel` and returning silently for the rest is what drew the
kitchen sink as a lone `+`: a TabView keeps its pages in `TabItems`, so every
tab was dropped, and WinUI renders a TabView with no items as nothing but its
add-tab button. A parent with nowhere to put a child now says so.

A row is a `Grid` and its children go into **columns**, `Auto` for content and
`*` for a spacer — a `StackPanel` hands each child the size it asks for and has
no leftover room to give away. A row and a `ZStack` are both Grids, so a row is
tagged and the tag is read back through `IPropertyValue`;
`unbox_value_or<hstring>` instantiates `IReference<hstring>`, which this header
set rejects.

## How a control answers back

A two-way control needs both directions, and the push path had neither until a
switch bound to a cell holding `true` drew itself `Off`.

**Down** — `wui.mui.FromViews` reads the bound cell while describing the tree,
and emits its value under whatever that control calls its value.
`wui.nui.Bindings` holds those names, because they are WinRT's: a switch calls
it `isOn`, a field `text`, a slider `value`. Reading the cell there is what
subscribes the render to it — the walk runs inside an effect.

**Up** — the control reports through the one event that carries its value, and
`wui_bridge_invoke_node_{string,float,int,bool}` carries it into Haxe. The value
is read off the event's **sender**, never off a captured control: capturing
would make the control own a handler that owns the control, a cycle WinRT has
no collector to break.

**Never re-assert a value a control already has.** A two-way control is written
by the user, then written again by the render that the user's own edit
provoked — the same value, a moment later. WinRT does not treat that as a
no-op: assigning `Text` moves the caret and assigning `IsOn` cuts the switch
animation off mid-slide. Both read as the control being rebuilt under the user's
hands, which is what push mode exists to avoid. `Text`, `IsOn` and `Value` are
compared before being written.

## Numbers, and which entry point they arrive through

A number does not know which of the two it is. Haxe answers
`Std.isOfType(1.0, Int)` with `true`, so a describing layer holding `Dynamic`
sends `max = 1.0` through the **integer** entry point. Each entry point used to
carry branches only for properties declared its own kind, so that call found
nothing and vanished — silently, and three defects came from it: a slider that
kept WinUI's default maximum of 100 and drew 0.4 pinned to the left, stack
spacings that never arrived because they are whole numbers, and a progress ring
one control over.

Which C type a number crossed as is an accident of its value. What it has to
become is written on the member, so the two numeric entry points accept each
other's properties and convert. Strings and booleans stay matched exactly:
neither has a form the other can be mistaken for.

## One tree per surface

A mounted tree is a **surface record** — its own sink, reconciler, render
effect and `rui.Lifetime`, plus the root handle it reconciles into
(`wui.nui.SurfaceRecord`). The Primary surface holds the *application's*
lifetime, because its render passes bracket `body()`, where the app's `keep`
keys are declared; a later surface (an auxiliary window) brings a fresh one.

Roots are **registered, not hardwired**: `BuildUI` calls
`wui::nodes::registerRoot(root)` and passes the handle it gets back to
`wui_bridge_render_nui(int)`. It used to be a literal `0` on both sides, seated
by a `reset()` that cleared the whole handle table first — fine with one
window, and a wipe of every other surface's controls the moment there are two.
The same rule now governs node callbacks: the registry is monotonic and never
wiped; a destroyed node's ids become holes, and a late event against a hole is
reported rather than routed to a stranger's closure.

Tearing a surface down is `SurfaceRecord.dispose()` — idempotent, releases the
render effect and the lifetime. `wui_bridge_dispose_primary()` is the
application-over seam: it disposes every auxiliary first (each releases its
own lifetime), then the Primary, whose lifetime carries everything the app
`own()`ed.

`test/MultiRootCheck.hx` pins all of this with two recording surfaces: an
update or destroy on one must leave the other's bindings, controls and
callbacks untouched.

## Auxiliary windows

A `@:surface(Auxiliary)` declaration on a mui app becomes a second WinUI
window, live — its own surface record, reconciled on its own state, in
declaration order (cardinality Many: N windows on the one UI thread is WinUI
3's normal shape, and the only thread hxcpp is attached to).

The layering is the hook pattern the sibling backends use: the bridge is wui
core and may not import `mui`, so `wui.mui.App`'s constructor installs
`HaxeBridge.auxiliaryRootsOf`, answering each declaration as a **node thunk**
(`FromViews.describe` runs in the thunk — the push path eats nodes, and the
conversion is the mui layer's business). `renderNui` mounts the auxiliaries
right after the Primary; `install()` constructed the app — and installed the
hook — before `BuildUI` ever ran, so the hook is always there.

Window creation crosses through a **slot**, not a symbol —
`wui_bridge_set_window_creator`, filled by `BuildUI`, consulted by the library
— so the hxcpp library stays linkable on its own, and a test injects a
counting creator on the Haxe side (`HaxeBridge.windowCreator`) without WinRT
existing at all. The generated `wui::nodes::createWindow` opens the Window,
registers a StackPanel root like any other surface's, and installs a `Closed`
handler that reports the handle to `wui_bridge_surface_closed`; the Haxe side
then disposes exactly that record. Closed windows are dead entries in a
pinned, never-shrinking window list — the handle-table policy again.

`test/AuxiliaryCheck.hx` drives the whole path as a real mui application with
the seam injected: one window per declaration, per-surface rebuilds, a close
that touches nothing else, and an application release that disposes the rest.

### ABI deltas for the next Windows validation pass

On top of the partition's list:

1. new slot in the hxcpp library: `wui_bridge_set_window_creator(int (*)(const char*))`,
   registered by the generated `BuildUI` before `wui_bridge_render_nui`;
2. new library export consumed by generated code: `wui_bridge_surface_closed(int)`,
   called by the `Closed` handler inside the generated `wui::nodes::createWindow`;
3. new generated function `wui::nodes::createWindow(const char*) -> int`
   (declared in `WuiNodes.h`, defined in `WuiNodes.cpp`, plus the pinned
   `g_windows` vector);
4. `wui_bridge_dispose_primary()` now tears down auxiliaries before the
   Primary — name unchanged, behaviour widened.

## What is still missing

The transpiled path's own state bridge does not push `TFloat` or `TBool` to the
UI — it says so at startup. That is the *other* path; nothing on this page
depends on it.
