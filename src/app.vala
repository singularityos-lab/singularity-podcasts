using Gtk;

namespace Singularity.Apps.Podcasts {

    public class PodcastsApp : Singularity.Application {
        public Library library;
        public Player player;
        public Downloads downloads;
        public MprisService mpris;
        public PlayQueue queue;
        public SleepTimer sleep;
        public GLib.Settings? settings;
        public double default_rate = 1.0;
        private bool trim_fallback;
        private bool boost_fallback;

        public bool trim_default {
            get { return settings != null ? settings.get_boolean ("trim-silence") : trim_fallback; }
            set {
                if (settings != null) settings.set_boolean ("trim-silence", value);
                else trim_fallback = value;
            }
        }

        public bool boost_default {
            get { return settings != null ? settings.get_boolean ("voice-boost") : boost_fallback; }
            set {
                if (settings != null) settings.set_boolean ("voice-boost", value);
                else boost_fallback = value;
            }
        }
        private KeyFile state = new KeyFile ();
        private string settings_path;
        private int64 last_listened;
        private int64 shown_badge = -1;
        private bool dock_buttons;
        private bool show_new_pending;

        public PodcastsApp () {
            Object (application_id: "dev.sinty.podcasts", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("new-episodes", 0, OptionFlags.NONE, OptionArg.NONE, _("Show the new episodes of your shows"), null);
        }

        protected override int handle_local_options (VariantDict options) {
            if (!options.contains ("new-episodes")) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("podcasts: %s", e.message);
                return 1;
            }
            if (get_is_remote ()) {
                activate_action ("show-new", null);
                return 0;
            }
            show_new_pending = true;
            return -1;
        }

        protected override void startup () {
            base.startup ();
            library = new Library ();
            player = new Player ();
            downloads = new Downloads (library);
            queue = new PlayQueue ();
            queue.prune (library);
            sleep = new SleepTimer ();
            sleep.notify["level"].connect (() => player.fade = sleep.level);
            sleep.expired.connect (() => {
                if (player.state == PlayState.PLAYING || player.state == PlayState.LOADING) player.pause ();
                player.fade = 1.0;
            });
            var source = SettingsSchemaSource.get_default ();
            if (source != null && source.lookup ("dev.sinty.podcasts", true) != null) settings = new GLib.Settings ("dev.sinty.podcasts");
            settings_path = Path.build_filename (Environment.get_user_config_dir (), "singularity", "podcasts.ini");
            try {
                state.load_from_file (settings_path, KeyFileFlags.NONE);
            } catch (Error e) {
            }
            try {
                default_rate = state.get_double ("Playback", "rate").clamp (0.5, 3.0);
                player.change_rate (default_rate);
            } catch (Error e) {
            }
            try {
                player.volume = state.get_double ("Playback", "volume");
            } catch (Error e) {
            }
            mpris = new MprisService (player, library);
            mpris.raise_requested.connect (() => activate ());
            mpris.quit_requested.connect (() => quit_app ());
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);

            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            var f1 = new GLib.Menu ();
            f1.append (_("Add Podcast…"), "win.add");
            file.append_section (null, f1);
            var f2 = new GLib.Menu ();
            f2.append (_("Import Subscriptions…"), "win.import");
            f2.append (_("Export Subscriptions…"), "win.export");
            file.append_section (null, f2);
            var f3 = new GLib.Menu ();
            f3.append (_("Close Window"), "win.close");
            f3.append (_("Quit"), "app.quit");
            file.append_section (null, f3);
            menu.append_submenu (_("File"), file);

            var edit = new GLib.Menu ();
            var e1 = new GLib.Menu ();
            e1.append (_("Find"), "win.find");
            edit.append_section (null, e1);
            var e2 = new GLib.Menu ();
            e2.append (_("Mark All as Played"), "win.mark-all");
            e2.append (_("Show Playback Settings…"), "win.show-settings");
            e2.append (_("Unsubscribe"), "win.unsubscribe");
            edit.append_section (null, e2);
            var e3 = new GLib.Menu ();
            e3.append (_("Clear Up Next"), "win.queue-clear");
            edit.append_section (null, e3);
            var e4 = new GLib.Menu ();
            e4.append (_("Settings"), "app.settings");
            edit.append_section (null, e4);
            menu.append_submenu (_("Edit"), edit);

            var view = new GLib.Menu ();
            var v1 = new GLib.Menu ();
            v1.append (_("Shows"), "win.go-shows");
            v1.append (_("New Episodes"), "win.go-new");
            v1.append (_("In Progress"), "win.go-progress");
            v1.append (_("Downloads"), "win.go-downloads");
            v1.append (_("Discover"), "win.go-discover");
            v1.append (_("Up Next"), "win.go-queue");
            view.append_section (null, v1);
            var v2 = new GLib.Menu ();
            v2.append (_("Back"), "win.back");
            v2.append (_("Refresh"), "win.refresh");
            view.append_section (null, v2);
            var v3 = new GLib.Menu ();
            v3.append (_("Chapters"), "win.chapters");
            v3.append (_("Show Sidebar"), "win.toggle-sidebar");
            view.append_section (null, v3);
            menu.append_submenu (_("View"), view);

            var playback = new GLib.Menu ();
            var p1 = new GLib.Menu ();
            p1.append (_("Play or Pause"), "win.play-pause");
            p1.append (_("Stop"), "win.stop");
            playback.append_section (null, p1);
            var p2 = new GLib.Menu ();
            p2.append (_("Skip Back 10 Seconds"), "win.skip-back");
            p2.append (_("Skip Forward 30 Seconds"), "win.skip-forward");
            p2.append (_("Previous Chapter"), "win.chapter-prev");
            p2.append (_("Next Chapter"), "win.chapter-next");
            p2.append (_("Next in Up Next"), "win.queue-next");
            playback.append_section (null, p2);
            var p3 = new GLib.Menu ();
            var speed = new GLib.Menu ();
            speed.append (_("Faster"), "win.faster");
            speed.append (_("Slower"), "win.slower");
            speed.append (_("Normal Speed"), "win.normal-speed");
            p3.append_submenu (_("Speed"), speed);
            p3.append (_("Trim Silence"), "win.trim-silence");
            p3.append (_("Voice Boost"), "win.voice-boost");
            playback.append_section (null, p3);
            var p4 = new GLib.Menu ();
            p4.append (_("Sleep Timer…"), "win.sleep-timer");
            p4.append (_("Cancel Sleep Timer"), "win.cancel-sleep");
            playback.append_section (null, p4);
            menu.append_submenu (_("Playback"), playback);

            var help = new GLib.Menu ();
            help.append (_("About Podcasts"), "app.about");
            menu.append_submenu (_("Help"), help);
            set_menubar (menu);

            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => quit_app ());
            add_action (quit);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.podcasts");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            about_name = _("Podcasts");
            about_version = "0.1.0";
            about_description = _("Follow shows, listen to new episodes and pick up where you left off.");
            about_website = "https://github.com/singularityos-lab/singularity-desktop";
            about_license = _("GNU General Public License, version 3 only");
            about_credits = _("Directory search by the Apple Podcasts directory");
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.go-queue", { "<Control>6" });
            set_accels_for_action ("win.chapters", { "<Control><Shift>h" });
            set_accels_for_action ("win.queue-next", { "<Control>Page_Down" });
            set_accels_for_action ("win.chapter-prev", { "<Control>bracketleft" });
            set_accels_for_action ("win.chapter-next", { "<Control>bracketright" });
            set_accels_for_action ("win.sleep-timer", { "<Control>t" });
            set_accels_for_action ("win.cancel-sleep", { "<Control><Shift>t" });
            set_accels_for_action ("win.show-settings", { "<Control>p" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("win.toggle-sidebar", { "F9" });
            set_accels_for_action ("win.normal-speed", { "<Control>0" });
            set_accels_for_action ("win.play-pause", { "<Control>space" });
            set_accels_for_action ("win.stop", { "<Control>period" });
            set_accels_for_action ("win.add", { "<Control>n" });
            set_accels_for_action ("win.import", { "<Control>o" });
            set_accels_for_action ("win.export", { "<Control><Shift>s" });
            set_accels_for_action ("win.find", { "<Control>f" });
            set_accels_for_action ("win.refresh", { "<Control>r", "F5" });
            set_accels_for_action ("win.back", { "<Alt>Left" });
            set_accels_for_action ("win.go-shows", { "<Control>1" });
            set_accels_for_action ("win.go-new", { "<Control>2" });
            set_accels_for_action ("win.go-progress", { "<Control>3" });
            set_accels_for_action ("win.go-downloads", { "<Control>4" });
            set_accels_for_action ("win.go-discover", { "<Control>5" });
            set_accels_for_action ("win.skip-back", { "<Control>Left" });
            set_accels_for_action ("win.skip-forward", { "<Control>Right" });
            set_accels_for_action ("win.faster", { "<Control>plus", "<Control>equal" });
            set_accels_for_action ("win.slower", { "<Control>minus" });

            Timeout.add_seconds (3600, () => {
                var w = get_active_window () as PodcastsWindow;
                if (w != null) w.refresh_all.begin (true);
                return Source.CONTINUE;
            });

            var play_episode = new SimpleAction ("play-episode", VariantType.STRING);
            play_episode.activate.connect ((param) => {
                string[] parts = param.get_string ().split ("\n", 2);
                if (parts.length != 2) return;
                var e = library.find_episode (parts[0], parts[1]);
                activate ();
                var w = get_active_window () as PodcastsWindow;
                if (e != null && w != null && player.episode != e) w.play_episode (e);
            });
            add_action (play_episode);
            var show_new = new SimpleAction ("show-new", null);
            show_new.activate.connect (() => {
                activate ();
                var w = get_active_window () as PodcastsWindow;
                if (w != null) w.go ("new");
            });
            add_action (show_new);

            try {
                last_listened = state.get_int64 ("Playback", "last-listened");
            } catch (Error e) {
                last_listened = new DateTime.now_utc ().to_unix ();
                save_settings ();
            }
            library.changed.connect (update_badge);
            library.episode_changed.connect (() => update_badge ());
            player.notify["state"].connect (() => {
                if (player.state == PlayState.PLAYING) {
                    last_listened = new DateTime.now_utc ().to_unix ();
                    save_settings ();
                    update_badge ();
                }
                sync_dock_buttons ();
            });
            player.notify["episode"].connect (sync_dock_buttons);
            var conn = get_dbus_connection ();
            if (conn != null) {
                conn.signal_subscribe ("dev.sinty.Dock", "dev.sinty.Dock", "ActionInvoked", "/dev/sinty/Dock", null, DBusSignalFlags.NONE,
                    (c, sender, path, iface, name, parameters) => {
                        string app_id, action_id;
                        parameters.get ("(ss)", out app_id, out action_id);
                        if (app_id.down () != "dev.sinty.podcasts" || player.episode == null) return;
                        if (action_id == "back30") player.skip (-30);
                        else if (action_id == "forward30") player.skip (30);
                    });
                Bus.watch_name_on_connection (conn, "dev.sinty.Dock", BusNameWatcherFlags.NONE, () => {
                    if (dock_buttons) {
                        dock_buttons = false;
                        sync_dock_buttons ();
                    }
                    shown_badge = -1;
                    update_badge ();
                }, null);
            }
            update_badge ();
        }

        public int new_episode_count () {
            int n = 0;
            foreach (var s in library.shows) {
                foreach (var e in s.episodes) {
                    if (!e.played && e.position == 0 && e.published > last_listened) n++;
                }
            }
            return n;
        }

        private void update_badge () {
            var conn = get_dbus_connection ();
            if (conn == null) return;
            int64 n = new_episode_count ();
            if (n == shown_badge) return;
            shown_badge = n;
            var props = new VariantBuilder (VariantType.VARDICT);
            props.add ("{sv}", "count", new Variant.int64 (n));
            props.add ("{sv}", "count-visible", new Variant.boolean (n > 0));
            try {
                conn.emit_signal (null, "/com/canonical/Unity/LauncherEntry", "com.canonical.Unity.LauncherEntry", "Update",
                    new Variant ("(s@a{sv})", "application://dev.sinty.podcasts.desktop", props.end ()));
            } catch (Error e) {
                warning ("podcasts: %s", e.message);
            }
        }

        private void sync_dock_buttons () {
            var conn = get_dbus_connection ();
            if (conn == null) return;
            bool want = player.episode != null && player.state != PlayState.STOPPED;
            if (want == dock_buttons) return;
            dock_buttons = want;
            if (!want) {
                conn.call.begin ("dev.sinty.Dock", "/dev/sinty/Dock", "dev.sinty.Dock", "ClearSuffix",
                    new Variant ("(s)", "dev.sinty.podcasts"), null, DBusCallFlags.NO_AUTO_START, 2000, null);
                return;
            }
            var widgets = new VariantBuilder (new VariantType ("a(sa{sv})"));
            widgets.add ("(s@a{sv})", "button", dock_button ("back30", "media-seek-backward-symbolic", _("Back 30 Seconds")));
            widgets.add ("(s@a{sv})", "button", dock_button ("forward30", "media-seek-forward-symbolic", _("Forward 30 Seconds")));
            conn.call.begin ("dev.sinty.Dock", "/dev/sinty/Dock", "dev.sinty.Dock", "SetSuffix",
                new Variant ("(sv)", "dev.sinty.podcasts", widgets.end ()), null, DBusCallFlags.NO_AUTO_START, 2000, null);
        }

        private static Variant dock_button (string id, string icon, string tooltip) {
            var props = new VariantBuilder (VariantType.VARDICT);
            props.add ("{sv}", "id", new Variant.string (id));
            props.add ("{sv}", "icon", new Variant.string (icon));
            props.add ("{sv}", "tooltip", new Variant.string (tooltip));
            return props.end ();
        }

        public void save_settings () {
            state.set_int64 ("Playback", "last-listened", last_listened);
            state.set_double ("Playback", "rate", default_rate);
            state.set_double ("Playback", "volume", player.volume);
            DirUtils.create_with_parents (Path.get_dirname (settings_path), 0700);
            try {
                state.save_to_file (settings_path);
            } catch (Error e) {
            }
        }

        private void quit_app () {
            foreach (var w in get_windows ()) w.close ();
        }

        public override void activate () {
            if (show_new_pending) {
                show_new_pending = false;
                activate_action ("show-new", null);
                return;
            }
            var w = get_active_window () as PodcastsWindow;
            if (w == null) {
                w = new PodcastsWindow (this);
                int64 age = new DateTime.now_utc ().to_unix () - library.last_refresh;
                if (library.shows.size > 0 && age > 3600) w.refresh_all.begin (true);
            }
            w.present ();
        }

        public override void open (File[] files, string hint) {
            activate ();
            var w = get_active_window () as PodcastsWindow;
            if (w == null) return;
            foreach (var file in files) {
                string uri = file.get_uri ();
                int colon = uri.index_of ("://");
                if (colon < 0) continue;
                string scheme = uri.substring (0, colon).down ();
                string rest = uri.substring (colon + 3);
                if (scheme == "sinty-podcasts") {
                    try {
                        var parsed = Uri.parse (uri, UriFlags.NONE);
                        var q = Uri.parse_params (parsed.get_query () ?? "", -1, "&", UriParamsFlags.NONE);
                        w.open_moment (q["show"] ?? "", q["episode"] ?? "", int.parse (q["t"] ?? "0"));
                    } catch (Error err) {
                        warning ("Podcasts: bad moment link %s", uri);
                    }
                    continue;
                }
                string url;
                if (scheme == "itpc" || scheme == "pcast" || scheme == "feed" || scheme == "podcast") url = "https://" + rest;
                else if (scheme == "http" || scheme == "https") url = uri;
                else continue;
                w.subscribe.begin (url, true);
            }
        }

        public override void shutdown () {
            downloads.cancel_all ();
            if (player.episode != null) library.set_position (player.episode, player.position ());
            library.save ();
            sleep.cancel ();
            save_settings ();
            player.shutdown ();
            mpris.shutdown ();
            base.shutdown ();
        }

        private const string CSS = """
.podcasts-grid {
    padding: 8px 24px 32px 24px;
}

.podcasts-card {
    padding: 8px;
    border-radius: 18px;
    background: transparent;
}

.podcasts-card .podcasts-art {
    box-shadow: 0 4px 14px alpha(black, 0.16);
    transition: box-shadow 150ms ease;
}

.podcasts-card:hover .podcasts-art {
    box-shadow: 0 0 0 3px alpha(@accent_bg_color, 0.55), 0 6px 18px alpha(black, 0.18);
}

.podcasts-art-8 {
    border-radius: 8px;
}

.podcasts-art-10 {
    border-radius: 10px;
}

.podcasts-art-14 {
    border-radius: 14px;
}

.podcasts-art-16 {
    border-radius: 16px;
}

.podcasts-card-title {
    font-weight: 700;
}

.podcasts-badge {
    font-size: 11px;
    font-weight: 800;
    padding: 2px 8px;
    border-radius: 99px;
    color: @accent_fg_color;
    background-color: @accent_bg_color;
}

.podcasts-page {
    padding: 8px 24px 32px 24px;
}

.podcasts-page-title {
    font-weight: 800;
    font-size: 22px;
}

.podcasts-show-title {
    font-weight: 800;
    font-size: 24px;
}

.podcasts-list {
    background: transparent;
}

.podcasts-list > row {
    border-radius: 12px;
    padding: 8px 10px;
    margin: 1px 0;
}

.podcasts-list > row.podcasts-current {
    background-color: alpha(@accent_bg_color, 0.12);
}

.podcasts-episode-title {
    font-weight: 600;
}

.podcasts-played .podcasts-episode-title {
    opacity: 0.55;
}

.podcasts-progress trough,
.podcasts-progress progress {
    min-height: 3px;
    border-radius: 3px;
}

.podcasts-round {
    border-radius: 99px;
    min-width: 34px;
    min-height: 34px;
    padding: 0;
}

.podcasts-player {
    padding: 10px 18px;
    border-top: 1px solid alpha(@borders, 0.6);
    background-color: @window_bg_color;
}

.podcasts-player-title {
    font-weight: 700;
}

.podcasts-player-time {
    font-size: 12px;
    font-feature-settings: "tnum";
    opacity: 0.7;
}

.podcasts-play {
    border-radius: 99px;
    min-width: 42px;
    min-height: 42px;
    padding: 0;
    background-color: @accent_bg_color;
    color: @accent_fg_color;
}

.podcasts-speed {
    font-feature-settings: "tnum";
    font-weight: 700;
    border-radius: 99px;
    padding: 4px 10px;
}

.podcasts-description {
    padding: 12px 14px;
    border-radius: 12px;
    background-color: alpha(@window_fg_color, 0.05);
}

.podcasts-toast {
    padding: 8px 16px;
    border-radius: 18px;
    background-color: alpha(black, 0.75);
    color: white;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-podcasts", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-podcasts", "UTF-8");
        Intl.textdomain ("singularity-podcasts");
        Gst.init (ref args);
        return new PodcastsApp ().run (args);
    }
}
