package wui.state;

/**
 * Two-way binding between a parent state and a child control.
 * Used for TextBox, ToggleSwitch, Slider, etc. where the control
 * both reads from and writes to a state value.
 *
 * Usage:
 *   var name = new State<String>("", "name");
 *   new TextBox("Enter name", Binding.fromState(name))
 */
class Binding<T> {
    public var getter:() -> T;
    public var setter:T -> Void;

    public function new(getter:() -> T, setter:T -> Void) {
        this.getter = getter;
        this.setter = setter;
    }

    public function get():T {
        return getter();
    }

    public function set(value:T):Void {
        setter(value);
    }

    /** Create a two-way binding from a State<T>. */
    public static function fromState<T>(state:State<T>):Binding<T> {
        return new Binding<T>(
            () -> state.value,
            (v) -> state.value = v
        );
    }
}
