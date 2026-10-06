namespace Singularity.Apps.Podcasts {

    public class SilenceSkipper : Object {
        public double threshold_db = -45.0;
        public int64 min_silence = 600 * Gst.MSECOND;
        public int64 step = 500 * Gst.MSECOND;
        private int64 silent_since = -1;

        public void reset () {
            silent_since = -1;
        }

        public int64 feed (double loudest_db, int64 position) {
            if (loudest_db > threshold_db) {
                silent_since = -1;
                return -1;
            }
            if (silent_since < 0 || position < silent_since) {
                silent_since = position;
                return -1;
            }
            if (position - silent_since < min_silence) return -1;
            silent_since = -1;
            return position + step;
        }
    }

    namespace Effects {
        public const string BIN_NAME = "podcasts-effects";
        public const int TRIM_THRESHOLD_DB = -40;
        public const int64 TRIM_MIN_SILENCE = 400 * Gst.MSECOND;
        public const double[] VOICE_FREQS = { 90.0, 250.0, 3000.0, 6500.0 };
        public const double[] VOICE_GAINS = { -8.0, -2.0, 4.0, 2.0 };
        public const double[] VOICE_WIDTHS = { 80.0, 200.0, 2000.0, 3000.0 };

        public bool has (string factory) {
            return Gst.ElementFactory.find (factory) != null;
        }

        public string[] plan (bool trim, bool boost, bool can_remove_silence) {
            string[] names = {};
            if (trim) {
                if (can_remove_silence) {
                    names += "audioconvert";
                    names += "capsfilter";
                    names += "removesilence";
                } else {
                    names += "level";
                }
            }
            if (boost) {
                names += "audioconvert";
                names += "equalizer-nbands";
                names += "audiodynamic";
                names += "volume";
            }
            names += "audioconvert";
            names += "scaletempo";
            return names;
        }

        private Gst.Element make (string factory) throws Error {
            var e = Gst.ElementFactory.make (factory, null);
            if (e == null) throw new IOError.NOT_SUPPORTED (_("The GStreamer element %s is missing.").printf (factory));
            return e;
        }

        public Gst.Element build (bool trim, bool boost, out bool level_fallback) throws Error {
            level_fallback = false;
            bool can_remove = has ("removesilence");
            if (trim && !can_remove) level_fallback = true;
            var bin = new Gst.Bin (BIN_NAME);
            Gst.Element? first = null;
            Gst.Element? last = null;
            foreach (string factory in plan (trim, boost, can_remove)) {
                var e = make (factory);
                switch (factory) {
                    case "capsfilter":
                        e.set ("caps", Gst.Caps.from_string ("audio/x-raw,format=S16LE,channels=1"));
                        e.name = "trim-caps";
                        break;
                    case "removesilence":
                        e.set ("remove", true);
                        e.set ("squash", true);
                        e.set ("threshold", TRIM_THRESHOLD_DB);
                        e.set ("minimum-silence-time", (uint64) TRIM_MIN_SILENCE);
                        e.name = "trim";
                        break;
                    case "level":
                        e.set ("post-messages", true);
                        e.set ("interval", (uint64) (100 * Gst.MSECOND));
                        e.name = "trim-level";
                        break;
                    case "equalizer-nbands":
                        e.set ("num-bands", VOICE_FREQS.length);
                        var proxy = (Gst.ChildProxy) e;
                        for (int i = 0; i < VOICE_FREQS.length; i++) {
                            var band = proxy.get_child_by_index (i);
                            band.set ("freq", VOICE_FREQS[i]);
                            band.set ("bandwidth", VOICE_WIDTHS[i]);
                            band.set ("gain", VOICE_GAINS[i]);
                        }
                        e.name = "voice-eq";
                        break;
                    case "audiodynamic":
                        Gst.Util.set_object_arg (e, "characteristics", "soft-knee");
                        Gst.Util.set_object_arg (e, "mode", "compressor");
                        e.set ("threshold", 0.18f);
                        e.set ("ratio", 0.45f);
                        e.name = "voice-compressor";
                        break;
                    case "volume":
                        e.set ("volume", 1.6);
                        e.name = "voice-gain";
                        break;
                    case "scaletempo":
                        e.name = "tempo";
                        break;
                    default:
                        break;
                }
                bin.add (e);
                if (last != null && !last.link (e)) throw new IOError.FAILED (_("The audio effects could not be connected."));
                if (first == null) first = e;
                last = e;
            }
            bin.add_pad (new Gst.GhostPad ("sink", first.get_static_pad ("sink")));
            bin.add_pad (new Gst.GhostPad ("src", last.get_static_pad ("src")));
            return bin;
        }

        public Gst.Element? find (Gst.Element bin, string name) {
            var b = bin as Gst.Bin;
            return b != null ? b.get_by_name (name) : null;
        }
    }
}
