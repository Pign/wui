import wui.View;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Spacer;
import wui.ui.ForEach;
import wui.modifiers.ViewModifier.FontStyle;
import wui.modifiers.ViewModifier.ColorValue;
import wui.state.ImmutableList;
import wui.state.StateAction;
import wui.state.StateBridge;

/**
 * Demonstrates the two row-tap patterns that compose with `ForEach` :
 *
 *   1. **Typed callback** — `Custom(staticFn)` where `staticFn` is
 *      typed `(Int) -> Void`. The macro detects the signature and
 *      routes through a parametric `wui.generated.Callbacks` wrapper
 *      that receives the row index from the C++ Tapped handler.
 *
 *   2. **Closure** — `Custom(() -> { … idx … })`. The macro converts
 *      the typed body to an untyped Expr via `closureBodyToExpr`,
 *      rewriting references to the ForEach lambda's index local as
 *      bare `idx` identifiers. Haxe re-types the converted body
 *      inside the generated wrapper where `idx:Int` is the param.
 *
 * Both produce the same C++ shape : a parametric wrapper invoked
 * from `_row.Tapped([i](...) { Callbacks_obj::wui_cb_<N>(i); });`.
 *
 * The example shows a left column with typed-callback rows and a
 * right column with closure rows. Clicking a row in either updates
 * the `status` line below to indicate which row fired which path —
 * proves that both compile to the same runtime behaviour.
 */
typedef Item = { id:String, label:String };

class ForeachCallbacks extends wui.App {
    @:state var items:ImmutableList<Item> = ImmutableList.fromArray([
        { id: "a", label: "Apple"    },
        { id: "b", label: "Banana"   },
        { id: "c", label: "Cherry"   },
        { id: "d", label: "Date"     },
        { id: "e", label: "Elderberry" },
    ]);
    @:state var status:String = "Tap any row.";

    static function main() {}

    override function appName():String return "ForEach Callbacks";

    // Typed callback target — referenced by name in pattern 1.
    public static function typedTap(idx:Int):Void {
        StateBridge.setString("status", "Typed callback fired for row #" + idx);
    }

    override function body():View {
        return new VStack([
            new Text("ForEach row-tap callbacks")
                .font(TitleLarge)
                .foregroundColor(ColorValue.Rgb(186, 195, 255)),

            new Text("Two equivalent ways to wire a row tap")
                .font(Body)
                .foregroundColor(ColorValue.Rgb(140, 145, 157)),

            new Spacer(20),

            new HStack([
                // ── Pattern 1 — typed callback ──
                new VStack([
                    new Text("Pattern 1 — typed callback")
                        .font(BodyStrong)
                        .foregroundColor(ColorValue.Rgb(186, 195, 255)),
                    new Text("Custom(StaticFn) where StaticFn : (Int) -> Void")
                        .font(Caption)
                        .foregroundColor(ColorValue.Rgb(140, 145, 157)),
                    new ForEach(items, (item:Item, idx:Int) ->
                        new HStack([
                            new Text(item.label),
                            new Text(" — "),
                            new Text(item.id),
                        ])
                            .padding(10)
                            .onTap(StateAction.Custom(ForeachCallbacks.typedTap))
                    ),
                ]).spacing(8).padding().width(380),

                // ── Pattern 2 — closure with capture ──
                new VStack([
                    new Text("Pattern 2 — closure with capture")
                        .font(BodyStrong)
                        .foregroundColor(ColorValue.Rgb(186, 195, 255)),
                    new Text("Custom(() -> { … idx … }) — multi-statement OK")
                        .font(Caption)
                        .foregroundColor(ColorValue.Rgb(140, 145, 157)),
                    new ForEach(items, (item:Item, idx:Int) ->
                        new HStack([
                            new Text(item.label),
                            new Text(" — "),
                            new Text(item.id),
                        ])
                            .padding(10)
                            .onTap(StateAction.Custom(() -> {
                                // Body is arbitrary Haxe — multi-statement,
                                // multiple captures of idx, expressions,
                                // calls to different statics. The macro
                                // converts the typed expression to an
                                // untyped Expr and re-types it inside the
                                // wrapper where `idx:Int` is the param.
                                // Note : capturing the row item itself
                                // (`item.id`) isn't supported yet — only
                                // the index `idx` is plumbed through. The
                                // item field accessor route would mirror
                                // what `ForEachAccessor` already does at
                                // render time.
                                var rank = idx + 1;
                                StateBridge.setString(
                                    "status",
                                    "Closure fired for row #" + rank + " (zero-based " + idx + ")"
                                );
                            }))
                    ),
                ]).spacing(8).padding().width(380),
            ]),

            new Spacer(20),

            new Text(status)
                .font(Body)
                .foregroundColor(ColorValue.Rgb(186, 195, 255))
                .padding(),
        ])
            .spacing(8)
            .padding()
            .horizontalAlignment(Center);
    }
}
