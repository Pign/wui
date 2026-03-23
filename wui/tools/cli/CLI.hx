package tools.cli;

import sys.FileSystem;
import sys.io.File;

class CLI {
    static var cwd:String;

    static function main() {
        cwd = Sys.getCwd();
        var args = Sys.args();

        // When run via haxelib, the last arg is the calling directory
        if (args.length > 0) {
            var lastArg = args[args.length - 1];
            if (FileSystem.exists(lastArg) && FileSystem.isDirectory(lastArg)) {
                cwd = lastArg;
                args.pop();
            }
        }

        if (args.length == 0) {
            printUsage();
            return;
        }

        var command = args[0];
        var commandArgs = args.slice(1);

        switch (command) {
            case "init":
                Init.run(cwd, commandArgs);
            case "build":
                Build.run(cwd, commandArgs);
            case "run":
                Run.run(cwd, commandArgs);
            case "clean":
                Clean.run(cwd, commandArgs);
            case "help":
                printUsage();
            case "version":
                Sys.println("wui 0.1.0");
            default:
                Sys.println('Unknown command: $command');
                printUsage();
                Sys.exit(1);
        }
    }

    static function printUsage() {
        Sys.println("wui - Build native WinUI 3 Windows apps in Haxe\n");
        Sys.println("Usage: wui <command> [options]\n");
        Sys.println("Commands:");
        Sys.println("  init [name]     Scaffold a new wui project");
        Sys.println("  build           Build the application");
        Sys.println("  run             Build and run");
        Sys.println("  clean           Remove build artifacts");
        Sys.println("  help            Show this help message");
        Sys.println("  version         Show version\n");
        Sys.println("Options:");
        Sys.println("  --release       Build Release configuration (default: Debug)");
        Sys.println("  --arch=ARCH     Target architecture: x64|arm64 (default: x64)");
        Sys.println("  --verbose, -v   Show MSBuild output");
    }
}
