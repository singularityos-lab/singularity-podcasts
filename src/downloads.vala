namespace Singularity.Apps.Podcasts {

    public class Downloads : Object {
        private Library library;
        private Gee.HashMap<string, Cancellable> active = new Gee.HashMap<string, Cancellable> ();
        private Gee.HashMap<string, double?> progress = new Gee.HashMap<string, double?> ();
        public string dir;

        public signal void progress_changed (Episode e);
        public signal void finished (Episode e, string? error);

        public Downloads (Library library) {
            this.library = library;
            dir = Path.build_filename (Environment.get_user_cache_dir (), "singularity-podcasts", "episodes");
        }

        private static string id (Episode e) {
            return e.show_url + "\n" + e.key ();
        }

        public bool is_active (Episode e) {
            return active.has_key (id (e));
        }

        public int count () {
            return active.size;
        }

        public double fraction (Episode e) {
            var f = progress[id (e)];
            return f != null ? f : -1;
        }

        public void cancel (Episode e) {
            var c = active[id (e)];
            if (c != null) c.cancel ();
        }

        public void cancel_all () {
            foreach (var c in active.values) c.cancel ();
        }

        private static string extension (Episode e) {
            string path = e.audio_url;
            int q = path.index_of ("?");
            if (q >= 0) path = path.substring (0, q);
            string base_name = Path.get_basename (path);
            int dot = base_name.last_index_of (".");
            if (dot > 0) {
                string ext = base_name.substring (dot + 1).down ();
                if (ext.length >= 2 && ext.length <= 4) return ext;
            }
            switch (e.mime) {
                case "audio/ogg": return "ogg";
                case "audio/opus": return "opus";
                case "audio/x-m4a":
                case "audio/mp4": return "m4a";
                case "video/mp4": return "mp4";
                default: return "mp3";
            }
        }

        public void start (Episode e) {
            if (is_active (e) || e.is_downloaded () || e.audio_url == "") return;
            run.begin (e);
        }

        private async void run (Episode e) {
            string key = id (e);
            var cancel = new Cancellable ();
            active[key] = cancel;
            progress[key] = 0;
            progress_changed (e);
            DirUtils.create_with_parents (dir, 0700);
            string target = Path.build_filename (dir, "%s.%s".printf (Checksum.compute_for_string (ChecksumType.MD5, key), extension (e)));
            var part = File.new_for_path (target + ".part");
            string? error = null;
            try {
                if (Uri.peek_scheme (e.audio_url) != "http" && Uri.peek_scheme (e.audio_url) != "https") throw new IOError.INVALID_ARGUMENT (_("The episode address is not valid."));
                var msg = new Soup.Message ("GET", e.audio_url);
                InputStream input;
                try {
                    input = yield Net.get ().send_async (msg, Priority.LOW, cancel);
                } catch (Error err) {
                    throw Net.friendly (err);
                }
                if (msg.status_code < 200 || msg.status_code >= 300) throw new IOError.FAILED (_("The server answered with an error (HTTP %u).").printf (msg.status_code));
                int64 total = msg.response_headers.get_content_length ();
                if (total <= 0) total = e.size;
                var output = yield part.replace_async (null, false, FileCreateFlags.PRIVATE, Priority.LOW, cancel);
                int64 done = 0;
                int64 last = 0;
                while (true) {
                    var chunk = yield input.read_bytes_async (65536, Priority.LOW, cancel);
                    if (chunk.get_size () == 0) break;
                    size_t written;
                    yield output.write_all_async (chunk.get_data (), Priority.LOW, cancel, out written);
                    done += (int64) chunk.get_size ();
                    if (total > 0 && done - last > total / 200) {
                        last = done;
                        progress[key] = double.min ((double) done / total, 1.0);
                        progress_changed (e);
                    }
                }
                yield output.close_async (Priority.LOW, cancel);
                yield input.close_async (Priority.LOW, null);
                if (done == 0) throw new IOError.FAILED (_("The server sent an empty file."));
                yield part.move_async (File.new_for_path (target), FileCopyFlags.OVERWRITE, Priority.LOW, cancel, null);
                if (library.find_show (e.show_url) == null) {
                    FileUtils.remove (target);
                } else {
                    e.download_path = target;
                    library.save ();
                }
            } catch (Error err) {
                if (!(err is IOError.CANCELLED)) error = err.message;
                try {
                    part.delete ();
                } catch (Error de) {
                }
            }
            active.unset (key);
            progress.unset (key);
            progress_changed (e);
            finished (e, error);
        }
    }
}
