package tools.cli;

import sys.FileSystem;
import sys.io.File;
import haxe.io.Path;
import haxe.Json;

typedef WuiConfig = {
    appName:String,
    packageName:String,
    displayName:String,
    windowsAppSdkVersion:String,
    targetFramework:String,
    architecture:String
};

class Build {
    public static function run(cwd:String, args:Array<String>) {
        var verbose = args.indexOf("--verbose") >= 0 || args.indexOf("-v") >= 0;
        var release = args.indexOf("--release") >= 0;
        var config = release ? "Release" : "Debug";

        // Parse architecture
        var arch = "x64";
        for (arg in args) {
            if (StringTools.startsWith(arg, "--arch=")) {
                arch = arg.substr(7);
            }
        }

        // Read wui.json
        var wuiJsonPath = Path.join([cwd, "wui.json"]);
        if (!FileSystem.exists(wuiJsonPath)) {
            Sys.println("Error: wui.json not found. Run 'wui init' first.");
            Sys.exit(1);
        }

        var wuiConfig:WuiConfig = Json.parse(File.getContent(wuiJsonPath));
        Sys.println('Building ${wuiConfig.appName} ($config, $arch)...');

        // Step 1: Run Haxe compilation (generates C++ via hxcpp + macro-generated C++/WinRT files)
        Sys.println("[1/4] Compiling Haxe...");
        var buildHxml = Path.join([cwd, "build.hxml"]);
        if (!FileSystem.exists(buildHxml)) {
            Sys.println("Error: build.hxml not found.");
            Sys.exit(1);
        }

        var haxeResult = runCommand(cwd, "haxe", ["build.hxml"], verbose);
        if (haxeResult != 0) {
            Sys.println("Error: Haxe compilation failed.");
            Sys.exit(1);
        }

        // Step 2: Build hxcpp static library
        Sys.println("[2/4] Building hxcpp static library...");
        var cppBuildDir = Path.join([cwd, "build", "cpp"]);
        var hxcppResult = runCommand(cppBuildDir, "haxelib", ["run", "hxcpp", "Build.xml", "-Dstatic_link"], verbose);
        if (hxcppResult != 0) {
            Sys.println("Error: hxcpp compilation failed.");
            Sys.exit(1);
        }

        // Step 3: NuGet restore
        Sys.println("[3/4] Restoring NuGet packages...");
        var winuiDir = Path.join([cwd, "build", "winui"]);
        var packagesDir = Path.join([cwd, "build", "packages"]);
        var nugetResult = runCommand(winuiDir, "nuget", [
            "restore", "packages.config",
            "-PackagesDirectory", packagesDir
        ], verbose);
        if (nugetResult != 0) {
            Sys.println("Warning: NuGet restore failed. Trying dotnet restore...");
        }

        // Step 4: MSBuild
        Sys.println("[4/4] Building WinUI application...");
        var vcxproj = Path.join([winuiDir, '${wuiConfig.appName}.vcxproj']);
        var msbuildResult = runCommand(winuiDir, "msbuild", [
            vcxproj,
            '/p:Configuration=$config',
            '/p:Platform=$arch',
            verbose ? "/v:normal" : "/v:minimal"
        ], verbose);
        if (msbuildResult != 0) {
            Sys.println("Error: MSBuild failed.");
            Sys.exit(1);
        }

        Sys.println('Build complete: build/winui/$config/${wuiConfig.appName}.exe');
    }

    public static function runCommand(workDir:String, cmd:String, args:Array<String>, verbose:Bool):Int {
        if (verbose) {
            Sys.println('  > $cmd ${args.join(" ")}');
        }
        var oldCwd = Sys.getCwd();
        Sys.setCwd(workDir);
        var result = Sys.command(cmd, args);
        Sys.setCwd(oldCwd);
        return result;
    }
}
