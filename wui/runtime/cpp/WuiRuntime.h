#pragma once
// WUI Runtime - C++/WinRT helpers
// This file is the reference copy. The BridgeGenerator macro
// generates a version of this into each project's build/winui/ directory.
//
// Provides:
// - UI thread dispatch (runOnUIThread)
// - String conversion (toHString)
// - Color helpers (colorBrush, named brushes)
// - Thickness/CornerRadius helpers

#include <functional>
#include <string>
#include <vector>
#include <unordered_map>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

namespace wui { namespace runtime {

    // ---- UI Thread Dispatch ----

    inline winrt::Microsoft::UI::Dispatching::DispatcherQueue dispatcherQueue{ nullptr };

    inline void runOnUIThread(std::function<void()> fn) {
        if (dispatcherQueue && !dispatcherQueue.HasThreadAccess()) {
            dispatcherQueue.TryEnqueue(
                winrt::Microsoft::UI::Dispatching::DispatcherQueueHandler(fn));
        } else {
            fn();
        }
    }

    // ---- String Conversion ----

    inline winrt::hstring toHString(const std::wstring& s) {
        return winrt::hstring(s);
    }

    inline winrt::hstring toHString(const wchar_t* s) {
        return winrt::hstring(s);
    }

    inline winrt::hstring toHString(int value) {
        return winrt::hstring(std::to_wstring(value));
    }

    inline winrt::hstring toHString(double value) {
        return winrt::hstring(std::to_wstring(value));
    }

    inline winrt::hstring toHString(bool value) {
        return winrt::hstring(value ? L"true" : L"false");
    }

    // ---- State Change Notification ----

    inline void onStateChanged(const char* name, const char* value) {
        // State updates flow through direct subscriber lambdas in pure C++ mode.
        // This hook is provided for debugging/logging.
    }

    // ---- Color Helpers ----

    inline winrt::Microsoft::UI::Xaml::Media::SolidColorBrush
    colorBrush(uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255) {
        winrt::Windows::UI::Color color{ a, r, g, b };
        return winrt::Microsoft::UI::Xaml::Media::SolidColorBrush(color);
    }

    inline auto blackBrush()       { return colorBrush(0, 0, 0); }
    inline auto whiteBrush()       { return colorBrush(255, 255, 255); }
    inline auto redBrush()         { return colorBrush(255, 0, 0); }
    inline auto greenBrush()       { return colorBrush(0, 128, 0); }
    inline auto blueBrush()        { return colorBrush(0, 0, 255); }
    inline auto yellowBrush()      { return colorBrush(255, 255, 0); }
    inline auto orangeBrush()      { return colorBrush(255, 165, 0); }
    inline auto purpleBrush()      { return colorBrush(128, 0, 128); }
    inline auto grayBrush()        { return colorBrush(128, 128, 128); }
    inline auto transparentBrush() { return colorBrush(0, 0, 0, 0); }

    // ---- Thickness / CornerRadius ----

    inline winrt::Microsoft::UI::Xaml::Thickness uniformThickness(double value) {
        return { value, value, value, value };
    }

    inline winrt::Microsoft::UI::Xaml::CornerRadius uniformCornerRadius(double value) {
        return { value, value, value, value };
    }

}} // namespace wui::runtime
