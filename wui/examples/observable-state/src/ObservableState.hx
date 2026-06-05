import wui.View;
import wui.Effect;
import wui.Window;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.ui.Spacer;
import wui.ui.ForEach;
import wui.state.ImmutableList;
import wui.state.StateBridge;
import wui.modifiers.ViewModifier.FontStyle;

typedef Row = { id:String, label:String };

/**
 * Exercise the three remaining macro gaps :
 *
 *  - **Gap #1a** — `settings.fontSize.value` inside `effects()` should
 *    read C++ source of truth via `StateBridge`, not stale Haxe-side
 *    `_value`. Currently goes through `get_value()` which returns
 *    the initial value forever (bridge writes don't update
 *    `Settings._fontSize._value`).
 *
 *  - **Gap #1b** — same as above for the closure inside `.onTap(...)`
 *    on the "Read settings" button below. The lifted closure body
 *    needs the same rewrite as `effects()` gets — otherwise the
 *    Window title shows the initial settings every tap.
 *
 *  - **Gap #2** — the `ForEach` row tap closure captures `themeLabel`
 *    declared in `body()`. With the current macro the lifted builder
 *    fails to resolve it (only row-lambda locals are re-declared).
 */
class ObservableState extends wui.App {
    @:state var settings:Settings = new Settings();
    @:state var status:String = "ready";
    @:state var rows:ImmutableList<Row> = ImmutableList.fromArray([
        { id: "a", label: "Apple"  },
        { id: "b", label: "Banana" },
        { id: "c", label: "Cherry" },
    ]);

    static function main() {}

    override function appName():String return "Observable State";

    override function effects():Void {
        // Gap #1a — should re-fire on darkMode flip and read the
        // CURRENT bridge-side darkMode, not the initial false.
        Effect.run(() -> {
            var mode = settings.darkMode.value;
            Window.setTitle('Observable State — ' + (mode ? 'dark' : 'light'));
        }, [settings.darkMode]);
    }

    public static function bumpFontSize():Void {
        var cur = StateBridge.getInt("settings.fontSize");
        StateBridge.setInt("settings.fontSize", cur + 1);
    }

    public static function toggleDarkMode():Void {
        StateBridge.setBool("settings.darkMode", !StateBridge.getBool("settings.darkMode"));
    }

    override function body():View {
        // Gap #2 — captured by the ForEach row tap closure below.
        var themeLabel = "current theme :";

        return new VStack([
            new Text("Observable composite state demo").font(TitleLarge),
            new Spacer(8),

            // Display the live state through @:state field binding —
            // the macro recognises `settings.fontSize` as a composite
            // and emits a StateBridge subscription.
            new Text("Font size : " + settings.fontSize),
            new Text("Nickname : " + settings.nickname),

            new HStack([
                new Button("+ font size", null, ObservableState.bumpFontSize),
                new Button("toggle dark", null, ObservableState.toggleDarkMode),
                new Button("Read settings", null, () -> {
                    // Gap #1b — lifted closure reads composite .value.
                    // Should resolve via StateBridge, not stale _value.
                    var fs = settings.fontSize.value;
                    var dm = settings.darkMode.value;
                    StateBridge.setString("status", 'font=$fs dark=$dm');
                }),
            ]).spacing(8),

            new Text(status).font(Caption),
            new Spacer(8),

            new ForEach(rows, (row:Row, idx:Int) -> {
                new HStack([
                    new Text(row.id),
                    new Text(row.label),
                ])
                    .padding(6)
                    .onTap(() -> {
                        // Gap #2 — `themeLabel` is a body() local
                        // captured into the row tap closure. The row
                        // tap builder picks it up via localExprs and
                        // re-declares it with its original init.
                        StateBridge.setString(
                            "status",
                            themeLabel + " row " + idx + " (" + row.label + ")"
                        );
                    });
            }),
        ])
            .spacing(6)
            .padding();
    }
}
