using Gtk;
using GLib;
using Singularity;

namespace SingularityPodcastsWidget {

    public class NewEpisodesProvider : Object, OverviewWidgetProvider {
        public string id { get { return "podcasts.new-episodes"; } }
        public string provider_id { get { return "dev.sinty.podcasts"; } }
        public string display_name { get { return _("New Episodes"); } }
        public string icon_name { get { return "dev.sinty.podcasts"; } }
        public WidgetSize[] supported_sizes {
            get {
                if (_sizes == null) {
                    _sizes = new WidgetSize[3];
                    _sizes[0] = WidgetSize (2, 2);
                    _sizes[1] = WidgetSize (4, 2);
                    _sizes[2] = WidgetSize (4, 4);
                }
                return _sizes;
            }
        }
        private WidgetSize[] _sizes;

        public Gtk.Widget create_instance (string instance_id, WidgetSize size, Variant? config) {
            return new NewEpisodesInstance (size);
        }
    }

    private class EpisodeInfo : Object {
        public string show_url = "";
        public string show_title = "";
        public string key = "";
        public string title = "";
        public string image = "";
        public string show_image = "";
        public int duration;
        public int64 published;
    }

    public class NewEpisodesInstance : Gtk.Box {
        private const int COVER = 44;
        private Gtk.Box list;
        private Gtk.Label empty;
        private FileMonitor? monitor;
        private string path;
        private int limit;
        private int last_height = -1;

        public NewEpisodesInstance (WidgetSize size) {
            Object (orientation: Orientation.VERTICAL, spacing: 6);
            add_css_class ("overview-widget-card");
            hexpand = true;
            vexpand = true;
            limit = size.h >= 4 ? 12 : 6;

            var header = new Gtk.Label (_("New Episodes"));
            header.add_css_class ("heading");
            header.halign = Align.START;
            header.margin_start = 14;
            header.margin_top = 10;
            append (header);

            list = new Gtk.Box (Orientation.VERTICAL, 4);
            list.margin_start = 8;
            list.margin_end = 8;
            list.margin_bottom = 8;
            list.vexpand = true;
            append (list);

            empty = new Gtk.Label (_("New episodes of your shows appear here."));
            empty.add_css_class ("dim-label");
            empty.wrap = true;
            empty.justify = Justification.CENTER;
            empty.vexpand = true;
            empty.margin_start = 14;
            empty.margin_end = 14;
            append (empty);

            path = Path.build_filename (Environment.get_user_data_dir (), "singularity", "podcasts", "library.json");
            try {
                monitor = File.new_for_path (path).monitor_file (FileMonitorFlags.NONE);
                monitor.changed.connect ((f, o, ev) => {
                    if (ev == FileMonitorEvent.CHANGES_DONE_HINT || ev == FileMonitorEvent.CREATED || ev == FileMonitorEvent.DELETED) refresh ();
                });
            } catch (Error e) {
                monitor = null;
            }
            refresh ();
        }

        private Gee.List<EpisodeInfo> load () {
            var all = new Gee.ArrayList<EpisodeInfo> ();
            if (!FileUtils.test (path, FileTest.EXISTS)) return all;
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (path);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return all;
                var o = root.get_object ();
                if (!o.has_member ("shows")) return all;
                foreach (var sn in o.get_array_member ("shows").get_elements ()) {
                    if (sn.get_node_type () != Json.NodeType.OBJECT) continue;
                    var so = sn.get_object ();
                    string show_url = so.get_string_member_with_default ("url", "");
                    if (show_url == "" || !so.has_member ("episodes")) continue;
                    foreach (var en in so.get_array_member ("episodes").get_elements ()) {
                        if (en.get_node_type () != Json.NodeType.OBJECT) continue;
                        var eo = en.get_object ();
                        if (eo.get_boolean_member_with_default ("played", false)) continue;
                        if (eo.get_int_member_with_default ("position", 0) > 0) continue;
                        var e = new EpisodeInfo ();
                        e.show_url = show_url;
                        e.show_title = so.get_string_member_with_default ("title", "");
                        e.show_image = so.get_string_member_with_default ("image", "");
                        e.title = eo.get_string_member_with_default ("title", "");
                        e.image = eo.get_string_member_with_default ("image", "");
                        e.duration = (int) eo.get_int_member_with_default ("duration", 0);
                        e.published = eo.get_int_member_with_default ("published", 0);
                        string guid = eo.get_string_member_with_default ("guid", "");
                        string audio = eo.get_string_member_with_default ("audio", "");
                        e.key = guid != "" ? guid : (audio != "" ? audio : "%s|%s".printf (e.title, e.published.to_string ()));
                        all.add (e);
                    }
                }
            } catch (Error e) {
                warning ("podcasts widget: %s", e.message);
            }
            all.sort ((a, b) => a.published > b.published ? -1 : (a.published < b.published ? 1 : 0));
            return all.size > limit ? all.slice (0, limit) : all;
        }

        public override void size_allocate (int width, int height, int baseline) {
            base.size_allocate (width, height, baseline);
            if (height == last_height) return;
            last_height = height;
            Idle.add (() => {
                fit_rows ();
                return Source.REMOVE;
            });
        }

        private void fit_rows () {
            int room = list.get_height ();
            if (room <= 0) return;
            int used = 0;
            Widget? child = list.get_first_child ();
            bool full = false;
            while (child != null) {
                int min, nat, mb, nb;
                child.measure (Orientation.VERTICAL, list.get_width (), out min, out nat, out mb, out nb);
                bool fits = !full && used + nat <= room;
                if (fits) used += nat + list.spacing;
                else full = true;
                child.set_child_visible (fits);
                child = child.get_next_sibling ();
            }
        }

        private void refresh () {
            Widget? child;
            while ((child = list.get_first_child ()) != null) list.remove (child);
            var episodes = load ();
            empty.visible = episodes.size == 0;
            list.visible = episodes.size > 0;
            foreach (var e in episodes) list.append (make_row (e));
            Idle.add (() => {
                fit_rows ();
                return Source.REMOVE;
            });
        }

        private Gtk.Widget make_row (EpisodeInfo e) {
            var button = new Gtk.Button ();
            button.add_css_class ("flat");
            button.add_css_class ("overview-widget-tile");
            button.tooltip_text = _("Play %s").printf (e.title);
            var row = new Gtk.Box (Orientation.HORIZONTAL, 10);
            row.append (make_cover (e));
            var text = new Gtk.Box (Orientation.VERTICAL, 2);
            text.valign = Align.CENTER;
            text.hexpand = true;
            var title = new Gtk.Label (e.title);
            title.xalign = 0;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.add_css_class ("heading");
            text.append (title);
            string line = e.show_title;
            string length = format_length (e.duration);
            if (length != "") line = line != "" ? "%s · %s".printf (line, length) : length;
            var sub = new Gtk.Label (line);
            sub.xalign = 0;
            sub.ellipsize = Pango.EllipsizeMode.END;
            sub.add_css_class ("caption");
            sub.add_css_class ("dim-label");
            text.append (sub);
            row.append (text);
            button.child = row;
            string target = e.show_url + "\n" + e.key;
            button.clicked.connect (() => play (target));
            return button;
        }

        private static string format_length (int seconds) {
            if (seconds <= 0) return "";
            int minutes = (seconds + 30) / 60;
            if (minutes < 60) return ngettext ("%d min", "%d min", int.max (minutes, 1)).printf (int.max (minutes, 1));
            int h = minutes / 60, m = minutes % 60;
            if (m == 0) return ngettext ("%d hr", "%d hr", h).printf (h);
            return _("%d hr %d min").printf (h, m);
        }

        private Gtk.Widget make_cover (EpisodeInfo e) {
            var image = new Gtk.Image ();
            image.pixel_size = COVER;
            image.icon_name = "dev.sinty.podcasts";
            foreach (string url in new string[] { e.image, e.show_image }) {
                if (url == "") continue;
                string file = Path.build_filename (Environment.get_user_cache_dir (), "singularity-podcasts", "artwork",
                    Checksum.compute_for_string (ChecksumType.MD5, url) + ".png");
                if (!FileUtils.test (file, FileTest.EXISTS)) continue;
                try {
                    var pixbuf = new Gdk.Pixbuf.from_file_at_scale (file, COVER, COVER, true);
                    image.paintable = Gdk.Texture.for_pixbuf (pixbuf);
                    break;
                } catch (Error err) {
                }
            }
            return image;
        }

        private void play (string target) {
            Bus.get.begin (BusType.SESSION, null, (o, res) => {
                try {
                    var bus = Bus.get.end (res);
                    var args = new VariantBuilder (new VariantType ("av"));
                    args.add ("v", new Variant.string (target));
                    bus.call.begin ("dev.sinty.podcasts", "/dev/sinty/podcasts", "org.freedesktop.Application", "ActivateAction",
                        new Variant ("(s@av@a{sv})", "play-episode", args.end (), new VariantBuilder (VariantType.VARDICT).end ()),
                        null, DBusCallFlags.NONE, 10000, null);
                } catch (Error err) {
                    warning ("podcasts widget: %s", err.message);
                }
            });
        }
    }

    [CCode (cname = "singularity_podcasts_widget_new")]
    public static Object singularity_podcasts_widget_new () {
        return new NewEpisodesProvider ();
    }
}
