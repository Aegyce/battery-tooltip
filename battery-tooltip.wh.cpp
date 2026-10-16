// ==WindhawkMod==
// @id              battery-tooltip
// @name            Battery Tooltip
// @description     A Windhawk mod for Windows 11 that shows battery charging and discharging power and estimated remaining time in the native battery icon tooltip.
// @version         1.3.1
// @author          Aegyce
// @license         MIT
// @include         explorer.exe
// @architecture    x86-64
// @compilerOptions -lruntimeobject -lole32 -loleaut32 -lcomctl32
// ==/WindhawkMod==

// ==WindhawkModReadme==
/*
# Battery Tooltip
Changes only the original battery icon's hover tooltip. No new battery icon.
Time is an estimate. Charging time uses the current net charging rate, so it
can increase as charging slows near full. Missing telemetry is shown as --.
Disable this mod to restore saved native tooltip content. No system DLLs,
battery charge thresholds, taskbar layout, or power settings are changed.
Preview modes use sample data; switch back to live after viewing.
Language follows Windows by default. English and Simplified Chinese can also
be selected explicitly in the mod settings.
*/
// ==/WindhawkModReadme==

// ==WindhawkModSettings==
/*
- language: auto
  $name: Language / 语言
  $options:
  - auto: Follow Windows / 跟随系统
  - en: English
  - zh-CN: 简体中文
- previewMode: 0
  $name: Preview mode
  $options:
  - 0: Live battery data
  - 1: Charging sample (not real telemetry)
  - 2: Discharging sample (not real telemetry)
- chargeTargetPercent: 100
  $name: Charging target (%)
  $description: Match your configured battery charge limit for the time estimate.
*/
// ==/WindhawkModSettings==

#include <atomic>
#include <algorithm>
#include <cmath>
#include <cwchar>
#include <string>
#include <vector>
#include <cstdint>

enum class Language { Chinese, English };

Language ResolveLanguage(const std::wstring& setting, uint16_t uiLanguage) {
    if (setting == L"zh-CN") return Language::Chinese;
    if (setting == L"en" || setting == L"en-US") return Language::English;
    // LANG_CHINESE = 0x04; the low 10 bits identify the primary language.
    return (uiLanguage & 0x3ff) == 0x04 ? Language::Chinese : Language::English;
}

#ifndef BATTERY_TOOLTIP_TEST
#include <windhawk_api.h>
#include <windhawk_utils.h>
#include <windows.h>
#undef GetCurrentTime
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Devices.Power.h>
#include <winrt/Windows.System.Power.h>
#include <winrt/Windows.UI.Xaml.Controls.h>

using namespace winrt;
using namespace Windows::Foundation;
using namespace Windows::UI::Xaml;
using namespace Windows::UI::Xaml::Controls;

std::atomic<bool> g_stopping{false};
std::atomic<int> g_preview{0};
std::atomic<int> g_target{100};
std::atomic<int> g_openCount{0};
std::atomic<Language> g_language{Language::English};
UINT g_restoreMessage;
std::atomic<HWND> g_taskbar{nullptr};
std::atomic<bool> g_hookAttempted{false};
std::atomic<bool> g_hookReady{false};
#endif

struct Snapshot {
    int percent = -1;
    bool ac = false;
    int state = 0; // 0 idle, 1 charging, 2 discharging
    bool rateKnown = false;
    double watts = 0;
    double seconds = -1;
};

void ApplyRate(Snapshot& s, bool available, int rate) {
    if (!available || std::abs(static_cast<double>(rate)) >= 1000000) return;
    if (rate > 0) s.state = 1;
    if (rate < 0) s.state = 2;
    s.rateKnown = true;
    s.watts = std::abs(static_cast<double>(rate)) / 1000;
}

std::wstring FormatDuration(double seconds) {
    if (!std::isfinite(seconds) || seconds < 0 || seconds > 7 * 86400)
        return L"--";
    int minutes = std::max(1, static_cast<int>(std::ceil(seconds / 60)));
    int hours = minutes / 60;
    minutes %= 60;
    std::wstring result;
    if (hours) result = std::to_wstring(hours) + L" h";
    if (minutes) {
        if (!result.empty()) result += L" ";
        result += std::to_wstring(minutes) + L" min";
    }
    return result;
}

std::wstring Format(const Snapshot& s, Language language = Language::Chinese) {
    bool english = language == Language::English;
    std::wstring source = english ? (s.ac ? L"AC power" : L"Battery power")
                                  : (s.ac ? L"外接电源" : L"电池供电");
    if (!s.state) return source + (english ? L"\nBattery idle" : L"\n电池未充放电");
    std::wstring text = source + L"\n";
    text += english ? (s.state == 1 ? L"Charging " : L"Discharging ")
                    : (s.state == 1 ? L"充电 " : L"放电 ");
    if (s.rateKnown) {
        wchar_t value[32];
        swprintf_s(value, L"%.1f W", s.watts);
        text += value;
    } else text += L"-- W";
    return text + (english ? L" · Remaining " : L" · 剩余 ") + FormatDuration(s.seconds);
}

#ifndef BATTERY_TOOLTIP_TEST
Snapshot ReadBattery() {
    if (g_preview == 1) return {75, true, 1, true, 18.5, 40 * 60};
    if (g_preview == 2) return {75, false, 2, true, 8.2, 320 * 60};
    Snapshot s;
    SYSTEM_POWER_STATUS power{};
    if (GetSystemPowerStatus(&power)) {
        s.percent = power.BatteryLifePercent <= 100 ? power.BatteryLifePercent : -1;
        s.ac = power.ACLineStatus == 1;
    }
    auto report = Windows::Devices::Power::Battery::AggregateBattery().GetReport();
    using Status = Windows::System::Power::BatteryStatus;
    auto status = report.Status();
    s.state = status == Status::Charging ? 1 : status == Status::Discharging ? 2 : 0;
    auto rate = report.ChargeRateInMilliwatts();
    // A signed, nonzero rate is stronger evidence than AC-online status.
    ApplyRate(s, static_cast<bool>(rate), rate ? rate.Value() : 0);
    auto full = report.FullChargeCapacityInMilliwattHours();
    auto remaining = report.RemainingCapacityInMilliwattHours();
    if (s.state && full && remaining && s.rateKnown && s.watts > 0) {
        double amount = s.state == 1
            ? std::max(0.0, full.Value() * g_target.load() / 100.0 - remaining.Value())
            : std::max(0.0, static_cast<double>(remaining.Value()));
        s.seconds = amount / (s.watts * 1000) * 3600;
    }
    if (s.state == 2) {
        auto estimate = Windows::System::Power::PowerManager::RemainingDischargeTime();
        double seconds = std::chrono::duration<double>(estimate).count();
        if (seconds > 0 && seconds < 7 * 86400) s.seconds = seconds;
    }
    return s;
}

struct SavedTooltip {
    weak_ref<ToolTip> tooltip;
    IInspectable original{nullptr};
    IInspectable replacement{nullptr};
};
// Accessed only on the taskbar UI thread.
std::vector<SavedTooltip> g_saved;

void RestoreAll() {
    for (auto& saved : g_saved) {
        try {
            if (auto tooltip = saved.tooltip.get()) {
                // Preserve native updates that occurred after our replacement.
                if (tooltip.Content() == saved.replacement) {
                    tooltip.Content(saved.original);
                    auto nativeText = unbox_value_or<hstring>(saved.original, hstring{});
                    Wh_SetStringValue(L"lastRestoredTooltip", nativeText.c_str());
                }
            }
        } catch (...) {}
    }
    g_saved.clear();
}

using OpenedFn = void(WINAPI*)(void*, const IInspectable&, const RoutedEventArgs&);
OpenedFn g_originalOpened;

void WINAPI OpenedHook(void* self, const IInspectable& sender, const RoutedEventArgs& args) {
    g_taskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
    // Restore our old content before letting the native handler update it.
    RestoreAll();
    g_originalOpened(self, sender, args);
    if (g_stopping) return;
    try {
        Wh_SetIntValue(L"openCount", ++g_openCount);
        Wh_SetStringValue(L"lastSender", get_class_name(sender).c_str());
        auto tooltip = sender.try_as<ToolTip>();
        if (!tooltip) {
            if (auto element = sender.try_as<DependencyObject>())
                tooltip = ToolTipService::GetToolTip(element).try_as<ToolTip>();
        }
        if (!tooltip) { Wh_SetStringValue(L"lastError", L"No ToolTip sender"); return; }
        auto content = tooltip.Content();
        Wh_SetStringValue(L"originalContentType", content ? get_class_name(content).c_str() : L"null");
        Wh_SetIntValue(L"isOpen", tooltip.IsOpen());
        auto language = g_language.load();
        std::wstring text = Format(ReadBattery(), language);
        auto replacement = box_value(hstring(text));
        g_saved.push_back({make_weak(tooltip), content, replacement});
        tooltip.Content(replacement);
        Wh_SetStringValue(L"lastTooltip", text.c_str());
        Wh_SetStringValue(L"lastLanguage", language == Language::English ? L"en" : L"zh-CN");
        Wh_SetStringValue(L"lastError", L"");
    } catch (const hresult_error& error) {
        Wh_SetStringValue(L"lastError", error.message().c_str());
    } catch (...) { Wh_SetStringValue(L"lastError", L"Unexpected tooltip error"); }
}

LRESULT CALLBACK RestoreHook(int code, WPARAM wParam, LPARAM lParam) {
    if (code >= 0) {
        auto message = reinterpret_cast<CWPSTRUCT*>(lParam);
        if (message->message == g_restoreMessage) RestoreAll();
    }
    return CallNextHookEx(nullptr, code, wParam, lParam);
}

void ReadSettings() {
    auto language = Wh_GetStringSetting(L"language");
    g_language = ResolveLanguage(language ? language : L"auto", GetUserDefaultUILanguage());
    if (language) Wh_FreeStringSetting(language);
    g_preview = std::clamp(Wh_GetIntSetting(L"previewMode"), 0, 2);
    g_target = std::clamp(Wh_GetIntSetting(L"chargeTargetPercent"), 1, 100);
}

void MarkHookReady() {
    g_hookReady = true;
    Wh_SetIntValue(L"runtimeProcessId", GetCurrentProcessId());
    Wh_SetStringValue(L"runtimeStatus", L"ready");
    Wh_SetStringValue(L"lastError", L"");
}

bool InstallTooltipHook(HMODULE module) {
    if (g_hookAttempted.exchange(true)) return false;
    // Use the exact ABI name discovered on this system if undecorated names differ.
    WH_FIND_SYMBOL_OPTIONS options{sizeof(options)};
    options.noUndecoratedSymbols = TRUE;
    WH_FIND_SYMBOL found{};
    HANDLE search = Wh_FindFirstSymbol(module, &options, &found);
    if (!search) {
        Wh_SetStringValue(L"lastError", L"Cannot enumerate SystemTray.dll symbols");
        return false;
    }
    void* address = nullptr;
    do {
        if (wcscmp(found.symbolDecorated, L"?OnTooltipOpened@BatteryIconContent@implementation@SystemTray@winrt@@QEAAXAEBUIInspectable@Foundation@Windows@4@AEBURoutedEventArgs@Xaml@UI@74@@Z") == 0) {
            address = found.address; break;
        }
    } while (Wh_FindNextSymbol(search, &found));
    Wh_FindCloseSymbol(search);
    if (!address) {
        Wh_SetStringValue(L"lastError", L"Battery tooltip symbol is unsupported on this Windows build");
        return false;
    }
    if (!Wh_SetFunctionHook(address, reinterpret_cast<void*>(OpenedHook), reinterpret_cast<void**>(&g_originalOpened))) {
        Wh_SetStringValue(L"lastError", L"Cannot hook the battery tooltip handler");
        return false;
    }
    return true;
}

using LoadLibraryExFn = decltype(&LoadLibraryExW);
LoadLibraryExFn g_originalLoadLibraryEx;

HMODULE WINAPI LoadLibraryExHook(LPCWSTR path, HANDLE file, DWORD flags) {
    auto module = g_originalLoadLibraryEx(path, file, flags);
    if (!g_stopping && module && !g_hookAttempted &&
        GetModuleHandleW(L"SystemTray.dll") == module && InstallTooltipHook(module)) {
        if (Wh_ApplyHookOperations()) MarkHookReady();
        else Wh_SetStringValue(L"lastError", L"Cannot apply deferred tooltip hook");
    }
    return module;
}

BOOL Wh_ModInit() {
    auto taskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
    DWORD owner = 0;
    if (taskbar) GetWindowThreadProcessId(taskbar, &owner);
    // Ignore separate folder processes, but permit the shell's early startup.
    if (owner && owner != GetCurrentProcessId()) return FALSE;
    g_taskbar = taskbar;
    ReadSettings();
    g_restoreMessage = RegisterWindowMessageW(L"BatteryTooltip.Restore");
    Wh_SetIntValue(L"runtimeProcessId", GetCurrentProcessId());
    Wh_SetStringValue(L"runtimeStatus", L"waiting");
    Wh_SetStringValue(L"lastError", L"");
    if (!g_restoreMessage) return FALSE;
    if (auto module = GetModuleHandleW(L"SystemTray.dll")) return InstallTooltipHook(module);
    // Explorer may not have created its taskbar or loaded XAML yet.
    auto kernelBase = GetModuleHandleW(L"kernelbase.dll");
    auto loadLibrary = GetProcAddress(kernelBase, "LoadLibraryExW");
    if (!loadLibrary || !Wh_SetFunctionHook(reinterpret_cast<void*>(loadLibrary),
            reinterpret_cast<void*>(LoadLibraryExHook), reinterpret_cast<void**>(&g_originalLoadLibraryEx))) {
        Wh_SetStringValue(L"lastError", L"Cannot monitor SystemTray.dll loading");
        return FALSE;
    }
    return TRUE;
}

void Wh_ModAfterInit() {
    if (g_originalOpened) { MarkHookReady(); return; }
    // Close the race between the initial module check and hook activation.
    if (auto module = GetModuleHandleW(L"SystemTray.dll")) {
        if (InstallTooltipHook(module)) {
            if (Wh_ApplyHookOperations()) MarkHookReady();
            else Wh_SetStringValue(L"lastError", L"Cannot apply deferred tooltip hook");
        }
    }
}

void Wh_ModSettingsChanged() { ReadSettings(); }

void Wh_ModBeforeUninit() {
    g_stopping = true;
    if (g_hookReady) Wh_SetStringValue(L"runtimeStatus", L"stopped");
    // Restore content synchronously on its owning thread. No delayed delegates
    // or event handlers are left behind when the DLL is unloaded.
    auto taskbar = g_taskbar.load();
    if (!taskbar) taskbar = FindWindowW(L"Shell_TrayWnd", nullptr);
    DWORD owner = 0;
    DWORD thread = GetWindowThreadProcessId(taskbar, &owner);
    if (!thread || owner != GetCurrentProcessId()) return;
    if (thread == GetCurrentThreadId()) { RestoreAll(); return; }
    HMODULE module = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                      reinterpret_cast<LPCWSTR>(RestoreHook), &module);
    auto hook = SetWindowsHookExW(WH_CALLWNDPROC, RestoreHook, module, thread);
    if (hook) {
        SendMessageW(taskbar, g_restoreMessage, 0, 0);
        UnhookWindowsHookEx(hook);
    }
}
#endif
