import wui.state.Observable;

/**
 * Composite reactive value — one StateBridge entry per @:state field,
 * keyed `settings.<field>` once the App's StateMacro injects
 * `_attach("settings")` after construction.
 */
class Settings extends Observable {
    @:state public var fontSize:Int = 14;
    @:state public var darkMode:Bool = false;
    @:state public var nickname:String = "anon";

    public function new() super();
}
