import wui.View;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.ui.Spacer;
import wui.modifiers.ViewModifier.FontStyle;
import wui.modifiers.ViewModifier.ColorValue;
import wui.modifiers.ViewModifier.HorizontalAlign;

class Counter extends wui.App {
    @:state var count:Int = 0;

    static function main() {}

    override function appName():String {
        return "Counter";
    }

    override function body():View {
        return new VStack([
            new Spacer(),
            new Text("Counter")
                .font(Title)
                .padding(),
            new Text("Count: " + count)
                .font(TitleLarge)
                .foregroundColor(AccentColor)
                .padding(),
            new HStack([
                new Button("-", null, count.dec(1))
                    .padding(),
                new Button("Reset", null, count.setTo(0))
                    .padding(),
                new Button("+", null, count.inc(1))
                    .padding()
            ]).spacing(8),
            // Trois closures Haxe, après trois boutons StateAction : si la
            // numérotation de la macro et celle de l'exécution divergeaient, un
            // clic exécuterait la *mauvaise* closure plutôt que rien du tout —
            // ce que trois libellés distincts rendent visible immédiatement.
            new HStack([
                new Button("Haxe A").onClick(() -> report("A")).padding(),
                new Button("Haxe B").onClick(() -> report("B")).padding(),
                new Button("Haxe C").onClick(() -> report("C")).padding()
            ]).spacing(8),
            // W3 : l'écriture part de Haxe et l'affichage doit suivre.
            //
            // `count` vit ici, dans l'instance construite au démarrage ; le C++
            // garde son `s_count`. Écrire `count.value` traverse le puits
            // plateforme, le pont, puis le gestionnaire généré, qui affecte
            // `s_count` et appelle `notify_count()` sur le thread UI.
            //
            // Attendu tant que W4 n'est pas fait : les boutons `+`/`-`/`Reset`
            // modifient `s_count` sans prévenir Haxe, donc les deux valeurs
            // divergent. Ce bouton-ci écrase l'écart en réaffectant depuis Haxe.
            new Button("Haxe +10").onClick(() -> {
                count.value = count.value + 10;
                trace('[wui] count Haxe = ${count.value}');
            }).padding(),
            new Spacer()
        ]).horizontalAlignment(Center);
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
