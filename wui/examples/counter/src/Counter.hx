import wui.View;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.state.StateAction;
import wui.ui.Spacer;
import wui.ui.TextBox;
import wui.modifiers.ViewModifier.FontStyle;
import wui.modifiers.ViewModifier.ColorValue;
import wui.modifiers.ViewModifier.HorizontalAlign;

class Counter extends wui.App {
    @:state var count:Int = 0;
    @:state var label:String = "";

    static function main() {}

    override function appName():String {
        return "Counter";
    }

    override function body():View {
        // Écrit en instructions : la macro suit désormais ce qu'on fait à une
        // locale après sa déclaration, pas seulement son initialiseur.
        var title = new Text("Counter");
        title.font(Title);
        title.padding();

        var display = new Text("Count: " + count);
        display.font(TitleLarge);
        display.foregroundColor(AccentColor);
        display.padding();

        var minus = new Button("-", null, count.dec(1));
        minus.padding();
        var reset = new Button("Reset", null, count.setTo(0));
        reset.padding();
        var plus = new Button("+", null, count.inc(1));
        plus.padding();

        var a = new Button("Haxe A");
        a.onClick(() -> report("A"));
        a.padding();
        var b = new Button("Haxe B");
        b.onClick(() -> report("B"));
        b.padding();
        var c = new Button("Haxe C");
        c.onClick(() -> report("C"));
        c.padding();

        var field = new TextBox("Tapez ici...", label);
        field.padding();
        var echo = new Text("Texte Haxe : " + label);
        echo.padding();

        var writer = new Button("Haxe écrit le texte");
        writer.onClick(() -> {
            label.value = "écrit depuis Haxe (" + count.value + ")";
            trace('[wui] label = ${label.value}');
        });
        writer.padding();

        var custom = new Button("Custom ×2", null, Custom(() -> {
            count.value = count.value * 2;
            trace('[wui] Custom : count = ${count.value}');
        }));
        custom.padding();

        var root = new VStack([
            new Spacer(), title, display,
            new HStack([minus, reset, plus], 8),
            new HStack([a, b, c], 8),
            field, echo, writer, custom,
            new Spacer()
        ]);
        root.horizontalAlignment(Center);
        return root;
    }

    /**
        Du Haxe arbitraire, hors du vocabulaire du transpileur.

        Une boucle, une concaténation et un compteur statique : rien ici ne
        pourrait être traduit en `inc`/`dec`/`setTo`/`tog`. C'est précisément
        l'intérêt — si cette ligne s'affiche au clic, le plafond d'expressivité
        est levé.
    **/
    static var clicks:Int = 0;

    /** Le dernier bouton actionné. Lu par le test d'ordre des identifiants. **/
    public static var last:String = null;

    static function report(which:String):Void {
        clicks++;
        last = which;
        var marks = "";
        for (i in 0...clicks) marks += "*";
        trace('[wui] bouton $which, clic n°$clicks $marks');
    }
}
