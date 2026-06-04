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

    /**
     * Optional companion bridge key carrying a monotonic Int "version".
     * Set non-null when the State holds an `wui.state.Immutable` value:
     * the list/record itself stays Haxe-side (no C++ copy of the
     * payload), and only this counter crosses to C++ so widgets like
     * `ForEach` can re-render on whole-value replacement. Null for
     * primitive @:state where the value goes directly through the
     * StateBridge.
     */
    var _versionKey:Null<String>;
    var _version:Int = 0;

    /** Global registry of all state instances by name. */
    public static var _registry:Map<String, Dynamic> = new Map();

    public function new(initial:T, stateName:String, ?versionKey:String) {
        _value = initial;
        name = stateName;
        _versionKey = versionKey;
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
        if (_versionKey != null) {
            // Bump the companion trigger so C++-side subscribers
            // (ForEach rebuild handlers) get notified. The Haxe-side
            // _value remains the source of truth — only the counter
            // travels through the bridge.
            _version++;
            try {
                wui.state.StateBridge.setInt(_versionKey, _version);
            } catch (_:Dynamic) {
                // Bridge key not yet registered (e.g. early in App
                // construction before UIBuilder wires it up). Skipping
                // is safe: the first real set after wiring will catch
                // up because we still bumped _version locally.
            }
        }
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

    /** Read the current value. Alias for `value`. **/
    public function get():T {
        return _value;
    }

    /** Set a new value and notify subscribers. Alias for `value = x`. **/
    public function set(v:T):Void {
        value = v;
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
