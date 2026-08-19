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
        if (declared != null && !isEmptyRoot(declared)) return declared;
        return wui.mui.FromViews.describe(body());
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
