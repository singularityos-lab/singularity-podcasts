namespace Singularity.Apps.Podcasts {

    public class QueueItem : Object {
        public string show_url = "";
        public string key = "";

        public QueueItem (string show_url, string key) {
            this.show_url = show_url;
            this.key = key;
        }

        public bool matches (Episode e) {
            return show_url == e.show_url && key == e.key ();
        }
    }

    public class PlayQueue : Object {
        public const int LIMIT = 1000;

        public Gee.ArrayList<QueueItem> items = new Gee.ArrayList<QueueItem> ();
        public string error = "";
        private string path;

        public signal void changed ();

        public PlayQueue (string? file = null) {
            path = file ?? Path.build_filename (Environment.get_user_data_dir (), "singularity", "podcasts", "queue.json");
            if (!FileUtils.test (path, FileTest.EXISTS)) return;
            try {
                string data;
                FileUtils.get_contents (path, out data);
                items.add_all (parse (data));
            } catch (Error e) {
                error = e.message;
            }
        }

        public static Gee.List<QueueItem> parse (string data) throws Error {
            var list = new Gee.ArrayList<QueueItem> ();
            var parser = new Json.Parser ();
            parser.load_from_data (data, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return list;
            var o = root.get_object ();
            if (!o.has_member ("queue") || o.get_member ("queue").get_node_type () != Json.NodeType.ARRAY) return list;
            var seen = new Gee.HashSet<string> ();
            foreach (var n in o.get_array_member ("queue").get_elements ()) {
                if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                var item = n.get_object ();
                string show = item.get_string_member_with_default ("show", "");
                string key = item.get_string_member_with_default ("episode", "");
                if (show == "" || key == "" || !seen.add (show + "\n" + key)) continue;
                list.add (new QueueItem (show, key));
                if (list.size >= LIMIT) break;
            }
            return list;
        }

        public bool save () {
            var arr = new Json.Array ();
            foreach (var item in items) {
                var o = new Json.Object ();
                o.set_string_member ("show", item.show_url);
                o.set_string_member ("episode", item.key);
                arr.add_object_element (o);
            }
            var o = new Json.Object ();
            o.set_int_member ("version", 1);
            o.set_array_member ("queue", arr);
            var root = new Json.Node (Json.NodeType.OBJECT);
            root.set_object (o);
            var gen = new Json.Generator ();
            gen.root = root;
            bool ok = true;
            DirUtils.create_with_parents (Path.get_dirname (path), 0700);
            try {
                FileUtils.set_contents (path, gen.to_data (null));
                error = "";
            } catch (Error e) {
                error = e.message;
                ok = false;
            }
            changed ();
            return ok;
        }

        public int index_of (Episode e) {
            for (int i = 0; i < items.size; i++) if (items[i].matches (e)) return i;
            return -1;
        }

        public bool contains (Episode e) {
            return index_of (e) >= 0;
        }

        public bool add (Episode e) {
            if (contains (e) || items.size >= LIMIT) return false;
            items.add (new QueueItem (e.show_url, e.key ()));
            save ();
            return true;
        }

        public void add_next (Episode e) {
            int i = index_of (e);
            if (i == 0) return;
            if (i > 0) items.remove_at (i);
            items.insert (0, new QueueItem (e.show_url, e.key ()));
            while (items.size > LIMIT) items.remove_at (items.size - 1);
            save ();
        }

        public bool remove (Episode e) {
            int i = index_of (e);
            if (i < 0) return false;
            items.remove_at (i);
            save ();
            return true;
        }

        public bool move (int from, int to) {
            if (from < 0 || from >= items.size) return false;
            to = to.clamp (0, items.size - 1);
            if (from == to) return false;
            var item = items.remove_at (from);
            items.insert (to, item);
            save ();
            return true;
        }

        public QueueItem? pop () {
            if (items.size == 0) return null;
            var item = items.remove_at (0);
            save ();
            return item;
        }

        public void clear () {
            if (items.size == 0) return;
            items.clear ();
            save ();
        }

        public Gee.List<Episode> resolve (Library library) {
            var list = new Gee.ArrayList<Episode> ();
            foreach (var item in items) {
                var e = library.find_episode (item.show_url, item.key);
                if (e != null) list.add (e);
            }
            return list;
        }

        public bool prune (Library library) {
            bool dropped = false;
            for (int i = items.size - 1; i >= 0; i--) {
                if (library.find_episode (items[i].show_url, items[i].key) == null) {
                    items.remove_at (i);
                    dropped = true;
                }
            }
            if (dropped) save ();
            return dropped;
        }
    }
}
