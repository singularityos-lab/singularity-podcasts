namespace Singularity.Apps.Podcasts {

    public enum SleepMode {
        OFF,
        MINUTES,
        END_OF_EPISODE,
        END_OF_CHAPTER
    }

    public class SleepTimer : Object {
        public const int FADE_SECONDS = 30;
        public const int[] PRESETS = { 15, 30, 45, 60 };

        public delegate double LeftFunc ();

        public SleepMode mode { get; private set; default = SleepMode.OFF; }
        public double level { get; private set; default = 1.0; }
        public bool active { get { return mode != SleepMode.OFF; } }

        private int64 deadline;
        private LeftFunc? left_func;
        private uint tick_id;
        private bool driven;

        public signal void changed ();
        public signal void expired ();

        public SleepTimer (bool driven = true) {
            this.driven = driven;
        }

        public static int64 now () {
            return get_monotonic_time ();
        }

        public void start_minutes (int minutes, int64 at = -1) {
            if (at < 0) at = now ();
            stop_ticking ();
            left_func = null;
            mode = SleepMode.MINUTES;
            deadline = at + (int64) minutes.clamp (1, 24 * 60) * 60 * TimeSpan.SECOND;
            level = 1.0;
            start_ticking ();
            changed ();
        }

        public void start_track (SleepMode track_mode, owned LeftFunc left) {
            if (track_mode != SleepMode.END_OF_EPISODE && track_mode != SleepMode.END_OF_CHAPTER) return;
            stop_ticking ();
            left_func = (owned) left;
            mode = track_mode;
            level = 1.0;
            start_ticking ();
            changed ();
        }

        public void cancel () {
            if (mode == SleepMode.OFF) return;
            stop_ticking ();
            mode = SleepMode.OFF;
            left_func = null;
            level = 1.0;
            changed ();
        }

        public void finish () {
            if (mode == SleepMode.OFF) return;
            expire ();
        }

        private double left_seconds (int64 at) {
            if (mode == SleepMode.MINUTES) return (double) (deadline - at) / TimeSpan.SECOND;
            if (left_func != null) return left_func ();
            return -1;
        }

        public int remaining (int64 at = -1) {
            if (at < 0) at = now ();
            if (mode == SleepMode.OFF) return -1;
            double left = left_seconds (at);
            if (left < 0 && mode != SleepMode.MINUTES) return -1;
            return (int) Math.ceil (double.max (left, 0));
        }

        public bool update (int64 at) {
            if (mode == SleepMode.OFF) return false;
            double left = left_seconds (at);
            if (left < 0 && mode != SleepMode.MINUTES) {
                level = 1.0;
                return false;
            }
            level = fade_level (left, FADE_SECONDS);
            if (mode == SleepMode.END_OF_EPISODE) return false;
            if (left > (mode == SleepMode.MINUTES ? 0.0 : 0.25)) return false;
            expire ();
            return true;
        }

        private void expire () {
            stop_ticking ();
            mode = SleepMode.OFF;
            left_func = null;
            expired ();
            if (mode == SleepMode.OFF) level = 1.0;
            changed ();
        }

        public static double fade_level (double left, int fade_seconds) {
            if (left <= 0) return 0.0;
            if (left >= fade_seconds) return 1.0;
            return left / fade_seconds;
        }

        public static string format (int seconds) {
            if (seconds < 0) seconds = 0;
            int h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60;
            if (h > 0) return "%d:%02d:%02d".printf (h, m, s);
            return "%d:%02d".printf (m, s);
        }

        private void start_ticking () {
            if (!driven) return;
            tick_id = Timeout.add (250, () => {
                uint id = tick_id;
                tick_id = 0;
                if (update (now ()) || mode == SleepMode.OFF) return Source.REMOVE;
                tick_id = id;
                changed ();
                return Source.CONTINUE;
            });
        }

        private void stop_ticking () {
            if (tick_id != 0) Source.remove (tick_id);
            tick_id = 0;
        }
    }
}
