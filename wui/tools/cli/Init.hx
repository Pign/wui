package tools.cli;

import sys.FileSystem;
import sys.io.File;
import haxe.io.Path;

class Init {
    public static function run(cwd:String, args:Array<String>) {
        var name = args.length > 0 ? args[0] : "MyApp";
        var className = toClassName(name);
        var projectDir = Path.join([cwd, name]);

        if (FileSystem.exists(projectDir)) {
            Sys.println('Error: Directory "$name" already exists.');
            Sys.exit(1);
        }

        Sys.println('Creating new wui project: $name');

        // Create directory structure
        FileSystem.createDirectory(projectDir);
        FileSystem.createDirectory(Path.join([projectDir, "src"]));

        // Write wui.json
        File.saveContent(Path.join([projectDir, "wui.json"]), buildWuiJson(name));

        // Write build.hxml
        File.saveContent(Path.join([projectDir, "build.hxml"]), buildHxml(className));

        // Write main source file
        File.saveContent(Path.join([projectDir, "src", '$className.hx']), buildMainSource(className, name));

        Sys.println('Project created at: $projectDir');
        Sys.println('');
        Sys.println('Next steps:');
        Sys.println('  cd $name');
        Sys.println('  wui run');
    }

    static function toClassName(name:String):String {
        var splitter = ~/[^a-zA-Z0-9]+/g;
        var parts = splitter.split(name);
        var result = "";
        for (part in parts) {
            if (part.length > 0) {
                result += part.charAt(0).toUpperCase() + part.substr(1);
            }
        }
        if (result.length == 0) return "MyApp";
        var first = result.charAt(0);
        if (first >= "0" && first <= "9") result = "App" + result;
        return result;
    }

    static function buildWuiJson(name:String):String {
        return '{
    "appName": "$name",
    "packageName": "com.haxe.${name.toLowerCase()}",
    "displayName": "$name",
    "windowsAppSdkVersion": "1.5.*",
    "targetFramework": "net8.0-windows10.0.22621.0",
    "architecture": "x64"
}
';
    }

    static function buildHxml(className:String):String {
        return '-cp src
-lib wui
--macro wui.macros.WinUIGenerator.register()
-main $className
-cpp build/cpp
-D static_link
-D HXCPP_M64
';
    }

    static function buildMainSource(className:String, displayName:String):String {
        return 'import wui.App;
import wui.View;
import wui.ui.VStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.ui.Spacer;
import wui.modifiers.ViewModifier.FontStyle;

class $className extends wui.App {
    static function main() {}

    override function appName():String {
        return "$displayName";
    }

    override function body():View {
        return new VStack([
            new Spacer(),
            new Text("Hello from Haxe!")
                .font(TitleLarge)
                .padding(),
            new Spacer()
        ]);
    }
}
';
    }
}
