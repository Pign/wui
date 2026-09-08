import wui.View;
import wui.ui.VStack;
import wui.ui.Text;
import wui.ui.TextBox;

class FormDemo extends wui.App {
    @:state var name:String = "";

    static function main() {}

    override function appName():String {
        return "Form Demo";
    }

    override function body():View {
        // Statement style: the macro follows what is done to a local after its
        // declaration, and a property assignment is a statement, not a chain.
        var heading = new Text("Settings");
        heading.font = "Title";

        return new VStack([
            heading,
            new TextBox("Enter your name...", name_),
            new Text("Hello, " + name_)
        ]);
    }
}
