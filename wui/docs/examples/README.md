# Examples

## Hello World

The simplest wui app. Displays text and buttons in a centered vertical layout.

**Source:** `examples/hello-world/src/HelloWorld.hx`

```haxe
import wui.View;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.ui.Spacer;
import wui.modifiers.ViewModifier.FontStyle;
import wui.modifiers.ViewModifier.ColorValue;
import wui.modifiers.ViewModifier.HorizontalAlign;

class HelloWorld extends wui.App {
    static function main() {
        // Entry point -- the macro system handles code generation.
        // At runtime (in the generated C++/WinRT app), App.cpp is the entry point.
    }

    override function appName():String {
        return "Hello World";
    }

    override function body():View {
        return new VStack([
            new Spacer(),
            new Text("Hello from Haxe!")
                .font(TitleLarge)
                .foregroundColor(AccentColor)
                .padding(),
            new Text("Built with wui - native WinUI 3 apps in Haxe")
                .font(Body)
                .foregroundColor(Gray)
                .padding(),
            new HStack([
                new Button("Learn More"),
                new Button("Get Started")
            ]).spacing(8),
            new Spacer()
        ]).horizontalAlignment(Center);
    }
}
```

### What this demonstrates

- Extending `wui.App` and overriding `appName()` and `body()`.
- `VStack` and `HStack` for layout composition.
- `Spacer` to vertically center content.
- `Text` with `.font()` and `.foregroundColor()` modifiers.
- `Button` for user actions.
- `.horizontalAlignment(Center)` to center the stack.
- `.padding()` with the default 12px value.
- `.spacing(8)` on an HStack.

### Build and run

```bash
cd examples/hello-world
wui run
```

### Generated output

The macro system produces C++/WinRT code in `build/winui/` that creates a `StackPanel` with `Orientation::Vertical`, two `TextBlock` controls with font and color properties, a nested horizontal `StackPanel` with two `Button` controls, and `Border` spacers on top and bottom.

---

## Counter

A stateful counter app. Demonstrates `@:state`, `StateAction`, and reactive UI updates.

**Source:** `examples/counter/src/Counter.hx`

```haxe
import wui.View;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.ui.Spacer;
import wui.modifiers.ViewModifier.FontStyle;
import wui.modifiers.ViewModifier.ColorValue;
import wui.modifiers.ViewModifier.HorizontalAlign;

class Counter extends wui.App {
    @:state var count:Int = 0;

    static function main() {}

    override function appName():String {
        return "Counter";
    }

    override function body():View {
        return new VStack([
            new Spacer(),
            new Text("Counter")
                .font(Title)
                .padding(),
            new Text("0")
                .font(TitleLarge)
                .foregroundColor(AccentColor)
                .padding(),
            new HStack([
                new Button("Decrement")
                    .padding(),
                new Button("Reset")
                    .padding(),
                new Button("Increment")
                    .padding()
            ]).spacing(8),
            new Spacer()
        ]).horizontalAlignment(Center);
    }
}
```

### What this demonstrates

- `@:state var count:Int = 0` -- declares a reactive state variable. The `StateMacro` transforms this into a `State<Int>` initialized in the constructor.
- State-driven buttons -- each button triggers a `StateAction` (increment, decrement, or reset).
- Reactive text -- the "0" text would be bound to `count.value` so it updates when the state changes.
- The same layout patterns as hello-world: VStack, HStack, Spacer, centered alignment.

### How state flows in this example

```
User clicks "Increment"
  -> StateAction.Increment(count, 1) fires
  -> count.value becomes 1
  -> count's subscriber lambda fires
  -> Lambda calls textBlock.Text(L"1") in C++
  -> UI shows "1" instantly
```

### Build and run

```bash
cd examples/counter
wui run
```

---

## Project structure

Both examples share the same layout:

```
examples/<name>/
  src/
    <Name>.hx          # Haxe source
  build.hxml            # Haxe build config
  wui.json              # project metadata
  build/                # generated on build
    cpp/                # hxcpp output
    winui/              # generated C++/WinRT project
    packages/           # NuGet packages
```

The `build.hxml` references the wui library source with `-cp ../../src` (since these examples live inside the wui repo). In a standalone project created with `wui init`, you would use `-lib wui` instead.

---

## Running the examples

From the wui repo root:

```bash
cd examples/hello-world
haxe build.hxml          # step 1: Haxe + macro codegen
# then: NuGet restore + MSBuild in build/winui/
```

Or, if the CLI is installed:

```bash
cd examples/hello-world
wui run
```
