using Gtk;

namespace Singularity.Apps.Podcasts {

    public class ArtworkCache : Object {
        private static ArtworkCache? instance;
        private Gee.HashMap<string, Gdk.Texture> textures = new Gee.HashMap<string, Gdk.Texture> ();
        private Gee.HashSet<string> pending = new Gee.HashSet<string> ();
        private Gee.HashSet<string> failed = new Gee.HashSet<string> ();
        private string dir;
        private int running;
        private Gee.LinkedList<string> queue = new Gee.LinkedList<string> ();

        public const int MAX_SIZE = 360;

        public signal void loaded (string url);

        public static ArtworkCache get_default () {
            if (instance == null) instance = new ArtworkCache ();
            return instance;
        }

        private ArtworkCache () {
            dir = Path.build_filename (Environment.get_user_cache_dir (), "singularity-podcasts", "artwork");
            DirUtils.create_with_parents (dir, 0700);
        }

        public string file_for (string url) {
            return Path.build_filename (dir, Checksum.compute_for_string (ChecksumType.MD5, url) + ".png");
        }

        public Gdk.Texture? peek (string url) {
            return textures[url];
        }

        public void retry_failed () {
            failed.clear ();
        }

        public void request (string url) {
            if (url == "" || textures.has_key (url) || pending.contains (url) || failed.contains (url)) return;
            pending.add (url);
            queue.add (url);
            pump ();
        }

        private void pump () {
            while (running < 4 && queue.size > 0) {
                string url = queue.poll_head ();
                running++;
                load.begin (url, (o, res) => {
                    load.end (res);
                    running--;
                    pump ();
                });
            }
        }

        private async void load (string url) {
            string path = file_for (url);
            Gdk.Texture? tex = null;
            bool fresh = false;
            try {
                var info = File.new_for_path (path).query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
                var age = new DateTime.now_utc ().difference (info.get_modification_date_time ());
                fresh = age < 30 * TimeSpan.DAY;
            } catch (Error e) {
            }
            if (fresh) tex = yield decode (null, path);
            if (tex == null) {
                try {
                    var bytes = yield Net.fetch (url);
                    tex = yield decode (bytes, path);
                } catch (Error e) {
                    if (FileUtils.test (path, FileTest.EXISTS)) tex = yield decode (null, path);
                }
            }
            pending.remove (url);
            if (tex != null) textures[url] = tex;
            else failed.add (url);
            loaded (url);
        }

        private async Gdk.Texture? decode (Bytes? data, string path) {
            Gdk.Texture? result = null;
            SourceFunc cb = decode.callback;
            new Thread<bool> ("podcasts-artwork", () => {
                try {
                    if (data != null) {
                        var loader = new Gdk.PixbufLoader ();
                        loader.write_bytes (data);
                        loader.close ();
                        var pix = loader.get_pixbuf ();
                        if (pix != null) {
                            int w = pix.width, h = pix.height;
                            double scale = double.min (1.0, (double) MAX_SIZE / int.max (w, h));
                            if (scale < 1.0) pix = pix.scale_simple (int.max (1, (int) (w * scale)), int.max (1, (int) (h * scale)), Gdk.InterpType.BILINEAR);
                            pix.savev (path, "png", {}, {});
                        }
                    }
                    result = Gdk.Texture.from_filename (path);
                } catch (Error e) {
                    result = null;
                }
                Idle.add ((owned) cb);
                return true;
            });
            yield;
            return result;
        }
    }

    public class ArtworkView : Widget {
        private string url = "";
        private Gdk.Texture? texture;
        private int size;
        public bool fixed_size;
        private float radius;
        private ulong handler;

        public ArtworkView (int size, float radius = 10) {
            this.size = size;
            this.radius = radius;
            add_css_class ("podcasts-art");
            add_css_class ("podcasts-art-%d".printf ((int) radius));
            overflow = Overflow.HIDDEN;
            handler = ArtworkCache.get_default ().loaded.connect ((u) => {
                if (u != url) return;
                texture = ArtworkCache.get_default ().peek (u);
                queue_draw ();
            });
        }

        public override void dispose () {
            if (handler != 0) ArtworkCache.get_default ().disconnect (handler);
            handler = 0;
            base.dispose ();
        }

        public void set_url (string u) {
            url = u;
            texture = ArtworkCache.get_default ().peek (u);
            if (texture == null) ArtworkCache.get_default ().request (u);
            queue_draw ();
        }

        public override SizeRequestMode get_request_mode () {
            return SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        public override void measure (Orientation o, int for_size, out int minimum, out int natural, out int mb, out int nb) {
            if (o == Orientation.VERTICAL && for_size > 0 && !fixed_size) minimum = natural = for_size;
            else minimum = natural = size;
            mb = nb = -1;
        }

        public override void snapshot (Snapshot snap) {
            float w = get_width (), h = get_height ();
            var rect = Graphene.Rect ().init (0, 0, w, h);
            var clip = Gsk.RoundedRect ().init_from_rect (rect, radius);
            snap.push_rounded_clip (clip);
            if (texture != null) {
                float tw = texture.width, th = texture.height;
                float scale = float.min (w / tw, h / th);
                if (tw * scale < w || th * scale < h) {
                    var bg = Gdk.RGBA ();
                    bg.parse ("#8e6bd8");
                    bg.alpha = 0.16f;
                    snap.append_color (bg, rect);
                }
                var tr = Graphene.Rect ().init ((w - tw * scale) / 2, (h - th * scale) / 2, tw * scale, th * scale);
                snap.append_scaled_texture (texture, Gsk.ScalingFilter.TRILINEAR, tr);
            } else {
                var bg = Gdk.RGBA ();
                bg.parse ("#8e6bd8");
                bg.alpha = 0.16f;
                snap.append_color (bg, rect);
                int icon = (int) (float.min (w, h) * 0.62f);
                var theme = IconTheme.get_for_display (get_display ());
                var paintable = theme.lookup_icon ("dev.sinty.podcasts", null, icon, get_scale_factor (), get_direction (), 0);
                snap.save ();
                snap.translate (Graphene.Point () { x = (w - icon) / 2, y = (h - icon) / 2 });
                paintable.snapshot (snap, icon, icon);
                snap.restore ();
            }
            snap.pop ();
        }
    }
}
