using System;
using System.Windows.Forms;

namespace BatteryTooltip {
    // A hidden top-level window receives power broadcasts even when nobody
    // interacts with the desktop. Message-only windows do not receive broadcasts.
    public sealed class PowerNotificationWindow : NativeWindow, IDisposable {
        public const string WindowTitle = "BatteryTooltip.PowerNotifications";
        private readonly Action resume;

        public PowerNotificationWindow(Action resume) {
            if (resume == null) throw new ArgumentNullException("resume");
            this.resume = resume;
            CreateHandle(new CreateParams { Caption = WindowTitle, Parent = IntPtr.Zero,
                Style = unchecked((int)0x80000000), ExStyle = 0x80 }); // Hidden WS_POPUP / WS_EX_TOOLWINDOW
        }

        protected override void WndProc(ref Message message) {
            if (message.Msg == 0x218) { // WM_POWERBROADCAST
                long powerEvent = message.WParam.ToInt64();
                if (powerEvent == 18 || powerEvent == 7 || powerEvent == 6) {
                    // Automatic, user-initiated, and critical resume respectively.
                    // SystemEvents.PowerModeChanged omits the automatic event.
                    resume();
                    message.Result = new IntPtr(1);
                    return;
                }
            }
            base.WndProc(ref message);
        }

        public void Dispose() { DestroyHandle(); }
    }
}
