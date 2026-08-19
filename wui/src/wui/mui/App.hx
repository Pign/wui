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
