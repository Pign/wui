import wui.View;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Spacer;
import wui.ui.ForEach;
import wui.modifiers.ViewModifier.FontStyle;
import wui.modifiers.ViewModifier.ColorValue;
import wui.state.ImmutableList;
import wui.state.StateBridge;

/**
 * Demonstrates the two row-tap shapes that compose with `ForEach`.
 * Both are just closures now — `.onTap` accepts `() -> Void` directly :
 *
 *   1. **Static fn ref**    `.onTap(MyApp.handleTap)`         — no captures
 *   2. **Anonymous closure** `.onTap(() -> { … idx … })`     — full captures
 *
 * Inside a ForEach row, anonymous closures can reach for `idx`,
 * `item.<field>`, and any locals declared earlier in the row lambda
 * body. hxcpp's runtime closure machinery handles the captures ; the
 * macro materialises `item` from the State registry via a typed cast
 * so field accesses retype correctly.
 *
 * The example shows a left column with static-ref rows and a right
 * column with closure rows. Clicking a row in either updates the
 * `status` line below to indicate which path fired.
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

    // Static fn target — referenced by name in pattern 1. The macro
    // wraps it in a closure that calls `staticTap(idx)` so it still
    // sees the row index even though the source ref has no captures.
    public static function staticTap(idx:Int):Void {
        StateBridge.setString("status", "Static fn fired for row #" + idx);
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
                // ── Pattern 1 — static fn ref ──
                new VStack([
                    new Text("Pattern 1 — static fn ref")
                        .font(BodyStrong)
                        .foregroundColor(ColorValue.Rgb(186, 195, 255)),
                    new Text(".onTap(MyApp.staticTap) where staticTap : (Int) -> Void")
                        .font(Caption)
                        .foregroundColor(ColorValue.Rgb(140, 145, 157)),
                    new ForEach(items, (item:Item, idx:Int) ->
                        new HStack([
                            new Text(item.label),
                            new Text(" — "),
                            new Text(item.id),
                        ])
                            .padding(10)
                            .onTap(ForeachCallbacks.staticTap)
                    ),
                ]).spacing(8).padding().width(380),

                // ── Pattern 2 — closure with capture ──
                new VStack([
                    new Text("Pattern 2 — closure with capture")
                        .font(BodyStrong)
                        .foregroundColor(ColorValue.Rgb(186, 195, 255)),
                    new Text(".onTap(() -> { … idx, item.<field>, locals … })")
                        .font(Caption)
                        .foregroundColor(ColorValue.Rgb(140, 145, 157)),
                    new ForEach(items, (item:Item, idx:Int) -> {
                        // Body is arbitrary Haxe — multi-statement,
                        // captures of idx + typed item field accesses +
                        // locals declared in the row lambda. All handled
                        // at runtime by hxcpp's closure machinery.
                        var rank = idx + 1;
                        new HStack([
                            new Text(item.label),
                            new Text(" — "),
                            new Text(item.id),
                        ])
                            .padding(10)
                            .onTap(() -> {
                                StateBridge.setString(
                                    "status",
                                    "Closure fired for row #" + rank
                                        + " (zero-based " + idx + ") — "
                                        + item.label
                                );
                            });
                    }),
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
