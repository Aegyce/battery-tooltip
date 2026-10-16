using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class NativeProcessTests {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo {
        public int Size;
        public IntPtr Reserved, Desktop, Title;
        public int X, Y, XSize, YSize, XCountChars, YCountChars, FillAttribute;
        public uint Flags;
        public short ShowWindow, ReservedSize;
        public IntPtr ReservedData, Input, Output, Error;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation { public IntPtr Process, Thread; public uint ProcessId, ThreadId; }
    [DllImport("kernel32.dll")] private static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern void GetStartupInfo(out StartupInfo startup);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindow(string name, string title);
    [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool QueryInformationJobObject(IntPtr job, int infoClass, IntPtr data, uint length, out uint returned);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr data, uint length);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcess(string application, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes,
        bool inheritHandles, uint flags, IntPtr environment, string directory, ref StartupInfo startup, out ProcessInformation info);
    [DllImport("kernel32.dll")] private static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);

    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static void WaitFor(string path) {
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!File.Exists(path) && DateTime.UtcNow < deadline) Thread.Sleep(50);
        Check(File.Exists(path), "Timed out waiting for " + path);
    }
    private static void Probe(string root, string name) {
        bool inJob;
        Check(IsProcessInJob(GetCurrentProcess(), IntPtr.Zero, out inJob), "Cannot query job membership");
        uint limits = 0;
        IntPtr data = Marshal.AllocHGlobal(144);
        try {
            uint returned;
            if (inJob) {
                Check(QueryInformationJobObject(IntPtr.Zero, 9, data, 144, out returned), "Cannot query job limits");
                limits = (uint)Marshal.ReadInt32(data, 16);
            }
        } finally { Marshal.FreeHGlobal(data); }
        string path = Path.Combine(root, name);
        StartupInfo startup;
        GetStartupInfo(out startup);
        File.WriteAllText(path + ".tmp", Process.GetCurrentProcess().Id + "|" + inJob + "|" + (GetConsoleWindow() != IntPtr.Zero) + "|" + limits + "|" + startup.ShowWindow + "|" + startup.Flags);
        File.Move(path + ".tmp", path);
        Thread.Sleep(30000);
    }
    private static int Main(string[] arguments) {
        try { return Run(arguments); }
        catch (Exception error) {
            string detail = error.GetType().FullName + ": " + error.Message + "\n" + error.StackTrace;
            File.WriteAllText(Path.Combine(arguments[0], "failure-" + Process.GetCurrentProcess().Id + ".txt"), detail);
            Console.Error.WriteLine(detail);
            return 1;
        }
    }
    private static int Run(string[] arguments) {
        string root = arguments[0];
        string self = typeof(NativeProcessTests).Assembly.Location;
        if (arguments.Length > 1) {
            if (arguments[1] == "--probe") { Probe(root, "detached.txt"); return 0; }
            if (arguments[1] == "--visible-probe") { Probe(root, "visible.txt"); return 0; }
            if (arguments[1] == "--desktop-probe") { Probe(root, "desktop.txt"); return 0; }
            // Control process uses the previous Start-Process behavior.
            var start = new ProcessStartInfo(self, "\"" + root + "\" --control") { UseShellExecute = false, CreateNoWindow = true };
            if (arguments[1] == "--owner") {
                using (Process control = Process.Start(start)) { }
                BatteryTooltip.NativeProcess.StartDetached(self, "\"" + root + "\" --probe", root);
                BatteryTooltip.NativeProcess.StartDetached(self, "\"" + root + "\" --visible-probe", root, true);
                if (FindWindow("Shell_TrayWnd", null) != IntPtr.Zero)
                    BatteryTooltip.NativeProcess.StartViaDesktop(Path.Combine(root, "GUI fixture.exe"), "\"" + root + "\" --desktop-probe", root);
                Thread.Sleep(30000);
            } else { Probe(root, "control.txt"); }
            return 0;
        }
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        IntPtr data = Marshal.AllocHGlobal(144);
        Process detached = null, controlProcess = null, desktopProcess = null, visibleProcess = null;
        var info = new ProcessInformation();
        try {
            for (int i = 0; i < 144; i++) Marshal.WriteByte(data, i, 0);
            Marshal.WriteInt32(data, 16, 0x2800); // KILL_ON_JOB_CLOSE | BREAKAWAY_OK
            Check(SetInformationJobObject(job, 9, data, 144), "Cannot configure test job");
            var startup = new StartupInfo { Size = Marshal.SizeOf(typeof(StartupInfo)) };
            Check(CreateProcess(self, new StringBuilder("\"" + self + "\" \"" + root + "\" --owner"), IntPtr.Zero, IntPtr.Zero,
                false, 0x08000004, IntPtr.Zero, root, ref startup, out info), "Cannot start fixture owner");
            Check(AssignProcessToJobObject(job, info.Process), "Cannot assign fixture owner to job");
            ResumeThread(info.Thread);
            WaitFor(Path.Combine(root, "detached.txt"));
            WaitFor(Path.Combine(root, "control.txt"));
            WaitFor(Path.Combine(root, "visible.txt"));
            bool hasDesktop = FindWindow("Shell_TrayWnd", null) != IntPtr.Zero;
            if (hasDesktop) WaitFor(Path.Combine(root, "desktop.txt"));
            string[] result = File.ReadAllText(Path.Combine(root, "detached.txt")).Split('|');
            string[] previous = File.ReadAllText(Path.Combine(root, "control.txt")).Split('|');
            string[] visible = File.ReadAllText(Path.Combine(root, "visible.txt")).Split('|');
            string[] desktop = hasDesktop ? File.ReadAllText(Path.Combine(root, "desktop.txt")).Split('|') : null;
            detached = Process.GetProcessById(int.Parse(result[0]));
            controlProcess = Process.GetProcessById(int.Parse(previous[0]));
            visibleProcess = Process.GetProcessById(int.Parse(visible[0]));
            if (hasDesktop) desktopProcess = Process.GetProcessById(int.Parse(desktop[0]));
            bool inFixtureJob;
            Check(IsProcessInJob(detached.Handle, job, out inFixtureJob) && !inFixtureJob, "Detached process inherited the launcher's job");
            Check(result[2] == "False", "Detached process acquired a console");
            Check(result[4] == "0" && (uint.Parse(result[5]) & 1) != 0, "Background workers lost their hidden initial show state");
            Check(visible[4] == "1" && (uint.Parse(visible[5]) & 1) != 0, "Manager inherited SW_HIDE and would delay its taskbar button until activation");
            Check(visible[2] == "False", "Visible GUI startup acquired a console");
            Check(previous[1] == "True", "Control process did not inherit its parent's job");
            if (hasDesktop) {
                Check(IsProcessInJob(desktopProcess.Handle, job, out inFixtureJob) && !inFixtureJob, "Desktop process inherited the launcher's job");
                Check((uint.Parse(desktop[3]) & 0x2000) == 0, "Desktop process retained an outer kill-on-close job");
                Check(desktop[2] == "False", "GUI process acquired a console");
            }
            CloseHandle(job); job = IntPtr.Zero;
            Check(controlProcess.WaitForExit(5000), "Previous startup behavior survived job closure unexpectedly");
            Check(!detached.WaitForExit(500), "Detached process died with its launcher's job");
            Check(!visibleProcess.WaitForExit(500), "Manager process died with its launcher's job");
            if (hasDesktop) Check(!desktopProcess.WaitForExit(500), "Desktop process died with its launcher's job");
            Console.WriteLine(hasDesktop ? "13 native process checks passed: consoles absent, GUI startup visible, previous termination reproduced, desktop launch independent of both parent jobs."
                : "9 native process checks passed; 4 desktop integration checks skipped (no interactive desktop).");
            return 0;
        } finally {
            if (job != IntPtr.Zero) CloseHandle(job);
            if (info.Thread != IntPtr.Zero) CloseHandle(info.Thread);
            if (info.Process != IntPtr.Zero) CloseHandle(info.Process);
            Marshal.FreeHGlobal(data);
            if (detached != null) { if (!detached.HasExited) detached.Kill(); detached.Dispose(); }
            if (controlProcess != null) controlProcess.Dispose();
            if (desktopProcess != null) { if (!desktopProcess.HasExited) desktopProcess.Kill(); desktopProcess.Dispose(); }
            if (visibleProcess != null) { if (!visibleProcess.HasExited) visibleProcess.Kill(); visibleProcess.Dispose(); }
        }
    }
}
