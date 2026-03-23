package tools.cli;

import sys.FileSystem;
import sys.io.File;
import haxe.io.Path;
import haxe.Json;

class Run {
    public static function run(cwd:String, args:Array<String>) {
        // Build first
        Build.run(cwd, args);

        // Determine config (default Release, matching Build.hx)
        var debug = args.indexOf("--debug") >= 0;
        var config = debug ? "Debug" : "Release";
        var arch = "x64";
        for (arg in args) {
            if (StringTools.startsWith(arg, "--arch=")) {
                arch = arg.substr(7);
            }
        }

        // Read wui.json for app name
        var wuiConfig:Build.WuiConfig = Json.parse(
            File.getContent(Path.join([cwd, "wui.json"]))
        );

        var exePath = Path.join([cwd, "build", "winui", arch, config, '${wuiConfig.appName}.exe']);
        if (!FileSystem.exists(exePath)) {
            Sys.println('Error: Executable not found at $exePath');
            Sys.exit(1);
        }

        Sys.println('Running ${wuiConfig.appName}...');
        Sys.command(exePath);
    }
}
