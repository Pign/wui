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

        // Force the Haxe/WinUI bridge into the build.
        //
        // Nothing in an app references wui.bridge.HaxeBridge, so without this the
        // module is never loaded, hxcpp never emits it, and `wui_bridge_init` --
        // which the generated App.cpp declares and calls -- does not exist. The
        // link would fail on Windows with an unresolved external, long after the
        // point where the mistake was made. `sui` forces its bridge the same way.
        Context.getModule("wui.bridge.HaxeBridge");

        // Say that a WinUI project is being generated, so the node sink emits its
        // native calls. Without this the sink compiles to no-ops and the library
        // links on its own -- a test binary has no WuiNodes.cpp to call into.
        Compiler.define("wui_winui");

        // Collect types after typing phase
        Context.onAfterTyping(function(types:Array<haxe.macro.Type.ModuleType>) {
            // Judge the node trees written in this build before anything else:
            // an unknown type or a mistyped property is a source mistake, and
            // rendering `?TypeName` for it would only postpone the discovery.
            NodeValidator.check(types);

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

        // An app marked @:nui renders through the push contract instead of the
        // generated UI: the window gets an empty root and Haxe mounts into it.
        var pushMode = switch (appType) {
            case TInst(ref, _): ref.get().meta.has(":nui");
            case _: false;
        };
        UIBuilder.pushMode = pushMode;

        // Build the view tree from body()
        var viewTree = buildViewTree(appType);

        // Number the Haxe closures. Must mirror HaxeBridge.collect() exactly:
        // depth-first over children, counting only buttons that carry one.
        var callbackCount = assignCallbackIds(viewTree, 0);

        // The class the runtime instantiates to reach those closures.
        var appClassPath = switch (appType) {
            case TInst(ref, _):
                var c = ref.get();
                c.pack.length > 0 ? c.pack.join(".") + "." + c.name : c.name;
            case _: appName;
        };

        // Generate all files
        Sys.println('[wui] Generating C++/WinRT project for "$appName"...');

        ProjectGenerator.generate(appName, winuiDir);
        Sys.println("[wui]   Generated .vcxproj, packages.config, pch.h");

        BridgeGenerator.generate(appName, winuiDir, windowWidth, windowHeight, appClassPath, callbackCount);
        Sys.println("[wui]   Generated App.h, App.cpp, WuiRuntime.h");

        UIBuilder.generateMainWindow(viewTree, winuiDir);
        Sys.println("[wui]   Generated MainWindow.h, MainWindow.cpp");

        Sys.println('[wui] C++/WinRT project generated at: $winuiDir');
    }

    /** Is this argument a literal `null`, as in `new Button("x", null, action)`? **/
    static function isNullLiteral(expr:TypedExpr):Bool {
        if (expr == null) return true;
        return switch (expr.expr) {
            case TConst(TNull): true;
            default: false;
        };
    }

    /**
     * Give every closure-bearing button its id, depth-first, and return how many
     * were numbered.
     *
     * This walk is one half of a contract; `wui.bridge.HaxeBridge.collect()` is
     * the other. They must visit the same buttons in the same order, or a click
     * runs the wrong closure -- quietly, since both sides are individually
     * consistent. Changing one without the other is the way to break W2.
     */
    static function assignCallbackIds(node:ViewNode, next:Int):Int {
        if (node == null) return next;

        if (node.viewType == "Button" && node.properties.exists("hasHaxeCallback")) {
            node.properties.set("haxeCallbackId", next);
            next++;
        }

        for (child in node.children) {
            next = assignCallbackIds(child, next);
        }

        return next;
    }

    /**
     * Collect @:state fields from the App subclass.
     */
    static function collectStateFields(type:Type):Array<{name:String, type:String, initial:String}> {
        var result:Array<{name:String, type:String, initial:String}> = [];
        UIBuilder.allStateNames = [];
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    // Check if the field is a State<T> type
                    switch (field.type) {
                        case TInst(tref, params):
                            var typeName = tref.get().name;
                            if (typeName == "State" && params.length > 0) {
                                // Only the types that have a C++ static here. An
                                // unmapped one used to fall back to `int`, which
                                // declared `static int s_todos = 0` for an array
                                // state -- a static nothing writes, next to a
                                // notify nothing calls. A state whose home is
                                // elsewhere (a list is rebuilt by Haxe) should
                                // produce nothing rather than a plausible lie.
                                var cppType:String = null;
                                var initial:String = null;
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
                                // Two different questions, and they had one
                                // answer between them until a list broke:
                                //
                                //  - which states get a C++ static?  (typed ones)
                                //  - which names ARE states?         (all of them)
                                //
                                // Restricting the first list to mappable types
                                // silently un-recognised `todos` as a state, so
                                // the ListView bound to nothing at all.
                                UIBuilder.allStateNames.push(field.name);
                                if (cppType != null) {
                                    result.push({ name: field.name, type: cppType, initial: initial });
                                }
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
                properties: textProps
            }],
            properties: defaultProps
        };
    }

    /**
     * Analyze a typed expression to build a ViewNode tree.
     */
    // Map of local variable names to their expressions (for temp var resolution)
    static var localExprs:Map<String, TypedExpr> = new Map();

    /**
     * What was done to a local *after* it was declared.
     *
     * Only the initialiser used to be recorded, so a view built in statements
     * lost everything that followed:
     *
     *     var a = new Button("Haxe A");   // kept
     *     a.onClick(() -> report("A"));   // lost
     *     a.padding = 12;                 // lost
     *
     * The build still succeeded and the app still ran -- with half its controls
     * missing. Silence again, from the tool this time.
     */
    static var localMutations:Map<String, Array<TypedExpr>> = new Map();

    /** Which local, if any, this expression is acting on. **/
    static function mutatedLocal(expr:TypedExpr):Null<String> {
        return switch (expr.expr) {
            case TBinop(OpAssign, {expr: TField({expr: TLocal(v)}, _)}, _): v.name;
            case TCall({expr: TField({expr: TLocal(v)}, _)}, _): v.name;
            case _: null;
        };
    }

    /** Replay onto `node` what the block did to the local it came from. **/
    static function applyMutations(name:String, node:ViewNode):ViewNode {
        var pending = localMutations.get(name);
        if (pending == null) return node;

        for (expr in pending) {
            switch (expr.expr) {
                // `a.padding = 12`
                case TBinop(OpAssign, {expr: TField(_, fa)}, value):
                    var key = fieldNameOf(fa);
                    if (key == null) continue;
                    var v:Dynamic = extractFloatValue(value);
                    if (v == null) v = extractStringOrExpr(value);
                    if (v != null) node.properties.set(key, v);

                // `a.onClick(...)`, and property assignments.
                //
                // `a.padding = 12` does not reach here as an assignment: a
                // declared property has a setter, so the typed AST holds a call
                // to `set_padding`. Reading it as a call is the only way to see
                // an assignment at all.
                case TCall({expr: TField(_, fa)}, args):
                    var called = fieldNameOf(fa);
                    if (called != null && StringTools.startsWith(called, "set_") && args.length > 0) {
                        var key = called.substr(4);

                        // `onClick` is a declared property now, so assigning it
                        // arrives as `set_onClick` -- but what the generator needs
                        // from it is the mark that this button carries a closure,
                        // not a value it could emit.
                        if (key == "onClick") {
                            node.properties.set("hasHaxeCallback", true);
                            continue;
                        }

                        var v:Dynamic = extractFloatValue(args[0]);
                        if (v == null) v = extractStringOrExpr(args[0]);
                        if (v != null) node.properties.set(key, v);
                    } else if (called == "onClick" && args.length > 0) {
                        node.properties.set("hasHaxeCallback", true);
                    }

                case _:
            }
        }
        return node;
    }

    static function fieldNameOf(fa:FieldAccess):Null<String> {
        return switch (fa) {
            case FInstance(_, _, cf): cf.get().name;
            case FDynamic(sn): sn;
            case FClosure(_, cf): cf.get().name;
            case _: null;
        };
    }

    static function analyzeBodyExpr(texpr:TypedExpr):ViewNode {
        if (texpr == null) {
            return defaultNode();
        }

        switch (texpr.expr) {
            case TReturn(e):
                if (e != null) return analyzeBodyExpr(e);

            case TBlock(exprs):
                // First pass: the bindings, and what is done to them afterwards.
                for (expr in exprs) {
                    switch (expr.expr) {
                        case TVar(v, e):
                            if (e != null) localExprs.set(v.name, e);
                        default:
                            var target = mutatedLocal(expr);
                            if (target != null) {
                                if (!localMutations.exists(target)) localMutations.set(target, []);
                                localMutations.get(target).push(expr);
                            }
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
                // Resolve temp variables to their original expressions, then
                // replay whatever the block did to them afterwards.
                var resolved = localExprs.get(v.name);
                if (resolved != null) return applyMutations(v.name, analyzeBodyExpr(resolved));

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
                { viewType: "StackPanel", children: children, properties: props };

            case "wui.ui.HStack":
                var children = args.length > 0 ? extractChildArray(args[0]) : [];
                var spacing = args.length > 1 ? extractFloatValue(args[1]) : null;
                var props:Map<String, Dynamic> = new Map();
                props.set("orientation", "Horizontal");
                if (spacing != null) props.set("spacing", spacing);
                { viewType: "StackPanel", children: children, properties: props };

            case "wui.ui.ZStack":
                var children = args.length > 0 ? extractChildArray(args[0]) : [];
                { viewType: "Grid", children: children, properties: new Map() };

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
                { viewType: "TextBlock", children: [], properties: props };

            case "wui.ui.Button":
                var label = args.length > 0 ? extractStringOrExpr(args[0]) : "Button";
                var props:Map<String, Dynamic> = new Map();
                props.set("label", label);
                // args[1] = icon (optional), args[2] = action (StateAction)
                //
                // The action is no longer translated into C++. It is marked, given
                // an id like any Haxe closure, and `wui.bridge.Actions` runs the
                // enum at runtime. That is what lets `Custom`, `Sequence`, `Append`
                // and `Remove` work at all -- the translator understood four of the
                // nine constructors and dropped the others without a word.
                if (args.length > 2 && !isNullLiteral(args[2])) {
                    props.set("hasHaxeCallback", true);
                }
                { viewType: "Button", children: [], properties: props };

            case "wui.ui.ListView":
                // Only the bound state's name is taken here. The rows are Haxe's
                // business: the generator cannot know how many there will be, so
                // it emits an empty control and the runtime fills it.
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var stateRef = deepExtractStateRef(args[0]);
                    if (stateRef != null) props.set("boundState", stateRef);
                }
                { viewType: "ListView", children: [], properties: props };

            case "wui.ui.Spacer":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var minSize = extractFloatValue(args[0]);
                    if (minSize != null) props.set("minSize", minSize);
                }
                { viewType: "Spacer", children: [], properties: props };

            case "wui.ui.TextBox":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var placeholder = extractStringOrExpr(args[0]);
                    if (placeholder != null) props.set("placeholder", placeholder);
                }
                if (args.length > 1) {
                    var stateRef = deepExtractStateRef(args[1]);
                    if (stateRef != null) props.set("boundState", stateRef);
                }
                { viewType: "TextBox", children: [], properties: props };

            case "wui.ui.ToggleSwitch":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var label = extractStringOrExpr(args[0]);
                    if (label != null) props.set("label", label);
                }
                if (args.length > 1) {
                    var stateRef = deepExtractStateRef(args[1]);
                    if (stateRef != null) props.set("boundState", stateRef);
                }
                { viewType: "ToggleSwitch", children: [], properties: props };

            case "wui.ui.CheckBox":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var label = extractStringOrExpr(args[0]);
                    if (label != null) props.set("label", label);
                }
                if (args.length > 1) {
                    var stateRef = deepExtractStateRef(args[1]);
                    if (stateRef != null) props.set("boundState", stateRef);
                }
                { viewType: "CheckBox", children: [], properties: props };

            case "wui.ui.Slider":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) props.set("min", extractFloatValue(args[0]));
                if (args.length > 1) props.set("max", extractFloatValue(args[1]));
                // args[2] = binding, args[3] = step
                if (args.length > 2) {
                    var stateRef = deepExtractStateRef(args[2]);
                    if (stateRef != null) props.set("boundState", stateRef);
                }
                if (args.length > 3) props.set("step", extractFloatValue(args[3]));
                { viewType: "Slider", children: [], properties: props };

            case "wui.ui.Image":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) props.set("source", extractStringOrExpr(args[0]));
                { viewType: "Image", children: [], properties: props };

            case "wui.ui.ScrollViewer":
                var children = args.length > 0 ? [analyzeBodyExpr(args[0])] : [];
                { viewType: "ScrollViewer", children: children, properties: new Map() };

            case "wui.ui.ProgressRing":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    props.set("value", extractFloatValue(args[0]));
                    props.set("isIndeterminate", "false");
                } else {
                    props.set("isIndeterminate", "true");
                }
                { viewType: "ProgressRing", children: [], properties: props };

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

                // `.onClick(fn)` is not a modifier: it marks the button as
                // carrying a Haxe closure. The id is assigned later, by walking
                // the finished tree -- numbering here would follow the order the
                // typed AST is visited, which for a chained call is inner-first
                // and does not match the depth-first walk the runtime does.
                if (fieldName == "onClick" && args.length > 0) {
                    baseNode.properties.set("hasHaxeCallback", true);
                }


                return baseNode;
            default:
        }

        return defaultNode();
    }

    /**
     * Extract a modifier from a method name and arguments.
     */
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
                var fieldName = switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: null;
                };
                // state.value access
                if (fieldName == "value") return extractStateFieldRef(obj);
                // Direct field reference (this.count)
                if (fieldName != null) {
                    for (sf in UIBuilder.allStateNames) {
                        if (fieldName == sf) return sf;
                    }
                }
                return null;

            case TLocal(v):
                // Check if this local is a known state field
                var resolved = localExprs.get(v.name);
                if (resolved != null) return extractStateFieldRef(resolved);
                // Check against state fields
                for (sf in UIBuilder.allStateNames) {
                    if (v.name == sf) return sf;
                }
                return null;

            default:
                return null;
        }
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
                for (sf in UIBuilder.allStateNames) {
                    if (v.name == sf) return sf;
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
                    for (sf in UIBuilder.allStateNames) {
                        if (fName == sf) return sf;
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
                        var valueExpr = stateToWstring(stateRef);
                        return {
                            text: prefix + "0",
                            boundState: stateRef,
                            format: 'CTRL.Text(winrt::hstring(L"$escaped" + $valueExpr));'
                        };
                    }
                    // count + "suffix"
                    var stateRef1 = deepExtractStateRef(e1);
                    var suffix = extractStringOrExpr(e2);
                    if (stateRef1 != null && suffix != null && suffix != "...") {
                        var escaped = UIBuilder.escapeWideString(suffix);
                        var valueExpr = stateToWstring(stateRef1);
                        return {
                            text: "0" + suffix,
                            boundState: stateRef1,
                            format: 'CTRL.Text(winrt::hstring($valueExpr + L"$escaped"));'
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

    /** Return C++ expression to convert a state variable to std::wstring. */
    static function stateToWstring(stateName:String):String {
        for (sf in UIBuilder.stateFields) {
            if (sf.name == stateName) {
                if (sf.type == "std::wstring") return 's_$stateName';
                if (sf.type == "bool") return '(s_$stateName ? std::wstring(L"true") : std::wstring(L"false"))';
                return 'std::to_wstring(s_$stateName)';
            }
        }
        return 'std::to_wstring(s_$stateName)';
    }

    static function defaultNode():ViewNode {
        return {
            viewType: "StackPanel",
            children: [],
            properties: new Map()
        };
    }
    #end
}
