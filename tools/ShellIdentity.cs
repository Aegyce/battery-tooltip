using System;
using System.IO;
using System.Runtime.InteropServices;

namespace BatteryTooltip {
    public static class ShellIdentity {
        public const string AppId = "Aegyce.BatteryTooltip.Manager";
        private static readonly Guid PropertySet = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
        private static readonly Guid StoreId = typeof(IPropertyStore).GUID;

        [StructLayout(LayoutKind.Sequential)]
        private struct PropertyKey {
            public Guid Format;
            public uint Id;
            public PropertyKey(uint id) { Format = PropertySet; Id = id; }
        }

        // PROPVARIANT's union occupies two pointer-sized slots on both x86 and x64.
        [StructLayout(LayoutKind.Sequential)]
        private struct PropVariant : IDisposable {
            public ushort Type, Reserved1, Reserved2, Reserved3;
            public IntPtr Value, Padding;
            public PropVariant(string value) {
                Type = value == null ? (ushort)0 : (ushort)31; // VT_EMPTY / VT_LPWSTR
                Reserved1 = Reserved2 = Reserved3 = 0;
                Value = value == null ? IntPtr.Zero : Marshal.StringToCoTaskMemUni(value);
                Padding = IntPtr.Zero;
            }
            public void Dispose() { PropVariantClear(ref this); }
        }

        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore {
            void GetCount(out uint count);
            void GetAt(uint index, out PropertyKey key);
            void GetValue(ref PropertyKey key, out PropVariant value);
            void SetValue(ref PropertyKey key, ref PropVariant value);
            void Commit();
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void SetCurrentProcessExplicitAppUserModelID(string appId);
        [DllImport("shell32.dll", PreserveSig = false)]
        private static extern void SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, out IPropertyStore store);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void SHGetPropertyStoreFromParsingName(string path, IntPtr context, uint flags, ref Guid iid, out IPropertyStore store);
        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(ref PropVariant value);

        public static void InitializeProcess() { SetCurrentProcessExplicitAppUserModelID(AppId); }

        private static IPropertyStore WindowStore(IntPtr window) {
            Guid iid = StoreId;
            IPropertyStore store;
            SHGetPropertyStoreForWindow(window, ref iid, out store);
            return store;
        }

        private static IPropertyStore ShortcutStore(string path, bool write) {
            Guid iid = StoreId;
            IPropertyStore store;
            SHGetPropertyStoreFromParsingName(Path.GetFullPath(path), IntPtr.Zero, write ? 2u : 0u, ref iid, out store);
            return store;
        }

        private static void Set(IPropertyStore store, uint id, string text) {
            PropertyKey key = new PropertyKey(id);
            PropVariant value = new PropVariant(text);
            try { store.SetValue(ref key, ref value); }
            finally { value.Dispose(); }
        }

        private static string Get(IPropertyStore store, uint id) {
            PropertyKey key = new PropertyKey(id);
            PropVariant value;
            store.GetValue(ref key, out value);
            try { return value.Type == 31 ? Marshal.PtrToStringUni(value.Value) : null; }
            finally { value.Dispose(); }
        }

        public static void ConfigureWindow(IntPtr window, string root) {
            IPropertyStore store = WindowStore(window);
            try {
                // Portable launches also need relaunch metadata: no installed shortcut is required.
                // Apply relaunch properties before the ID so Explorer sees a complete identity.
                Set(store, 2, "\"" + Path.Combine(root, @"tools\BatteryTooltip.exe") + "\"");
                Set(store, 3, Path.Combine(root, @"assets\battery-tooltip.ico") + ",0");
                Set(store, 4, "Battery Tooltip");
                Set(store, 5, AppId);
            } finally { Marshal.ReleaseComObject(store); }
        }

        public static void ClearWindow(IntPtr window) {
            IPropertyStore store = WindowStore(window);
            try { foreach (uint id in new uint[] { 5, 2, 3, 4 }) Set(store, id, null); }
            finally { Marshal.ReleaseComObject(store); }
        }

        public static void ConfigureShortcut(string path) {
            IPropertyStore store = ShortcutStore(path, true);
            try { Set(store, 5, AppId); store.Commit(); }
            finally { Marshal.ReleaseComObject(store); }
        }

        public static string GetShortcutAppId(string path) {
            IPropertyStore store = ShortcutStore(path, false);
            try { return Get(store, 5); }
            finally { Marshal.ReleaseComObject(store); }
        }

        public static string GetWindowProperty(IntPtr window, uint id) {
            IPropertyStore store = WindowStore(window);
            try { return Get(store, id); }
            finally { Marshal.ReleaseComObject(store); }
        }
    }
}
