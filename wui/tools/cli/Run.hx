package tools.cli;

import sys.FileSystem;
import sys.io.File;
import haxe.io.Path;
import haxe.Json;

class Run {
    public static function run(cwd:String, args:Array<String>) {
        // Build first
        Build.run(cwd, args);

        // Determine config
        var release = args.indexOf("--release") >= 0;
        var config = release ? "Release" : "Debug";

        // Read wui.json for app name
        var wuiConfig:Build.WuiConfig = haxe.Json.parse(
            File.getContent(Path.join([cwd, "wui.json"]))
        );

        var exePath = Path.join([cwd, "build", "winui", config, '${wuiConfig.appName}.exe']);
        if (!FileSystem.exists(exePath)) {
            Sys.println('Error: Executable not found at $exePath');
            Sys.exit(1);
        }

        Sys.println('Running ${wuiConfig.appName}...');
        Sys.command(exePath);
    }
}
