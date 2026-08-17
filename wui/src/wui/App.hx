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

    /**
        What this application owns for as long as it runs.

        An effect an application starts — watching connectivity, a subscription,
        a timer — has to be stopped, and there is exactly one moment every
        backend agrees on: the application is over.

        ```haxe
        lifetime.ownEffect(new Effect(() -> { … Effect.onCleanup(stop); }));
        ```

        **There is no view lifetime here, and that is not an oversight.** A view
        disappearing is observable to Haxe only where Haxe reconciles the tree —
        the push backends — and not at all where the host walks it, which is what
        `sui` and `aui` do. Offering a hook that fired on two backends and stayed
        silent on the others would be worse than not offering one.
    **/
    public final lifetime = new rui.Lifetime();

    public function new() {}

    /** Override to set the application/window title. */
    public function appName():String {
        return "WUI App";
    }

    /** Override to define the root view tree. */
    public function body():View {
        return new View();
    }
}
