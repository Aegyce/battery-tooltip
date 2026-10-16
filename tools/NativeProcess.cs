using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace BatteryTooltip {
    public static class NativeProcess {
        public static void StartViaDesktop(string path, string arguments, string directory) {
            // Use the desktop's automation object, not a new Shell.Application
            // instance: only the desktop actually launches from Explorer.
            object shell = null, windows = null, desktop = null, document = null, application = null;
            try {
                shell = Activator.CreateInstance(Type.GetTypeFromProgID("Shell.Application"));
                windows = ((dynamic)shell).Windows();
                object location = 0, root = 0;
                int window;
                desktop = ((dynamic)windows).FindWindowSW(ref location, ref root, 8, out window, 1);
                if (desktop == null) throw new InvalidOperationException("The Windows desktop is not ready. Try again after signing in.");
                document = ((dynamic)desktop).Document;
                application = ((dynamic)document).Application;
                ((dynamic)application).ShellExecute(path, arguments, directory, "open", 0);
            } finally {
                foreach (object item in new[] { application, document, desktop, windows, shell })
                    if (item != null && Marshal.IsComObject(item)) Marshal.ReleaseComObject(item);
            }
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct StartupInfo {
            public int Size;
            public string Reserved, Desktop, Title;
            public int X, Y, XSize, YSize, XCountChars, YCountChars, FillAttribute;
            public uint Flags;
            public short ShowWindow, ReservedSize;
            public IntPtr ReservedData, Input, Output, Error;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInformation {
            public IntPtr Process, Thread;
            public uint ProcessId, ThreadId;
        }
        [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool QueryInformationJobObject(IntPtr job, int infoClass, IntPtr buffer, uint length, out uint returned);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateProcess(string application, StringBuilder command, IntPtr processAttributes,
            IntPtr threadAttributes, bool inheritHandles, uint flags, IntPtr environment, string directory,
            ref StartupInfo startup, out ProcessInformation information);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);

        public static uint StartDetached(string path, string arguments, string directory) {
            return StartDetached(path, arguments, directory, false);
        }

        public static uint StartDetached(string path, string arguments, string directory, bool showWindow) {
            // Hidden windows alone still inherit a launcher's job. A temporary
            // task can then terminate the long-lived runtime when its job closes.
            uint flags = 0x08000000; // CREATE_NO_WINDOW
            bool inJob;
            if (!IsProcessInJob(GetCurrentProcess(), IntPtr.Zero, out inJob))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if (inJob) {
                IntPtr buffer = Marshal.AllocHGlobal(144);
                try {
                    uint returned;
                    if (!QueryInformationJobObject(IntPtr.Zero, 9, buffer, 144, out returned))
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    uint limits = (uint)Marshal.ReadInt32(buffer, 16);
                    if ((limits & 0x800) != 0) flags |= 0x01000000; // BREAKAWAY_OK
                    else if ((limits & 0x2000) != 0 && (limits & 0x1000) == 0)
                        throw new InvalidOperationException("This launcher cannot start an independent background process. Open Battery Tooltip from the Start menu.");
                } finally { Marshal.FreeHGlobal(buffer); }
            }
            // CREATE_NO_WINDOW suppresses the console independently of the GUI's
            // initial show state. SW_HIDE delays WPF's taskbar button until activation.
            var startup = new StartupInfo { Size = Marshal.SizeOf(typeof(StartupInfo)), Flags = 1, ShowWindow = (short)(showWindow ? 1 : 0) };
            ProcessInformation information;
            if (!CreateProcess(path, new StringBuilder("\"" + path + "\" " + arguments), IntPtr.Zero,
                IntPtr.Zero, false, flags, IntPtr.Zero, directory, ref startup, out information))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            try { return information.ProcessId; }
            finally { CloseHandle(information.Thread); CloseHandle(information.Process); }
        }
    }
}
