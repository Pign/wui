package wui.state;

/**
 * Marker base class for composite state types eligible to be `@:state`.
 *
 * Under the "@:state must be primitive, nullary enum, Observable, or
 * Immutable" rule, Observable is the bucket for **field-level
 * reactive** composites: classes whose individual fields participate
 * in the reactive bridge (each @:observable-typed field decomposes
 * into a separate StateBridge entry under a dotted key).
 *
 * Constraints enforced by [[StateMacro]]:
 *  - An Observable's @:state fields must themselves be @:state-eligible.
 *  - Non-@:state fields are allowed (caches, helpers) but stay inert.
 *  - Observables don't fabricate their own bridge entries at
 *    construction time — they wait for `_attach(scope)` to be called
 *    by the enclosing scope (an App or a parent Observable). Until
 *    then, accessing a State<T> field returns `null`.
 *
 * Usage:
 *
 *   class Settings extends Observable {
 *     @:state var darkMode:Bool = false;
 *     @:state var fontSize:Int = 14;
 *   }
 *
 *   class MyApp extends App {
 *     @:state var settings:Settings = new Settings();
 *     // StateMacro injects `settings._attach("settings")` post-init
 *   }
 *
 * The dotted scope ("settings.darkMode") becomes the StateBridge key.
 * In C++ codegen the key is sanitised to `s_settings_darkMode`.
 */
@:autoBuild(wui.macros.StateMacro.build())
class Observable {
    /** Set by the enclosing scope via `_attach`. Bridge keys are built
        as `_scope + "." + fieldName`. */
    @:noCompletion public var _scope:String = "";

    public function new() {}

    /** Called once by the enclosing scope after construction to wire
        the Observable into the bridge. The actual State<T> field
        initialisations are emitted into the macro-generated override
        of this method on each Observable subclass. */
    public function _attach(scope:String):Void {
        _scope = scope;
    }
}
