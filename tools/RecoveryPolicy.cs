using System;
using System.Collections.Generic;

namespace BatteryTooltip {
    public enum RecoveryAction { None, Start, Restart, Stop }

    public sealed class RecoveryPolicy {
        private readonly Queue<DateTime> attempts = new Queue<DateTime>();
        private DateTime nextAttempt = DateTime.MinValue;
        private DateTime? unreadySince;
        private bool failedRecovery;
        public bool Throttled { get; private set; }
        public void WorkerFailed() { failedRecovery = true; }

        public RecoveryAction Evaluate(DateTime now, bool? enabled, bool autoRecover, bool running, bool ready, bool resumed) {
            if (enabled == false || !autoRecover) return RecoveryAction.Stop;
            // An unreadable/partial configuration is never permission to start.
            if (enabled == null) return RecoveryAction.None;
            while (attempts.Count > 0 && now - attempts.Peek() >= TimeSpan.FromMinutes(10)) attempts.Dequeue();
            Throttled = attempts.Count >= 3;
            if (resumed) unreadySince = now;
            if (running && ready) { unreadySince = null; failedRecovery = false; return RecoveryAction.None; }
            if (running && !failedRecovery) {
                if (unreadySince == null) unreadySince = now;
                if (now - unreadySince.Value < TimeSpan.FromSeconds(90)) return RecoveryAction.None;
            }
            if (Throttled || now < nextAttempt) return RecoveryAction.None;
            attempts.Enqueue(now);
            nextAttempt = now.AddSeconds(10 * attempts.Count);
            unreadySince = now;
            failedRecovery = false;
            return running ? RecoveryAction.Restart : RecoveryAction.Start;
        }
    }
}
