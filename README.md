# Battery Tooltip

[![Test and release](https://github.com/Aegyce/battery-tooltip/actions/workflows/ci.yml/badge.svg)](https://github.com/Aegyce/battery-tooltip/actions/workflows/ci.yml)

A Windhawk mod for Windows 11 that shows battery charging and discharging power and estimated remaining time in the native battery icon tooltip.

Experimental version: **0.2.0**. GitHub repository name: **battery-tooltip**.

The mod keeps the existing battery icon, taskbar percentage, and click behavior. It adds no battery tray icon. English and Simplified Chinese are supported, with `W`, `h`, and `min` units. Language follows Windows by default; other Windows languages fall back to English.

## Tooltip examples

English:

```text
AC power
Charging 18.5 W · Remaining 40 min
```

```text
AC power
Discharging 8.2 W · Remaining 5 h 20 min
```

```text
AC power
Battery idle
```

Simplified Chinese:

External power with an idle battery:

```text
外接电源
电池未充放电
```

Charging:

```text
外接电源
充电 18.5 W · 剩余 40 min
```

Discharging while plugged in:

```text
外接电源
放电 8.2 W · 剩余 5 h 20 min
```

On battery power, the first line reads `电池供电`. Power-source detection is independent of the battery's net charging or discharging direction. A negative battery rate is shown as discharging even when external power is connected.

## Language selection

In the mod settings, choose **Follow Windows**, **English**, or **简体中文**. For the portable runtime, use:

```powershell
& .\tools\Language.ps1 -Language en
& .\tools\Language.ps1 -Language zh-CN
& .\tools\Language.ps1 -Language auto
```

Reopen the tooltip to apply the language change. Both languages use the same telemetry and estimate rules.

## What the readings mean

- Power is the battery's net charge/discharge rate, not whole-computer power consumption. Idle batteries show their state without a power reading.
- Discharge time uses Windows' estimate when available. Charge time is estimated from capacity remaining to the configured target and the current charging rate. Charging usually slows near full, which can change the estimate.
- Missing or unreasonable values appear as `--` instead of a misleading zero.
- Data refreshes whenever the tooltip opens; an already-open tooltip does not refresh continuously.

## Try it and roll back

1. On a new machine, install Python 3 and run `Setup.cmd`. It downloads and verifies the official Windhawk 1.7.3 offline installer, extracts a portable runtime, runs tests, and compiles the mod. The mod stays disabled after building.
2. Run `Start.cmd` to enable the trial. Hover over the existing battery icon.
3. Run `Rollback.cmd` to disable the mod. The script verifies that its DLL has unloaded from Explorer, then exits this project's portable Windhawk. Saved native tooltip content is restored during unloading. A failed rollback produces an error instead of reporting success.

The trial creates no startup entry, replaces no Windows system files, and installs no additional hardware-reading driver. It does not change charge thresholds, power plans, or taskbar layout. Once rollback completes, the project directory can be removed.

Alternatively, create a custom mod in an existing Windhawk installation, paste `battery-tooltip.wh.cpp`, and compile it. Use Windhawk's disable toggle to roll back that installation; the project scripts manage only the bundled portable runtime.

## Compatibility

The initial trial loaded on **Windows 11 25H2, build 26200.9457, x64**. The user confirmed that the modified tooltip appeared on the original battery icon and that the two-line sample fitted. Other Windows builds and real charging/discharging transitions have not yet been validated on hardware.

The mod hooks the native battery tooltip's opening handler in `SystemTray.dll`. It refuses to enable if the expected symbol cannot be found. Windows updates may require compatibility changes. Initial symbol downloads require internet access.

## Sample previews

Run these commands from the project directory:

```powershell
& .\tools\Preview.ps1 -Mode 1 # Fictional charging sample
& .\tools\Preview.ps1 -Mode 2 # Fictional discharging sample
& .\tools\Preview.ps1 -Mode 0 # Return to live telemetry
```

Reopen the tooltip after changing modes. Sample values are not measurements.

The `chargeTargetPercent` setting defaults to 100. Match it to an existing charge limit, such as 80, if needed. This setting affects the time estimate only; it does not control battery charging. For the portable runtime, settings reside in `runtime/windhawk/AppData/Engine/Mods/local@battery-tooltip.ini`. Disable and reenable the mod after manually changing a setting.

## Development and releases

```powershell
python tools/test.py
python tools/build.py
```

Run `Rollback.cmd` before rebuilding an active mod. Each build uses a new DLL filename and keeps the mod disabled until explicitly started.

GitHub Actions runs formatting and edge-case tests, compiles the mod, and generates a downloadable package on pushes and pull requests. A `v*` tag matching `VERSION` triggers automatic GitHub Release creation.

Use minor increments for feature enhancements, patch increments for bug fixes, and major increments when a stable product milestone is reached. Keep `VERSION` and the mod's `@version` metadata in sync; the build rejects a mismatch.

## License

MIT. Windhawk and its compiler retain their own licenses and are downloaded separately; they are excluded from the Git repository.
