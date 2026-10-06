namespace Singularity.Apps.Podcasts {

    public errordomain FeedError {
        INVALID,
        NOT_A_FEED
    }

    public class Episode : Object {
        public string guid = "";
        public string title = "";
        public string description = "";
        public string link = "";
        public string audio_url = "";
        public string mime = "";
        public int64 size;
        public int duration;
        public int64 published;
        public string image_url = "";
        public string show_url = "";
        public int position;
        public bool played;
        public string download_path = "";
        public string chapters_url = "";
        public Gee.ArrayList<Chapter> chapters = new Gee.ArrayList<Chapter> ();
        public bool chapters_fetched;

        public string key () {
            if (guid != "") return guid;
            if (audio_url != "") return audio_url;
            return "%s|%s".printf (title, published.to_string ());
        }

        public bool is_downloaded () {
            return download_path != "" && FileUtils.test (download_path, FileTest.EXISTS);
        }

        public bool in_progress () {
            return !played && position > 0;
        }

        public int remaining () {
            return duration > 0 ? int.max (duration - position, 0) : 0;
        }

        public Json.Object to_json () {
            var o = new Json.Object ();
            o.set_string_member ("guid", guid);
            o.set_string_member ("title", title);
            o.set_string_member ("description", description);
            o.set_string_member ("link", link);
            o.set_string_member ("audio", audio_url);
            o.set_string_member ("mime", mime);
            o.set_int_member ("size", size);
            o.set_int_member ("duration", duration);
            o.set_int_member ("published", published);
            o.set_string_member ("image", image_url);
            o.set_int_member ("position", position);
            o.set_boolean_member ("played", played);
            o.set_string_member ("download", download_path);
            if (chapters_url != "") o.set_string_member ("chapters_url", chapters_url);
            if (chapters.size > 0) {
                var arr = new Json.Array ();
                foreach (var c in chapters) arr.add_object_element (c.to_json ());
                o.set_array_member ("chapters", arr);
            }
            if (chapters_fetched) o.set_boolean_member ("chapters_fetched", true);
            return o;
        }

        public static Episode from_json (Json.Object o) {
            var e = new Episode ();
            e.guid = o.get_string_member_with_default ("guid", "");
            e.title = o.get_string_member_with_default ("title", "");
            e.description = o.get_string_member_with_default ("description", "");
            e.link = o.get_string_member_with_default ("link", "");
            e.audio_url = o.get_string_member_with_default ("audio", "");
            e.mime = o.get_string_member_with_default ("mime", "");
            e.size = o.get_int_member_with_default ("size", 0);
            e.duration = (int) o.get_int_member_with_default ("duration", 0);
            e.published = o.get_int_member_with_default ("published", 0);
            e.image_url = o.get_string_member_with_default ("image", "");
            e.position = (int) o.get_int_member_with_default ("position", 0);
            e.played = o.get_boolean_member_with_default ("played", false);
            e.download_path = o.get_string_member_with_default ("download", "");
            e.chapters_url = o.get_string_member_with_default ("chapters_url", "");
            e.chapters_fetched = o.get_boolean_member_with_default ("chapters_fetched", false);
            if (o.has_member ("chapters") && o.get_member ("chapters").get_node_type () == Json.NodeType.ARRAY) {
                foreach (var n in o.get_array_member ("chapters").get_elements ()) {
                    if (n.get_node_type () == Json.NodeType.OBJECT) e.chapters.add (Chapter.from_json (n.get_object ()));
                }
                Chapters.normalize (e.chapters);
            }
            return e;
        }
    }

    public class Show : Object {
        public string feed_url = "";
        public string title = "";
        public string author = "";
        public string description = "";
        public string link = "";
        public string image_url = "";
        public int64 refreshed;
        public string error = "";
        public double speed;
        public int trim_silence = -1;
        public int voice_boost = -1;
        public Gee.ArrayList<Episode> episodes = new Gee.ArrayList<Episode> ();

        public int unplayed () {
            int n = 0;
            foreach (var e in episodes) if (!e.played) n++;
            return n;
        }

        public void sort () {
            episodes.sort ((a, b) => a.published > b.published ? -1 : (a.published < b.published ? 1 : 0));
        }

        public Json.Object to_json () {
            var o = new Json.Object ();
            o.set_string_member ("url", feed_url);
            o.set_string_member ("title", title);
            o.set_string_member ("author", author);
            o.set_string_member ("description", description);
            o.set_string_member ("link", link);
            o.set_string_member ("image", image_url);
            o.set_int_member ("refreshed", refreshed);
            if (speed > 0) o.set_double_member ("speed", speed);
            if (trim_silence >= 0) o.set_int_member ("trim_silence", trim_silence);
            if (voice_boost >= 0) o.set_int_member ("voice_boost", voice_boost);
            var arr = new Json.Array ();
            foreach (var e in episodes) arr.add_object_element (e.to_json ());
            o.set_array_member ("episodes", arr);
            return o;
        }

        public static Show from_json (Json.Object o) {
            var s = new Show ();
            s.feed_url = o.get_string_member_with_default ("url", "");
            s.title = o.get_string_member_with_default ("title", "");
            s.author = o.get_string_member_with_default ("author", "");
            s.description = o.get_string_member_with_default ("description", "");
            s.link = o.get_string_member_with_default ("link", "");
            s.image_url = o.get_string_member_with_default ("image", "");
            s.refreshed = o.get_int_member_with_default ("refreshed", 0);
            s.speed = o.get_double_member_with_default ("speed", 0);
            if (s.speed != 0 && (s.speed < 0.5 || s.speed > 3.0)) s.speed = 0;
            s.trim_silence = (int) o.get_int_member_with_default ("trim_silence", -1).clamp (-1, 1);
            s.voice_boost = (int) o.get_int_member_with_default ("voice_boost", -1).clamp (-1, 1);
            if (o.has_member ("episodes")) {
                foreach (var n in o.get_array_member ("episodes").get_elements ()) {
                    var e = Episode.from_json (n.get_object ());
                    e.show_url = s.feed_url;
                    s.episodes.add (e);
                }
            }
            return s;
        }
    }

    namespace Feed {
        public const string NS_ITUNES = "http://www.itunes.com/dtds/podcast-1.0.dtd";
        public const string NS_CONTENT = "http://purl.org/rss/1.0/modules/content/";
        public const string NS_ATOM = "http://www.w3.org/2005/Atom";
        public const string NS_MEDIA = "http://search.yahoo.com/mrss/";
        public const int MAX_DESCRIPTION = 6000;

        private bool is (Xml.Node* n, string name, string? ns = null) {
            if (n == null || n->type != Xml.ElementType.ELEMENT_NODE || n->name != name) return false;
            string href = n->ns != null && n->ns->href != null ? n->ns->href : "";
            if (ns == null) return href == "" || href == NS_ATOM || href.has_prefix ("http://purl.org/rss") || href.has_prefix ("http://backend.userland.com");
            return href == ns;
        }

        private Xml.Node* child (Xml.Node* parent, string name, string? ns = null) {
            for (Xml.Node* c = parent->children; c != null; c = c->next) if (is (c, name, ns)) return c;
            return null;
        }

        private string text (Xml.Node* parent, string name, string? ns = null) {
            Xml.Node* c = child (parent, name, ns);
            return c != null ? (c->get_content () ?? "").strip () : "";
        }

        private string attr (Xml.Node* n, string name) {
            if (n == null) return "";
            return (n->get_prop (name) ?? "").strip ();
        }

        public Show parse (string data, string feed_url) throws FeedError {
            if (data.strip () == "") throw new FeedError.INVALID (_("The feed is empty."));
            Xml.Doc* doc = Xml.Parser.read_memory (data, data.length, feed_url, null, Xml.ParserOption.NONET | Xml.ParserOption.RECOVER | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING | Xml.ParserOption.NOCDATA);
            if (doc == null) throw new FeedError.INVALID (_("The feed could not be read."));
            Xml.Node* root = doc->get_root_element ();
            Show? show = null;
            if (root != null && root->name == "rss") {
                Xml.Node* channel = child (root, "channel");
                if (channel != null) show = parse_rss (channel, root);
            } else if (root != null && root->name == "RDF") {
                Xml.Node* channel = child (root, "channel");
                if (channel != null) show = parse_rss (channel, root);
            } else if (root != null && root->name == "feed") {
                show = parse_atom (root);
            }
            delete doc;
            if (show == null) throw new FeedError.NOT_A_FEED (_("This address is not a podcast feed."));
            show.feed_url = feed_url;
            foreach (var e in show.episodes) e.show_url = feed_url;
            show.sort ();
            return show;
        }

        private Show parse_rss (Xml.Node* channel, Xml.Node* root) {
            var s = new Show ();
            s.title = Sanitize.to_text (text (channel, "title"));
            s.link = text (channel, "link");
            s.author = Sanitize.to_text (text (channel, "author", NS_ITUNES));
            if (s.author == "") s.author = Sanitize.to_text (text (channel, "managingEditor"));
            string desc = text (channel, "summary", NS_ITUNES);
            if (desc == "") desc = text (channel, "description");
            s.description = clip (Sanitize.to_text (desc));
            s.image_url = attr (child (channel, "image", NS_ITUNES), "href");
            if (s.image_url == "") {
                Xml.Node* img = child (channel, "image");
                if (img != null) s.image_url = text (img, "url");
            }
            Xml.Node* holder = channel;
            if (child (channel, "item") == null) holder = root;
            for (Xml.Node* c = holder->children; c != null; c = c->next) {
                if (!is (c, "item")) continue;
                var e = new Episode ();
                e.title = Sanitize.to_text (text (c, "title"));
                e.guid = text (c, "guid");
                e.link = text (c, "link");
                string body = text (c, "encoded", NS_CONTENT);
                if (body == "") body = text (c, "description");
                if (body == "") body = text (c, "summary", NS_ITUNES);
                e.description = clip (Sanitize.to_text (body));
                Xml.Node* enc = child (c, "enclosure");
                if (enc != null) {
                    e.audio_url = attr (enc, "url");
                    e.mime = attr (enc, "type");
                    e.size = int64.parse (attr (enc, "length"));
                }
                if (e.audio_url == "") {
                    Xml.Node* media = child (c, "content", NS_MEDIA);
                    if (media != null) {
                        e.audio_url = attr (media, "url");
                        e.mime = attr (media, "type");
                    }
                }
                e.duration = parse_duration (text (c, "duration", NS_ITUNES));
                string date = text (c, "pubDate");
                e.published = date != "" ? parse_rfc822 (date) : parse_iso8601 (text (c, "date", "http://purl.org/dc/elements/1.1/"));
                e.image_url = attr (child (c, "image", NS_ITUNES), "href");
                Xml.Node* pc = child (c, "chapters", Chapters.NS_PODCAST);
                if (pc != null) {
                    string url = attr (pc, "url");
                    string type = attr (pc, "type").down ();
                    if ((type == "" || type.contains ("json")) && (url.has_prefix ("https://") || url.has_prefix ("http://"))) e.chapters_url = url;
                }
                Xml.Node* psc = child (c, "chapters", Chapters.NS_PSC);
                if (psc != null) e.chapters.add_all (Chapters.parse_psc (psc));
                if (e.audio_url == "") continue;
                if (e.title == "") e.title = _("Untitled Episode");
                s.episodes.add (e);
            }
            if (s.title == "") s.title = _("Untitled Podcast");
            return s;
        }

        private Show parse_atom (Xml.Node* feed) {
            var s = new Show ();
            s.title = Sanitize.to_text (text (feed, "title"));
            s.description = clip (Sanitize.to_text (text (feed, "subtitle")));
            Xml.Node* author = child (feed, "author");
            if (author != null) s.author = Sanitize.to_text (text (author, "name"));
            s.image_url = attr (child (feed, "image", NS_ITUNES), "href");
            if (s.image_url == "") s.image_url = text (feed, "logo");
            if (s.image_url == "") s.image_url = text (feed, "icon");
            for (Xml.Node* c = feed->children; c != null; c = c->next) {
                if (is (c, "link") && (attr (c, "rel") == "" || attr (c, "rel") == "alternate")) s.link = attr (c, "href");
                if (!is (c, "entry")) continue;
                var e = new Episode ();
                e.title = Sanitize.to_text (text (c, "title"));
                e.guid = text (c, "id");
                string body = text (c, "content");
                if (body == "") body = text (c, "summary");
                e.description = clip (Sanitize.to_text (body));
                for (Xml.Node* l = c->children; l != null; l = l->next) {
                    if (!is (l, "link")) continue;
                    string rel = attr (l, "rel");
                    if (rel == "enclosure" && e.audio_url == "") {
                        e.audio_url = attr (l, "href");
                        e.mime = attr (l, "type");
                        e.size = int64.parse (attr (l, "length"));
                    } else if (rel == "" || rel == "alternate") {
                        e.link = attr (l, "href");
                    }
                }
                string date = text (c, "published");
                if (date == "") date = text (c, "updated");
                e.published = parse_iso8601 (date);
                e.duration = parse_duration (text (c, "duration", NS_ITUNES));
                if (e.audio_url == "") continue;
                if (e.title == "") e.title = _("Untitled Episode");
                s.episodes.add (e);
            }
            if (s.title == "") s.title = _("Untitled Podcast");
            return s;
        }

        private string clip (string s) {
            if (s.length <= MAX_DESCRIPTION) return s;
            int cut = s.index_of_nth_char (s.char_count (MAX_DESCRIPTION) - 1);
            return s.substring (0, cut).strip () + "…";
        }

        public string? find_alternate (string html) {
            try {
                var re = new Regex ("<link[^>]+>", RegexCompileFlags.CASELESS);
                var href_re = new Regex ("href\\s*=\\s*[\"']([^\"']+)[\"']", RegexCompileFlags.CASELESS);
                MatchInfo m;
                re.match (html, 0, out m);
                while (m.matches ()) {
                    string tag = m.fetch (0);
                    string low = tag.down ();
                    if (low.contains ("alternate") && (low.contains ("application/rss+xml") || low.contains ("application/atom+xml"))) {
                        MatchInfo h;
                        if (href_re.match (tag, 0, out h)) return Sanitize.decode_entities (h.fetch (1));
                    }
                    m.next ();
                }
            } catch (Error e) {
            }
            return null;
        }

        public int parse_duration (string raw) {
            string s = raw.strip ();
            if (s == "") return 0;
            string[] parts = s.split (":");
            if (parts.length > 3) return 0;
            int total = 0;
            foreach (string p in parts) {
                string t = p.strip ();
                int dot = t.index_of (".");
                if (dot >= 0) t = t.substring (0, dot);
                if (t == "") t = "0";
                for (int i = 0; i < t.length; i++) if (!t[i].isdigit ()) return 0;
                total = total * 60 + int.parse (t);
            }
            return total;
        }

        private int month_of (string m) {
            string[] names = { "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" };
            string k = m.down ();
            if (k.length < 3) return 0;
            k = k.substring (0, 3);
            for (int i = 0; i < 12; i++) if (names[i] == k) return i + 1;
            return 0;
        }

        private int zone_offset (string z) {
            switch (z.up ()) {
                case "":
                case "GMT":
                case "UT":
                case "UTC":
                case "Z":
                    return 0;
                case "EST": return -5 * 3600;
                case "EDT": return -4 * 3600;
                case "CST": return -6 * 3600;
                case "CDT": return -5 * 3600;
                case "MST": return -7 * 3600;
                case "MDT": return -6 * 3600;
                case "PST": return -8 * 3600;
                case "PDT": return -7 * 3600;
            }
            if (z.length >= 5 && (z[0] == '+' || z[0] == '-')) {
                string d = z.substring (1).replace (":", "");
                if (d.length != 4) return 0;
                int h = int.parse (d.substring (0, 2)), m = int.parse (d.substring (2, 2));
                int off = h * 3600 + m * 60;
                return z[0] == '-' ? -off : off;
            }
            return 0;
        }

        public int64 parse_rfc822 (string raw) {
            string s = raw.strip ();
            int comma = s.index_of (",");
            if (comma >= 0) s = s.substring (comma + 1);
            string[] tok = {};
            foreach (string t in s.split_set (" \t")) if (t != "") tok += t;
            if (tok.length < 3) return parse_iso8601 (raw);
            int day = int.parse (tok[0]);
            int month = month_of (tok[1]);
            if (month == 0 && month_of (tok[0]) != 0) {
                month = month_of (tok[0]);
                day = int.parse (tok[1]);
            }
            int year = int.parse (tok[2]);
            if (year < 100) year += year < 70 ? 2000 : 1900;
            if (day < 1 || day > 31 || month == 0 || year < 1900) return parse_iso8601 (raw);
            int hh = 0, mm = 0, ss = 0;
            if (tok.length > 3) {
                string[] t = tok[3].split (":");
                if (t.length >= 2) {
                    hh = int.parse (t[0]);
                    mm = int.parse (t[1]);
                    if (t.length > 2) ss = int.parse (t[2]);
                }
            }
            string zone = tok.length > 4 ? tok[4] : "";
            var dt = new DateTime.utc (year, month, day, hh.clamp (0, 23), mm.clamp (0, 59), ss.clamp (0, 59));
            if (dt == null) return 0;
            return dt.to_unix () - zone_offset (zone);
        }

        public int64 parse_iso8601 (string raw) {
            string s = raw.strip ();
            if (s == "") return 0;
            if (s.length == 10) s += "T00:00:00Z";
            var dt = new DateTime.from_iso8601 (s, new TimeZone.utc ());
            return dt != null ? dt.to_unix () : 0;
        }
    }

    namespace Sanitize {
        private struct Entity {
            public string name;
            public unichar code;
        }

        private const Entity[] ENTITIES = {
            { "amp", '&' }, { "lt", '<' }, { "gt", '>' }, { "quot", '"' }, { "apos", '\'' },
            { "nbsp", 0xA0 }, { "hellip", 0x2026 }, { "mdash", 0x2014 }, { "ndash", 0x2013 },
            { "rsquo", 0x2019 }, { "lsquo", 0x2018 }, { "rdquo", 0x201D }, { "ldquo", 0x201C },
            { "copy", 0xA9 }, { "reg", 0xAE }, { "trade", 0x2122 }, { "bull", 0x2022 }, { "middot", 0xB7 },
            { "eacute", 0xE9 }, { "egrave", 0xE8 }, { "agrave", 0xE0 }, { "aacute", 0xE1 }, { "ograve", 0xF2 },
            { "oacute", 0xF3 }, { "ugrave", 0xF9 }, { "uacute", 0xFA }, { "igrave", 0xEC }, { "iacute", 0xED },
            { "auml", 0xE4 }, { "ouml", 0xF6 }, { "uuml", 0xFC }, { "szlig", 0xDF }, { "ccedil", 0xE7 },
            { "ntilde", 0xF1 }, { "euro", 0x20AC }, { "pound", 0xA3 }
        };

        public string decode_entities (string s) {
            if (!s.contains ("&")) return s;
            var sb = new StringBuilder ();
            int i = 0;
            while (i < s.length) {
                char c = s[i];
                if (c == '&') {
                    int semi = s.index_of (";", i);
                    if (semi > i + 1 && semi - i <= 12) {
                        string name = s.substring (i + 1, semi - i - 1);
                        unichar code = 0;
                        if (name.has_prefix ("#x") || name.has_prefix ("#X")) {
                            code = (unichar) uint64.parse (name.substring (2), 16);
                        } else if (name.has_prefix ("#")) {
                            code = (unichar) uint64.parse (name.substring (1));
                        } else {
                            foreach (var e in ENTITIES) if (e.name == name) code = e.code;
                        }
                        if (code != 0 && code.validate ()) {
                            sb.append_unichar (code);
                            i = semi + 1;
                            continue;
                        }
                    }
                }
                sb.append_c (c);
                i++;
            }
            return sb.str;
        }

        public string to_text (string html) {
            if (html == "") return "";
            string s = html.replace ("\r\n", "\n").replace ("\r", "\n");
            bool markup = s.contains ("<") && s.contains (">");
            if (markup) {
                try {
                    s = new Regex ("<!--.*?-->", RegexCompileFlags.DOTALL).replace (s, -1, 0, "");
                    s = new Regex ("<(script|style)[^>]*>.*?</\\1\\s*>", RegexCompileFlags.DOTALL | RegexCompileFlags.CASELESS).replace (s, -1, 0, "");
                    s = new Regex ("\\s+").replace (s, -1, 0, " ");
                    s = new Regex ("<br\\s*/?>", RegexCompileFlags.CASELESS).replace (s, -1, 0, "\n");
                    s = new Regex ("<li[^>]*>", RegexCompileFlags.CASELESS).replace (s, -1, 0, "\n• ");
                    s = new Regex ("</?(p|div|ul|ol|h[1-6]|blockquote|table|tr|section|article)(\\s[^>]*)?>", RegexCompileFlags.CASELESS).replace (s, -1, 0, "\n\n");
                    s = new Regex ("<[^>]*>").replace (s, -1, 0, "");
                } catch (RegexError e) {
                }
            }
            s = decode_entities (s);
            if (!s.validate ()) s = s.make_valid ();
            var sb = new StringBuilder ();
            int blank = 0;
            bool started = false;
            foreach (string raw in s.split ("\n")) {
                string line = collapse (raw);
                if (line == "") {
                    blank++;
                    continue;
                }
                if (started) sb.append (blank > 0 ? "\n\n" : "\n");
                sb.append (line);
                started = true;
                blank = 0;
            }
            return sb.str;
        }

        private string collapse (string line) {
            var sb = new StringBuilder ();
            bool space = false;
            unichar ch;
            int idx = 0;
            while (line.get_next_char (ref idx, out ch)) {
                if (ch == ' ' || ch == '\t' || ch == 0xA0) {
                    space = true;
                    continue;
                }
                if (space && sb.len > 0) sb.append_c (' ');
                space = false;
                sb.append_unichar (ch);
            }
            return sb.str;
        }
    }
}
