import wui.View;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.ui.Spacer;

class HelloWorld extends wui.App {
    static function main() {
        // Entry point — the macro system handles code generation.
        // At runtime (in the generated C++/WinRT app), App.cpp is the entry point.
    }

    override function appName():String {
        return "Hello World";
    }

    override function body():View {
        // Statement style: the macro follows what is done to a local after its
        // declaration, and a property assignment is a statement, not a chain.
        var title = new Text("Hello from Haxe!");
        title.font = "TitleLarge";
        title.foregroundColor = "accent";
        title.padding = 12;

        var subtitle = new Text("Built with wui - native WinUI 3 apps in Haxe");
        subtitle.font = "Body";
        subtitle.foregroundColor = "gray";
        subtitle.padding = 12;

        var root = new VStack([
            new Spacer(),
            title,
            subtitle,
            new HStack([
                new Button("Learn More"),
                new Button("Get Started")
            ], 8),
            new Spacer()
        ]);
        root.horizontalAlignment = "Center";
        return root;
    }
}
