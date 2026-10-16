using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace BatteryTooltip {
    public static class RuntimeWatch {
        public static string Identity(string root) {
            using (var hash = SHA256.Create())
                return BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(Path.GetFullPath(root).TrimEnd('\\').ToLowerInvariant()))).Replace("-", "");
        }
        public static int Run(string root) {
            string identity = Identity(root);
            using (var mutex = new Mutex(false, @"Local\BatteryTooltip.Watch." + identity)) {
                bool owned;
                try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
                if (!owned) return 0;
                try {
                    using (var stop = new EventWaitHandle(false, EventResetMode.ManualReset, @"Local\BatteryTooltip.WatchStop." + identity))
                    using (var context = new WatchContext(root, stop)) Application.Run(context);
                } finally { mutex.ReleaseMutex(); }
            }
            return 0;
        }
        private sealed class WatchContext : ApplicationContext {
            private readonly string root, runtimePath, configPath, storagePath;
            private readonly EventWaitHandle stop;
            private readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
            private readonly RecoveryPolicy policy = new RecoveryPolicy();
            private readonly PowerNotificationWindow powerWindow;
            private Process runtime;
            private Process recoveryWorker;
            private int resumed;
            private bool disposed;
            private string lastProblem = "";
            [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindow(string name, string title);
            [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint owner);
            public WatchContext(string root, EventWaitHandle stop) {
                this.root = root; this.stop = stop;
                runtimePath = Path.Combine(root, @"runtime\windhawk\windhawk.exe");
                configPath = Path.Combine(root, @"runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini");
                storagePath = Path.Combine(root, @"runtime\windhawk\AppData\Engine\ModsWritable\local@battery-tooltip.ini");
                powerWindow = new PowerNotificationWindow(delegate { Interlocked.Exchange(ref resumed, 1); });
                timer.Interval = 2000;
                timer.Tick += Tick;
                timer.Start();
                Log("Monitor started: pid=" + Process.GetCurrentProcess().Id);
            }
            private static string Value(string text, string name) {
                return Regex.Match(text, @"(?m)^" + Regex.Escape(name) + @"=([^\r\n]*)").Groups[1].Value.Trim();
            }
            private void Log(string message) {
                try {
                    string directory = Path.Combine(root, "artifacts");
                    Directory.CreateDirectory(directory);
                    string log = Path.Combine(directory, "runtime-watch.log");
                    if (File.Exists(log) && new FileInfo(log).Length > 1048576) {
                        if (File.Exists(log + ".1")) File.Delete(log + ".1");
                        File.Move(log, log + ".1");
                    }
                    File.AppendAllText(log, DateTimeOffset.Now.ToString("o") + " " + message + Environment.NewLine);
                } catch { }
            }
            private void Problem(string text) { if (text != lastProblem) { Log(text); lastProblem = text; } }
            private void Tick(object sender, EventArgs args) {
                if (stop.WaitOne(0)) { ExitThread(); return; }
                try {
                    if (recoveryWorker != null) {
                        if (!recoveryWorker.HasExited) return;
                        Log("Recovery worker completed: exitCode=" + recoveryWorker.ExitCode);
                        if (recoveryWorker.ExitCode != 0) policy.WorkerFailed();
                        recoveryWorker.Dispose(); recoveryWorker = null;
                    }
                    string config = File.ReadAllText(configPath);
                    string disabled = Value(config, "Disabled");
                    bool? enabled = disabled == "0" ? true : disabled == "1" ? false : (bool?)null;
                    // Optional portable-runtime setting; missing means enabled.
                    bool autoRecover = Value(config, "autoRecover") != "0";
                    if (enabled == false || !autoRecover) { Log("Monitor stopped by configuration"); ExitThread(); return; }
                    if (enabled == null) { Problem("Configuration invalid; recovery suspended"); return; }
                    bool resume = Interlocked.Exchange(ref resumed, 0) != 0;
                    if (resume) Log("Resume received; checking runtime and hook");
                    if (runtime != null && runtime.HasExited) {
                        Log("Runtime exited: pid=" + runtime.Id + " exitCode=" + runtime.ExitCode);
                        runtime.Dispose(); runtime = null;
                    }
                    if (runtime == null) {
                        int session = Process.GetCurrentProcess().SessionId;
                        foreach (Process candidate in Process.GetProcessesByName("windhawk")) {
                            bool match = false;
                            try { match = candidate.SessionId == session && string.Equals(candidate.MainModule.FileName, runtimePath, StringComparison.OrdinalIgnoreCase); }
                            catch { }
                            if (match && runtime == null) { runtime = candidate; IntPtr handle = runtime.Handle; Log("Tracking runtime: pid=" + runtime.Id); }
                            else candidate.Dispose();
                        }
                    }
                    bool ready = false;
                    if (runtime != null) {
                        string storage = "";
                        try { storage = File.ReadAllText(storagePath); } catch (IOException) { }
                        uint owner;
                        GetWindowThreadProcessId(FindWindow("Shell_TrayWnd", null), out owner);
                        ready = owner != 0 && Value(storage, "runtimeStatus") == "ready" && Value(storage, "runtimeProcessId") == owner.ToString();
                    }
                    RecoveryAction action = policy.Evaluate(DateTime.UtcNow, enabled, autoRecover, runtime != null, ready, resume);
                    if (action == RecoveryAction.None) {
                        if (policy.Throttled && !ready) Problem("Recovery throttled: three attempts in ten minutes; waiting before retry");
                        else if (ready) lastProblem = "";
                        return;
                    }
                    // Stop is checked again after observation, immediately before launch.
                    if (stop.WaitOne(0) || Value(File.ReadAllText(configPath), "Disabled") != "0") return;
                    string shell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe");
                    string command = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + Path.Combine(root, @"tools\Recover.ps1") + "\"";
                    var start = new ProcessStartInfo(shell, command) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = root };
                    recoveryWorker = Process.Start(start);
                    IntPtr workerHandle = recoveryWorker.Handle;
                    Log("Recovery " + action + ": worker=" + recoveryWorker.Id);
                } catch (FileNotFoundException) { Problem("Configuration or runtime missing; monitor exiting"); ExitThread(); }
                catch (Exception error) { Problem("Recovery error: " + error.Message); }
            }
            protected override void Dispose(bool disposing) {
                if (disposing && !disposed) {
                    disposed = true;
                    timer.Stop(); timer.Dispose();
                    powerWindow.Dispose();
                    if (recoveryWorker != null) {
                        try { if (!recoveryWorker.HasExited) { recoveryWorker.Kill(); recoveryWorker.WaitForExit(5000); } }
                        catch (Exception error) { Log("Recovery worker cleanup: " + error.Message); }
                        recoveryWorker.Dispose();
                    }
                    if (runtime != null) runtime.Dispose();
                    Log("Monitor exited");
                }
                base.Dispose(disposing);
            }
        }
    }
}
