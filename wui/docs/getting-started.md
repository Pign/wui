# Getting Started with wui

wui lets you write native WinUI 3 desktop apps in Haxe. You describe your UI with a declarative view tree, and wui's macro system compiles it to C++/WinRT code that MSBuild turns into a native `.exe`.

## Prerequisites

| Tool | Version | Why |
|------|---------|-----|
| **Haxe** | 4.x+ | Language compiler |
| **hxcpp** | latest | Haxe-to-C++ target (install via `haxelib install hxcpp`) |
| **Visual Studio 2022** | 17.x+ | With the **"Desktop development with C++"** workload and **Windows App SDK C++ Templates** component |
| **NuGet CLI** | 6.x+ | Package restore for Windows App SDK, CppWinRT, and SDK Build Tools |
| **Windows 10/11** | 10.0.22621+ | Target OS |

### Install Haxe and hxcpp

```bash
# Install Haxe from https://haxe.org/download/
haxelib install hxcpp
haxelib install wui
```

### Visual Studio workload

Open the Visual Studio Installer and make sure **Desktop development with C++** is checked. Under **Individual components**, also enable:

- MSVC v143 (or later) C++ build tools
- Windows App SDK C++ Templates
- Windows 10/11 SDK (10.0.22621.0 or later)

### NuGet CLI

Download `nuget.exe` from https://www.nuget.org/downloads and place it on your `PATH`. Verify:

```bash
nuget --version
```

## Create a project

```bash
wui init MyApp
cd MyApp
```

This scaffolds:

```
MyApp/
  src/
    MyApp.hx       # your app
  build.hxml        # Haxe build config
  wui.json          # project metadata
```

## The generated source

```haxe
import wui.App;
import wui.View;
import wui.ui.VStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.ui.Spacer;

class MyApp extends wui.App {
    override function appName():String {
        return "MyApp";
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
```

Every wui app extends `wui.App` and overrides two methods:

- `appName()` -- sets the window title.
- `body()` -- returns the root view tree.

## Build

```bash
wui build
```

This runs four steps:

1. Haxe compilation (Haxe source -> hxcpp C++)
2. hxcpp static library build
3. NuGet package restore (Windows App SDK, CppWinRT, SDK Build Tools)
4. MSBuild (C++/WinRT project -> native `.exe`)

The output lands in `build/winui/Debug/MyApp.exe`.

## Run

```bash
wui run
```

Builds if needed, then launches the `.exe`. Your WinUI 3 window appears.

## Release build

```bash
wui build --release
wui run --release
```

Produces an optimized binary at `build/winui/Release/MyApp.exe`.

## Minimal hello-world

The smallest possible wui app:

```haxe
import wui.View;
import wui.ui.Text;

class Hello extends wui.App {
    override function appName():String return "Hello";

    override function body():View {
        return new Text("Hello, WinUI 3!");
    }
}
```

Build and run:

```bash
wui build
wui run
```

A native Windows desktop window appears with the text "Hello, WinUI 3!" rendered by a WinUI `TextBlock`.

## Next steps

- [Views](views/README.md) -- all available UI components
- [Modifiers](modifiers.md) -- styling, layout, and interaction modifiers
- [State](state/README.md) -- reactive state management
- [CLI reference](cli.md) -- all commands and options
- [Architecture](architecture.md) -- how the compilation pipeline works
