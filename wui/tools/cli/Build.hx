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

        // Three defines make hxcpp produce something a WinUI project can link.
        // Each was found by a link error, in this order:
        //
        //  - `static_link`: emit `__lib__` instead of `__main__`, so there is no
        //    second `main` and `__hxcpp_lib_main()` exists to boot from. hxcpp
        //    then runs `lib.exe` itself and writes `lib<App>.lib`.
        //  - the architecture: hxcpp still defaults to 32-bit on Windows while
        //    the project builds for `arch`. The mismatch surfaces as an
        //    *unresolved* `wui_bridge_init`, not as an architecture error, since
        //    x86 decorates `extern "C"` symbols with a leading underscore.
        //  - `ABI=-MD`: hxcpp defaults to the static C runtime, WinUI uses the
        //    dynamic one, and the linker refuses to mix them (LNK2038).
        var archDefine = (arch == "x86") ? "HXCPP_M32" : "HXCPP_M64";
        var haxeResult = runCommand(cwd, "haxe", [
            "build.hxml", "-D", "static_link", "-D", archDefine, "-D", "ABI=-MD"
        ], verbose);
        if (haxeResult != 0) {
            Sys.println("Error: Haxe compilation failed.");
            Sys.exit(1);
        }

        // Step 1b: confirm hxcpp produced the library the project links against
        checkHaxeLibrary(cwd, wuiConfig.appName);

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
        Find an MSBuild.exe that can actually build this project, then fall back
        to PATH.

        **Newest is not the same as capable.** A WinUI 3 project needs the Appx
        MSBuild tasks, which ship with the IDE workloads but *not* with Build
        Tools. Picking the latest install can therefore land on one that fails
        mid-build with MSB4062 -- and because the exe is linked before the
        packaging targets run, that failure looks survivable while it has in fact
        skipped copying the Windows App SDK runtime next to the app, which then
        dies at startup. Prefer an install that has the tasks.
    **/
    static function findMSBuild():String {
        // Try vswhere first (standard location)
        var vswhere = "C:\\Program Files (x86)\\Microsoft Visual Studio\\Installer\\vswhere.exe";
        if (FileSystem.exists(vswhere)) {
            var process = new sys.io.Process(vswhere, [
                "-products", "*", "-sort",
                "-requires", "Microsoft.Component.MSBuild",
                "-find", "MSBuild\\**\\Bin\\MSBuild.exe"
            ]);
            var output = StringTools.trim(process.stdout.readAll().toString());
            var exitCode = process.exitCode();
            process.close();
            if (exitCode == 0 && output.length > 0) {
                var candidates = [];
                for (line in output.split("\n")) {
                    var p = StringTools.trim(line);
                    if (p.length > 0 && FileSystem.exists(p)) candidates.push(p);
                }
                for (p in candidates) {
                    if (hasAppxTasks(p)) {
                        Sys.println('  Found MSBuild: $p');
                        return p;
                    }
                }
                if (candidates.length > 0) {
                    Sys.println('  Found MSBuild: ${candidates[0]}');
                    Sys.println("  Warning: no Appx MSBuild tasks in this install; a WinUI build may fail with MSB4062.");
                    return candidates[0];
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
        Does this MSBuild ship the Appx packaging tasks a WinUI project needs?

        They live beside the binary, under `MSBuild\Microsoft\VisualStudio\v17.0`,
        so the answer is a file test rather than a guess about which edition or
        workload is installed.
    **/
    static function hasAppxTasks(msbuildExe:String):Bool {
        var dir = Path.directory(msbuildExe); // ...\MSBuild\Current\Bin
        var msbuildRoot = Path.directory(Path.directory(dir)); // ...\MSBuild
        var task = Path.join([
            msbuildRoot, "Microsoft", "VisualStudio", "v17.0",
            "AppxPackage", "Microsoft.Build.AppxPackage.dll"
        ]);
        return FileSystem.exists(task);
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

    /**
        Confirm hxcpp produced `build/cpp/lib<App>.lib`, which the generated
        project links against.

        **wui does not run the librarian itself.** Building with `-D static_link`
        makes hxcpp emit `__lib__` in place of `__main__` and archive its own
        objects with `lib.exe`, which gets the architecture, the C runtime and
        the object set right by construction. An earlier version packed the
        objects by hand and got all three wrong in turn.

        A missing library is not fatal here: the link will say so, with a better
        message than anything this step could invent.
    **/
    static function checkHaxeLibrary(cwd:String, appName:String):Void {
        if (Sys.systemName() != "Windows") {
            Sys.println("[1b/3] Skipping the Haxe library: needs MSVC (Windows only).");
            return;
        }

        var libPath = Path.join([cwd, "build", "cpp", "lib" + appName + ".lib"]);
        if (FileSystem.exists(libPath)) {
            var mb = Math.round(FileSystem.stat(libPath).size / 1024 / 1024 * 10) / 10;
            Sys.println('[1b/3] Haxe library ready: lib${appName}.lib (${mb} MB).');
        } else {
            Sys.println('[1b/3] Warning: lib${appName}.lib not found; the link step will report it.');
        }
    }
}
