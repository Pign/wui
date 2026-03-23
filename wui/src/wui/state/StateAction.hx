package wui.state;

/**
 * Declarative state mutations. Used with Button and other interactive controls
 * to describe what should happen when the user interacts with a control.
 *
 * The UIBuilder macro translates these into C++/WinRT code that directly
 * calls State<T>::set() — no serialization, no bridge.
 *
 * Usage:
 *   new Button("Add", null, count.inc(1))
 *   new Button("Reset", null, count.setTo(0))
 *   new Button("Toggle", null, isDark.tog())
 */
enum StateAction {
    /** Increment a numeric state by amount. */
    Increment(state:Dynamic, amount:Dynamic);

    /** Decrement a numeric state by amount. */
    Decrement(state:Dynamic, amount:Dynamic);

    /** Set a state to a specific value. */
    SetValue(state:Dynamic, value:Dynamic);

    /** Toggle a boolean state. */
    Toggle(state:Dynamic);

    /** Append a value to an array state. */
    Append(state:Dynamic, value:Dynamic);

    /** Remove a value from an array state. */
    Remove(state:Dynamic, value:Dynamic);

    /** Execute a custom callback. */
    Custom(callback:() -> Void);

    /** Wrap an action with animation. */
    Animated(action:StateAction, curve:AnimationCurve);

    /** Execute multiple actions in sequence. */
    Sequence(actions:Array<StateAction>);
}

enum AnimationCurve {
    Default;
    Linear;
    EaseIn;
    EaseOut;
    EaseInOut;
    Spring;
    Bouncy;
}
