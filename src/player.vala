namespace Singularity.Apps.Podcasts {

    public enum PlayState {
        STOPPED,
        LOADING,
        PLAYING,
        PAUSED
    }

    public class Player : Object {
        public const double[] RATES = { 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0 };
        public const int SKIP_BACK = 10;
        public const int SKIP_FORWARD = 30;

        private Gst.Element? playbin;
        private uint bus_watch;
        private uint tick_id;
        private bool want_playing;
        private bool prerolled;
        private bool buffering;
        private int64 pending_seek = -1;
        private int64 last_position;
        private int64 upstream_position = -1;
        private bool trim_active;
        private bool boost_active;
        private bool level_fallback;
        private SilenceSkipper skipper = new SilenceSkipper ();
        private double user_volume = 1.0;
        private double _fade = 1.0;

        public Episode? episode { get; private set; }
        public PlayState state { get; private set; default = PlayState.STOPPED; }
        public double rate { get; private set; default = 1.0; }
        public bool available { get { return playbin != null; } }

        public signal void tick ();
        public signal void failed (string message);
        public signal void finished (Episode e);
        public signal void seeked (int64 microseconds);

        public double volume {
            get { return user_volume; }
            set {
                user_volume = value.clamp (0.0, 1.0);
                apply_volume ();
            }
        }

        public double fade {
            get { return _fade; }
            set {
                _fade = value.clamp (0.0, 1.0);
                apply_volume ();
            }
        }

        public bool trim_silence { get { return trim_active; } }
        public bool voice_boost { get { return boost_active; } }
        public string effects_error { get; private set; default = ""; }

        private void apply_volume () {
            if (playbin != null) playbin.set ("volume", user_volume * _fade);
        }

        public Player () {
            playbin = Gst.ElementFactory.make ("playbin", "podcasts-player");
            if (playbin == null) return;
            playbin.set ("flags", 0x2 | 0x10 | 0x100);
            install_effects ();
            bus_watch = playbin.get_bus ().add_watch (Priority.DEFAULT, on_message);
            tick_id = Timeout.add (500, () => {
                if (state == PlayState.PLAYING) tick ();
                return Source.CONTINUE;
            });
        }

        private void install_effects () {
            effects_error = "";
            level_fallback = false;
            upstream_position = -1;
            skipper.reset ();
            Gst.Element? filter = null;
            bool fallback = false;
            try {
                filter = Effects.build (trim_active, boost_active, out fallback);
            } catch (Error e) {
                effects_error = e.message;
                try {
                    filter = Effects.build (false, false, out fallback);
                } catch (Error e2) {
                    filter = Gst.ElementFactory.make ("scaletempo", null);
                }
            }
            level_fallback = fallback;
            if (filter == null) return;
            var sink = filter.get_static_pad ("sink");
            if (sink != null && trim_active && !fallback) {
                sink.add_probe (Gst.PadProbeType.BUFFER | Gst.PadProbeType.EVENT_DOWNSTREAM, on_upstream);
            }
            playbin.set ("audio-filter", filter);
        }

        private Gst.Segment upstream_segment = new Gst.Segment ();

        private Gst.PadProbeReturn on_upstream (Gst.Pad pad, Gst.PadProbeInfo info) {
            if ((info.type & Gst.PadProbeType.BUFFER) != 0) {
                var buf = info.get_buffer ();
                if (buf != null && buf.pts != Gst.CLOCK_TIME_NONE && upstream_segment.format == Gst.Format.TIME) {
                    uint64 t = upstream_segment.to_stream_time (Gst.Format.TIME, buf.pts);
                    if (t != Gst.CLOCK_TIME_NONE) upstream_position = (int64) t;
                }
            } else {
                var ev = info.get_event ();
                if (ev != null && ev.type == Gst.EventType.SEGMENT) {
                    unowned Gst.Segment seg;
                    ev.parse_segment (out seg);
                    seg.copy_into (upstream_segment);
                } else if (ev != null && ev.type == Gst.EventType.FLUSH_STOP) {
                    upstream_position = -1;
                }
            }
            return Gst.PadProbeReturn.OK;
        }

        public void set_effects (bool trim, bool boost, bool reload = true) {
            if (playbin == null || (trim == trim_active && boost == boost_active)) return;
            trim_active = trim;
            boost_active = boost;
            if (episode == null || !reload) {
                playbin.set_state (Gst.State.NULL);
                install_effects ();
                return;
            }
            int64 at = raw_position ();
            bool resume = want_playing || state == PlayState.PLAYING;
            string? uri = null;
            playbin.get ("current-uri", out uri);
            if (uri == null) playbin.get ("uri", out uri);
            playbin.set_state (Gst.State.NULL);
            install_effects ();
            prerolled = false;
            buffering = false;
            last_position = at;
            pending_seek = at;
            want_playing = resume;
            if (uri != null) playbin.set ("uri", uri);
            state = PlayState.LOADING;
            if (playbin.set_state (Gst.State.PAUSED) == Gst.StateChangeReturn.FAILURE) fail (_("The episode could not be opened."));
        }

        public void shutdown () {
            if (tick_id != 0) Source.remove (tick_id);
            tick_id = 0;
            if (bus_watch != 0) Source.remove (bus_watch);
            bus_watch = 0;
            if (playbin != null) playbin.set_state (Gst.State.NULL);
        }

        public void open (Episode e, string uri, bool autoplay = true) {
            if (playbin == null) {
                failed (_("Audio playback is not available. The GStreamer playbin element is missing."));
                return;
            }
            playbin.set_state (Gst.State.NULL);
            episode = e;
            prerolled = false;
            buffering = false;
            int start = e.position;
            if (e.duration > 0 && start >= e.duration - 5) start = 0;
            last_position = (int64) start * Gst.SECOND;
            pending_seek = start > 0 || rate != 1.0 ? last_position : -1;
            want_playing = autoplay;
            playbin.set ("uri", uri);
            state = PlayState.LOADING;
            if (playbin.set_state (Gst.State.PAUSED) == Gst.StateChangeReturn.FAILURE) fail (_("The episode could not be opened."));
        }

        public void play () {
            if (playbin == null || episode == null) return;
            want_playing = true;
            if (!prerolled || buffering) {
                state = PlayState.LOADING;
                if (!prerolled) playbin.set_state (Gst.State.PAUSED);
                return;
            }
            playbin.set_state (Gst.State.PLAYING);
        }

        public void pause () {
            if (playbin == null || episode == null) return;
            last_position = raw_position ();
            want_playing = false;
            playbin.set_state (Gst.State.PAUSED);
            state = PlayState.PAUSED;
        }

        public void toggle () {
            if (state == PlayState.PLAYING || (state == PlayState.LOADING && want_playing)) pause ();
            else play ();
        }

        public void stop () {
            if (playbin != null) playbin.set_state (Gst.State.NULL);
            want_playing = false;
            prerolled = false;
            episode = null;
            state = PlayState.STOPPED;
        }

        private int64 raw_position () {
            int64 pos = -1;
            if (trim_active && !level_fallback) {
                if (prerolled && pending_seek < 0 && upstream_position >= 0) last_position = upstream_position;
                return last_position;
            }
            if (playbin != null && prerolled && pending_seek < 0 && playbin.query_position (Gst.Format.TIME, out pos) && pos >= 0) {
                last_position = pos;
            }
            return last_position;
        }

        public int position () {
            return (int) (raw_position () / Gst.SECOND);
        }

        public int64 position_us () {
            return raw_position () / 1000;
        }

        public int duration () {
            int64 dur = -1;
            if (playbin != null && prerolled && playbin.query_duration (Gst.Format.TIME, out dur) && dur > 0) return (int) (dur / Gst.SECOND);
            return episode != null ? episode.duration : 0;
        }

        public void seek_to (int seconds) {
            if (episode == null) return;
            int dur = duration ();
            if (dur > 0) seconds = seconds.clamp (0, int.max (dur - 1, 0));
            else seconds = int.max (seconds, 0);
            int64 target = (int64) seconds * Gst.SECOND;
            last_position = target;
            if (!prerolled) {
                pending_seek = target;
            } else {
                do_seek (target);
            }
            seeked (target / 1000);
            tick ();
        }

        public void skip (int delta) {
            seek_to (position () + delta);
        }

        public void preset_rate (double r) {
            rate = r.clamp (0.5, 3.0);
        }

        public void change_rate (double r) {
            rate = r.clamp (0.5, 3.0);
            if (episode == null) return;
            if (prerolled) do_seek (raw_position ());
            else pending_seek = last_position;
        }

        private void do_seek (int64 target) {
            upstream_position = -1;
            skipper.reset ();
            playbin.seek (rate, Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE, Gst.SeekType.SET, target, Gst.SeekType.NONE, (int64) Gst.CLOCK_TIME_NONE);
        }

        private void on_level (Gst.Message msg) {
            unowned Gst.Structure? st = msg.get_structure ();
            if (st == null || st.get_name () != "level") return;
            unowned Value? rms = st.get_value ("rms");
            if (rms == null) return;
            unowned ValueArray? arr = (ValueArray) rms.get_boxed ();
            if (arr == null || arr.n_values == 0) return;
            double loudest = -200.0;
            for (uint i = 0; i < arr.n_values; i++) loudest = double.max (loudest, arr.get_nth (i).get_double ());
            int64 target = skipper.feed (loudest, raw_position ());
            if (target < 0) return;
            int dur = duration ();
            if (dur > 0 && target >= (int64) dur * Gst.SECOND - Gst.SECOND) return;
            last_position = target;
            do_seek (target);
        }

        private void fail (string message) {
            if (playbin != null) playbin.set_state (Gst.State.NULL);
            want_playing = false;
            prerolled = false;
            state = PlayState.STOPPED;
            failed (message);
        }

        private bool on_message (Gst.Bus bus, Gst.Message msg) {
            switch (msg.type) {
                case Gst.MessageType.ASYNC_DONE:
                    prerolled = true;
                    if (pending_seek >= 0) {
                        int64 target = pending_seek;
                        pending_seek = -1;
                        do_seek (target);
                        break;
                    }
                    if (want_playing && !buffering) playbin.set_state (Gst.State.PLAYING);
                    else if (!want_playing) state = PlayState.PAUSED;
                    tick ();
                    break;
                case Gst.MessageType.BUFFERING:
                    int percent;
                    msg.parse_buffering (out percent);
                    if (percent < 100 && !buffering) {
                        buffering = true;
                        if (want_playing && prerolled) {
                            playbin.set_state (Gst.State.PAUSED);
                            state = PlayState.LOADING;
                        }
                    } else if (percent >= 100 && buffering) {
                        buffering = false;
                        if (want_playing && prerolled && pending_seek < 0) playbin.set_state (Gst.State.PLAYING);
                    }
                    break;
                case Gst.MessageType.STATE_CHANGED:
                    if (msg.src != playbin) break;
                    Gst.State old_state, new_state, pending;
                    msg.parse_state_changed (out old_state, out new_state, out pending);
                    if (new_state == Gst.State.PLAYING) state = PlayState.PLAYING;
                    else if (new_state == Gst.State.PAUSED && old_state == Gst.State.PLAYING) state = want_playing ? PlayState.LOADING : PlayState.PAUSED;
                    break;
                case Gst.MessageType.ELEMENT:
                    if (level_fallback && state == PlayState.PLAYING) on_level (msg);
                    break;
                case Gst.MessageType.EOS:
                    var e = episode;
                    playbin.set_state (Gst.State.NULL);
                    want_playing = false;
                    prerolled = false;
                    state = PlayState.STOPPED;
                    episode = null;
                    if (e != null) finished (e);
                    break;
                case Gst.MessageType.ERROR:
                    Error err;
                    string debug;
                    msg.parse_error (out err, out debug);
                    string text = err.message;
                    if (err is Gst.ResourceError) {
                        if (!NetworkMonitor.get_default ().network_available) text = _("You are offline. Download episodes to listen without a connection.");
                        else text = _("The episode could not be loaded: %s").printf (err.message);
                    } else if (err is Gst.StreamError || err is Gst.CoreError) {
                        text = _("This episode cannot be played: %s").printf (err.message);
                    }
                    fail (text);
                    break;
                default:
                    break;
            }
            return true;
        }
    }
}
