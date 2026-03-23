package wui.state;

/**
 * Reactive state container. Holds a value and notifies subscribers on change.
 *
 * In the pure C++ pipeline, State<T> compiles via hxcpp and subscriber
 * lambdas directly call C++/WinRT control setters — no bridge needed.
 *
 * Usage:
 *   @:state var count:Int = 0;
 *   // The @:state macro wraps this as State<Int>
 *   // Then: count.value = 5; // notifies all subscribers
 */
class State<T> {
    public var name:String;
    var _value:T;
    var _listeners:Array<T -> Void>;

    /** Global registry of all state instances by name. */
    public static var _registry:Map<String, Dynamic> = new Map();

    public function new(initial:T, stateName:String) {
        _value = initial;
        name = stateName;
        _listeners = [];
        _registry.set(stateName, this);
    }

    /** Get the current value. */
    public var value(get, set):T;

    function get_value():T {
        return _value;
    }

    /** Set the value and notify all subscribers. */
    function set_value(newValue:T):T {
        _value = newValue;
        for (listener in _listeners) {
            listener(newValue);
        }
        return newValue;
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
