package wui;

import wui.modifiers.ViewModifier;

/**
 * Base class for all WUI view elements.
 * Views form a tree structure and carry modifier chains
 * that are translated to C++/WinRT properties during code generation.
 */
class View {
    public var viewType:String;
    public var children:Array<View>;
    public var modifierChain:Array<ViewModifier>;
    public var properties:Map<String, Dynamic>;

    public function new(?viewType:String, ?children:Array<View>) {
        this.viewType = viewType != null ? viewType : "View";
        this.children = children != null ? children : [];
        this.modifierChain = [];
        this.properties = new Map();
    }

    /**
     * Override hook for user-defined View components — the macro
     * pipeline calls `WinUIGenerator.inlineUserBody` when it sees
     * `new MyComponent(...)` for any class extending `View` that
     * overrides `body()`. The override's expression is inlined into
     * the surrounding View tree at compile time, so this method
     * never runs at runtime; returning `this` here is a safe
     * placeholder.
     *
     * Constraints (enforced by the macro, not by the type system):
     *  - The constructor must assign each param to a same-named
     *    field with a plain `this.field = param` statement so the
     *    inliner can substitute.
     *  - `body()` must return a View expression composed of WUI
     *    primitives or other user components. References to
     *    `this.<field>` resolve to the corresponding constructor
     *    argument.
     */
    public function body():View {
        return this;
    }

    // --- Layout Modifiers ---

    public function padding(?amount:Float):View {
        modifierChain.push(Padding(amount != null ? amount : 12.0));
        return this;
    }

    public function margin(?amount:Float):View {
        modifierChain.push(Margin(amount != null ? amount : 12.0));
        return this;
    }

    public function frame(?width:Float, ?height:Float, ?minWidth:Float, ?maxWidth:Float, ?minHeight:Float, ?maxHeight:Float):View {
        modifierChain.push(Frame(width, height, minWidth, maxWidth, minHeight, maxHeight));
        return this;
    }

    public function width(w:Float):View {
        modifierChain.push(Width(w));
        return this;
    }

    public function height(h:Float):View {
        modifierChain.push(Height(h));
        return this;
    }

    public function horizontalAlignment(align:HorizontalAlign):View {
        modifierChain.push(HorizontalAlignment(align));
        return this;
    }

    public function verticalAlignment(align:VerticalAlign):View {
        modifierChain.push(VerticalAlignment(align));
        return this;
    }

    public function spacing(s:Float):View {
        modifierChain.push(Spacing(s));
        return this;
    }

    // --- Typography Modifiers ---

    public function font(style:FontStyle):View {
        modifierChain.push(Font(style));
        return this;
    }

    public function fontSize(size:Float):View {
        modifierChain.push(FontSize(size));
        return this;
    }

    public function bold():View {
        modifierChain.push(Bold);
        return this;
    }

    public function italic():View {
        modifierChain.push(Italic);
        return this;
    }

    // --- Color Modifiers ---

    public function foregroundColor(color:ColorValue):View {
        modifierChain.push(ForegroundColor(color));
        return this;
    }

    public function background(color:ColorValue):View {
        modifierChain.push(Background(color));
        return this;
    }

    public function opacity(value:Float):View {
        modifierChain.push(Opacity(value));
        return this;
    }

    // --- Shape Modifiers ---

    public function cornerRadius(radius:Float):View {
        modifierChain.push(CornerRadius(radius));
        return this;
    }

    public function borderBrush(color:ColorValue):View {
        modifierChain.push(BorderBrush(color));
        return this;
    }

    public function borderThickness(thickness:Float):View {
        modifierChain.push(BorderThickness(thickness));
        return this;
    }

    // --- Interaction Modifiers ---

    public function disabled(isDisabled:Bool = true):View {
        modifierChain.push(Disabled(isDisabled));
        return this;
    }

    public function visible(isVisible:Bool = true):View {
        modifierChain.push(Visible(isVisible));
        return this;
    }

    public function toolTip(text:String):View {
        modifierChain.push(ToolTip(text));
        return this;
    }

    // --- Interaction Modifiers ---

    /**
     * Tap handler — fires the closure when the user clicks or taps
     * anywhere inside the view's bounds. Works uniformly on primitives
     * and user components ; the macro pipeline emits a `Tapped` event
     * on the resulting C++ control during `applyModifiers`.
     *
     * `StateAction` is `() -> Void` — pass a closure or a static fn ref :
     *
     *     new MyComponent(...)
     *         .onTap(() -> selectedIdx.value = 3)
     *         .onTap(() -> isExpanded.value = !isExpanded.value)
     *         .onTap(MyApp.handleRowTap)
     *
     * Inside a `ForEach` row, the closure can capture the lambda's
     * `idx`, `item.<field>` accesses, and locals declared earlier in
     * the row lambda body — all handled at runtime by hxcpp closures
     * (see the row tap builder in the WUI macro).
     */
    public function onTap(action:wui.state.StateAction):View {
        modifierChain.push(OnTap(action));
        return this;
    }

    // --- Lifecycle Modifiers ---

    public function onLoaded(callback:() -> Void):View {
        modifierChain.push(OnLoaded(callback));
        return this;
    }
}
