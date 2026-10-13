using System;
using System.Runtime.InteropServices;
class Symbols {
    [DllImport("dbghelp.dll", CharSet=CharSet.Unicode)] static extern bool SymInitializeW(IntPtr process, string path, bool invade);
    [DllImport("dbghelp.dll")] static extern uint SymSetOptions(uint options);
    [DllImport("dbghelp.dll", CharSet=CharSet.Unicode)] static extern ulong SymLoadModuleExW(IntPtr process, IntPtr file, string image, string module, ulong address, uint size, IntPtr data, uint flags);
    delegate bool Callback(IntPtr info, uint size, IntPtr context);
    [DllImport("dbghelp.dll", CharSet=CharSet.Unicode)] static extern bool SymEnumSymbolsW(IntPtr process, ulong baseAddress, string mask, Callback callback, IntPtr context);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("dbghelp.dll")] static extern bool SymCleanup(IntPtr process);
    static void Main(string[] args) {
        IntPtr p = GetCurrentProcess();
        SymSetOptions(0x10 | 0x80000000);
        Console.WriteLine("init=" + SymInitializeW(p, args[1], false));
        ulong b = SymLoadModuleExW(p, IntPtr.Zero, args[0], null, 0, 0, IntPtr.Zero, 0);
        Console.WriteLine("base=" + b.ToString("X"));
        Callback cb = (info, size, context) => {
            int len = Marshal.ReadInt32(info, 76);
            string name = Marshal.PtrToStringUni(IntPtr.Add(info, 84), len).TrimEnd('\0');
            Console.WriteLine(Marshal.ReadInt64(info, 56).ToString("X") + " " + name);
            return true;
        };
        Console.WriteLine("enum=" + SymEnumSymbolsW(p, b, args.Length > 2 ? args[2] : "*", cb, IntPtr.Zero));
        SymCleanup(p);
    }
}
