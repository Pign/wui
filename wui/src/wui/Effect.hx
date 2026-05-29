package wui;

/**
 * useEffect-equivalent for reactive side-effects. The lambda runs once
 * at startup and re-runs each time one of the named `@:state` deps
 * changes — under the hood, the WUI macro lifts the body into a
 * `wui.generated.Callbacks` method and pushes it into each dep's
 * listener list (the same infrastructure that powers view bindings).
 *
 * Usage:
 *
 *   class MyApp extends wui.App {
 *     @:state var unreadCount:Int = 0;
 *
 *     override function effects():Void {
 *       Effect.run(() -> {
 *         var n = StateBridge.getInt("unreadCount");
 *         Window.setTitle('Inbox ($n) — Courrier Libre');
 *       }, [unreadCount]);
 *     }
 *   }
 *
 * Why deps are typed refs (`[unreadCount]`) rather than strings: the
 * macro accepts either form, but a typed ref catches typos at compile
 * time and survives renames. Strings still work as an escape hatch
 * when the @:state field isn't in scope (e.g. calling Effect.run from
 * `static main()`).
 *
 * Constraints (macro-extracted, not runtime-resolved):
 *  - Calls live inside the App's `effects():Void` override (instance
 *    context, so @:state fields are addressable as `searchQuery`).
 *    Calls from other methods are silently ignored.
 *  - The deps argument MUST be an inline array literal. A variable
 *    holding the array (`var deps = [...]; Effect.run(fn, deps);`)
 *    won't be picked up.
 *  - Each dep is either a typed `@:state` field ref or a string literal
 *    matching a state field name.
 *  - Empty deps `[]` means "run once at startup, never re-run"
 *    (matches React's `useEffect(fn, [])` semantics).
 *
 * The body of this static method is intentionally empty: the WUI macro
 * recognises `Effect.run(...)` calls during the typing pass and rewrites
 * them into C++ listener subscriptions. If you call it from a context
 * the macro doesn't analyse, it silently no-ops.
 */
class Effect {
    public static function run(fn:Void->Void, deps:Array<Dynamic>):Void {
        // Intercepted by `WinUIGenerator.collectEffects` at compile time.
        // No runtime work happens here.
    }
}
