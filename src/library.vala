namespace Singularity.Apps.Podcasts {

    public class Library : Object {
        public Gee.ArrayList<Show> shows = new Gee.ArrayList<Show> ();
        public int64 last_refresh;
        public string path;
        private uint save_id;

        public signal void changed ();
        public signal void episode_changed (Episode e);

        public Library (string? file = null) {
            path = file ?? Path.build_filename (Environment.get_user_data_dir (), "singularity", "podcasts", "library.json");
            load ();
        }

        private void load () {
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (path);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return;
                var o = root.get_object ();
                last_refresh = o.get_int_member_with_default ("refreshed", 0);
                if (!o.has_member ("shows")) return;
                foreach (var n in o.get_array_member ("shows").get_elements ()) {
                    var s = Show.from_json (n.get_object ());
                    if (s.feed_url != "") shows.add (s);
                }
            } catch (Error e) {
            }
        }

        public bool save () {
            if (save_id != 0) {
                Source.remove (save_id);
                save_id = 0;
            }
            var o = new Json.Object ();
            o.set_int_member ("version", 1);
            o.set_int_member ("refreshed", last_refresh);
            var arr = new Json.Array ();
            foreach (var s in shows) arr.add_object_element (s.to_json ());
            o.set_array_member ("shows", arr);
            var root = new Json.Node (Json.NodeType.OBJECT);
            root.set_object (o);
            var gen = new Json.Generator ();
            gen.root = root;
            DirUtils.create_with_parents (Path.get_dirname (path), 0700);
            try {
                return FileUtils.set_contents (path, gen.to_data (null));
            } catch (Error e) {
                warning ("podcasts: could not save the library: %s", e.message);
                return false;
            }
        }

        public void schedule_save () {
            if (save_id != 0) return;
            save_id = Timeout.add_seconds (2, () => {
                save_id = 0;
                save ();
                return Source.REMOVE;
            });
        }

        public Show? find_show (string url) {
            foreach (var s in shows) if (s.feed_url == url) return s;
            return null;
        }

        public Episode? find_episode (string show_url, string key) {
            var s = find_show (show_url);
            if (s == null) return null;
            foreach (var e in s.episodes) if (e.key () == key) return e;
            return null;
        }

        public void add_show (Show s) {
            var existing = find_show (s.feed_url);
            if (existing != null) {
                merge (existing, s);
            } else {
                s.refreshed = new DateTime.now_utc ().to_unix ();
                shows.add (s);
                sort_shows ();
            }
            save ();
            changed ();
        }

        public void remove_show (Show s) {
            foreach (var e in s.episodes) delete_download (e);
            shows.remove (s);
            save ();
            changed ();
        }

        public void sort_shows () {
            shows.sort ((a, b) => a.title.collate (b.title));
        }

        public int merge (Show target, Show fresh) {
            var old = new Gee.HashMap<string, Episode> ();
            foreach (var e in target.episodes) old[e.key ()] = e;
            var result = new Gee.ArrayList<Episode> ();
            var seen = new Gee.HashSet<string> ();
            int added = 0;
            foreach (var e in fresh.episodes) {
                string k = e.key ();
                if (seen.contains (k)) continue;
                seen.add (k);
                var prev = old[k];
                if (prev != null) {
                    prev.title = e.title;
                    prev.description = e.description;
                    prev.link = e.link;
                    prev.audio_url = e.audio_url;
                    prev.mime = e.mime;
                    prev.size = e.size;
                    if (e.duration > 0) prev.duration = e.duration;
                    prev.published = e.published;
                    prev.image_url = e.image_url;
                    if (prev.chapters_url != e.chapters_url) {
                        prev.chapters_url = e.chapters_url;
                        prev.chapters_fetched = false;
                        prev.chapters.clear ();
                    }
                    if (e.chapters.size > 0) {
                        prev.chapters.clear ();
                        prev.chapters.add_all (e.chapters);
                    }
                    result.add (prev);
                    continue;
                }
                added++;
                e.show_url = target.feed_url;
                result.add (e);
            }
            foreach (var e in target.episodes) {
                if (seen.contains (e.key ())) continue;
                if (e.download_path != "" || e.in_progress ()) result.add (e);
            }
            target.title = fresh.title != "" ? fresh.title : target.title;
            target.author = fresh.author;
            target.description = fresh.description;
            target.link = fresh.link;
            if (fresh.image_url != "") target.image_url = fresh.image_url;
            target.episodes = result;
            target.error = "";
            target.refreshed = new DateTime.now_utc ().to_unix ();
            target.sort ();
            return added;
        }

        public Gee.List<Episode> latest (int limit = 100) {
            var all = new Gee.ArrayList<Episode> ();
            foreach (var s in shows) all.add_all (s.episodes);
            all.sort ((a, b) => a.published > b.published ? -1 : (a.published < b.published ? 1 : 0));
            return all.size > limit ? all.slice (0, limit) : all;
        }

        public Gee.List<Episode> in_progress () {
            var list = new Gee.ArrayList<Episode> ();
            foreach (var s in shows) foreach (var e in s.episodes) if (e.in_progress ()) list.add (e);
            list.sort ((a, b) => a.published > b.published ? -1 : (a.published < b.published ? 1 : 0));
            return list;
        }

        public Gee.List<Episode> downloaded () {
            var list = new Gee.ArrayList<Episode> ();
            foreach (var s in shows) foreach (var e in s.episodes) if (e.download_path != "") list.add (e);
            list.sort ((a, b) => a.published > b.published ? -1 : (a.published < b.published ? 1 : 0));
            return list;
        }

        public void set_played (Episode e, bool played) {
            e.played = played;
            if (played) e.position = 0;
            schedule_save ();
            episode_changed (e);
        }

        public void set_position (Episode e, int seconds) {
            e.position = int.max (seconds, 0);
            schedule_save ();
        }

        public void mark_all_played (Show s) {
            foreach (var e in s.episodes) {
                e.played = true;
                e.position = 0;
            }
            save ();
            changed ();
        }

        public void delete_download (Episode e) {
            if (e.download_path == "") return;
            FileUtils.remove (e.download_path);
            e.download_path = "";
            schedule_save ();
            episode_changed (e);
        }

        public Gee.List<Outline> outlines () {
            var list = new Gee.ArrayList<Outline> ();
            foreach (var s in shows) list.add (new Outline (s.title, s.feed_url, s.link));
            return list;
        }
    }
}
