namespace Singularity.Apps.Podcasts {

    [DBus (name = "org.mpris.MediaPlayer2")]
    public class MprisRoot : Object {
        public signal void raise_requested ();
        public signal void quit_requested ();

        public bool can_quit { get { return true; } }
        public bool can_raise { get { return true; } }
        public bool has_track_list { get { return false; } }
        public string identity { owned get { return _("Podcasts"); } }
        public string desktop_entry { owned get { return "dev.sinty.podcasts"; } }
        public string[] supported_uri_schemes { owned get { return {}; } }
        public string[] supported_mime_types { owned get { return {}; } }

        public void raise () throws DBusError, IOError {
            raise_requested ();
        }

        public void quit () throws DBusError, IOError {
            quit_requested ();
        }
    }

    [DBus (name = "org.mpris.MediaPlayer2.Player")]
    public class MprisPlayer : Object {
        private Player player;
        private Library library;

        public signal void seeked (int64 position);

        public MprisPlayer (Player player, Library library) {
            this.player = player;
            this.library = library;
        }

        public string playback_status {
            owned get {
                switch (player.state) {
                    case PlayState.PLAYING: return "Playing";
                    case PlayState.PAUSED: return "Paused";
                    case PlayState.LOADING: return "Playing";
                    default: return "Stopped";
                }
            }
        }

        public double rate {
            get { return player.rate; }
            set { player.change_rate (value); }
        }

        public double minimum_rate { get { return 0.5; } }
        public double maximum_rate { get { return 3.0; } }

        public double volume {
            get { return player.volume; }
            set { player.volume = value; }
        }

        public int64 position { get { return player.episode != null ? player.position_us () : 0; } }
        public bool can_go_next { get { return player.episode != null; } }
        public bool can_go_previous { get { return player.episode != null; } }
        public bool can_play { get { return player.episode != null; } }
        public bool can_pause { get { return player.episode != null; } }
        public bool can_seek { get { return player.episode != null; } }
        public bool can_control { get { return true; } }

        public HashTable<string, Variant> metadata {
            owned get {
                var t = new HashTable<string, Variant> (str_hash, str_equal);
                var e = player.episode;
                if (e == null) {
                    t["mpris:trackid"] = new Variant.object_path ("/org/mpris/MediaPlayer2/TrackList/NoTrack");
                    return t;
                }
                t["mpris:trackid"] = new Variant.object_path (MprisService.track_path (e));
                t["xesam:title"] = e.title;
                var show = library.find_show (e.show_url);
                if (show != null) {
                    t["xesam:album"] = show.title;
                    string[] artists = { show.author != "" ? show.author : show.title };
                    t["xesam:artist"] = artists;
                }
                int dur = player.duration ();
                if (dur > 0) t["mpris:length"] = new Variant.int64 ((int64) dur * 1000000);
                string art = e.image_url != "" ? e.image_url : (show != null ? show.image_url : "");
                if (art != "") {
                    string file = ArtworkCache.get_default ().file_for (art);
                    string uri = art;
                    try {
                        if (FileUtils.test (file, FileTest.EXISTS)) uri = Filename.to_uri (file);
                    } catch (Error err) {
                    }
                    t["mpris:artUrl"] = uri;
                }
                if (e.audio_url != "") t["xesam:url"] = e.audio_url;
                return t;
            }
        }

        public void next () throws DBusError, IOError {
            player.skip (Player.SKIP_FORWARD);
        }

        public void previous () throws DBusError, IOError {
            player.skip (-Player.SKIP_BACK);
        }

        public void pause () throws DBusError, IOError {
            if (player.state == PlayState.PLAYING || player.state == PlayState.LOADING) player.pause ();
        }

        public void play_pause () throws DBusError, IOError {
            player.toggle ();
        }

        public void stop () throws DBusError, IOError {
            player.pause ();
        }

        public void play () throws DBusError, IOError {
            player.play ();
        }

        public void seek (int64 offset) throws DBusError, IOError {
            if (player.episode == null) return;
            int64 target = player.position_us () + offset;
            if (target < 0) target = 0;
            player.seek_to ((int) (target / 1000000));
        }

        public void set_position (ObjectPath track_id, int64 position) throws DBusError, IOError {
            var e = player.episode;
            if (e == null || (string) track_id != MprisService.track_path (e)) return;
            int dur = player.duration ();
            if (position < 0 || (dur > 0 && position > (int64) dur * 1000000)) return;
            player.seek_to ((int) (position / 1000000));
        }

        public void open_uri (string uri) throws DBusError, IOError {
        }
    }

    public class MprisService : Object {
        private Player player;
        private MprisRoot root;
        private MprisPlayer mpris_player;
        private DBusConnection? conn;
        private uint own_id;
        private uint root_id;
        private uint player_id;

        public signal void raise_requested ();
        public signal void quit_requested ();

        public static string track_path (Episode e) {
            return "/dev/sinty/podcasts/track/%u".printf ((e.show_url + e.key ()).hash ());
        }

        public MprisService (Player player, Library library) {
            this.player = player;
            root = new MprisRoot ();
            mpris_player = new MprisPlayer (player, library);
            root.raise_requested.connect (() => raise_requested ());
            root.quit_requested.connect (() => quit_requested ());
            player.notify["state"].connect (() => changed ({ "PlaybackStatus", "CanPlay", "CanPause", "CanSeek", "CanGoNext", "CanGoPrevious" }));
            player.notify["episode"].connect (() => changed ({ "Metadata", "CanPlay", "CanPause", "CanSeek", "CanGoNext", "CanGoPrevious" }));
            player.notify["rate"].connect (() => changed ({ "Rate" }));
            player.seeked.connect ((us) => mpris_player.seeked (us));
            own_id = Bus.own_name (BusType.SESSION, "org.mpris.MediaPlayer2.singularity-podcasts", BusNameOwnerFlags.NONE, on_bus, null, null);
        }

        private void on_bus (DBusConnection c) {
            conn = c;
            try {
                root_id = c.register_object ("/org/mpris/MediaPlayer2", root);
                player_id = c.register_object ("/org/mpris/MediaPlayer2", mpris_player);
            } catch (IOError e) {
                warning ("podcasts: MPRIS is not available: %s", e.message);
            }
        }

        public void refresh_metadata () {
            changed ({ "Metadata" });
        }

        private void changed (string[] names) {
            if (conn == null || player_id == 0) return;
            var props = new VariantBuilder (VariantType.VARDICT);
            foreach (string n in names) {
                Variant? v = null;
                switch (n) {
                    case "PlaybackStatus": v = mpris_player.playback_status; break;
                    case "Metadata": v = mpris_player.metadata; break;
                    case "Rate": v = mpris_player.rate; break;
                    case "CanPlay": v = mpris_player.can_play; break;
                    case "CanPause": v = mpris_player.can_pause; break;
                    case "CanSeek": v = mpris_player.can_seek; break;
                    case "CanGoNext": v = mpris_player.can_go_next; break;
                    case "CanGoPrevious": v = mpris_player.can_go_previous; break;
                }
                if (v != null) props.add ("{sv}", n, v);
            }
            try {
                conn.emit_signal (null, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "PropertiesChanged",
                    new Variant.tuple ({ new Variant.string ("org.mpris.MediaPlayer2.Player"), props.end (), new Variant.array (VariantType.STRING, {}) }));
            } catch (Error e) {
            }
        }

        public void shutdown () {
            if (conn != null) {
                if (root_id != 0) conn.unregister_object (root_id);
                if (player_id != 0) conn.unregister_object (player_id);
            }
            root_id = player_id = 0;
            if (own_id != 0) Bus.unown_name (own_id);
            own_id = 0;
        }
    }
}
