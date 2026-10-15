# Battery Tooltip

[![Test and release](https://github.com/Aegyce/battery-tooltip/actions/workflows/ci.yml/badge.svg)](https://github.com/Aegyce/battery-tooltip/actions/workflows/ci.yml)

A Windhawk mod for Windows 11 that shows battery charging and discharging power and estimated remaining time in the native battery icon tooltip.

Stable release: **1.0.0**. GitHub repository name: **battery-tooltip**.

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

## Install, start, and stop

1. Download `BatteryTooltip-1.0.0.zip` from [GitHub Releases](https://github.com/Aegyce/battery-tooltip/releases/latest), extract it to a permanent directory, and run `Install.cmd` (or `Setup.cmd`). The package includes the compiled mod and dependencies; Python is not required. Setup downloads and verifies the official Windhawk 1.7.3 offline installer and extracts the portable runtime.
2. Installation starts the mod, verifies that its tooltip hook is ready, and enables automatic startup for the current Windows user. Hover over the existing battery icon. Keep the installation directory in place.
3. Run `Status.cmd` to inspect the installed version, module loading, hook readiness, and automatic startup. `Start.cmd` starts the mod manually without changing the startup preference.
4. Run `Rollback.cmd` to remove this installation's startup entry and disable the mod. The script verifies that its DLL has unloaded from Explorer, then exits this project's portable Windhawk. Saved native tooltip content is restored during unloading. A failed rollback produces an error instead of reporting success.

To install without automatic startup, run `Install.cmd -NoAutoStart`. To prepare a package without starting it, add `-NoStart`. Enable or disable automatic startup independently with:

```powershell
& .\tools\Startup.ps1 -Mode Enable
& .\tools\Startup.ps1 -Mode Disable
& .\tools\Startup.ps1 -Mode Status
```

Automatic startup waits up to 90 seconds for the taskbar and native tooltip hook. Startup failures are written to `artifacts/startup.log`; a failed launch is not reported as successful. Initialization supports Explorer starting before `SystemTray.dll` loads. A normal sleep/hibernate resume keeps the existing process; it does not require a separate scheduled task.

Install over an existing directory to upgrade; the old module is stopped first and existing language, preview, and charge-target settings are preserved. Disable startup before moving the directory, then install from its new location.

Configuration updates stage a complete file and atomically replace the INI. File-lock failures preserve the original, invalid/empty configurations are rejected, and a `.bak` file holds the previous valid configuration. Start, language, preview, and rollback scripts can read this backup if the current configuration is damaged. If neither copy is valid, `Setup.cmd` rebuilds the configuration.

Automatic startup uses one current-user `Run` registry entry; the scripts do not overwrite or remove an entry owned by another installation directory. No Windows system files are replaced and no additional hardware-reading driver is installed. Charge thresholds, power plans, and taskbar layout are preserved. Once rollback completes, the project directory can be removed.

Alternatively, create a custom mod in an existing Windhawk installation, paste `battery-tooltip.wh.cpp`, and compile it. Use Windhawk's disable toggle to roll back that installation; the project scripts manage only the bundled portable runtime.

## Compatibility

The native tooltip was validated on **Windows 11 25H2, build 26200.9457, x64**. Other Windows builds have not been validated on hardware. Automated checks cover formatting, signed charge/discharge rates, atomic configuration recovery, startup ownership, and precompiled installation. Reboot/login and sleep/hibernate cycles still require hardware verification; the stable release label does not expand the tested Windows compatibility range.

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
powershell -NoProfile -ExecutionPolicy Bypass -File tests/ConfigTests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/InstallTests.ps1
python tools/build.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Package.ps1
```

Run `Rollback.cmd` before rebuilding an active mod. Each build uses a new DLL filename and keeps the mod disabled until explicitly started.

Installing from a source checkout without `Precompiled/manifest.json` requires Python 3 and compiles locally. Downloaded release packages use the checksummed precompiled files instead.

GitHub Actions runs formatting and edge-case tests, compiles the mod, and generates a downloadable package on pushes and pull requests. A `v*` tag matching `VERSION` triggers automatic GitHub Release creation.

Use minor increments for feature enhancements, patch increments for bug fixes, and major increments when a stable product milestone is reached. Keep `VERSION` and the mod's `@version` metadata in sync; the build rejects a mismatch.

## License

MIT. Windhawk and its compiler retain their own licenses and are downloaded separately; they are excluded from the Git repository.
