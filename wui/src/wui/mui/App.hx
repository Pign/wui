package wui.mui;


/**
	`wui`'s conformance for `mui.App`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
@:nui
@:autoBuild(mui.macros.Surfaces.build())
class App extends wui.App {
    var _appTitle:String = "App";

    public function new() {
        super();
        // The bridge is wui core and may not import mui, so the mui layer
        // installs the hook that turns Auxiliary declarations into extra
        // windows. Every mui app sets the same static — idempotent by
        // construction. Installed in the constructor, which install() runs
        // before BuildUI ever calls renderNui, so the hook is always there
        // when the auxiliaries mount.
        wui.bridge.HaxeBridge.auxiliaryRootsOf = muiAuxiliaryRoots;
        // The View->Node describer, for the detached corner (Companion
        // projection, widget snapshots): FromViews already speaks the canon,
        // it just signs the shared register.
        mui.surface.Describe.impl = v -> wui.mui.FromViews.describe(v);
    }

    /**
        Every surface this application declares: Primary — `body()`, always —
        plus whatever `@:surface` methods collected into `declaredSurfaces()`.
        Override to declare past the sugar: `super.surfaces().concat([…])`.
        On wui the Primary content is `nuiBody()`'s concern; the declaration
        still names `body()` — the tree `nuiBody()` falls back to describing.
    **/
    public function surfaces():Array<mui.surface.SurfaceDecl> {
        return [mui.surface.SurfaceDecl.Tree(mui.surface.SurfaceRole.Primary, "body", () -> body())]
            .concat(declaredSurfaces());
    }

    /** What `@:surface` declared. `mui.macros.Surfaces` overrides this on the
        application; the default is the empty answer. **/
    public function declaredSurfaces():Array<mui.surface.SurfaceDecl> return [];

    /**
        The declared Auxiliary windows, as node thunks. Cardinality Many —
        WinUI puts N windows on the one UI thread, so every declaration gets
        one, in declaration order. The thunk describes the declaration's view
        tree as nodes on every run, exactly the way `nuiBody()` serves the
        Primary: the conversion is this layer's business, so the bridge stays
        free of both `mui` and the converter.
    **/
    static function muiAuxiliaryRoots(app:Dynamic):Array<{id:String, node:() -> nui.Node}> {
        var mine:App = cast app;
        var out = [];
        for (d in mine.surfaces()) switch (d) {
            case Tree(mui.surface.SurfaceRole.Auxiliary, id, content):
                out.push({id: id, node: function() return wui.mui.FromViews.describe(content())});
            case _:
        }
        return out;
    }

    /**
        The view, as a `nui` node tree — what `ui()` markup produces.

        This is the end-to-end chain: markup checked at compile time against the
        target backend, producing a tree the backend renders. `wui` takes it
        through the push contract; `cui` has a `NodeRenderer` that does the same
        for a terminal. Each backend renders the same tree its own way, which is
        the whole point of a shared node model.
    **/
    public function view():nui.Node {
        return new nui.Node("VStack");
    }

    /**
        What wui's push mode calls.

        Either shape of application answers it. An app that overrides `view()`
        describes nodes directly, and that is handed to the sink. An app that
        overrides `body()` — the shape the other three backends take — has its
        view tree *described* as nodes by `wui.mui.FromViews`.

        Before this, `body()` was a stub the push renderer never called: an app
        written the ordinary way compiled for wui and drew an empty window,
        which is the one thing a layer like this exists to prevent.
    **/
    public function nuiBody():nui.Node {
        var declared = view();
        var root = (declared != null && !isEmptyRoot(declared))
            ? declared
            : wui.mui.FromViews.describe(body());
        return withMenuBar(root);
    }

    /**
        Inject the declared command sets as a MenuBar above the Primary tree.

        No new bridge machinery on purpose: the menu is ORDINARY NODES in the
        Primary tree, so reconciliation gives live labels for free — nuiBody()
        runs inside the render effect, the command thunks are re-sampled on
        every describe, and a label that reads state re-applies as a text prop
        like any other. One MenuBarItem per CommandSet declaration, titled from
        the set id — N menus, which SwiftUI's CommandsBuilder could not do.

        The chord crosses as one packed int (wui.mui.Chords); a chord outside
        the grammar keeps its item's label and click without an accelerator —
        Chords already said why, once. The Command.action closures ride the
        existing PCallback path: an id crosses, never a closure.
    **/
    function withMenuBar(root:nui.Node):nui.Node {
        var bar:Null<nui.Node> = null;
        for (d in surfaces()) switch (d) {
            case CommandSet(id, commands):
                if (bar == null) bar = new nui.Node("MenuBar");
                var item = new nui.Node("MenuBarItem");
                item.prop("title", nui.PropValue.PString(menuTitle(id)));
                for (cmd in commands()) {
                    var mi = new nui.Node("MenuFlyoutItem");
                    mi.prop("text", nui.PropValue.PString(cmd.label));
                    mi.prop("onClick", nui.PropValue.PCallback(cmd.action));
                    if (cmd.shortcut != null) {
                        var packed = wui.mui.Chords.parse(cmd.shortcut);
                        if (packed != null) mi.prop("accelerator", nui.PropValue.PInt(packed));
                    }
                    item.child(mi);
                }
                bar.child(item);
            case _:
        }
        if (bar == null) return root;

        var wrapped = new nui.Node("VStack");
        wrapped.child(bar);
        wrapped.child(root);
        return wrapped;
    }

    /** "shortcuts" -> "Shortcuts": the same one-capital rule the auxiliary
        window titles follow. **/
    static function menuTitle(id:String):String {
        if (id == null || id.length == 0) return "Commands";
        return id.charAt(0).toUpperCase() + id.substr(1);
    }

    /** The placeholder `view()` returns when an app never overrode it. **/
    function isEmptyRoot(node:nui.Node):Bool {
        return node.type == "VStack"
            && (node.children == null || node.children.length == 0)
            && (node.props == null || !node.props.keys().hasNext());
    }

    // wui.App requires it. An app that overrides it gets it described as nodes;
    // one that does not gets an empty root, and its `view()` is what renders.
    override function body():wui.View {
        return new wui.ui.VStack([]);
    }

    /** Set the application title. Maps to wui's appName(). **/
    public var appTitle(get, set):String;

    function get_appTitle():String return _appTitle;
    function set_appTitle(v:String):String { _appTitle = v; return v; }

    override function appName():String return _appTitle;
}
