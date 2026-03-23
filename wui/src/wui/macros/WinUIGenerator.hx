package wui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Type;
import haxe.macro.Expr;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.UIBuilder.ModifierData;

using haxe.macro.Tools;
#end

/**
 * Main code generation orchestrator. Registered as a macro in build.hxml:
 *   --macro wui.macros.WinUIGenerator.register()
 *
 * After Haxe compilation completes, this macro:
 * 1. Finds all App subclasses
 * 2. Analyzes their body() method to build a ViewNode tree
 * 3. Calls ProjectGenerator to emit .vcxproj, packages.config, pch.h
 * 4. Calls BridgeGenerator to emit App.h/cpp, WuiRuntime.h
 * 5. Calls UIBuilder to emit MainWindow.h/cpp with imperative C++/WinRT code
 */
class WinUIGenerator {
    #if macro
    static var registered:Bool = false;
    static var collectedTypes:Array<Type> = [];

    /**
     * Call this from build.hxml:
     *   --macro wui.macros.WinUIGenerator.register()
     */
    public static function register():Void {
        if (registered) return;
        registered = true;

        // Collect types after typing phase
        Context.onAfterTyping(function(types:Array<haxe.macro.Type.ModuleType>) {
            for (mt in types) {
                switch (mt) {
                    case TClassDecl(ref):
                        var cls = ref.get();
                        if (isAppSubclass(cls)) {
                            collectedTypes.push(TInst(ref, []));
                        }
                    default:
                }
            }
        });

        // Generate after all compilation is done
        Context.onAfterGenerate(function() {
            generate();
        });
    }

    static function generate():Void {
        // Find the output directory from compiler config
        var cppOutput = Compiler.getOutput();
        if (cppOutput == null) cppOutput = "build/cpp";

        var buildDir = Path.directory(cppOutput);
        if (buildDir == "") buildDir = ".";
        var winuiDir = Path.join([buildDir, "winui"]);

        if (!FileSystem.exists(winuiDir)) {
            FileSystem.createDirectory(winuiDir);
        }

        if (collectedTypes.length == 0) {
            Context.warning("wui: No App subclass found. Create a class extending wui.App.", Context.currentPos());
            return;
        }

        // Use the first App subclass found
        var appType = collectedTypes[0];
        var appName = getAppName(appType);
        var windowWidth = getWindowWidth(appType);
        var windowHeight = getWindowHeight(appType);

        // Collect @:state fields
        UIBuilder.stateFields = collectStateFields(appType);

        // Build the view tree from body()
        var viewTree = buildViewTree(appType);

        // Generate all files
        Sys.println('[wui] Generating C++/WinRT project for "$appName"...');

        ProjectGenerator.generate(appName, winuiDir);
        Sys.println("[wui]   Generated .vcxproj, packages.config, pch.h");

        BridgeGenerator.generate(appName, winuiDir, windowWidth, windowHeight);
        Sys.println("[wui]   Generated App.h, App.cpp, WuiRuntime.h");

        UIBuilder.generateMainWindow(viewTree, winuiDir);
        Sys.println("[wui]   Generated MainWindow.h, MainWindow.cpp");

        Sys.println('[wui] C++/WinRT project generated at: $winuiDir');
    }

    /**
     * Collect @:state fields from the App subclass.
     */
    static function collectStateFields(type:Type):Array<{name:String, type:String, initial:String}> {
        var result:Array<{name:String, type:String, initial:String}> = [];
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    // Check if the field is a State<T> type
                    switch (field.type) {
                        case TInst(tref, params):
                            var typeName = tref.get().name;
                            if (typeName == "State" && params.length > 0) {
                                var cppType = "int"; // default
                                var initial = "0";
                                switch (params[0]) {
                                    case TAbstract(aref, _):
                                        var aname = aref.get().name;
                                        if (aname == "Int") { cppType = "int"; initial = "0"; }
                                        else if (aname == "Float") { cppType = "double"; initial = "0.0"; }
                                        else if (aname == "Bool") { cppType = "bool"; initial = "false"; }
                                    case TInst(sref, _):
                                        if (sref.get().name == "String") { cppType = "std::wstring"; initial = 'L""'; }
                                    default:
                                }
                                result.push({ name: field.name, type: cppType, initial: initial });
                            }
                        default:
                    }
                }
            default:
        }
        return result;
    }

    static function isAppSubclass(cls:ClassType):Bool {
        if (cls.superClass == null) return false;
        var superRef = cls.superClass.t.get();
        if (superRef.pack.join(".") == "wui" && superRef.name == "App") return true;
        return isAppSubclass(superRef);
    }

    /**
     * Extract the app name from the appName() method or class name.
     */
    static function getAppName(type:Type):String {
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    if (field.name == "appName") {
                        switch (field.type) {
                            case TFun(_, ret):
                                if (field.expr() != null) {
                                    var str = extractStringReturn(field.expr());
                                    if (str != null) return str;
                                }
                            default:
                        }
                    }
                }
                return cls.name;
            default:
                return "WuiApp";
        }
    }

    static function getWindowWidth(type:Type):Int {
        return getIntField(type, "windowWidth", 800);
    }

    static function getWindowHeight(type:Type):Int {
        return getIntField(type, "windowHeight", 600);
    }

    static function getIntField(type:Type, fieldName:String, defaultVal:Int):Int {
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    if (field.name == fieldName) {
                        if (field.expr() != null) {
                            var val = extractIntValue(field.expr());
                            if (val != null) return val;
                        }
                    }
                }
            default:
        }
        return defaultVal;
    }

    /**
     * Build a ViewNode tree by analyzing the body() method's AST.
     */
    static function buildViewTree(type:Type):ViewNode {
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    if (field.name == "body") {
                        if (field.expr() != null) {
                            return analyzeBodyExpr(field.expr());
                        }
                    }
                }
            default:
        }

        // Default empty view
        var defaultProps:Map<String, Dynamic> = new Map();
        defaultProps.set("orientation", "Vertical");
        var textProps:Map<String, Dynamic> = new Map();
        textProps.set("text", "Hello from WUI!");
        return {
            viewType: "StackPanel",
            children: [{
                viewType: "TextBlock",
                children: [],
                modifiers: [],
                properties: textProps
            }],
            modifiers: [],
            properties: defaultProps
        };
    }

    /**
     * Analyze a typed expression to build a ViewNode tree.
     */
    // Map of local variable names to their expressions (for temp var resolution)
    static var localExprs:Map<String, TypedExpr> = new Map();

    static function analyzeBodyExpr(texpr:TypedExpr):ViewNode {
        if (texpr == null) {
            return defaultNode();
        }

        switch (texpr.expr) {
            case TReturn(e):
                if (e != null) return analyzeBodyExpr(e);

            case TBlock(exprs):
                // First pass: collect all local variable bindings
                for (expr in exprs) {
                    switch (expr.expr) {
                        case TVar(v, e):
                            if (e != null) localExprs.set(v.name, e);
                        default:
                    }
                }
                // Second pass: find the return or last expression
                for (expr in exprs) {
                    switch (expr.expr) {
                        case TReturn(e):
                            if (e != null) return analyzeBodyExpr(e);
                        default:
                    }
                }
                if (exprs.length > 0) {
                    return analyzeBodyExpr(exprs[exprs.length - 1]);
                }

            case TNew(cls, _, args):
                return analyzeNewExpr(cls.get(), args);

            case TCall(func, args):
                return analyzeCallExpr(func, args, texpr);

            case TParenthesis(e):
                return analyzeBodyExpr(e);

            case TFunction(tfunc):
                if (tfunc.expr != null) return analyzeBodyExpr(tfunc.expr);

            case TCast(e, _):
                return analyzeBodyExpr(e);

            case TLocal(v):
                // Resolve temp variables to their original expressions
                var resolved = localExprs.get(v.name);
                if (resolved != null) return analyzeBodyExpr(resolved);

            case TVar(v, e):
                if (e != null) {
                    localExprs.set(v.name, e);
                    return analyzeBodyExpr(e);
                }

            default:
                // Unhandled expression types are silently ignored
        }

        return defaultNode();
    }

    /**
     * Analyze a `new ClassName(args)` expression.
     */
    static function analyzeNewExpr(cls:ClassType, args:Array<TypedExpr>):ViewNode {
        var fullName = cls.pack.join(".") + (cls.pack.length > 0 ? "." : "") + cls.name;

        return switch (fullName) {
            case "wui.ui.VStack":
                var children = args.length > 0 ? extractChildArray(args[0]) : [];
                var spacing = args.length > 1 ? extractFloatValue(args[1]) : null;
                var props:Map<String, Dynamic> = new Map();
                props.set("orientation", "Vertical");
                if (spacing != null) props.set("spacing", spacing);
                { viewType: "StackPanel", children: children, modifiers: [], properties: props };

            case "wui.ui.HStack":
                var children = args.length > 0 ? extractChildArray(args[0]) : [];
                var spacing = args.length > 1 ? extractFloatValue(args[1]) : null;
                var props:Map<String, Dynamic> = new Map();
                props.set("orientation", "Horizontal");
                if (spacing != null) props.set("spacing", spacing);
                { viewType: "StackPanel", children: children, modifiers: [], properties: props };

            case "wui.ui.ZStack":
                var children = args.length > 0 ? extractChildArray(args[0]) : [];
                { viewType: "Grid", children: children, modifiers: [], properties: new Map() };

            case "wui.ui.Text":
                var props:Map<String, Dynamic> = new Map();
                // Check for state-bound text (e.g., "Count: " + count)
                var textArg = args.length > 0 ? args[0] : null;
                // Resolve local variable if needed
                if (textArg != null) {
                    switch (textArg.expr) {
                        case TLocal(v):
                            var resolved = localExprs.get(v.name);
                            if (resolved != null) textArg = resolved;
                        default:
                    }
                }
                var bound = textArg != null ? extractStateBoundText(textArg) : null;
                if (bound != null) {
                    props.set("text", bound.text);
                    props.set("boundState", bound.boundState);
                    props.set("boundFormat", bound.format);
                } else {
                    var text = args.length > 0 ? extractStringOrExpr(args[0]) : "Text";
                    props.set("text", text);
                }
                { viewType: "TextBlock", children: [], modifiers: [], properties: props };

            case "wui.ui.Button":
                var label = args.length > 0 ? extractStringOrExpr(args[0]) : "Button";
                var props:Map<String, Dynamic> = new Map();
                props.set("label", label);
                // args[1] = icon (optional), args[2] = action (StateAction)
                if (args.length > 2) {
                    var actionCode = extractStateAction(args[2]);
                    if (actionCode != null) {
                        props.set("onClick", actionCode);
                    }
                }
                { viewType: "Button", children: [], modifiers: [], properties: props };

            case "wui.ui.Spacer":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var minSize = extractFloatValue(args[0]);
                    if (minSize != null) props.set("minSize", minSize);
                }
                { viewType: "Spacer", children: [], modifiers: [], properties: props };

            case "wui.ui.TextBox":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var placeholder = extractStringOrExpr(args[0]);
                    if (placeholder != null) props.set("placeholder", placeholder);
                }
                { viewType: "TextBox", children: [], modifiers: [], properties: props };

            case "wui.ui.ToggleSwitch":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var label = extractStringOrExpr(args[0]);
                    if (label != null) props.set("label", label);
                }
                { viewType: "ToggleSwitch", children: [], modifiers: [], properties: props };

            case "wui.ui.CheckBox":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var label = extractStringOrExpr(args[0]);
                    if (label != null) props.set("label", label);
                }
                { viewType: "CheckBox", children: [], modifiers: [], properties: props };

            case "wui.ui.Slider":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) props.set("min", extractFloatValue(args[0]));
                if (args.length > 1) props.set("max", extractFloatValue(args[1]));
                { viewType: "Slider", children: [], modifiers: [], properties: props };

            case "wui.ui.Image":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) props.set("source", extractStringOrExpr(args[0]));
                { viewType: "Image", children: [], modifiers: [], properties: props };

            case "wui.ui.ScrollViewer":
                var children = args.length > 0 ? [analyzeBodyExpr(args[0])] : [];
                { viewType: "ScrollViewer", children: children, modifiers: [], properties: new Map() };

            case "wui.ui.ProgressRing":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    props.set("value", extractFloatValue(args[0]));
                    props.set("isIndeterminate", "false");
                } else {
                    props.set("isIndeterminate", "true");
                }
                { viewType: "ProgressRing", children: [], modifiers: [], properties: props };

            default:
                defaultNode();
        };
    }

    /**
     * Analyze a method call — could be a modifier chain.
     */
    static function analyzeCallExpr(func:TypedExpr, args:Array<TypedExpr>, fullExpr:TypedExpr):ViewNode {
        switch (func.expr) {
            case TField(obj, fa):
                var fieldName = switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FStatic(_, cf): cf.get().name;
                    case FAnon(cf): cf.get().name;
                    case FDynamic(s): s;
                    case FClosure(_, cf): cf.get().name;
                    case FEnum(_, ef): ef.name;
                };

                var baseNode = analyzeBodyExpr(obj);

                var modifier = extractModifier(fieldName, args);
                if (modifier != null) {
                    baseNode.modifiers.push(modifier);
                }

                return baseNode;
            default:
        }

        return defaultNode();
    }

    /**
     * Extract a modifier from a method name and arguments.
     */
    static function extractModifier(name:String, args:Array<TypedExpr>):ModifierData {
        return switch (name) {
            case "padding":
                var amount = args.length > 0 ? extractFloatValue(args[0]) : null;
                { type: "Padding", values: [amount != null ? amount : 12.0] };
            case "margin":
                var amount = args.length > 0 ? extractFloatValue(args[0]) : null;
                { type: "Margin", values: [amount != null ? amount : 12.0] };
            case "font":
                var style = args.length > 0 ? extractEnumName(args[0]) : "Body";
                { type: "Font", values: [style] };
            case "fontSize":
                var size = args.length > 0 ? extractFloatValue(args[0]) : 14.0;
                { type: "FontSize", values: [size] };
            case "bold":
                { type: "Bold", values: [] };
            case "italic":
                { type: "Italic", values: [] };
            case "foregroundColor":
                var color = args.length > 0 ? extractEnumName(args[0]) : "Black";
                { type: "ForegroundColor", values: [color] };
            case "background":
                var color = args.length > 0 ? extractEnumName(args[0]) : "White";
                { type: "Background", values: [color] };
            case "opacity":
                var value = args.length > 0 ? extractFloatValue(args[0]) : 1.0;
                { type: "Opacity", values: [value] };
            case "width":
                var w = args.length > 0 ? extractFloatValue(args[0]) : 0.0;
                { type: "Width", values: [w] };
            case "height":
                var h = args.length > 0 ? extractFloatValue(args[0]) : 0.0;
                { type: "Height", values: [h] };
            case "cornerRadius":
                var r = args.length > 0 ? extractFloatValue(args[0]) : 0.0;
                { type: "CornerRadius", values: [r] };
            case "horizontalAlignment":
                var align = args.length > 0 ? extractEnumName(args[0]) : "Stretch";
                { type: "HorizontalAlignment", values: [align] };
            case "verticalAlignment":
                var align = args.length > 0 ? extractEnumName(args[0]) : "Stretch";
                { type: "VerticalAlignment", values: [align] };
            case "spacing":
                var s = args.length > 0 ? extractFloatValue(args[0]) : 8.0;
                { type: "Spacing", values: [s] };
            case "disabled":
                var d = args.length > 0 ? extractBoolValue(args[0]) : true;
                { type: "Disabled", values: [d] };
            case "visible":
                var v = args.length > 0 ? extractBoolValue(args[0]) : true;
                { type: "Visible", values: [v] };
            case "toolTip":
                var text = args.length > 0 ? extractStringOrExpr(args[0]) : "";
                { type: "ToolTip", values: [text] };
            case "borderBrush":
                var color = args.length > 0 ? extractEnumName(args[0]) : "Gray";
                { type: "BorderBrush", values: [color] };
            case "borderThickness":
                var t = args.length > 0 ? extractFloatValue(args[0]) : 1.0;
                { type: "BorderThickness", values: [t] };
            case "frame":
                var vals:Array<Dynamic> = [];
                for (i in 0...6) {
                    vals.push(i < args.length ? extractFloatValue(args[i]) : null);
                }
                { type: "Frame", values: vals };
            default:
                null;
        };
    }

    // ---- Value Extraction Helpers ----

    static function extractChildArray(expr:TypedExpr):Array<ViewNode> {
        if (expr == null) return [];
        switch (expr.expr) {
            case TArrayDecl(exprs):
                return [for (e in exprs) analyzeBodyExpr(e)];
            default:
                return [analyzeBodyExpr(expr)];
        }
    }

    static function extractStringOrExpr(expr:TypedExpr):String {
        if (expr == null) return null;
        switch (expr.expr) {
            case TConst(TString(s)):
                return s;
            case TConst(TInt(i)):
                return Std.string(i);
            case TConst(TFloat(s)):
                return s;
            default:
                return "...";
        }
    }

    static function extractStringReturn(texpr:TypedExpr):String {
        if (texpr == null) return null;
        switch (texpr.expr) {
            case TReturn(e):
                return extractStringOrExpr(e);
            case TBlock(exprs):
                for (e in exprs) {
                    var s = extractStringReturn(e);
                    if (s != null) return s;
                }
            case TConst(TString(s)):
                return s;
            default:
        }
        return null;
    }

    static function extractFloatValue(expr:TypedExpr):Null<Float> {
        if (expr == null) return null;
        switch (expr.expr) {
            case TConst(TFloat(s)):
                return Std.parseFloat(s);
            case TConst(TInt(i)):
                return i * 1.0;
            default:
                return null;
        }
    }

    static function extractIntValue(expr:TypedExpr):Null<Int> {
        if (expr == null) return null;
        switch (expr.expr) {
            case TConst(TInt(i)):
                return i;
            case TConst(TFloat(s)):
                return Std.parseInt(s);
            default:
                return null;
        }
    }

    static function extractBoolValue(expr:TypedExpr):Bool {
        if (expr == null) return true;
        switch (expr.expr) {
            case TConst(TBool(b)):
                return b;
            default:
                return true;
        }
    }

    static function extractEnumName(expr:TypedExpr):String {
        if (expr == null) return "";
        switch (expr.expr) {
            case TField(_, fa):
                return switch (fa) {
                    case FEnum(_, ef): ef.name;
                    case FStatic(_, cf): cf.get().name;
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: "";
                };
            case TConst(TString(s)):
                return s;
            default:
                return "";
        }
    }

    /**
     * Check if an expression references a @:state field.
     * Returns the field name if it does, null otherwise.
     */
    static function extractStateFieldRef(expr:TypedExpr):String {
        if (expr == null) return null;
        switch (expr.expr) {
            case TField(obj, fa):
                // state.value access — check if obj is a state field
                var fieldName = switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: null;
                };
                if (fieldName == "value") return extractStateFieldRef(obj);
                return null;

            case TLocal(v):
                // Check if this local is a known state field
                var resolved = localExprs.get(v.name);
                if (resolved != null) return extractStateFieldRef(resolved);
                // Check against state fields
                for (sf in UIBuilder.stateFields) {
                    if (v.name == sf.name) return sf.name;
                }
                return null;

            case TField(_, fa):
                var name = switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: null;
                };
                // Direct field reference like this.count
                if (name != null) {
                    for (sf in UIBuilder.stateFields) {
                        if (name == sf.name) return sf.name;
                    }
                }
                return null;
            default:
                return null;
        }
    }

    /**
     * Try to extract a state action from a typed expression.
     * Detects patterns like: count.inc(1), count.dec(1), count.setTo(0), count.tog()
     * Returns a C++ code string or null.
     */
    static function extractStateAction(expr:TypedExpr):String {
        if (expr == null) return null;

        // Resolve local variables
        switch (expr.expr) {
            case TLocal(v):
                var resolved = localExprs.get(v.name);
                if (resolved != null) return extractStateAction(resolved);
            default:
        }

        switch (expr.expr) {
            case TCall(func, args):
                switch (func.expr) {
                    case TField(obj, fa):
                        var methodName = switch (fa) {
                            case FInstance(_, _, cf): cf.get().name;
                            case FDynamic(s): s;
                            default: null;
                        };

                        // obj should be a state field
                        var stateName = extractStateFieldRef(obj);
                        if (stateName == null) return null;

                        var amount = args.length > 0 ? extractFloatValue(args[0]) : null;
                        var amountStr = amount != null ? Std.string(Std.int(amount)) : "1";

                        return switch (methodName) {
                            case "inc": 's_$stateName += $amountStr; notify_$stateName();';
                            case "dec": 's_$stateName -= $amountStr; notify_$stateName();';
                            case "setTo":
                                var val = amount != null ? Std.string(Std.int(amount)) : "0";
                                's_$stateName = $val; notify_$stateName();';
                            case "tog": 's_$stateName = !s_$stateName; notify_$stateName();';
                            default: null;
                        };
                    default:
                }
            default:
        }
        return null;
    }

    /**
     * Analyze a Text argument for state-bound expressions.
     * Detects: "prefix" + stateField patterns.
     * Returns {text, boundState, format} or null if not state-bound.
     */
    /**
     * Recursively search an expression for a state field reference,
     * unwrapping calls like .toString(), Std.string(), etc.
     */
    static function deepExtractStateRef(expr:TypedExpr):String {
        if (expr == null) return null;

        // Direct state ref
        var direct = extractStateFieldRef(expr);
        if (direct != null) return direct;

        switch (expr.expr) {
            case TLocal(v):
                // Check if local name matches a state field
                for (sf in UIBuilder.stateFields) {
                    if (v.name == sf.name) return sf.name;
                }
                var resolved = localExprs.get(v.name);
                if (resolved != null) return deepExtractStateRef(resolved);
            case TCall(func, args):
                // Unwrap: Std.string(count), count.toString(), etc.
                for (arg in args) {
                    var found = deepExtractStateRef(arg);
                    if (found != null) return found;
                }
                // Check the function target too (for count.toString())
                switch (func.expr) {
                    case TField(obj, _):
                        return deepExtractStateRef(obj);
                    default:
                }
            case TField(obj, fa):
                // Check field name against state fields
                var fName = switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: null;
                };
                if (fName != null) {
                    for (sf in UIBuilder.stateFields) {
                        if (fName == sf.name) return sf.name;
                    }
                }
                return deepExtractStateRef(obj);
            default:
        }
        return null;
    }

    static function extractStateBoundText(expr:TypedExpr):{text:String, boundState:String, format:String} {
        if (expr == null) return null;

        // Resolve locals
        switch (expr.expr) {
            case TLocal(v):
                var resolved = localExprs.get(v.name);
                if (resolved != null) return extractStateBoundText(resolved);
            default:
        }

        switch (expr.expr) {
            case TBinop(op, e1, e2):
                var opName = Std.string(op);
                if (opName == "OpAdd") {
                    var prefix = extractStringOrExpr(e1);
                    // Deep search for state ref in e2 (may be wrapped in toString/Std.string)
                    var stateRef = deepExtractStateRef(e2);
                    if (prefix != null && prefix != "..." && stateRef != null) {
                        var escaped = UIBuilder.escapeWideString(prefix);
                        return {
                            text: prefix + "0",
                            boundState: stateRef,
                            format: 'CTRL.Text(winrt::hstring(L"$escaped" + std::to_wstring(s_$stateRef)));'
                        };
                    }
                    // count + "suffix"
                    var stateRef1 = deepExtractStateRef(e1);
                    var suffix = extractStringOrExpr(e2);
                    if (stateRef1 != null && suffix != null && suffix != "...") {
                        var escaped = UIBuilder.escapeWideString(suffix);
                        return {
                            text: "0" + suffix,
                            boundState: stateRef1,
                            format: 'CTRL.Text(winrt::hstring(std::to_wstring(s_$stateRef1) + L"$escaped"));'
                        };
                    }
                }
            default:
                // Check if the expression itself is a state reference
                var stateRef = deepExtractStateRef(expr);
                if (stateRef != null) {
                    return {
                        text: "0",
                        boundState: stateRef,
                        format: 'CTRL.Text(winrt::hstring(std::to_wstring(s_$stateRef)));'
                    };
                }
        }
        return null;
    }

    static function defaultNode():ViewNode {
        return {
            viewType: "StackPanel",
            children: [],
            modifiers: [],
            properties: new Map()
        };
    }
    #end
}
