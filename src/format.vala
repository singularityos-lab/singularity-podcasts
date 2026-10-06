namespace Singularity.Apps.Podcasts {

    namespace Format {
        public string clock (int64 seconds) {
            if (seconds < 0) seconds = 0;
            int h = (int) (seconds / 3600), m = (int) ((seconds % 3600) / 60), s = (int) (seconds % 60);
            if (h > 0) return "%d:%02d:%02d".printf (h, m, s);
            return "%d:%02d".printf (m, s);
        }

        public string length (int seconds) {
            if (seconds <= 0) return "";
            int minutes = (seconds + 30) / 60;
            if (minutes < 1) return _("Under a minute");
            if (minutes < 60) return ngettext ("%d min", "%d min", minutes).printf (minutes);
            int h = minutes / 60, m = minutes % 60;
            if (m == 0) return ngettext ("%d hr", "%d hr", h).printf (h);
            return _("%d hr %d min").printf (h, m);
        }

        public string remaining (int seconds) {
            if (seconds <= 0) return "";
            return _("%s left").printf (length (seconds));
        }

        public string speed (double rate) {
            char[] buf = new char[16];
            string s = rate.format (buf, "%.2f");
            while (s.has_suffix ("0")) s = s.substring (0, s.length - 1);
            if (s.has_suffix (".")) s = s.substring (0, s.length - 1);
            return s.replace (",", ".") + "x";
        }

        public string date (int64 stamp, DateTime? now_ref = null) {
            if (stamp <= 0) return "";
            var now = (now_ref ?? new DateTime.now_local ()).to_local ();
            var d = new DateTime.from_unix_local (stamp);
            var today = new DateTime.local (now.get_year (), now.get_month (), now.get_day_of_month (), 0, 0, 0);
            var day = new DateTime.local (d.get_year (), d.get_month (), d.get_day_of_month (), 0, 0, 0);
            int64 diff = today.difference (day) / TimeSpan.DAY;
            if (diff == 0) return _("Today");
            if (diff == 1) return _("Yesterday");
            if (diff > 1 && diff < 7) return d.format ("%A");
            if (d.get_year () == now.get_year ()) return d.format ("%-d %B");
            return d.format ("%-d %B %Y");
        }
    }
}
