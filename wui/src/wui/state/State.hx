package wui.state;

/**
 * Reactive state container, backed by `rui.state.State` — the core shared with
 * the other La Pavoiserie backends. The subscriber list is registered as the
 * platform sink, so a write notifies it exactly as before.
 *
 * Usage:
 *   @:state var count:Int = 0;
 *   // The @:state macro wraps this as State<Int>
 *   // Then: count.value = 5; // notifies all subscribers
 *
 * This class DOES run in a built app, as of W3. `WinUIGenerator` still emits the
 * C++ statics (`s_<name>`, `s_<name>_listeners`, `notify_<name>()`) and they are
 * still what the controls read — but they are no longer the source of truth for
 * a Haxe write. `HaxeBridge.bindStates()` subscribes to every instance in
 * `_registry` and forwards to the generated `ApplyIntState`, which assigns the
 * static and notifies, on the UI thread.
 *
 * **Two sources of truth remain, on purpose.** The generated Click handlers for
 * `StateAction`s still mutate `s_<name>` directly, without telling Haxe, so the
 * two values drift if both paths are used. W4 removes the translation and leaves
 * only this one. Until then, mixing them is expected to look wrong.
 *
 * Only `Int` is pushed today; other types are reported, not silently dropped.
 * See `wui-hxcpp.md` in the atelier repo for the sequence.
 */
class State<T> extends rui.state.State<T> {
    var _listeners:Array<T -> Void>;

    /** Global registry of all state instances by name. */
    public static var _registry:Map<String, Dynamic> = new Map();

    public function new(initial:T, stateName:String) {
        super(initial, stateName);
        _listeners = [];
        _registry.set(stateName, this);
        // The subscriber list is the platform sink: in the C++ pipeline those
        // lambdas call WinRT control setters directly.
        setPlatformSink(function(v:T) {
            for (listener in _listeners.copy()) listener(v);
        });
    }

    /** Subscribe to value changes. */
    public function subscribe(fn:T -> Void):Void {
        _listeners.push(fn);
    }

    /** Unsubscribe from value changes. */
    public function unsubscribe(fn:T -> Void):Void {
        _listeners.remove(fn);
    }

    // --- Convenience StateAction builders ---

    /** Create an action that increments this state by amount. */
    public function inc(amount:Dynamic):StateAction {
        return Increment(this, amount);
    }

    /** Create an action that decrements this state by amount. */
    public function dec(amount:Dynamic):StateAction {
        return Decrement(this, amount);
    }

    /** Create an action that sets this state to a specific value. */
    public function setTo(val:T):StateAction {
        return SetValue(this, val);
    }

    /** Create an action that toggles this boolean state. */
    public function tog():StateAction {
        return Toggle(this);
    }

    /** Create an action that appends a value to this array state. */
    public function appendAction(val:Dynamic):StateAction {
        return Append(this, val);
    }

    // --- Static helpers ---

    /** Get a state by name from the global registry. */
    public static function getByName(name:String):Dynamic {
        return _registry.get(name);
    }

    /** Set a state value by name (for bridge calls). */
    public static function setByName(name:String, value:String):Void {
        var state = _registry.get(name);
        if (state != null) {
            state.value = value;
        }
    }
}
