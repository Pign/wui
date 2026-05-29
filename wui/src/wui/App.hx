package wui;

/**
 * Base class for WUI applications.
 * Subclass this and override body() to define your app's UI.
 *
 * Example:
 *   class MyApp extends wui.App {
 *       override function appName():String return "MyApp";
 *       override function body():View {
 *           return new wui.ui.VStack([
 *               new wui.ui.Text("Hello from Haxe!")
 *           ]);
 *       }
 *   }
 */
@:autoBuild(wui.macros.StateMacro.build())
class App {
    public var windowWidth:Int = 800;
    public var windowHeight:Int = 600;

    public function new() {}

    /** Override to set the application/window title. */
    public function appName():String {
        return "WUI App";
    }

    /** Override to pick the Window's translucent material.
        Defaults to Mica — the Windows 11 native look.
        Return Backdrop.None for a solid opaque window. */
    public function backdrop():Backdrop {
        return Mica;
    }

    /** Override to populate the Window's title bar with a custom view
        tree (search box, breadcrumbs, tabs — File Explorer / Edge style).
        Returning `null` keeps the default system title bar that just
        shows `appName()`.

        The returned view becomes the draggable region; interactive
        controls inside it (Button, TextBox) stay clickable. The system
        always reserves the rightmost ~138px for the min/max/close
        caption buttons — codegen auto-pads the root to keep your widgets
        from sliding under them. */
    public function titleBar():View {
        return null;
    }

    /** Override to declare reactive side-effects via [[Effect.run]].
        The body is never invoked at runtime — the WUI macro walks it at
        compile time, lifts every `Effect.run(fn, [deps])` lambda into
        the generated callbacks module, and wires each dep's listener
        list to re-invoke the lambda.

        Why a dedicated virtual rather than `main()`: this method runs
        in instance context, so `@:state` fields are addressable as
        typed refs (`searchQuery` instead of `"searchQuery"`) — typos
        become compile errors and rename refactors carry through.

        Example:

            override function effects():Void {
              Effect.run(() -> {
                var q = StateBridge.getString("searchQuery");
                Window.setTitle('Inbox: $q — Courrier Libre');
              }, [searchQuery]);
            } */
    public function effects():Void {}

    /** Override to define the root view tree. */
    public function body():View {
        return new View();
    }
}
