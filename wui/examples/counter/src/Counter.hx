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
            new Spacer()
        ]).horizontalAlignment(Center);
    }
}
