package tools.cli;

import sys.FileSystem;
import haxe.io.Path;

class Clean {
    public static function run(cwd:String, args:Array<String>) {
        var buildDir = Path.join([cwd, "build"]);
        if (FileSystem.exists(buildDir)) {
            Sys.println("Removing build/ directory...");
            removeDir(buildDir);
            Sys.println("Clean complete.");
        } else {
            Sys.println("Nothing to clean.");
        }
    }

    static function removeDir(path:String) {
        if (FileSystem.isDirectory(path)) {
            for (entry in FileSystem.readDirectory(path)) {
                removeDir(Path.join([path, entry]));
            }
            FileSystem.deleteDirectory(path);
        } else {
            FileSystem.deleteFile(path);
        }
    }
}
