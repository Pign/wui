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

    /** Override to define the root view tree. */
    public function body():View {
        return new View();
    }
}
