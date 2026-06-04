package wui.state;

/**
  Read/write `@:state` fields by name from Haxe code (typically a click
  handler closure passed to `.onTap(...)` or `Button`'s action arg).
  All accessors are thin wrappers around
  `extern "C" clw_state_{set,get}_{string,int,bool,double}` dispatch
  functions that `UIBuilder` emits into `MainWindow.cpp` — the dispatch
  looks the field up by wstring name at runtime.

  Usage (inside a `.onTap(() -> { ... })` closure):
    wui.state.StateBridge.setString("loginStatus", "Démarrage…");
    var current = wui.state.StateBridge.getString("loginStatus");
    wui.state.StateBridge.setInt("count", 42);

  Names are the `@:state` field names declared on the App subclass.
  Unknown names are silently ignored on set; gets return type-default
  ("", 0, false, 0.0).
**/
#if cpp
@:keep
@:cppFileCode('
#include <windows.h>
#include <string>

extern "C" void clw_state_set_string(const wchar_t* name, int name_len, const wchar_t* val, int val_len);
extern "C" void clw_state_get_string(const wchar_t* name, int name_len, const wchar_t** out_buf, int* out_len);
extern "C" void clw_state_set_int(const wchar_t* name, int name_len, int val);
extern "C" int clw_state_get_int(const wchar_t* name, int name_len);
extern "C" void clw_state_set_double(const wchar_t* name, int name_len, double val);
extern "C" double clw_state_get_double(const wchar_t* name, int name_len);
extern "C" void clw_state_set_bool(const wchar_t* name, int name_len, bool val);
extern "C" bool clw_state_get_bool(const wchar_t* name, int name_len);

// Convert a UTF-16 buffer to a UTF-8-backed hxcpp ::String.
//
// `::String(const char *, int)` in our hxcpp build stores the input
// pointer verbatim — it does NOT copy the bytes (verified empirically
// via pointer-equality diag : the returned String\'s `utf8_str()`
// pointed at the same address as the source std::string\'s `c_str()`).
//
// Consequence : a stack-local `std::string` would be freed on function
// return and the Haxe String would dangle. Most of the time the
// allocator hadn\'t reused the slot yet so reads looked clean; under
// load (worker thread doing setString + getString in a tight loop) a
// wstring allocation from the dispatch path would reuse the slot and
// the Haxe String would surface as the *name* of whichever field was
// just set — the source of the "deviceCode" / random-byte URL
// corruption in CLW-12.
//
// Fix : allocate the buffer through `hx::NewGCBytes` so the hxcpp GC
// tracks it as part of the String\'s reachable graph. As long as the
// String stays referenced, the buffer survives.
//
// We still go through UTF-8 because the `::String(const char16_t*, int)`
// overload resolves to `::String(const char*, int)` in this build and
// truncates the wide bytes at the first 0x00.
static ::String _wui_wide_to_string(const wchar_t* w, int wlen) {
    if (!w || wlen <= 0) return ::String();
    int u8len = WideCharToMultiByte(CP_UTF8, 0, w, wlen, nullptr, 0, nullptr, nullptr);
    if (u8len <= 0) return ::String();
    char* gcBuf = (char*)hx::NewGCBytes(nullptr, u8len + 1);
    WideCharToMultiByte(CP_UTF8, 0, w, wlen, gcBuf, u8len, nullptr, nullptr);
    gcBuf[u8len] = 0;
    return ::String((const char*)gcBuf, u8len);
}
')
class StateBridge {
    public static function setString(name:String, value:String):Void {
        untyped __cpp__('clw_state_set_string(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length, reinterpret_cast<const wchar_t*>(({1}).wc_str()), ({1}).length)', name, value);
    }

    public static function getString(name:String):String {
        var result:String = "";
        untyped __cpp__('const wchar_t* _buf = nullptr; int _len = 0; clw_state_get_string(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length, &_buf, &_len); {1} = _wui_wide_to_string(_buf, _len);', name, result);
        return result;
    }

    public static function setInt(name:String, value:Int):Void {
        untyped __cpp__('clw_state_set_int(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length, {1})', name, value);
    }

    public static function getInt(name:String):Int {
        var result:Int = 0;
        untyped __cpp__('{1} = clw_state_get_int(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length)', name, result);
        return result;
    }

    public static function setFloat(name:String, value:Float):Void {
        untyped __cpp__('clw_state_set_double(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length, {1})', name, value);
    }

    public static function getFloat(name:String):Float {
        var result:Float = 0.0;
        untyped __cpp__('{1} = clw_state_get_double(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length)', name, result);
        return result;
    }

    public static function setBool(name:String, value:Bool):Void {
        untyped __cpp__('clw_state_set_bool(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length, {1})', name, value);
    }

    public static function getBool(name:String):Bool {
        var result:Bool = false;
        untyped __cpp__('{1} = clw_state_get_bool(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length)', name, result);
        return result;
    }
}
#end
