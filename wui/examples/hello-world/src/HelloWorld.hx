import wui.View;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.ui.Spacer;
import wui.modifiers.ViewModifier.FontStyle;
import wui.modifiers.ViewModifier.ColorValue;
import wui.modifiers.ViewModifier.HorizontalAlign;

class HelloWorld extends wui.App {
    static function main() {
        // Entry point — the macro system handles code generation.
        // At runtime (in the generated C++/WinRT app), App.cpp is the entry point.
    }

    override function appName():String {
        return "Hello World";
    }

    override function body():View {
        return new VStack([
            new Spacer(),
            new Text("Hello from Haxe!")
                .font(TitleLarge)
                .foregroundColor(AccentColor)
                .padding(),
            new Text("Built with wui - native WinUI 3 apps in Haxe")
                .font(Body)
                .foregroundColor(Gray)
                .padding(),
            new HStack([
                new Button("Learn More"),
                new Button("Get Started")
            ]).spacing(8),
            new Spacer()
        ]).horizontalAlignment(Center);
    }
}
