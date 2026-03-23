package wui.state;

/**
 * Union type that can hold either a static value or a reactive State<T>.
 * Used by modifiers that support both static and state-bound values.
 *
 * Usage:
 *   .opacity(0.5)              // static
 *   .opacity(opacityState)     // reactive
 */
enum StateOr<T> {
    Static(value:T);
    Reactive(state:State<T>);
}
