# wui

Build **native WinUI 3 Windows apps in Haxe**. Your code compiles to C++ through
hxcpp, MSBuild links it against the Windows App SDK, and what ships is a genuine
desktop application.

```haxe
import wui.View;
import wui.ui.*;

class Counter extends wui.App {
    @:state var count:Int = 0;

    override function appName():String return "Counter";

    override function body():View {
        var display = new Text("Count: " + count);
        display.font = "TitleLarge";
        display.padding = 12;

        var minus = new Button("-", null, count_.dec(1));
        var plus = new Button("+", null, count_.inc(1));

        return new VStack([display, new HStack([minus, plus])]);
    }
}
```

Abridged from `examples/counter`.

## How it runs

`body()` runs on the device and produces a view tree; a push renderer walks it
and patches the WinUI elements that changed. A state write reaches the elements
that display it and nothing else.

## Getting started

```bash
haxelib git wui https://github.com/lapavoiserie/wui
haxelib run wui init MyApp
cd MyApp && haxelib run wui run
```

Needs Haxe 4.3+, hxcpp, Visual Studio 2022 with the C++ desktop workload, and
NuGet on the path.

## The build has two halves, and it matters

hxcpp **compiles** but does not link: it packs its objects into `lib<App>.lib`
and stops, because the `main` WinUI provides would clash with hxcpp's. MSBuild
performs the only link there is.

That is why a [`kui`](https://lapavoiserie.github.io/kui/) capability reaching
Windows through `wui` puts anything that must be *linked* in its `msbuild`
payload — a `libs` entry addressed to hxcpp would reach a step that never runs.
`wui` renders that payload into the generated `.vcxproj` and `packages.config`.

## Part of La Pavoiserie

`wui` is one backend of [`mui`](https://lapavoiserie.github.io/mui/), which gives
an application one view vocabulary across six of them —
[`sui`](https://github.com/lapavoiserie/sui) for Apple platforms,
[`aui`](https://github.com/lapavoiserie/aui) for Android,
[`cui`](https://github.com/lapavoiserie/cui) for the terminal, and others. The
same `body()` runs on all of them.

## Documentation

<https://lapavoiserie.github.io/wui/>

## Licence

MIT.
