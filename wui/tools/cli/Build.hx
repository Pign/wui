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
        var debug = args.indexOf("--debug") >= 0;
        var config = debug ? "Debug" : "Release";

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

        // Auto-detect tool paths
        var msbuildPath = findMSBuild();
        var nugetPath = findNuGet();

        // Step 1: Run Haxe compilation
        Sys.println("[1/3] Compiling Haxe...");
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

        // Step 2: NuGet restore
        Sys.println("[2/3] Restoring NuGet packages...");
        var winuiDir = Path.join([cwd, "build", "winui"]);
        var packagesDir = Path.join([cwd, "build", "packages"]);
        if (!FileSystem.exists(packagesDir)) {
            FileSystem.createDirectory(packagesDir);
        }
        var nugetResult = runCommand(cwd, nugetPath, [
            "restore", Path.join([winuiDir, "packages.config"]),
            "-PackagesDirectory", packagesDir
        ], verbose);
        if (nugetResult != 0) {
            Sys.println("Warning: NuGet restore may have failed (exit code " + nugetResult + ").");
        }

        // Step 3: MSBuild
        Sys.println("[3/3] Building WinUI application...");
        var vcxproj = Path.join([winuiDir, '${wuiConfig.appName}.vcxproj']);
        var msbuildResult = runCommand(cwd, msbuildPath, [
            vcxproj,
            '-p:Configuration=$config',
            '-p:Platform=$arch',
            '-clp:ErrorsOnly',
            verbose ? "-v:normal" : "-v:minimal"
        ], verbose);

        // Check if the exe was produced (MSBuild may report non-fatal post-link errors)
        var exeDir = Path.join([winuiDir, arch, config]);
        var exeFile = Path.join([exeDir, '${wuiConfig.appName}.exe']);
        if (!FileSystem.exists(exeFile)) {
            Sys.println("Error: MSBuild failed — no exe produced.");
            Sys.exit(1);
        }

        var exePath = 'build/winui/$arch/$config/${wuiConfig.appName}.exe';
        Sys.println('Build complete: $exePath');
    }

    /**
     * Find MSBuild.exe using vswhere, then fallback to PATH.
     */
    static function findMSBuild():String {
        // Try vswhere first (standard location)
        var vswhere = "C:\\Program Files (x86)\\Microsoft Visual Studio\\Installer\\vswhere.exe";
        if (FileSystem.exists(vswhere)) {
            var process = new sys.io.Process(vswhere, [
                "-latest", "-products", "*",
                "-requires", "Microsoft.Component.MSBuild",
                "-find", "MSBuild\\**\\Bin\\MSBuild.exe"
            ]);
            var output = StringTools.trim(process.stdout.readAll().toString());
            var exitCode = process.exitCode();
            process.close();
            if (exitCode == 0 && output.length > 0) {
                // Take the first line (latest version)
                var firstLine = output.split("\n")[0];
                firstLine = StringTools.trim(firstLine);
                if (FileSystem.exists(firstLine)) {
                    Sys.println('  Found MSBuild: $firstLine');
                    return firstLine;
                }
            }
        }

        // Try common paths
        var commonPaths = [
            "C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\MSBuild\\Current\\Bin\\MSBuild.exe",
            "C:\\Program Files\\Microsoft Visual Studio\\2022\\Professional\\MSBuild\\Current\\Bin\\MSBuild.exe",
            "C:\\Program Files\\Microsoft Visual Studio\\2022\\Enterprise\\MSBuild\\Current\\Bin\\MSBuild.exe",
            "C:\\Program Files\\Microsoft Visual Studio\\2022\\BuildTools\\MSBuild\\Current\\Bin\\MSBuild.exe",
        ];
        for (p in commonPaths) {
            if (FileSystem.exists(p)) {
                Sys.println('  Found MSBuild: $p');
                return p;
            }
        }

        // Fallback to PATH
        Sys.println("  MSBuild: using PATH (run from Developer Command Prompt if this fails)");
        return "msbuild";
    }

    /**
     * Find nuget.exe — check common locations, then PATH.
     */
    static function findNuGet():String {
        // Check winget install location
        var home = Sys.getEnv("USERPROFILE");
        if (home == null) home = Sys.getEnv("HOME");
        if (home != null) {
            var wingetNuget = Path.join([home, "AppData", "Local", "Microsoft", "WinGet",
                "Packages", "Microsoft.NuGet_Microsoft.WinGet.Source_8wekyb3d8bbwe", "nuget.exe"]);
            if (FileSystem.exists(wingetNuget)) return wingetNuget;

            // Check winget links
            var wingetLink = Path.join([home, "AppData", "Local", "Microsoft", "WinGet", "Links", "nuget.exe"]);
            if (FileSystem.exists(wingetLink)) return wingetLink;
        }

        // Common paths
        var commonPaths = [
            "C:\\Program Files\\NuGet\\nuget.exe",
            "C:\\Program Files (x86)\\NuGet\\nuget.exe",
        ];
        for (p in commonPaths) {
            if (FileSystem.exists(p)) return p;
        }

        // Fallback to PATH
        return "nuget";
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
