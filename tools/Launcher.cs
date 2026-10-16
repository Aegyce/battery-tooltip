using System;
using System.IO;
using System.Windows.Forms;
using System.Text.RegularExpressions;

internal static class Launcher {
    [STAThread]
    private static int Main(string[] arguments) {
        string root = Directory.GetParent(AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar)).FullName;
        try {
            bool desktop = arguments.Length > 0 && arguments[0] == "--desktop";
            string mode = arguments.Length > (desktop ? 1 : 0) ? arguments[desktop ? 1 : 0] : "";
            bool startup = mode == "--start";
            bool watch = mode == "--watch";
            Match registration = Regex.Match(mode, @"^--startup-(Enable|Disable|Status):([a-f0-9]{32})$");
            if (arguments.Length > (desktop ? 2 : 1) || (mode != "" && !startup && !watch && !registration.Success)) throw new ArgumentException("Unknown launch argument.");
            if (!desktop) {
                DateTime deadline = DateTime.UtcNow.AddSeconds(startup ? 90 : 0);
                while (true) {
                    try {
                        BatteryTooltip.NativeProcess.StartViaDesktop(Path.Combine(root, @"tools\BatteryTooltip.exe"), "--desktop " + mode, root);
                        break;
                    } catch {
                        if (DateTime.UtcNow >= deadline) throw;
                        System.Threading.Thread.Sleep(500);
                    }
                }
                return 0;
            }
            Environment.SetEnvironmentVariable("BATTERY_TOOLTIP_DESKTOP_ROOT", root);
            if (watch) return BatteryTooltip.RuntimeWatch.Run(root);
            string shell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe");
            string script = Path.Combine(root, registration.Success ? @"tools\StartupWorker.ps1" : startup ? @"tools\Start.ps1" : @"tools\Manage.ps1");
            string command = "-NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\"";
            if (startup) command += " -TimeoutSeconds 90 -Quiet";
            if (registration.Success) command += " -Mode " + registration.Groups[1].Value + " -Token " + registration.Groups[2].Value;
            BatteryTooltip.NativeProcess.StartDetached(shell, command, root, !startup && !registration.Success);
            return 0;
        } catch (Exception error) {
            try {
                Directory.CreateDirectory(Path.Combine(root, "artifacts"));
                File.AppendAllText(Path.Combine(root, @"artifacts\launcher.log"), DateTimeOffset.Now.ToString("o") + " " + error + Environment.NewLine);
            } catch { }
            if (arguments.Length == 0) MessageBox.Show(error.Message, "Battery Tooltip", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
