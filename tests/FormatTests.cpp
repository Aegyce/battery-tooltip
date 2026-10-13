#define BATTERY_TOOLTIP_TEST
#include "../battery-tooltip.wh.cpp"
#include <iostream>
#include <limits>

int main() {
    int failed = 0;
    int checked = 0;
    auto check = [&](bool condition, const char* name) {
        ++checked;
        if (!condition) { std::cerr << "FAIL " << name << '\n'; ++failed; }
    };
    check(Format({99,true,0,true,0,-1}) == L"外接电源\n电池未充放电", "idle AC has no misleading system watts");
    check(Format({75,true,1,true,18.5,2400}) == L"外接电源\n充电 18.5 W · 剩余 40 min", "charging layout");
    check(Format({75,false,2,true,8.2,19200}) == L"电池供电\n放电 8.2 W · 剩余 5 h 20 min", "battery discharge");
    check(Format({75,true,2,true,8.2,19200}) == L"外接电源\n放电 8.2 W · 剩余 5 h 20 min", "discharge while plugged in");
    check(Format({75,false,2,false,0,-1}) == L"电池供电\n放电 -- W · 剩余 --", "unknown telemetry never becomes zero");
    check(FormatDuration(3600) == L"1 h", "hour boundary");
    check(FormatDuration(1) == L"1 min", "small duration");
    check(FormatDuration(std::numeric_limits<double>::infinity()) == L"--", "infinite estimate");
    check(FormatDuration(10*86400) == L"--", "unreasonable estimate");
    Snapshot plugged{99,true,0,false,0,-1};
    ApplyRate(plugged,true,-8200);
    check(plugged.ac && plugged.state == 2 && plugged.watts == 8.2, "negative battery rate wins even on AC");
    Snapshot contradictory{99,true,2,false,0,-1};
    ApplyRate(contradictory,true,18500);
    check(contradictory.state == 1 && contradictory.watts == 18.5, "net rate wins over stale status");
    Snapshot unavailable{99,true,0,false,0,-1};
    ApplyRate(unavailable,true,std::numeric_limits<int>::min());
    check(!unavailable.rateKnown, "unknown-rate sentinel is not a watt reading");
    check(ResolveLanguage(L"auto",0x0804) == Language::Chinese, "auto Simplified Chinese");
    check(ResolveLanguage(L"auto",0x0409) == Language::English, "auto English");
    check(ResolveLanguage(L"auto",0x040c) == Language::English, "unsupported language falls back to English");
    check(ResolveLanguage(L"en",0x0804) == Language::English, "English override on Chinese Windows");
    check(ResolveLanguage(L"zh-CN",0x0409) == Language::Chinese, "Chinese override on English Windows");
    check(Format({99,true,0,true,0,-1},Language::English) == L"AC power\nBattery idle", "English idle");
    check(Format({75,true,1,true,18.5,2400},Language::English) == L"AC power\nCharging 18.5 W · Remaining 40 min", "English charging");
    check(Format({75,false,2,true,8.2,19200},Language::English) == L"Battery power\nDischarging 8.2 W · Remaining 5 h 20 min", "English discharge");
    check(Format({75,true,2,true,8.2,19200},Language::English) == L"AC power\nDischarging 8.2 W · Remaining 5 h 20 min", "English discharge on AC");
    check(Format({75,false,2,false,0,-1},Language::English) == L"Battery power\nDischarging -- W · Remaining --", "English unknown telemetry");
    std::cout << checked << " checks, " << failed << " failures\n";
    return failed ? 1 : 0;
}
