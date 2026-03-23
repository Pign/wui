import wui.View;
import wui.ui.VStack;
import wui.ui.Text;
import wui.ui.TextBox;
import wui.modifiers.ViewModifier.FontStyle;

class FormDemo extends wui.App {
    @:state var name:String = "";

    static function main() {}

    override function appName():String {
        return "Form Demo";
    }

    override function body():View {
        return new VStack([
            new Text("Settings")
                .font(Title),
            new TextBox("Enter your name...", name),
            new Text("Hello, " + name)
        ]);
    }
}
