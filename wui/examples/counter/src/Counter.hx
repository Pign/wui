import wui.View;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.state.StateAction;
import wui.ui.Spacer;
import wui.ui.TextBox;

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
        title.font = "Title";
        title.padding = 12;

        var display = new Text("Count: " + count);
        display.font = "TitleLarge";
        display.foregroundColor = "accent";
        display.padding = 12;

        var minus = new Button("-", null, count.dec(1));
        minus.padding = 12;
        var reset = new Button("Reset", null, count.setTo(0));
        reset.padding = 12;
        var plus = new Button("+", null, count.inc(1));
        plus.padding = 12;

        var a = new Button("Haxe A");
        a.onClick = () -> report("A");
        a.padding = 12;
        var b = new Button("Haxe B");
        b.onClick = () -> report("B");
        b.padding = 12;
        var c = new Button("Haxe C");
        c.onClick = () -> report("C");
        c.padding = 12;

        var field = new TextBox("Tapez ici...", label);
        field.padding = 12;
        var echo = new Text("Texte Haxe : " + label);
        echo.padding = 12;

        var writer = new Button("Haxe écrit le texte");
        writer.onClick = () -> {
            label.value = "écrit depuis Haxe (" + count.value + ")";
            trace('[wui] label = ${label.value}');
        };
        writer.padding = 12;

        var custom = new Button("Custom ×2", null, Custom(() -> {
            count.value = count.value * 2;
            trace('[wui] Custom : count = ${count.value}');
        }));
        custom.padding = 12;

        var root = new VStack([
            new Spacer(), title, display,
            new HStack([minus, reset, plus], 8),
            new HStack([a, b, c], 8),
            field, echo, writer, custom,
            new Spacer()
        ]);
        root.horizontalAlignment = "Center";
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

    /**
        Régression du validateur de noeuds : la propriété REQUISE (`text`) est
        appliquée en dernier. L'ancien parcours jugeait aussi les chaînes
        partielles — `new Node("Text").prop("fontSize", …)` vu de l'intérieur —
        donc cet ordre était une fausse erreur de compilation. Que ce fichier
        compile sous `build.hxml` (où le validateur tourne) est le test ;
        CallbackOrder relit le contenu à l'exécution.
    **/
    @:keep
    public static function orderedChain():nui.Node {
        return new nui.Node("Text")
            .prop("fontSize", nui.PropValue.PFloat(20))
            .prop("text", nui.PropValue.PString("ordre libre"));
    }

    static function report(which:String):Void {
        clicks++;
        last = which;
        var marks = "";
        for (i in 0...clicks) marks += "*";
        trace('[wui] bouton $which, clic n°$clicks $marks');
    }
}
