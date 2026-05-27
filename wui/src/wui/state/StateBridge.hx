package wui.state;

/**
  Read/write `@:state` fields by name from Haxe code (typically a click
  handler lambda passed to `StateAction.Custom`). All accessors are
  thin wrappers around `extern "C" clw_state_{set,get}_{string,int,bool,double}`
  dispatch functions that `UIBuilder` emits into `MainWindow.cpp` —
  the dispatch looks the field up by wstring name at runtime.

  Usage (inside a `Custom(() -> { ... })` lambda):
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
// We go through UTF-8 because the `::String(const char16_t*, int)`
// overload appears to be picked up as `::String(const char*, int)` in
// our build, which then truncates the wide bytes at the first 0x00.
static ::String _wui_wide_to_string(const wchar_t* w, int wlen) {
    if (!w || wlen <= 0) return ::String();
    int u8len = WideCharToMultiByte(CP_UTF8, 0, w, wlen, nullptr, 0, nullptr, nullptr);
    if (u8len <= 0) return ::String();
    std::string u8((size_t)u8len, 0);
    WideCharToMultiByte(CP_UTF8, 0, w, wlen, &u8[0], u8len, nullptr, nullptr);
    return ::String(u8.c_str(), u8len);
}
')
class StateBridge {
    public static function setString(name:String, value:String):Void {
        untyped __cpp__('clw_state_set_string(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length, reinterpret_cast<const wchar_t*>(({1}).wc_str()), ({1}).length)', name, value);
    }

    public static function getString(name:String):String {
        var result:String = "";
        untyped __cpp__('const wchar_t* _buf; int _len; clw_state_get_string(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length, &_buf, &_len); {1} = _wui_wide_to_string(_buf, _len);', name, result);
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
