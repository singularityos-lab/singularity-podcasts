using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Podcasts {

    public class ShowCard : FlowBoxChild {
        public Show item;

        public ShowCard (Show s) {
            item = s;
            add_css_class ("podcasts-card");
            var box = new Box (Orientation.VERTICAL, 6);
            var overlay = new Overlay ();
            var art = new ArtworkView (164, 14);
            art.set_url (s.image_url);
            overlay.child = art;
            int unplayed = s.unplayed ();
            if (unplayed > 0) {
                var badge = new Label (unplayed > 99 ? "99+" : unplayed.to_string ());
                badge.add_css_class ("podcasts-badge");
                badge.halign = Align.END;
                badge.valign = Align.START;
                badge.margin_top = 8;
                badge.margin_end = 8;
                badge.tooltip_text = ngettext ("%d unplayed episode", "%d unplayed episodes", unplayed).printf (unplayed);
                overlay.add_overlay (badge);
            }
            box.append (overlay);
            var title = new Label (s.title);
            title.add_css_class ("podcasts-card-title");
            title.xalign = 0;
            title.wrap = true;
            title.lines = 2;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.max_width_chars = 18;
            box.append (title);
            if (s.author != "") {
                var author = new Label (s.author);
                author.add_css_class ("dim-label");
                author.add_css_class ("caption");
                author.xalign = 0;
                author.ellipsize = Pango.EllipsizeMode.END;
                author.max_width_chars = 22;
                box.append (author);
            }
            child = box;
        }
    }

    public class EpisodeRow : ListBoxRow {
        public Episode episode;
        public bool with_show;
        public Button play;
        public Label title;
        public Label meta;
        public Label download_label;
        public Image download_icon;
        public ProgressBar progress;
        public Button more;
        public ArtworkView? art;

        public EpisodeRow (Episode e, bool with_show) {
            episode = e;
            this.with_show = with_show;
            var box = new Box (Orientation.HORIZONTAL, 12);
            if (with_show) {
                var art = new ArtworkView (44, 8);
                art.valign = Align.CENTER;
                art.set_url (e.image_url);
                box.append (art);
                this.art = art;
            }
            var texts = new Box (Orientation.VERTICAL, 3);
            texts.hexpand = true;
            texts.valign = Align.CENTER;
            title = new Label (e.title);
            title.add_css_class ("podcasts-episode-title");
            title.xalign = 0;
            title.wrap = true;
            title.lines = 2;
            title.ellipsize = Pango.EllipsizeMode.END;
            texts.append (title);
            meta = new Label ("");
            meta.add_css_class ("dim-label");
            meta.add_css_class ("caption");
            meta.xalign = 0;
            meta.ellipsize = Pango.EllipsizeMode.END;
            texts.append (meta);
            progress = new ProgressBar ();
            progress.add_css_class ("podcasts-progress");
            progress.margin_top = 2;
            progress.set_size_request (120, -1);
            progress.halign = Align.START;
            texts.append (progress);
            box.append (texts);
            download_label = new Label ("");
            download_label.add_css_class ("podcasts-player-time");
            download_label.valign = Align.CENTER;
            box.append (download_label);
            download_icon = new Image.from_icon_name ("folder-download-symbolic");
            download_icon.add_css_class ("dim-label");
            download_icon.tooltip_text = _("Downloaded");
            download_icon.valign = Align.CENTER;
            box.append (download_icon);
            play = new Button.from_icon_name ("media-playback-start-symbolic");
            play.add_css_class ("podcasts-round");
            play.valign = Align.CENTER;
            box.append (play);
            more = new Button.from_icon_name ("view-more-symbolic");
            more.add_css_class ("flat");
            more.add_css_class ("podcasts-round");
            more.valign = Align.CENTER;
            more.tooltip_text = _("More");
            box.append (more);
            child = box;
        }
    }

    public class PlayerBar : Box {
        private Player player;
        private Library library;
        private ArtworkView art;
        private Label title;
        private Label subtitle;
        private Button play;
        private Spinner spinner;
        private Scale scale;
        private Label elapsed;
        private Label left;
        public Button speed;
        public Button chapters;
        public Button sleep;
        public Label sleep_label;
        private string show_title = "";
        private uint seek_id;
        private double seek_value;
        private bool updating;

        public signal void details_requested (Episode e);
        public signal void speed_requested ();
        public signal void chapters_requested ();
        public signal void sleep_requested ();

        public PlayerBar (Player player, Library library) {
            Object (orientation: Orientation.HORIZONTAL, spacing: 16);
            this.player = player;
            this.library = library;
            add_css_class ("podcasts-player");

            var info = new Box (Orientation.HORIZONTAL, 10);
            info.set_size_request (260, -1);
            art = new ArtworkView (48, 8);
            art.valign = Align.CENTER;
            art.halign = Align.START;
            art.fixed_size = true;
            info.append (art);
            var texts = new Box (Orientation.VERTICAL, 2);
            texts.valign = Align.CENTER;
            texts.hexpand = true;
            title = new Label ("");
            title.add_css_class ("podcasts-player-title");
            title.xalign = 0;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.max_width_chars = 28;
            texts.append (title);
            subtitle = new Label ("");
            subtitle.add_css_class ("dim-label");
            subtitle.add_css_class ("caption");
            subtitle.xalign = 0;
            subtitle.ellipsize = Pango.EllipsizeMode.END;
            subtitle.max_width_chars = 30;
            texts.append (subtitle);
            info.append (texts);
            var info_click = new GestureClick ();
            info_click.released.connect (() => {
                if (player.episode != null) details_requested (player.episode);
            });
            info.add_controller (info_click);
            append (info);

            var center = new Box (Orientation.VERTICAL, 2);
            center.hexpand = true;
            center.valign = Align.CENTER;
            var controls = new Box (Orientation.HORIZONTAL, 10);
            controls.halign = Align.CENTER;
            var back = new Button.from_icon_name ("media-seek-backward-symbolic");
            back.add_css_class ("flat");
            back.add_css_class ("podcasts-round");
            back.tooltip_text = _("Back %d Seconds").printf (Player.SKIP_BACK);
            back.clicked.connect (() => player.skip (-Player.SKIP_BACK));
            controls.append (back);
            var play_box = new Overlay ();
            play = new Button.from_icon_name ("media-playback-start-symbolic");
            play.add_css_class ("podcasts-play");
            play.clicked.connect (() => player.toggle ());
            play_box.child = play;
            spinner = new Spinner ();
            spinner.can_target = false;
            spinner.halign = Align.CENTER;
            spinner.valign = Align.CENTER;
            spinner.set_size_request (42, 42);
            play_box.add_overlay (spinner);
            controls.append (play_box);
            var fwd = new Button.from_icon_name ("media-seek-forward-symbolic");
            fwd.add_css_class ("flat");
            fwd.add_css_class ("podcasts-round");
            fwd.tooltip_text = _("Forward %d Seconds").printf (Player.SKIP_FORWARD);
            fwd.clicked.connect (() => player.skip (Player.SKIP_FORWARD));
            controls.append (fwd);
            center.append (controls);
            var seek_row = new Box (Orientation.HORIZONTAL, 8);
            elapsed = new Label ("0:00");
            elapsed.add_css_class ("podcasts-player-time");
            elapsed.width_chars = 7;
            elapsed.xalign = 1;
            seek_row.append (elapsed);
            scale = new Scale.with_range (Orientation.HORIZONTAL, 0, 1, 1);
            scale.draw_value = false;
            scale.hexpand = true;
            scale.tooltip_text = _("Position");
            scale.change_value.connect ((type, v) => {
                if (updating) return false;
                seek_value = v;
                if (seek_id != 0) Source.remove (seek_id);
                seek_id = Timeout.add (180, () => {
                    seek_id = 0;
                    player.seek_to ((int) seek_value);
                    return Source.REMOVE;
                });
                elapsed.label = Format.clock ((int64) v);
                return false;
            });
            seek_row.append (scale);
            left = new Label ("");
            left.add_css_class ("podcasts-player-time");
            left.width_chars = 8;
            left.xalign = 0;
            seek_row.append (left);
            center.append (seek_row);
            append (center);

            var right = new Box (Orientation.HORIZONTAL, 6);
            right.valign = Align.CENTER;
            speed = new Button.with_label (Format.speed (player.rate));
            speed.add_css_class ("flat");
            speed.add_css_class ("podcasts-speed");
            speed.tooltip_text = _("Playback Speed");
            speed.clicked.connect (() => speed_requested ());
            right.append (speed);
            chapters = new Button.from_icon_name ("view-list-symbolic");
            chapters.add_css_class ("flat");
            chapters.add_css_class ("podcasts-round");
            chapters.tooltip_text = _("Chapters");
            chapters.update_property (AccessibleProperty.LABEL, _("Chapters"), -1);
            chapters.visible = false;
            chapters.clicked.connect (() => chapters_requested ());
            right.append (chapters);
            sleep = new Button ();
            sleep.add_css_class ("flat");
            sleep.add_css_class ("podcasts-sleep");
            var sleep_box = new Box (Orientation.HORIZONTAL, 6);
            sleep_box.append (new Image.from_icon_name ("weather-clear-night-symbolic"));
            sleep_label = new Label ("");
            sleep_label.add_css_class ("podcasts-player-time");
            sleep_label.visible = false;
            sleep_box.append (sleep_label);
            sleep.child = sleep_box;
            sleep.tooltip_text = _("Sleep Timer");
            sleep.update_property (AccessibleProperty.LABEL, _("Sleep Timer"), -1);
            sleep.clicked.connect (() => sleep_requested ());
            right.append (sleep);
            var stop = new Button.from_icon_name ("media-playback-stop-symbolic");
            stop.add_css_class ("flat");
            stop.add_css_class ("podcasts-round");
            stop.tooltip_text = _("Stop");
            stop.clicked.connect (() => stop_requested ());
            right.append (stop);
            append (right);
        }

        public signal void stop_requested ();

        public void sync () {
            var e = player.episode;
            if (e == null) return;
            var show = library.find_show (e.show_url);
            title.label = e.title;
            title.tooltip_text = e.title;
            show_title = show != null ? show.title : "";
            subtitle.label = show_title;
            chapters.visible = e.chapters.size > 0;
            art.set_url (e.image_url != "" ? e.image_url : (show != null ? show.image_url : ""));
            bool playing = player.state == PlayState.PLAYING;
            bool loading = player.state == PlayState.LOADING;
            play.icon_name = playing || loading ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            play.tooltip_text = playing || loading ? _("Pause") : _("Play");
            spinner.spinning = loading;
            spinner.visible = loading;
            speed.label = Format.speed (player.rate);
            tick ();
        }

        public void set_chapter (Chapter? c) {
            var e = player.episode;
            chapters.visible = e != null && e.chapters.size > 0;
            if (c == null) {
                subtitle.label = show_title;
                subtitle.tooltip_text = null;
                return;
            }
            subtitle.label = c.title;
            subtitle.tooltip_text = _("Chapter: %s").printf (c.title);
        }

        public void tick () {
            if (player.episode == null || seek_id != 0) return;
            int pos = player.position ();
            int dur = player.duration ();
            updating = true;
            scale.set_range (0, double.max (dur, 1));
            scale.set_value (pos);
            scale.sensitive = dur > 0;
            updating = false;
            elapsed.label = Format.clock (pos);
            left.label = dur > 0 ? "-" + Format.clock (int.max (dur - pos, 0)) : "";
        }
    }

    public class PodcastsWindow : Singularity.Widgets.Window {
        private PodcastsApp app;
        private Library library;
        private Player player;
        private Downloads downloads;
        private PlayQueue queue;
        private SleepTimer sleep;
        private ListBox queue_list;
        private Stack queue_stack;
        private Button queue_clear;
        private int chapter_index = -1;
        private SimpleAction? trim_action;
        private bool actions_ready;
        private SimpleAction? boost_action;
        private Gee.HashSet<Episode> id3_checked = new Gee.HashSet<Episode> ();
        private AppSidebar sidebar;
        private Gee.HashMap<string, SidebarRow> nav = new Gee.HashMap<string, SidebarRow> ();
        private string section = "shows";
        private Show? current_show;
        private Stack stack;
        private FlowBox grid;
        private Box show_box;
        private ScrolledWindow show_scroll;
        private Label list_title;
        private Label list_hint;
        private ListBox list_box;
        private Stack list_stack;
        private Box list_empty;
        private string empty_key = "";
        private ListBox discover_list;
        private Stack discover_stack;
        private StatusPage discover_status;
        private Spinner discover_spinner;
        private Button discover_action;
        private string discover_action_kind = "";
        private Gee.ArrayList<EpisodeRow> rows = new Gee.ArrayList<EpisodeRow> ();
        private SearchBubble search;
        private Button back_bubble;
        private Button refresh_bubble;
        private Button more_bubble;
        private string query = "";
        private PlayerBar bar;
        private Revealer bar_reveal;
        private Overlay overlay;
        private Label? toast;
        private uint toast_id;
        private bool refreshing;
        private int refresh_added;
        private int refresh_failed;
        private string refresh_error = "";
        private Cancellable? search_cancel;
        private uint search_id;
        private int search_serial;
        private string last_search = "";
        private int shown_limit = 60;
        private int last_saved;

        public PodcastsWindow (PodcastsApp app) {
            Object (application: app);
            this.app = app;
            library = app.library;
            player = app.player;
            downloads = app.downloads;
            queue = app.queue;
            sleep = app.sleep;
            set_default_size (1120, 760);
            set_title (_("Podcasts"));

            sidebar = new AppSidebar (220);
            add_nav ("shows", "view-grid-symbolic", _("Shows"));
            add_nav ("new", "mail-unread-symbolic", _("New Episodes"));
            add_nav ("queue", "view-list-symbolic", _("Up Next"));
            add_nav ("progress", "document-open-recent-symbolic", _("In Progress"));
            add_nav ("downloads", "folder-download-symbolic", _("Downloads"));
            add_nav ("discover", "system-search-symbolic", _("Discover"));
            set_sidebar (sidebar);
            set_sidebar_visible (true);

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.vexpand = true;
            stack.add_named (build_welcome (), "welcome");
            stack.add_named (build_shows (), "shows");
            stack.add_named (build_show (), "show");
            stack.add_named (build_list (), "list");
            stack.add_named (build_discover (), "discover");
            stack.add_named (build_queue (), "queue");

            overlay = new Overlay ();
            overlay.child = stack;
            overlay.vexpand = true;
            bar = new PlayerBar (player, library);
            bar.details_requested.connect ((e) => show_details (e));
            bar.speed_requested.connect (() => speed_menu (bar.speed));
            bar.stop_requested.connect (() => stop_playback ());
            bar.chapters_requested.connect (() => chapters_menu (bar.chapters));
            bar.sleep_requested.connect (() => sleep_menu ());
            bar_reveal = new Revealer ();
            bar_reveal.transition_type = RevealerTransitionType.SLIDE_UP;
            bar_reveal.child = bar;
            var content = new Box (Orientation.VERTICAL, 0);
            content.append (overlay);
            content.append (bar_reveal);
            set_content (content);

            back_bubble = add_bubble_icon ("go-previous-symbolic", _("Back"), () => go_back ());
            search = add_bubble_search (_("Search Shows"), (t) => on_search (t));
            search.entry.activate.connect (() => {
                if (section == "discover") run_discover (search.text, true);
            });
            add_bubble_icon ("list-add-symbolic", _("Add Podcast (Ctrl+N)"), () => add_podcast ());
            refresh_bubble = add_bubble_icon ("view-refresh-symbolic", _("Refresh (Ctrl+R)"), () => refresh_all.begin (false));
            more_bubble = add_bubble_icon ("view-more-symbolic", _("More"), () => show_menu (more_bubble));

            install_actions ();
            library.changed.connect (() => {
                queue.prune (library);
                rebuild ();
            });
            queue.changed.connect (() => {
                update_actions ();
                if (section == "queue") rebuild ();
                else update_rows ();
            });
            sleep.changed.connect (sync_sleep);
            sleep.notify["active"].connect (update_actions);
            if (app.settings != null) {
                app.settings.changed.connect ((key) => {
                    if (key == "trim-silence" || key == "voice-boost") {
                        apply_show_settings (false);
                        sync_effect_actions ();
                    }
                });
            }
            library.episode_changed.connect (() => update_rows ());
            player.notify["state"].connect (() => on_player_state ());
            player.notify["episode"].connect (() => on_player_state ());
            player.tick.connect (() => on_tick ());
            player.finished.connect ((e) => on_finished (e));
            player.failed.connect ((m) => show_error (_("Could Not Play the Episode"), m));
            downloads.progress_changed.connect (() => update_rows ());
            downloads.finished.connect ((e, err) => {
                if (err != null) show_toast (_("Download failed: %s").printf (err));
                else if (e.download_path != "") show_toast (_("Downloaded %s").printf (e.title));
                if (section == "downloads") rebuild ();
                else update_rows ();
            });
            close_request.connect (() => {
                save_position ();
                library.save ();
                app.save_settings ();
                return false;
            });
            rebuild ();
            on_player_state ();
        }

        private void add_nav (string id, string icon, string title) {
            var row = new SidebarRow (icon, title);
            row.clicked.connect (() => go (id));
            nav[id] = row;
            sidebar.box.append (row);
        }

        private Widget build_welcome () {
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.podcasts";
            wp.title = _("Podcasts");
            wp.subtitle = _("Follow shows, listen to new episodes and pick up where you left off");
            wp.add_action ("audio-x-generic", _("Add Podcast"), _("Search the directory or enter a feed address"), () => add_podcast ());
            wp.add_action ("folder-download", _("Import Subscriptions"), _("Bring your shows from another app with an OPML file"), () => import_opml ());
            return wp;
        }

        private Widget build_shows () {
            grid = new FlowBox ();
            grid.add_css_class ("podcasts-grid");
            grid.selection_mode = SelectionMode.NONE;
            grid.activate_on_single_click = true;
            grid.homogeneous = true;
            grid.min_children_per_line = 1;
            grid.max_children_per_line = 8;
            grid.column_spacing = 12;
            grid.row_spacing = 16;
            grid.valign = Align.START;
            grid.set_filter_func ((child) => {
                if (query == "") return true;
                var s = ((ShowCard) child).item;
                return s.title.down ().contains (query) || s.author.down ().contains (query);
            });
            grid.child_activated.connect ((child) => open_show (((ShowCard) child).item));
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = grid;
            apply_view_edge (scroll);
            return scroll;
        }

        private Widget build_show () {
            show_box = new Box (Orientation.VERTICAL, 18);
            show_box.add_css_class ("podcasts-page");
            show_scroll = new ScrolledWindow ();
            show_scroll.hscrollbar_policy = PolicyType.NEVER;
            show_scroll.child = new Clamp (show_box) { maximum = 860 };
            apply_view_edge (show_scroll);
            return show_scroll;
        }

        private Widget build_list () {
            var box = new Box (Orientation.VERTICAL, 6);
            box.add_css_class ("podcasts-page");
            list_title = new Label ("");
            list_title.add_css_class ("podcasts-page-title");
            list_title.xalign = 0;
            box.append (list_title);
            list_hint = new Label ("");
            list_hint.add_css_class ("dim-label");
            list_hint.xalign = 0;
            list_hint.wrap = true;
            box.append (list_hint);
            list_box = new ListBox ();
            list_box.add_css_class ("podcasts-list");
            list_box.selection_mode = SelectionMode.NONE;
            list_box.row_activated.connect ((row) => {
                var er = row as EpisodeRow;
                if (er != null) show_details (er.episode);
            });
            list_box.margin_top = 6;
            box.append (list_box);
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = new Clamp (box) { maximum = 860 };
            apply_view_edge (scroll);
            list_empty = new Box (Orientation.VERTICAL, 0);
            list_empty.vexpand = true;
            list_stack = new Stack ();
            list_stack.add_named (scroll, "list");
            list_stack.add_named (list_empty, "empty");
            return list_stack;
        }

        private Widget build_discover () {
            var box = new Box (Orientation.VERTICAL, 6);
            box.add_css_class ("podcasts-page");
            var heading = new Label (_("Discover"));
            heading.add_css_class ("podcasts-page-title");
            heading.xalign = 0;
            box.append (heading);
            var credit = new Label (_("Results from the Apple Podcasts directory"));
            credit.add_css_class ("dim-label");
            credit.add_css_class ("caption");
            credit.xalign = 0;
            box.append (credit);
            discover_list = new ListBox ();
            discover_list.add_css_class ("podcasts-list");
            discover_list.selection_mode = SelectionMode.NONE;
            discover_list.margin_top = 6;
            discover_list.row_activated.connect ((row) => {
                var r = row.get_data<SearchResult> ("result");
                if (r == null) return;
                var existing = library.find_show (r.feed_url);
                if (existing != null) open_show (existing);
                else subscribe.begin (r.feed_url, true);
            });
            box.append (discover_list);
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = new Clamp (box) { maximum = 860 };
            apply_view_edge (scroll);
            discover_status = new StatusPage ();
            discover_status.icon_name = "dev.sinty.podcasts";
            discover_status.vexpand = true;
            discover_spinner = new Spinner ();
            discover_action = new Button ();
            discover_action.add_css_class ("pill");
            discover_action.halign = Align.CENTER;
            discover_action.clicked.connect (() => {
                if (discover_action_kind == "retry") run_discover (last_search, true);
                else if (discover_action_kind == "add") add_podcast ();
            });
            var discover_child = new Box (Orientation.VERTICAL, 12);
            discover_child.append (discover_spinner);
            discover_child.append (discover_action);
            discover_status.child = discover_child;
            var idle = new WelcomePage ();
            idle.is_section = true;
            idle.app_icon_name = "dev.sinty.podcasts";
            idle.title = _("Find New Podcasts");
            idle.subtitle = _("Type a name, a topic or a host in the search field and press Enter.");
            idle.add_action ("system-search", _("Search the Directory"), _("Look up shows by name, topic or host"), () => search.grab_focus_entry ());
            idle.add_action ("audio-x-generic", _("Add by Address"), _("Follow a show with its feed address"), () => add_podcast ());
            idle.add_action ("folder-download", _("Import Subscriptions"), _("Bring your shows from another app with an OPML file"), () => import_opml ());
            discover_stack = new Stack ();
            discover_stack.add_named (scroll, "results");
            discover_stack.add_named (discover_status, "status");
            discover_stack.add_named (idle, "idle");
            discover_stack.visible_child_name = "idle";
            return discover_stack;
        }

        private void discover_state (string title, string description, bool busy, string action = "") {
            discover_status.title = title;
            discover_status.description = description;
            discover_spinner.spinning = busy;
            discover_spinner.visible = busy;
            discover_action_kind = action;
            discover_action.visible = action != "";
            discover_action.label = action == "retry" ? _("Try Again") : _("Add by Address");
            discover_stack.visible_child_name = "status";
        }

        public void go (string id) {
            section = id;
            current_show = null;
            shown_limit = 60;
            if (search.text != "") search.clear ();
            query = "";
            rebuild ();
            if (id == "discover") {
                search.grab_focus_entry ();
                if (last_search != "") search.text = last_search;
            }
        }

        private void go_back () {
            if (section == "show") go ("shows");
        }

        private void sync_chrome () {
            string active = section == "show" ? "shows" : section;
            foreach (var e in nav.entries) e.value.set_active (e.key == active);
            back_bubble.visible = section == "show";
            update_actions ();
            more_bubble.visible = section == "show" || (section == "shows" && library.shows.size > 0);
            refresh_bubble.visible = library.shows.size > 0 && section != "discover";
            refresh_bubble.sensitive = !refreshing;
            switch (section) {
                case "discover": search.placeholder = _("Search the Directory"); break;
                case "shows": search.placeholder = _("Search Shows"); break;
                default: search.placeholder = _("Search Episodes"); break;
            }
        }

        private void rebuild () {
            if (current_show != null && !library.shows.contains (current_show)) {
                current_show = null;
                section = "shows";
            }
            bool empty = library.shows.size == 0;
            rows.clear ();
            if (section == "discover") {
                stack.visible_child_name = "discover";
                refresh_discover_buttons ();
            } else if (empty) {
                stack.visible_child_name = "welcome";
            } else if (section == "show" && current_show != null) {
                build_show_page (current_show);
                stack.visible_child_name = "show";
            } else if (section == "queue") {
                build_queue_page ();
                stack.visible_child_name = "queue";
            } else if (section == "shows") {
                build_grid ();
                stack.visible_child_name = "shows";
            } else {
                build_episode_list ();
                stack.visible_child_name = "list";
            }
            sync_chrome ();
        }

        private void build_grid () {
            Widget? c;
            while ((c = grid.get_first_child ()) != null) grid.remove (c);
            foreach (var s in library.shows) {
                var card = new ShowCard (s);
                var click = new GestureClick ();
                click.button = 3;
                click.pressed.connect ((n, x, y) => show_card_menu (card, x, y));
                card.add_controller (click);
                var press = new GestureLongPress ();
                press.pressed.connect ((x, y) => show_card_menu (card, x, y));
                card.add_controller (press);
                grid.append (card);
            }
        }

        private void show_card_menu (ShowCard card, double x, double y) {
            var s = card.item;
            var menu = new ContextMenu (card);
            menu.add_item (_("Open"), "document-open-symbolic", () => open_show (s));
            menu.add_item (_("Refresh"), "view-refresh-symbolic", () => refresh_show.begin (s));
            menu.add_item (_("Mark All as Played"), "object-select-symbolic", () => library.mark_all_played (s));
            menu.add_item (_("Playback Settings"), "emblem-system-symbolic", () => show_settings (s));
            menu.add_separator ();
            menu.add_item (_("Unsubscribe"), "user-trash-symbolic", () => confirm_unsubscribe (s), "destructive");
            menu.pointing_to = { (int) x, (int) y, 1, 1 };
            popup (menu);
        }

        private void popup (ContextMenu menu) {
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void anchor (ContextMenu menu, Widget w) {
            Graphene.Rect bounds;
            if (w.compute_bounds (menu.get_parent (), out bounds)) {
                var rect = Gdk.Rectangle ();
                rect.x = (int) bounds.origin.x;
                rect.y = (int) bounds.origin.y;
                rect.width = (int) bounds.size.width;
                rect.height = (int) bounds.size.height;
                menu.pointing_to = rect;
            }
            menu.position = PositionType.BOTTOM;
        }

        public void open_show (Show s) {
            section = "show";
            current_show = s;
            shown_limit = 60;
            if (search.text != "") search.clear ();
            query = "";
            rebuild ();
            show_scroll.vadjustment.value = 0;
        }

        private bool matches (Episode e) {
            if (query == "") return true;
            if (e.title.down ().contains (query)) return true;
            var s = library.find_show (e.show_url);
            return s != null && s.title.down ().contains (query);
        }

        private void build_show_page (Show s) {
            Widget? c;
            while ((c = show_box.get_first_child ()) != null) show_box.remove (c);
            var head = new Box (Orientation.HORIZONTAL, 22);
            var art = new ArtworkView (168, 16);
            art.valign = Align.START;
            art.set_url (s.image_url);
            head.append (art);
            var info = new Box (Orientation.VERTICAL, 6);
            info.hexpand = true;
            info.valign = Align.CENTER;
            var title = new Label (s.title);
            title.add_css_class ("podcasts-show-title");
            title.xalign = 0;
            title.wrap = true;
            title.selectable = true;
            info.append (title);
            if (s.author != "") {
                var author = new Label (s.author);
                author.add_css_class ("dim-label");
                author.xalign = 0;
                author.wrap = true;
                info.append (author);
            }
            string[] facts = {};
            facts += ngettext ("%d episode", "%d episodes", s.episodes.size).printf (s.episodes.size);
            int unplayed = s.unplayed ();
            if (unplayed > 0) facts += ngettext ("%d unplayed", "%d unplayed", unplayed).printf (unplayed);
            if (s.refreshed > 0) {
                string updated = Format.date (s.refreshed);
                if (updated == _("Today") || updated == _("Yesterday")) updated = updated.down ();
                facts += _("Updated %s").printf (updated);
            }
            var meta = new Label (string.joinv (" · ", facts));
            meta.add_css_class ("dim-label");
            meta.add_css_class ("caption");
            meta.xalign = 0;
            info.append (meta);
            if (s.description != "") {
                var desc = new Label (s.description);
                desc.xalign = 0;
                desc.wrap = true;
                desc.lines = 4;
                desc.ellipsize = Pango.EllipsizeMode.END;
                desc.margin_top = 4;
                info.append (desc);
                if (s.description.length > 240 || s.description.contains ("\n")) {
                    var more = new Button.with_label (_("Read More"));
                    more.add_css_class ("flat");
                    more.halign = Align.START;
                    more.clicked.connect (() => {
                        bool open = desc.lines == 4;
                        desc.lines = open ? -1 : 4;
                        desc.ellipsize = open ? Pango.EllipsizeMode.NONE : Pango.EllipsizeMode.END;
                        more.label = open ? _("Show Less") : _("Read More");
                    });
                    info.append (more);
                }
            }
            var actions = new Box (Orientation.HORIZONTAL, 8);
            actions.margin_top = 6;
            Episode? next = null;
            foreach (var e in s.episodes) {
                if (e.in_progress ()) {
                    next = e;
                    break;
                }
            }
            if (next == null) foreach (var e in s.episodes) {
                if (!e.played) {
                    next = e;
                    break;
                }
            }
            if (next == null && s.episodes.size > 0) next = s.episodes[0];
            if (next != null) {
                var target = next;
                var play = new Button.with_label (target.in_progress () ? _("Resume") : _("Play Latest"));
                play.add_css_class ("suggested-action");
                play.add_css_class ("pill");
                play.tooltip_text = target.title;
                play.clicked.connect (() => play_episode (target));
                actions.append (play);
            }
            var playback = new Button.with_label (_("Playback Settings"));
            playback.add_css_class ("pill");
            playback.clicked.connect (() => show_settings (s));
            actions.append (playback);
            if (s.link != "") {
                string link = s.link;
                var web = new Button.with_label (_("Website"));
                web.add_css_class ("pill");
                web.clicked.connect (() => new UriLauncher (link).launch.begin (this, null));
                actions.append (web);
            }
            info.append (actions);
            head.append (info);
            show_box.append (head);
            if (s.error != "") {
                var err = new Label (_("The last refresh failed: %s").printf (s.error));
                err.add_css_class ("error");
                err.xalign = 0;
                err.wrap = true;
                show_box.append (err);
            }
            var list = new ListBox ();
            list.add_css_class ("podcasts-list");
            list.selection_mode = SelectionMode.NONE;
            list.row_activated.connect ((row) => {
                var er = row as EpisodeRow;
                if (er != null) show_details (er.episode);
            });
            int shown = 0, total = 0;
            foreach (var e in s.episodes) {
                if (!matches (e)) continue;
                total++;
                if (shown >= shown_limit) continue;
                list.append (make_row (e, false));
                shown++;
            }
            if (total == 0) {
                var none = new Label (query != "" ? _("No episodes match your search.") : _("This show has no episodes yet."));
                none.add_css_class ("dim-label");
                none.margin_top = 12;
                show_box.append (none);
            } else {
                show_box.append (list);
            }
            if (total > shown) show_box.append (more_button (total - shown));
        }

        private Button more_button (int hidden) {
            var b = new Button.with_label (ngettext ("Show %d More Episode", "Show %d More Episodes", int.min (hidden, 60)).printf (int.min (hidden, 60)));
            b.add_css_class ("pill");
            b.halign = Align.CENTER;
            b.clicked.connect (() => {
                shown_limit += 60;
                double v = section == "show" ? show_scroll.vadjustment.value : 0;
                rebuild ();
                if (section == "show") Idle.add (() => {
                    show_scroll.vadjustment.value = v;
                    return Source.REMOVE;
                });
            });
            return b;
        }

        private void build_episode_list () {
            Widget? c;
            while ((c = list_box.get_first_child ()) != null) list_box.remove (c);
            Gee.List<Episode> items;
            string empty_title, empty_text;
            switch (section) {
                case "progress":
                    list_title.label = _("In Progress");
                    list_hint.label = _("Episodes you started and have not finished");
                    items = library.in_progress ();
                    empty_title = _("Nothing in Progress");
                    empty_text = _("Episodes you start listening to appear here, so you can continue later.");
                    break;
                case "downloads":
                    list_title.label = _("Downloads");
                    list_hint.label = _("Episodes saved on this computer, to listen without a connection");
                    items = library.downloaded ();
                    foreach (var s in library.shows) foreach (var e in s.episodes) if (downloads.is_active (e) && !items.contains (e)) items.insert (0, e);
                    empty_title = _("No Downloads");
                    empty_text = _("Download episodes from their menu to listen when you are offline.");
                    break;
                default:
                    list_title.label = _("New Episodes");
                    list_hint.label = _("The latest episodes of all your shows");
                    items = library.latest (400);
                    empty_title = _("No Episodes Yet");
                    empty_text = _("New episodes of your shows appear here after a refresh.");
                    break;
            }
            int shown = 0, total = 0;
            foreach (var e in items) {
                if (!matches (e)) continue;
                total++;
                if (shown >= shown_limit) continue;
                list_box.append (make_row (e, true));
                shown++;
            }
            if (total > shown) {
                var row = new ListBoxRow ();
                row.activatable = false;
                row.child = more_button (total - shown);
                list_box.append (row);
            }
            if (total == 0) {
                string key = query != "" ? "query" : section;
                if (key != empty_key || list_empty.get_first_child () == null) {
                    empty_key = key;
                    var old = list_empty.get_first_child ();
                    if (old != null) list_empty.remove (old);
                    list_empty.append (query != "" ? build_no_results () : build_empty_section (empty_title, empty_text));
                }
                list_stack.visible_child_name = "empty";
            } else {
                list_stack.visible_child_name = "list";
            }
        }

        private Widget build_no_results () {
            var page = new StatusPage ();
            page.icon_name = "system-search";
            page.title = _("No Results");
            page.description = _("No episodes match your search.");
            page.vexpand = true;
            var clear = new Button.with_label (_("Clear Search"));
            clear.add_css_class ("pill");
            clear.add_css_class ("suggested-action");
            clear.halign = Align.CENTER;
            clear.clicked.connect (() => search.clear ());
            page.child = clear;
            return page;
        }

        private Widget build_empty_section (string title, string text) {
            var wp = new WelcomePage ();
            wp.is_section = true;
            wp.vexpand = true;
            wp.app_icon_name = "dev.sinty.podcasts";
            wp.title = title;
            wp.subtitle = text;
            switch (section) {
                case "progress":
                    wp.add_action ("document-open-recent", _("New Episodes"), _("Start something new to listen to"), () => go ("new"));
                    wp.add_action ("folder-music", _("Your Shows"), _("Pick an episode from a show you follow"), () => go ("shows"));
                    break;
                case "downloads":
                    wp.add_action ("document-open-recent", _("New Episodes"), _("Find an episode to download"), () => go ("new"));
                    wp.add_action ("folder-music", _("Your Shows"), _("Browse the episodes of a show you follow"), () => go ("shows"));
                    break;
                default:
                    wp.add_action ("emblem-synchronizing", _("Refresh"), _("Look for new episodes of your shows"), () => refresh_all.begin (false));
                    wp.add_action ("folder-music", _("Your Shows"), _("Browse the shows you follow"), () => go ("shows"));
                    wp.add_action ("system-search", _("Discover"), _("Find new podcasts in the directory"), () => go ("discover"));
                    break;
            }
            return wp;
        }

        private EpisodeRow make_row (Episode e, bool with_show) {
            var row = new EpisodeRow (e, with_show);
            if (with_show && e.image_url == "") {
                var s = library.find_show (e.show_url);
                if (row.art != null && s != null) row.art.set_url (s.image_url);
            }
            row.play.clicked.connect (() => play_episode (e));
            row.more.clicked.connect (() => {
                var menu = new ContextMenu (row.more);
                episode_menu_items (menu, e);
                menu.position = PositionType.BOTTOM;
                popup (menu);
            });
            var click = new GestureClick ();
            click.button = 3;
            click.pressed.connect ((n, x, y) => {
                var menu = new ContextMenu (row);
                episode_menu_items (menu, e);
                menu.pointing_to = { (int) x, (int) y, 1, 1 };
                popup (menu);
            });
            row.add_controller (click);
            rows.add (row);
            update_row (row);
            return row;
        }

        private void episode_menu_items (ContextMenu menu, Episode e) {
            bool current = player.episode == e;
            bool playing = current && (player.state == PlayState.PLAYING || player.state == PlayState.LOADING);
            menu.add_item (playing ? _("Pause") : (e.in_progress () ? _("Resume") : _("Play")), playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic", () => play_episode (e));
            menu.add_item (_("Details"), "document-properties-symbolic", () => show_details (e));
            if (current) {
                int at = player.position ();
                var anchor = menu.get_parent ();
                menu.add_item (_("Add Moment to a Note…"), "document-send-symbolic", () => {
                    Idle.add (() => {
                        if (anchor != null) Singularity.Notes.NotePicker.popup (anchor, (id) => add_moment (e, at, id));
                        return Source.REMOVE;
                    });
                });
            }
            string share_link = e.link != "" ? e.link : e.audio_url;
            if (share_link != "") menu.add_item (_("Share…"), "singularity-share-symbolic", () => Singularity.Share.uris ((Gtk.Window) get_root (), { share_link }, e.title));
            if (player.episode != e) {
                int qi = queue.index_of (e);
                if (qi != 0) menu.add_item (_("Play Next"), "media-skip-forward-symbolic", () => {
                    queue.add_next (e);
                    show_toast (_("%s plays next").printf (e.title));
                });
                if (qi < 0) menu.add_item (_("Add to Up Next"), "list-add-symbolic", () => {
                    queue.add (e);
                    show_toast (_("Added to Up Next"));
                });
                else menu.add_item (_("Remove from Up Next"), "list-remove-symbolic", () => queue.remove (e));
            }
            if (e.played) menu.add_item (_("Mark as Unplayed"), "mail-unread-symbolic", () => library.set_played (e, false));
            else menu.add_item (_("Mark as Played"), "object-select-symbolic", () => {
                if (player.episode == e) stop_playback ();
                library.set_played (e, true);
            });
            if (downloads.is_active (e)) menu.add_item (_("Cancel Download"), "process-stop-symbolic", () => downloads.cancel (e));
            else if (e.is_downloaded ()) menu.add_item (_("Delete Download"), "user-trash-symbolic", () => delete_download (e));
            else menu.add_item (_("Download"), "folder-download-symbolic", () => start_download (e));
            if (section != "show") {
                var s = library.find_show (e.show_url);
                if (s != null) menu.add_item (_("Go to Show"), "view-grid-symbolic", () => open_show (s));
            }
            if (e.link != "") {
                string link = e.link;
                menu.add_item (_("Open Episode Page"), "web-browser-symbolic", () => new UriLauncher (link).launch.begin (this, null));
            }
            menu.add_item (_("Copy Audio Address"), "edit-copy-symbolic", () => {
                get_clipboard ().set_text (e.audio_url);
                show_toast (_("Address copied"));
            });
            if (section == "queue") queue_menu_items (menu, e);
        }

        private void update_row (EpisodeRow row) {
            var e = row.episode;
            bool current = player.episode == e;
            bool playing = current && (player.state == PlayState.PLAYING || player.state == PlayState.LOADING);
            row.play.icon_name = playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
            row.play.tooltip_text = playing ? _("Pause") : (e.in_progress () ? _("Resume") : _("Play"));
            if (current) row.add_css_class ("podcasts-current");
            else row.remove_css_class ("podcasts-current");
            if (e.played) row.add_css_class ("podcasts-played");
            else row.remove_css_class ("podcasts-played");
            string[] parts = {};
            if (row.with_show) {
                var s = library.find_show (e.show_url);
                if (s != null) parts += s.title;
            }
            string d = Format.date (e.published);
            if (d != "") parts += d;
            int pos = current ? player.position () : e.position;
            int dur = e.duration > 0 ? e.duration : (current ? player.duration () : 0);
            if (e.played) parts += _("Played");
            else if (pos > 0 && dur > 0) parts += Format.remaining (dur - pos);
            else if (dur > 0) parts += Format.length (dur);
            row.meta.label = string.joinv (" · ", parts);
            row.progress.visible = !e.played && pos > 0 && dur > 0;
            if (row.progress.visible) row.progress.fraction = ((double) pos / dur).clamp (0, 1);
            bool active = downloads.is_active (e);
            double f = downloads.fraction (e);
            row.download_label.visible = active;
            row.download_label.label = f > 0 ? "%d%%".printf ((int) (f * 100)) : _("Waiting");
            row.download_label.tooltip_text = _("Downloading");
            row.download_icon.visible = !active && e.download_path != "";
        }

        private void update_rows () {
            foreach (var r in rows) update_row (r);
        }

        private void on_player_state () {
            bool has = player.episode != null;
            bar_reveal.reveal_child = has;
            if (has) bar.sync ();
            chapter_index = -2;
            if (has) sync_chapter ();
            update_rows ();
            update_actions ();
            if (player.state == PlayState.PAUSED) save_position ();
        }

        private void on_tick () {
            bar.tick ();
            var e = player.episode;
            if (e == null) return;
            int pos = player.position ();
            if (e.duration <= 0) {
                int dur = player.duration ();
                if (dur > 0) {
                    e.duration = dur;
                    library.schedule_save ();
                    app.mpris.refresh_metadata ();
                }
            }
            if ((pos - last_saved).abs () >= 5) {
                last_saved = pos;
                library.set_position (e, pos);
                if (e.played) {
                    e.played = false;
                }
            }
            foreach (var r in rows) if (r.episode == e) update_row (r);
            sync_chapter ();
        }

        private void sync_chapter () {
            var e = player.episode;
            int idx = e != null && e.chapters.size > 0 ? Chapters.index_at (e.chapters, player.position ()) : -1;
            if (idx == chapter_index && e != null) return;
            chapter_index = idx;
            bar.set_chapter (idx >= 0 ? e.chapters[idx] : null);
        }

        private void save_position () {
            var e = player.episode;
            if (e == null) return;
            int pos = player.position ();
            last_saved = pos;
            library.set_position (e, pos);
        }

        private void on_finished (Episode e) {
            library.set_played (e, true);
            library.save ();
            queue.remove (e);
            if (section == "progress") rebuild ();
            if (sleep.active && sleep.mode != SleepMode.MINUTES) {
                sleep.finish ();
                show_toast (_("Finished %s").printf (e.title));
                return;
            }
            if (play_next_in_queue ()) return;
            show_toast (_("Finished %s").printf (e.title));
        }

        private bool play_next_in_queue () {
            while (queue.items.size > 0) {
                var item = queue.pop ();
                var next = library.find_episode (item.show_url, item.key);
                if (next == null) continue;
                show_toast (_("Up next: %s").printf (next.title));
                play_episode (next);
                return true;
            }
            return false;
        }

        public static string moment_uri (Episode e, int seconds) {
            return "sinty-podcasts://moment?show=%s&episode=%s&t=%d".printf (Uri.escape_string (e.show_url, null, false), Uri.escape_string (e.key (), null, false), seconds);
        }

        private void add_moment (Episode e, int seconds, string? note_id) {
            string when = "%d:%02d".printf (seconds / 60, seconds % 60);
            if (seconds >= 3600) when = "%d:%02d:%02d".printf (seconds / 3600, (seconds / 60) % 60, seconds % 60);
            try {
                var note = Singularity.Notes.NotePicker.target (note_id, e.title);
                Singularity.Notes.NotePicker.append (note, "[%s, %s](%s)\n".printf (e.title.replace ("]", ""), when, moment_uri (e, seconds)));
                show_toast (note_id == null ? _("Moment added to a new note") : _("Moment added to %s").printf (note.title));
            } catch (Error err) {
                show_error (_("Could Not Add the Moment"), err.message);
            }
        }

        public void open_moment (string show_url, string key, int seconds) {
            var e = library.find_episode (show_url, key);
            if (e == null) {
                show_toast (_("This episode is no longer in your library"));
                return;
            }
            if (player.episode == e) {
                player.seek_to (seconds);
                if (player.state != PlayState.PLAYING) player.toggle ();
                return;
            }
            library.set_position (e, seconds);
            play_episode (e);
        }

        public void play_episode (Episode e) {
            if (player.episode == e) {
                player.toggle ();
                return;
            }
            save_position ();
            string uri;
            if (e.is_downloaded ()) {
                try {
                    uri = Filename.to_uri (e.download_path);
                } catch (Error err) {
                    uri = e.audio_url;
                }
            } else {
                if (!NetworkMonitor.get_default ().network_available) {
                    show_error (_("You Are Offline"), _("Connect to the internet to stream this episode, or download episodes to listen without a connection."));
                    return;
                }
                uri = e.audio_url;
            }
            if (e.played) {
                e.played = false;
                e.position = 0;
            }
            last_saved = e.position;
            var show = library.find_show (e.show_url);
            player.preset_rate (show != null && show.speed > 0 ? show.speed : app.default_rate);
            player.set_effects (effective_trim (show), effective_boost (show), false);
            queue.remove (e);
            player.open (e, uri);
            library.schedule_save ();
            load_chapters.begin (e);
        }

        private void stop_playback () {
            save_position ();
            sleep.cancel ();
            player.stop ();
        }

        private void start_download (Episode e) {
            if (!NetworkMonitor.get_default ().network_available) {
                show_error (_("You Are Offline"), _("Connect to the internet to download episodes."));
                return;
            }
            downloads.start (e);
            show_toast (_("Downloading %s").printf (e.title));
        }

        private void delete_download (Episode e) {
            if (player.episode == e && e.is_downloaded ()) stop_playback ();
            library.delete_download (e);
            if (section == "downloads") rebuild ();
        }

        private void show_details (Episode e) {
            bool playing = player.episode == e && (player.state == PlayState.PLAYING || player.state == PlayState.LOADING);
            var dlg = new ConfirmDialog (app, e.title, null, null, playing ? _("Pause") : (e.in_progress () ? _("Resume") : _("Play")), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.set_default_size (560, 0);
            if (downloads.is_active (e)) dlg.set_secondary (_("Cancel Download"));
            else if (e.is_downloaded ()) dlg.set_secondary (_("Delete Download"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            else dlg.set_secondary (_("Download"));
            string[] facts = {};
            var s = library.find_show (e.show_url);
            if (s != null) facts += s.title;
            string d = Format.date (e.published);
            if (d != "") facts += d;
            if (e.duration > 0) facts += Format.length (e.duration);
            if (e.size > 0) facts += format_size ((uint64) e.size);
            if (e.played) facts += _("Played");
            else if (e.in_progress ()) facts += Format.remaining (e.remaining ());
            var meta = new Label (string.joinv (" · ", facts));
            meta.add_css_class ("dim-label");
            meta.wrap = true;
            meta.justify = Justification.CENTER;
            dlg.custom_area.append (meta);
            var text = new Label (e.description != "" ? e.description : _("This episode has no description."));
            text.wrap = true;
            text.wrap_mode = Pango.WrapMode.WORD_CHAR;
            text.xalign = 0;
            text.selectable = true;
            text.max_width_chars = 60;
            text.add_css_class ("podcasts-description");
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 340;
            scroll.child = text;
            dlg.custom_area.append (scroll);
            var chapter_group = new PreferencesGroup (_("Chapters"));
            var chapter_scroll = new ScrolledWindow ();
            chapter_scroll.hscrollbar_policy = PolicyType.NEVER;
            chapter_scroll.propagate_natural_height = true;
            chapter_scroll.max_content_height = 260;
            chapter_scroll.child = chapter_group;
            chapter_scroll.visible = false;
            dlg.custom_area.append (chapter_scroll);
            WelcomePage.ActionCallback fill = () => {
                chapter_group.clear ();
                foreach (var c in e.chapters) {
                    var ch = c;
                    var row = new ActionRow (ch.title, Format.clock ((int64) ch.start));
                    row.activated.connect (() => {
                        dlg.close_dialog ();
                        play_at (e, ch.start);
                    });
                    chapter_group.add_row (row);
                }
                chapter_scroll.visible = e.chapters.size > 0;
                if (e.chapters.size > 0) {
                    scroll.max_content_height = 160;
                    scroll.min_content_height = 60;
                    chapter_scroll.min_content_height = int.min (e.chapters.size * 58 + 44, 260);
                }
            };
            if (e.chapters.size > 0) fill ();
            else if (can_load_chapters (e)) load_chapters.begin (e, (o, res) => {
                load_chapters.end (res);
                fill ();
            });
            if (e.link != "") {
                string link = e.link;
                var web = new Button.with_label (_("Open Episode Page"));
                web.add_css_class ("flat");
                web.halign = Align.CENTER;
                web.clicked.connect (() => new UriLauncher (link).launch.begin (this, null));
                dlg.custom_area.append (web);
            }
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) play_episode (e);
                else if (r == ConfirmDialog.Response.SECONDARY) {
                    if (downloads.is_active (e)) downloads.cancel (e);
                    else if (e.is_downloaded ()) delete_download (e);
                    else start_download (e);
                }
            });
            dlg.present ();
        }

        private void speed_menu (Widget anchor_widget) {
            var menu = new ContextMenu (anchor_widget);
            foreach (double r in Player.RATES) {
                double rate = r;
                menu.add_item (Format.speed (rate), Math.fabs (player.rate - rate) < 0.01 ? "object-select-symbolic" : null, () => set_rate (rate));
            }
            var show = player.episode != null ? library.find_show (player.episode.show_url) : null;
            if (show != null) {
                bool own = show.speed > 0;
                menu.add_separator ();
                menu.add_item (_("Only for This Show"), own ? "object-select-symbolic" : null, () => {
                    if (own) {
                        show.speed = 0;
                        library.schedule_save ();
                        player.change_rate (app.default_rate);
                        bar.sync ();
                        show_toast (_("%s uses the default speed").printf (show.title));
                    } else {
                        show.speed = player.rate;
                        library.schedule_save ();
                        show_toast (_("%s always plays at %s").printf (show.title, Format.speed (show.speed)));
                    }
                });
            }
            menu.position = PositionType.TOP;
            popup (menu);
        }

        private void set_rate (double rate) {
            player.change_rate (rate);
            var show = player.episode != null ? library.find_show (player.episode.show_url) : null;
            if (show != null && show.speed > 0) {
                show.speed = player.rate;
                library.schedule_save ();
            } else {
                app.default_rate = player.rate;
            }
            bar.sync ();
            app.save_settings ();
        }

        private void step_rate (int dir) {
            int idx = 1;
            for (int i = 0; i < Player.RATES.length; i++) if (Math.fabs (Player.RATES[i] - player.rate) < 0.01) idx = i;
            idx = (idx + dir).clamp (0, Player.RATES.length - 1);
            set_rate (Player.RATES[idx]);
            show_toast (_("Speed %s").printf (Format.speed (player.rate)));
        }

        private void show_menu (Widget anchor_widget) {
            var menu = new ContextMenu (overlay);
            anchor (menu, anchor_widget);
            if (section == "show" && current_show != null) {
                var s = current_show;
                menu.add_item (_("Refresh Show"), "view-refresh-symbolic", () => refresh_show.begin (s));
                menu.add_item (_("Mark All as Played"), "object-select-symbolic", () => library.mark_all_played (s));
                menu.add_item (_("Playback Settings"), "emblem-system-symbolic", () => show_settings (s));
                if (s.link != "") {
                    string link = s.link;
                    menu.add_item (_("Open Website"), "web-browser-symbolic", () => new UriLauncher (link).launch.begin (this, null));
                }
                menu.add_item (_("Copy Feed Address"), "edit-copy-symbolic", () => {
                    get_clipboard ().set_text (s.feed_url);
                    show_toast (_("Address copied"));
                });
                menu.add_separator ();
                menu.add_item (_("Unsubscribe"), "user-trash-symbolic", () => confirm_unsubscribe (s), "destructive");
            } else {
                menu.add_item (_("Import Subscriptions…"), "document-open-symbolic", () => import_opml ());
                menu.add_item (_("Export Subscriptions…"), "document-save-symbolic", () => export_opml ());
            }
            popup (menu);
        }

        private void confirm_unsubscribe (Show s) {
            var dlg = new ConfirmDialog (app, _("Unsubscribe from %s?").printf (s.title), null,
                _("The show, its listening progress and its downloaded episodes are removed."), _("Unsubscribe"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                if (player.episode != null && player.episode.show_url == s.feed_url) stop_playback ();
                foreach (var e in s.episodes) if (downloads.is_active (e)) downloads.cancel (e);
                if (current_show == s) {
                    current_show = null;
                    section = "shows";
                }
                library.remove_show (s);
            });
            dlg.present ();
        }

        private void on_search (string t) {
            if (section == "discover") {
                if (search_id != 0) Source.remove (search_id);
                search_id = 0;
                if (t.strip ().length >= 3) {
                    search_id = Timeout.add (600, () => {
                        search_id = 0;
                        run_discover (search.text, false);
                        return Source.REMOVE;
                    });
                }
                return;
            }
            string q = t.strip ().down ();
            if (q == query) return;
            query = q;
            shown_limit = 60;
            if (section == "shows") grid.invalidate_filter ();
            else if (library.shows.size > 0) rebuild ();
        }

        private void run_discover (string text, bool force) {
            string term = text.strip ();
            if (term == "") return;
            if (search_id != 0) {
                Source.remove (search_id);
                search_id = 0;
            }
            if (Net.looks_like_url (term) && term.contains ("/")) {
                subscribe.begin (Net.normalize_url (term), true);
                return;
            }
            if (!force && term == last_search && discover_stack.visible_child_name == "results") return;
            last_search = term;
            if (search_cancel != null) search_cancel.cancel ();
            var cancel = new Cancellable ();
            search_cancel = cancel;
            int serial = ++search_serial;
            discover_state (_("Searching"), term, true);
            Net.search.begin (term, cancel, (o, res) => {
                if (serial != search_serial) return;
                try {
                    var results = Net.search.end (res);
                    show_results (results, term);
                } catch (Error e) {
                    if (e is IOError.CANCELLED) return;
                    discover_state (_("Search Is Not Available"), e.message, false, "retry");
                }
            });
        }

        private void show_results (Gee.List<SearchResult> results, string term) {
            Widget? c;
            while ((c = discover_list.get_first_child ()) != null) discover_list.remove (c);
            if (results.size == 0) {
                discover_state (_("No Podcasts Found"), _("Nothing matches “%s”. Try other words, or add the show with its feed address.").printf (term), false, "add");
                return;
            }
            foreach (var r in results) {
                var row = new ListBoxRow ();
                row.set_data<SearchResult> ("result", r);
                var box = new Box (Orientation.HORIZONTAL, 12);
                var art = new ArtworkView (56, 10);
                art.valign = Align.CENTER;
                art.set_url (r.artwork);
                box.append (art);
                var texts = new Box (Orientation.VERTICAL, 3);
                texts.hexpand = true;
                texts.valign = Align.CENTER;
                var title = new Label (r.title);
                title.add_css_class ("podcasts-episode-title");
                title.xalign = 0;
                title.wrap = true;
                title.lines = 2;
                title.ellipsize = Pango.EllipsizeMode.END;
                texts.append (title);
                string[] parts = {};
                if (r.author != "") parts += r.author;
                if (r.genre != "") parts += r.genre;
                if (r.episodes > 0) parts += ngettext ("%d episode", "%d episodes", r.episodes).printf (r.episodes);
                var sub = new Label (string.joinv (" · ", parts));
                sub.add_css_class ("dim-label");
                sub.add_css_class ("caption");
                sub.xalign = 0;
                sub.ellipsize = Pango.EllipsizeMode.END;
                texts.append (sub);
                box.append (texts);
                var add = new Button ();
                add.add_css_class ("pill");
                add.valign = Align.CENTER;
                string url = r.feed_url;
                add.clicked.connect (() => {
                    var existing = library.find_show (url);
                    if (existing != null) open_show (existing);
                    else subscribe.begin (url, false);
                });
                row.set_data<Button> ("button", add);
                box.append (add);
                row.child = box;
                discover_list.append (row);
            }
            refresh_discover_buttons ();
            discover_stack.visible_child_name = "results";
        }

        private void refresh_discover_buttons () {
            for (var c = discover_list.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var r = c.get_data<SearchResult> ("result");
                var b = c.get_data<Button> ("button");
                if (r == null || b == null) continue;
                bool have = library.find_show (r.feed_url) != null;
                b.label = have ? _("Open") : _("Subscribe");
                if (have) b.remove_css_class ("suggested-action");
                else b.add_css_class ("suggested-action");
            }
        }

        public void add_podcast () {
            var dlg = new ConfirmDialog (app, _("Add Podcast"), null, _("Enter the address of a podcast feed, or the name of a show to search for it."), _("Add"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.set_default_size (440, 0);
            var group = new PreferencesGroup (_("Podcast"));
            var entry = new EntryRow (_("Feed Address or Show Name"));
            group.add_row (entry);
            dlg.custom_area.append (group);
            var hint = new Label ("");
            hint.add_css_class ("dim-label");
            hint.add_css_class ("caption");
            hint.wrap = true;
            hint.max_width_chars = 44;
            dlg.custom_area.append (hint);
            dlg.primary_sensitive = false;
            entry.entry_changed.connect (() => {
                string t = entry.text.strip ();
                dlg.primary_sensitive = t != "";
                if (t == "") hint.label = "";
                else if (Net.looks_like_url (t)) hint.label = _("Subscribes to the feed at %s").printf (Net.normalize_url (t));
                else hint.label = _("Searches the podcast directory for “%s”").printf (t);
            });
            entry.entry_activated.connect (() => {
                if (entry.text.strip () == "") return;
                dlg.response (ConfirmDialog.Response.PRIMARY);
                dlg.close_dialog ();
            });
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                string t = entry.text.strip ();
                if (t == "") return;
                if (Net.looks_like_url (t)) {
                    subscribe.begin (Net.normalize_url (t), true);
                } else {
                    go ("discover");
                    search.text = t;
                    run_discover (t, true);
                }
            });
            dlg.present ();
            entry.grab_focus ();
        }

        public async void subscribe (string url, bool open) {
            var existing = library.find_show (url);
            if (existing != null) {
                if (open) open_show (existing);
                return;
            }
            show_toast (_("Adding the podcast…"), 0);
            try {
                var show = yield Net.fetch_show (url);
                existing = library.find_show (show.feed_url);
                if (existing != null) {
                    hide_toast ();
                    if (open) open_show (existing);
                    return;
                }
                library.add_show (show);
                show_toast (_("Subscribed to %s").printf (show.title));
                if (open) open_show (show);
                else refresh_discover_buttons ();
            } catch (Error e) {
                hide_toast ();
                show_error (_("Could Not Add the Podcast"), e.message);
            }
        }

        public async void refresh_show (Show s) {
            try {
                var fresh = yield Net.fetch_show (s.feed_url);
                int added = library.merge (s, fresh);
                library.save ();
                library.changed ();
                show_toast (added > 0 ? ngettext ("%d new episode", "%d new episodes", added).printf (added) : _("%s is up to date").printf (s.title));
            } catch (Error e) {
                s.error = e.message;
                rebuild ();
                show_error (_("Could Not Refresh %s").printf (s.title), e.message);
            }
        }

        public async void refresh_all (bool quiet) {
            if (refreshing || library.shows.size == 0) return;
            if (!NetworkMonitor.get_default ().network_available) {
                if (!quiet) show_error (_("You Are Offline"), _("Connect to the internet to look for new episodes."));
                return;
            }
            refreshing = true;
            ArtworkCache.get_default ().retry_failed ();
            sync_chrome ();
            if (!quiet) show_toast (_("Looking for new episodes…"), 0);
            refresh_added = 0;
            refresh_failed = 0;
            refresh_error = "";
            var todo = new Gee.LinkedList<Show> ();
            todo.add_all (library.shows);
            int workers = int.min (4, todo.size);
            int left = workers;
            SourceFunc cb = refresh_all.callback;
            for (int i = 0; i < workers; i++) {
                refresh_worker.begin (todo, (o, res) => {
                    refresh_worker.end (res);
                    if (--left == 0) Idle.add ((owned) cb);
                });
            }
            yield;
            library.last_refresh = new DateTime.now_utc ().to_unix ();
            library.save ();
            refreshing = false;
            library.changed ();
            if (refresh_failed > 0 && refresh_failed == library.shows.size) {
                if (!quiet) show_error (_("Could Not Refresh"), refresh_error);
                else hide_toast ();
            } else if (refresh_added > 0) {
                show_toast (ngettext ("%d new episode", "%d new episodes", refresh_added).printf (refresh_added));
            } else if (!quiet) {
                show_toast (refresh_failed > 0 ? ngettext ("%d show could not be refreshed", "%d shows could not be refreshed", refresh_failed).printf (refresh_failed) : _("Everything is up to date"));
            }
        }

        private async void refresh_worker (Gee.LinkedList<Show> todo) {
            while (todo.size > 0) {
                var s = todo.poll_head ();
                try {
                    var fresh = yield Net.fetch_show (s.feed_url);
                    if (library.shows.contains (s)) refresh_added += library.merge (s, fresh);
                } catch (Error e) {
                    s.error = e.message;
                    refresh_error = e.message;
                    refresh_failed++;
                }
            }
        }

        public void import_opml () {
            var dialog = new FileDialog ();
            dialog.title = _("Import Subscriptions");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = _("OPML Files");
            f.add_suffix ("opml");
            f.add_suffix ("xml");
            f.add_mime_type ("text/x-opml+xml");
            filters.append (f);
            dialog.filters = filters;
            dialog.open.begin (this, null, (o, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) import_file.begin (file);
                } catch (Error e) {
                }
            });
        }

        private async void import_file (File file) {
            Gee.List<Outline> outlines;
            try {
                uint8[] data;
                yield file.load_contents_async (null, out data, null);
                outlines = Opml.parse ((string) data);
            } catch (Error e) {
                show_error (_("Could Not Import"), e.message);
                return;
            }
            var todo = new Gee.ArrayList<Outline> ();
            foreach (var o in outlines) if (library.find_show (o.feed_url) == null) todo.add (o);
            if (todo.size == 0) {
                show_error (_("Nothing to Import"), outlines.size == 0 ? _("The file does not contain any podcast feeds.") : _("You are already subscribed to every show in this file."));
                return;
            }
            if (!NetworkMonitor.get_default ().network_available) {
                show_error (_("You Are Offline"), _("Connect to the internet to import your subscriptions."));
                return;
            }
            int done = 0, added = 0;
            string[] failed = {};
            foreach (var o in todo) {
                show_toast (_("Importing %d of %d…").printf (done + 1, todo.size), 0);
                try {
                    var show = yield Net.fetch_show (o.feed_url);
                    if (library.find_show (show.feed_url) == null) {
                        library.add_show (show);
                        added++;
                    }
                } catch (Error e) {
                    failed += o.title != "" ? o.title : o.feed_url;
                }
                done++;
            }
            hide_toast ();
            if (failed.length > 0) {
                show_error (ngettext ("%d Show Imported", "%d Shows Imported", added).printf (added),
                    _("These shows could not be added:\n%s").printf (string.joinv ("\n", failed)));
            } else {
                show_toast (ngettext ("%d show imported", "%d shows imported", added).printf (added));
            }
            if (section != "discover") go ("shows");
        }

        public void export_opml () {
            if (library.shows.size == 0) {
                show_error (_("Nothing to Export"), _("Subscribe to some shows first."));
                return;
            }
            var dialog = new FileDialog ();
            dialog.title = _("Export Subscriptions");
            dialog.initial_name = _("Podcasts") + ".opml";
            dialog.save.begin (this, null, (o, res) => {
                try {
                    var file = dialog.save.end (res);
                    if (file == null) return;
                    string text = Opml.serialize (library.outlines (), _("Podcasts"));
                    file.replace_contents (text.data, null, false, FileCreateFlags.REPLACE_DESTINATION, null);
                    show_toast (ngettext ("%d show exported", "%d shows exported", library.shows.size).printf (library.shows.size));
                } catch (Error e) {
                    if (!(e is Gtk.DialogError)) show_error (_("Could Not Export"), e.message);
                }
            });
        }

        private void enable (string name, bool on) {
            if (!actions_ready) return;
            var a = lookup_action (name) as SimpleAction;
            if (a != null && a.get_enabled () != on) a.set_enabled (on);
        }

        private void update_actions () {
            if (!actions_ready) return;
            bool has = player.episode != null;
            bool chapters = has && player.episode.chapters.size > 0;
            bool shows = library.shows.size > 0;
            foreach (string n in new string[] { "play-pause", "skip-back", "skip-forward", "stop", "faster", "slower", "normal-speed", "sleep-timer" }) enable (n, has);
            enable ("chapters", chapters);
            enable ("chapter-prev", chapters);
            enable ("chapter-next", chapters);
            enable ("queue-next", queue.items.size > 0);
            enable ("queue-clear", queue.items.size > 0);
            enable ("cancel-sleep", sleep.active);
            enable ("back", section == "show");
            enable ("mark-all", current_show != null);
            enable ("unsubscribe", current_show != null);
            enable ("show-settings", current_show != null || has);
            enable ("export", shows);
            enable ("refresh", shows && !refreshing);
        }

        private bool effective_trim (Show? show) {
            if (show != null && show.trim_silence >= 0) return show.trim_silence == 1;
            return app.trim_default;
        }

        private bool effective_boost (Show? show) {
            if (show != null && show.voice_boost >= 0) return show.voice_boost == 1;
            return app.boost_default;
        }

        private void apply_show_settings (bool with_rate) {
            var e = player.episode;
            if (e == null) return;
            var show = library.find_show (e.show_url);
            player.set_effects (effective_trim (show), effective_boost (show));
            if (player.effects_error != "") show_toast (player.effects_error);
            if (with_rate) player.change_rate (show != null && show.speed > 0 ? show.speed : app.default_rate);
            bar.sync ();
        }

        private void sync_effect_actions () {
            if (trim_action != null) trim_action.set_state (new Variant.boolean (app.trim_default));
            if (boost_action != null) boost_action.set_state (new Variant.boolean (app.boost_default));
        }

        private Gee.ArrayList<Singularity.Core.AppSettingOption> options (string[] ids, string[] labels) {
            var list = new Gee.ArrayList<Singularity.Core.AppSettingOption> ();
            for (int i = 0; i < ids.length; i++) {
                var o = new Singularity.Core.AppSettingOption ();
                o.id = ids[i];
                o.label = labels[i];
                list.add (o);
            }
            return list;
        }

        private string rate_id (double rate) {
            return "%.2f".printf (rate).replace (",", ".");
        }

        private SelectionRow toggle_choice (string title, bool global_on, int value, owned SelectionCallback done) {
            string def = global_on ? _("Default (On)") : _("Default (Off)");
            var row = new SelectionRow.with_options (title, options ({ "default", "on", "off" }, { def, _("On"), _("Off") }), value < 0 ? "default" : (value == 1 ? "on" : "off"));
            SelectionCallback cb = (owned) done;
            row.selected.connect ((id) => {
                row.current_value = id;
                row.expanded = false;
                cb (id == "default" ? -1 : (id == "on" ? 1 : 0));
            });
            return row;
        }

        public delegate void SelectionCallback (int value);

        private void show_settings (Show s) {
            var dlg = new ConfirmDialog (app, _("Playback Settings"), null, s.title, _("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.set_default_size (440, 0);
            var group = new PreferencesGroup (_("Playback"), _("Default follows the Podcasts settings. Trim Silence plays the show in mono."));
            string[] ids = { "default" };
            string[] labels = { _("Default (%s)").printf (Format.speed (app.default_rate)) };
            foreach (double r in Player.RATES) {
                ids += rate_id (r);
                labels += Format.speed (r);
            }
            double speed = s.speed;
            int trim = s.trim_silence;
            int boost = s.voice_boost;
            var speed_row = new SelectionRow.with_options (_("Speed"), options (ids, labels), s.speed > 0 ? rate_id (s.speed) : "default");
            speed_row.selected.connect ((id) => {
                speed_row.current_value = id;
                speed_row.expanded = false;
                speed = id == "default" ? 0 : double.parse (id);
            });
            group.add_row (speed_row);
            group.add_row (toggle_choice (_("Trim Silence"), app.trim_default, s.trim_silence, (v) => trim = v));
            group.add_row (toggle_choice (_("Voice Boost"), app.boost_default, s.voice_boost, (v) => boost = v));
            dlg.custom_area.append (group);
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                bool rate_changed = speed != s.speed;
                s.speed = speed;
                s.trim_silence = trim;
                s.voice_boost = boost;
                library.save ();
                if (player.episode != null && player.episode.show_url == s.feed_url) apply_show_settings (rate_changed);
            });
            dlg.present ();
        }

        private bool can_load_chapters (Episode e) {
            if (e.chapters.size > 0) return false;
            if (e.chapters_url != "" && !e.chapters_fetched) return true;
            return e.is_downloaded () && !id3_checked.contains (e);
        }

        private async void load_chapters (Episode e) {
            if (e.chapters.size == 0 && e.chapters_url != "" && !e.chapters_fetched) {
                try {
                    var list = yield Net.fetch_chapters (e.chapters_url);
                    e.chapters.clear ();
                    e.chapters.add_all (list);
                    e.chapters_fetched = true;
                    library.schedule_save ();
                } catch (Error err) {
                    if (err is IOError.INVALID_DATA || err is Json.ParserError) e.chapters_fetched = true;
                    warning ("podcasts: chapters for %s: %s", e.title, err.message);
                }
            }
            if (e.chapters.size == 0 && e.is_downloaded () && !id3_checked.contains (e)) {
                id3_checked.add (e);
                try {
                    var list = Chapters.read_id3_file (e.download_path);
                    if (list.size > 0) {
                        e.chapters.add_all (list);
                        library.schedule_save ();
                    }
                } catch (Error err) {
                    warning ("podcasts: chapters in %s: %s", e.download_path, err.message);
                }
            }
            if (player.episode == e) {
                bar.sync ();
                chapter_index = -2;
                sync_chapter ();
                update_actions ();
            }
        }

        private void play_at (Episode e, double seconds) {
            if (player.episode != e) play_episode (e);
            else if (player.state != PlayState.PLAYING) player.play ();
            if (player.episode == e) player.seek_to ((int) Math.round (seconds));
        }

        private void step_chapter (int dir) {
            var e = player.episode;
            if (e == null || e.chapters.size == 0) return;
            int pos = player.position ();
            int idx = Chapters.index_at (e.chapters, pos);
            int target;
            if (dir > 0) target = idx + 1;
            else target = idx >= 0 && pos - e.chapters[idx].start > 3 ? idx : idx - 1;
            if (target < 0) target = 0;
            if (target >= e.chapters.size) return;
            player.seek_to ((int) Math.round (e.chapters[target].start));
            show_toast (e.chapters[target].title);
        }

        private void chapters_menu (Widget anchor_widget) {
            var e = player.episode;
            if (e == null || e.chapters.size == 0) return;
            var menu = new ContextMenu (anchor_widget);
            int current = Chapters.index_at (e.chapters, player.position ());
            for (int i = 0; i < e.chapters.size; i++) {
                var c = e.chapters[i];
                menu.add_item ("%s  %s".printf (Format.clock ((int64) c.start), c.title), i == current ? "object-select-symbolic" : null, () => play_at (e, c.start));
            }
            menu.position = PositionType.TOP;
            popup (menu);
        }

        private void sync_sleep () {
            bool on = sleep.active;
            int left = sleep.remaining ();
            bar.sleep_label.visible = on;
            if (!on) {
                bar.sleep.tooltip_text = _("Sleep Timer");
                return;
            }
            string what = sleep.mode == SleepMode.END_OF_EPISODE ? _("End of episode") : (sleep.mode == SleepMode.END_OF_CHAPTER ? _("End of chapter") : "");
            bar.sleep_label.label = left >= 0 && (sleep.mode == SleepMode.MINUTES || left <= SleepTimer.FADE_SECONDS * 2) ? Format.clock (left) : what;
            bar.sleep.tooltip_text = left >= 0 ? _("Stops in %s").printf (Format.clock (left)) : what;
        }

        private double episode_left () {
            var e = player.episode;
            if (e == null) return -1;
            int d = player.duration ();
            if (d <= 0) return -1;
            return double.max ((d - player.position_us () / 1000000.0) / player.rate, 0);
        }

        private void sleep_menu () {
            if (player.episode == null) return;
            var menu = new ContextMenu (bar.sleep);
            foreach (int m in SleepTimer.PRESETS) {
                int minutes = m;
                menu.add_item (ngettext ("%d Minute", "%d Minutes", minutes).printf (minutes), null, () => sleep.start_minutes (minutes));
            }
            menu.add_item (_("End of Episode"), null, () => sleep.start_track (SleepMode.END_OF_EPISODE, () => episode_left ()));
            var e = player.episode;
            int idx = e.chapters.size > 0 ? Chapters.index_at (e.chapters, player.position ()) : -1;
            if (idx >= 0) {
                menu.add_item (_("End of Chapter"), null, () => {
                    int now_idx = Chapters.index_at (e.chapters, player.position ());
                    double end = now_idx >= 0 ? e.chapters[now_idx].end : -1;
                    sleep.start_track (SleepMode.END_OF_CHAPTER, () => {
                        if (player.episode != e) return 0;
                        double stop = end > 0 ? end : player.duration ();
                        if (stop <= 0) return -1;
                        return double.max ((stop - player.position_us () / 1000000.0) / player.rate, 0);
                    });
                });
            }
            menu.add_item (_("Custom…"), null, () => custom_sleep ());
            if (sleep.active) {
                menu.add_separator ();
                menu.add_item (_("Cancel Sleep Timer"), "process-stop-symbolic", () => sleep.cancel ());
            }
            menu.position = PositionType.TOP;
            popup (menu);
        }

        private void custom_sleep () {
            int last = app.settings != null ? app.settings.get_int ("sleep-custom-minutes") : 90;
            var dlg = new ConfirmDialog (app, _("Sleep Timer"), null,
                _("Playback fades out over the last 30 seconds and then stops."), _("Start"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.set_default_size (380, 0);
            var group = new PreferencesGroup (_("Stop After"));
            var minutes = new SpinRow (_("Minutes"), null, 1, 720, 5, last);
            group.add_row (minutes);
            dlg.custom_area.append (group);
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                int m = (int) minutes.value;
                if (app.settings != null) app.settings.set_int ("sleep-custom-minutes", m);
                sleep.start_minutes (m);
            });
            dlg.present ();
        }

        private Widget build_queue () {
            var box = new Box (Orientation.VERTICAL, 6);
            box.add_css_class ("podcasts-page");
            var head = new Box (Orientation.HORIZONTAL, 12);
            var texts = new Box (Orientation.VERTICAL, 2);
            texts.hexpand = true;
            var title = new Label (_("Up Next"));
            title.add_css_class ("podcasts-page-title");
            title.xalign = 0;
            texts.append (title);
            var hint = new Label (_("Episodes play one after another. Drag them to change the order."));
            hint.add_css_class ("dim-label");
            hint.xalign = 0;
            hint.wrap = true;
            texts.append (hint);
            head.append (texts);
            queue_clear = new Button.with_label (_("Clear"));
            queue_clear.add_css_class ("pill");
            queue_clear.valign = Align.CENTER;
            queue_clear.clicked.connect (() => confirm_clear_queue ());
            head.append (queue_clear);
            box.append (head);
            queue_list = new ListBox ();
            queue_list.add_css_class ("podcasts-list");
            queue_list.selection_mode = SelectionMode.NONE;
            queue_list.margin_top = 6;
            queue_list.row_activated.connect ((row) => {
                var er = row as EpisodeRow;
                if (er != null) show_details (er.episode);
            });
            box.append (queue_list);
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = new Clamp (box) { maximum = 860 };
            apply_view_edge (scroll);
            var empty = new WelcomePage ();
            empty.is_section = true;
            empty.app_icon_name = "dev.sinty.podcasts";
            empty.title = _("Nothing Up Next");
            empty.subtitle = _("Choose Add to Up Next or Play Next in an episode menu to line up what you want to hear.");
            empty.vexpand = true;
            empty.add_action ("document-open-recent", _("New Episodes"), _("Pick the latest episodes of your shows"), () => go ("new"));
            empty.add_action ("folder-music", _("Your Shows"), _("Browse the shows you follow"), () => go ("shows"));
            queue_stack = new Stack ();
            queue_stack.add_named (scroll, "list");
            queue_stack.add_named (empty, "empty");
            return queue_stack;
        }

        private void build_queue_page () {
            Widget? c;
            while ((c = queue_list.get_first_child ()) != null) queue_list.remove (c);
            var items = queue.resolve (library);
            for (int i = 0; i < items.size; i++) queue_list.append (make_queue_row (items[i], i, items.size));
            queue_stack.visible_child_name = items.size == 0 ? "empty" : "list";
        }

        private EpisodeRow make_queue_row (Episode e, int index, int count) {
            var row = make_row (e, true);
            var box = (Box) row.child;
            var handle = new Image.from_icon_name ("list-drag-handle-symbolic");
            handle.add_css_class ("dim-label");
            handle.valign = Align.CENTER;
            handle.tooltip_text = _("Drag to reorder");
            box.prepend (handle);
            var remove = new Button.from_icon_name ("list-remove-symbolic");
            remove.add_css_class ("flat");
            remove.add_css_class ("podcasts-round");
            remove.valign = Align.CENTER;
            remove.tooltip_text = _("Remove from Up Next");
            remove.update_property (AccessibleProperty.LABEL, _("Remove from Up Next"), -1);
            remove.clicked.connect (() => queue.remove (e));
            box.insert_child_after (remove, row.play);
            var drag = new DragSource ();
            drag.actions = Gdk.DragAction.MOVE;
            drag.prepare.connect ((x, y) => {
                var v = Value (typeof (int));
                v.set_int (index);
                return new Gdk.ContentProvider.for_value (v);
            });
            drag.drag_begin.connect ((d) => {
                drag.set_icon (new WidgetPaintable (row), 24, 24);
                row.add_css_class ("podcasts-dragging");
            });
            drag.drag_end.connect (() => row.remove_css_class ("podcasts-dragging"));
            row.add_controller (drag);
            var drop = new DropTarget (typeof (int), Gdk.DragAction.MOVE);
            drop.drop.connect ((val, x, y) => {
                int from = val.get_int ();
                int to = index;
                if (from < to && y < row.get_height () / 2) to--;
                else if (from > to && y > row.get_height () / 2) to++;
                return queue.move (from, to);
            });
            row.add_controller (drop);
            return row;
        }

        private void queue_menu_items (ContextMenu menu, Episode e) {
            int i = queue.index_of (e);
            if (i < 0) return;
            menu.add_separator ();
            if (i > 0) menu.add_item (_("Move to Top"), "go-up-symbolic", () => queue.move (i, 0));
            if (i > 0) menu.add_item (_("Move Up"), "go-up-symbolic", () => queue.move (i, i - 1));
            if (i < queue.items.size - 1) menu.add_item (_("Move Down"), "go-down-symbolic", () => queue.move (i, i + 1));
        }

        private void confirm_clear_queue () {
            if (queue.items.size == 0) return;
            var dlg = new ConfirmDialog (app, _("Clear Up Next?"), "edit-clear-all-symbolic",
                _("Every episode is removed from Up Next. The episodes stay in their shows."), _("Clear"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) queue.clear ();
            });
            dlg.present ();
        }

        private void show_error (string title, string message) {
            var dlg = new ConfirmDialog.message (app, title, "dialog-error", message);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.present ();
        }

        private void show_toast (string text, uint seconds = 3) {
            if (toast == null) {
                toast = new Label ("");
                toast.add_css_class ("podcasts-toast");
                toast.halign = Align.CENTER;
                toast.valign = Align.END;
                toast.margin_bottom = 20;
                toast.can_target = false;
                toast.wrap = true;
                toast.max_width_chars = 60;
                overlay.add_overlay (toast);
            }
            toast.label = text;
            toast.visible = true;
            if (toast_id != 0) Source.remove (toast_id);
            toast_id = 0;
            if (seconds == 0) return;
            toast_id = Timeout.add_seconds (seconds, () => {
                toast_id = 0;
                toast.visible = false;
                return Source.REMOVE;
            });
        }

        private void hide_toast () {
            if (toast_id != 0) Source.remove (toast_id);
            toast_id = 0;
            if (toast != null) toast.visible = false;
        }

        private void install_actions () {
            string[] names = { "add", "import", "export", "find", "refresh", "back", "mark-all", "unsubscribe",
                "go-shows", "go-new", "go-progress", "go-downloads", "go-discover",
                "play-pause", "skip-back", "skip-forward", "faster", "slower", "stop",
                "go-queue", "chapters", "queue-next", "queue-clear", "chapter-prev", "chapter-next",
                "sleep-timer", "cancel-sleep", "show-settings", "close", "toggle-sidebar", "normal-speed" };
            foreach (string n in names) {
                var a = new SimpleAction (n, null);
                string name = n;
                a.activate.connect (() => {
                    switch (name) {
                        case "add": add_podcast (); break;
                        case "import": import_opml (); break;
                        case "export": export_opml (); break;
                        case "find": search.grab_focus_entry (); break;
                        case "refresh":
                            if (section == "show" && current_show != null) refresh_show.begin (current_show);
                            else refresh_all.begin (false);
                            break;
                        case "back": go_back (); break;
                        case "mark-all": if (current_show != null) library.mark_all_played (current_show); break;
                        case "unsubscribe": if (current_show != null) confirm_unsubscribe (current_show); break;
                        case "go-shows": go ("shows"); break;
                        case "go-new": go ("new"); break;
                        case "go-progress": go ("progress"); break;
                        case "go-downloads": go ("downloads"); break;
                        case "go-discover": go ("discover"); break;
                        case "play-pause": if (player.episode != null) player.toggle (); break;
                        case "skip-back": player.skip (-Player.SKIP_BACK); break;
                        case "skip-forward": player.skip (Player.SKIP_FORWARD); break;
                        case "faster": step_rate (1); break;
                        case "slower": step_rate (-1); break;
                        case "stop": stop_playback (); break;
                        case "go-queue": go ("queue"); break;
                        case "close": close (); break;
                        case "toggle-sidebar": set_sidebar_visible (!get_sidebar_visible ()); break;
                        case "normal-speed":
                            if (player.episode != null) {
                                set_rate (1.0);
                                show_toast (_("Speed %s").printf (Format.speed (player.rate)));
                            }
                            break;
                        case "chapters": chapters_menu (bar.chapters); break;
                        case "queue-next":
                            if (player.episode != null) save_position ();
                            play_next_in_queue ();
                            break;
                        case "queue-clear": confirm_clear_queue (); break;
                        case "chapter-prev": step_chapter (-1); break;
                        case "chapter-next": step_chapter (1); break;
                        case "sleep-timer": sleep_menu (); break;
                        case "cancel-sleep": sleep.cancel (); break;
                        case "show-settings":
                            Show? target = current_show;
                            if (target == null && player.episode != null) target = library.find_show (player.episode.show_url);
                            if (target != null) show_settings (target);
                            break;
                    }
                });
                add_action (a);
            }
            var trim = new SimpleAction.stateful ("trim-silence", null, new Variant.boolean (app.trim_default));
            trim.activate.connect (() => {
                app.trim_default = !app.trim_default;
                trim.set_state (new Variant.boolean (app.trim_default));
                if (app.settings == null) apply_show_settings (false);
                show_toast (app.trim_default ? _("Trim Silence is on") : _("Trim Silence is off"));
            });
            add_action (trim);
            trim_action = trim;
            var boost = new SimpleAction.stateful ("voice-boost", null, new Variant.boolean (app.boost_default));
            boost.activate.connect (() => {
                app.boost_default = !app.boost_default;
                boost.set_state (new Variant.boolean (app.boost_default));
                if (app.settings == null) apply_show_settings (false);
                show_toast (app.boost_default ? _("Voice Boost is on") : _("Voice Boost is off"));
            });
            add_action (boost);
            boost_action = boost;
            actions_ready = true;
            update_actions ();
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                bool mods = (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SHIFT_MASK)) != 0;
                if (keyval == Gdk.Key.space && !mods && player.episode != null && !(get_focus () is Editable) && !(get_focus () is Button)) {
                    player.toggle ();
                    return true;
                }
                if (keyval == Gdk.Key.Escape && section == "show" && !(get_focus () is Editable)) {
                    go_back ();
                    return true;
                }
                return false;
            });
            ((Widget) this).add_controller (keys);
        }
    }
}
