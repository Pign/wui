package wui.state;

/**
 * Marker interface for value-replacement reactive state.
 *
 * Where `Observable` decomposes a composite into per-field bridge keys
 * and reacts at field granularity, `Immutable` types are observed via
 * whole-value replacement. The runtime holds the value Haxe-side as
 * the source of truth and bridges only a small trigger primitive (an
 * `Int` version counter) so the C++ side knows when to re-render
 * subscribed widgets.
 *
 * The rule (enforced by [[wui.macros.StateMacro]]):
 *
 *     @:state var foo:T
 *
 * requires `T` to be one of:
 *  - A primitive (String, Int, Float, Bool)
 *  - A class extending `wui.state.Observable`
 *  - A class implementing `wui.state.Immutable`
 *
 * Typical citizens: [[ImmutableList]] for ordered collections, plus
 * `@:record`-flavoured value types whose every field is `final` so
 * "mutation" returns a new instance.
 *
 * The marker is intentionally empty — Haxe's type checker only needs
 * to know "Foo implements Immutable" so the macro can recognise it.
 */
interface Immutable {}
