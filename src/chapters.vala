namespace Singularity.Apps.Podcasts {

    public class Chapter : Object {
        public double start;
        public double end = -1;
        public string title = "";
        public string url = "";
        public string image = "";

        public Json.Object to_json () {
            var o = new Json.Object ();
            o.set_double_member ("start", start);
            o.set_double_member ("end", end);
            o.set_string_member ("title", title);
            if (url != "") o.set_string_member ("url", url);
            if (image != "") o.set_string_member ("image", image);
            return o;
        }

        public static Chapter from_json (Json.Object o) {
            var c = new Chapter ();
            c.start = Chapters.number (o, "start");
            c.end = o.has_member ("end") ? Chapters.number (o, "end") : -1;
            c.title = o.get_string_member_with_default ("title", "");
            c.url = o.get_string_member_with_default ("url", "");
            c.image = o.get_string_member_with_default ("image", "");
            return c;
        }
    }

    namespace Chapters {
        public const string NS_PODCAST = "https://podcastindex.org/namespace/1.0";
        public const string NS_PSC = "http://podlove.org/simple-chapters";
        public const int MAX_CHAPTERS = 500;

        public double number (Json.Object o, string member) {
            if (!o.has_member (member)) return -1;
            var n = o.get_member (member);
            if (n.get_node_type () != Json.NodeType.VALUE) return -1;
            var t = n.get_value_type ();
            if (t == typeof (double)) return n.get_double ();
            if (t == typeof (int64)) return (double) n.get_int ();
            if (t == typeof (string)) return parse_npt (n.get_string () ?? "");
            return -1;
        }

        public double parse_npt (string raw) {
            string s = raw.strip ();
            if (s == "") return -1;
            string[] parts = s.split (":");
            if (parts.length > 3) return -1;
            double total = 0;
            for (int i = 0; i < parts.length; i++) {
                string p = parts[i].strip ();
                if (p == "") return -1;
                bool last = i == parts.length - 1;
                int dots = 0;
                for (int j = 0; j < p.length; j++) {
                    if (p[j] == '.') dots++;
                    else if (!p[j].isdigit ()) return -1;
                }
                if (dots > (last ? 1 : 0)) return -1;
                double v = double.parse (p);
                if (i > 0 && v >= 60) return -1;
                total = total * 60 + v;
            }
            return total;
        }

        private string text_of (string? s) {
            return Sanitize.to_text ((s ?? "").strip ());
        }

        public Gee.List<Chapter> parse_json (string data) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (data, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) throw new IOError.INVALID_DATA (_("The chapters file is not valid."));
            var o = root.get_object ();
            if (!o.has_member ("chapters") || o.get_member ("chapters").get_node_type () != Json.NodeType.ARRAY) throw new IOError.INVALID_DATA (_("The chapters file is not valid."));
            var list = new Gee.ArrayList<Chapter> ();
            foreach (var n in o.get_array_member ("chapters").get_elements ()) {
                if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                var c = n.get_object ();
                if (c.has_member ("toc") && c.get_member ("toc").get_value_type () == typeof (bool) && !c.get_boolean_member ("toc")) continue;
                var ch = new Chapter ();
                ch.start = number (c, "startTime");
                if (ch.start < 0) continue;
                ch.end = number (c, "endTime");
                ch.title = c.has_member ("title") && c.get_member ("title").get_value_type () == typeof (string) ? text_of (c.get_string_member ("title")) : "";
                ch.url = c.has_member ("url") && c.get_member ("url").get_value_type () == typeof (string) ? c.get_string_member ("url").strip () : "";
                ch.image = c.has_member ("img") && c.get_member ("img").get_value_type () == typeof (string) ? c.get_string_member ("img").strip () : "";
                list.add (ch);
                if (list.size >= MAX_CHAPTERS) break;
            }
            normalize (list);
            return list;
        }

        public Gee.List<Chapter> parse_psc (Xml.Node* holder) {
            var list = new Gee.ArrayList<Chapter> ();
            if (holder == null) return list;
            for (Xml.Node* c = holder->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "chapter") continue;
                if (c->ns == null || c->ns->href != NS_PSC) continue;
                var ch = new Chapter ();
                ch.start = parse_npt (c->get_prop ("start") ?? "");
                if (ch.start < 0) continue;
                ch.title = text_of (c->get_prop ("title"));
                ch.url = (c->get_prop ("href") ?? "").strip ();
                ch.image = (c->get_prop ("image") ?? "").strip ();
                list.add (ch);
                if (list.size >= MAX_CHAPTERS) break;
            }
            normalize (list);
            return list;
        }

        public void normalize (Gee.List<Chapter> list) {
            list.sort ((a, b) => a.start < b.start ? -1 : (a.start > b.start ? 1 : 0));
            for (int i = list.size - 1; i > 0; i--) {
                if (Math.fabs (list[i].start - list[i - 1].start) < 0.001) list.remove_at (i);
            }
            for (int i = 0; i < list.size; i++) {
                if (list[i].title == "") list[i].title = _("Chapter %d").printf (i + 1);
                if (i + 1 < list.size) {
                    double next = list[i + 1].start;
                    if (list[i].end <= list[i].start || list[i].end > next) list[i].end = next;
                } else if (list[i].end <= list[i].start) {
                    list[i].end = -1;
                }
            }
        }

        public int index_at (Gee.List<Chapter> list, double position) {
            int found = -1;
            for (int i = 0; i < list.size; i++) {
                if (list[i].start <= position + 0.001) found = i;
                else break;
            }
            return found;
        }

        private uint32 be32 (uint8[] d, int at) {
            return ((uint32) d[at] << 24) | ((uint32) d[at + 1] << 16) | ((uint32) d[at + 2] << 8) | (uint32) d[at + 3];
        }

        private uint32 syncsafe (uint8[] d, int at) {
            return ((uint32) (d[at] & 0x7f) << 21) | ((uint32) (d[at + 1] & 0x7f) << 14) | ((uint32) (d[at + 2] & 0x7f) << 7) | (uint32) (d[at + 3] & 0x7f);
        }

        private uint8[] unsync (uint8[] d) {
            var out_data = new ByteArray ();
            for (int i = 0; i < d.length; i++) {
                out_data.append ({ d[i] });
                if (d[i] == 0xff && i + 1 < d.length && d[i + 1] == 0x00) i++;
            }
            return out_data.steal ();
        }

        private string decode_text (uint8[] d, int from, int to) {
            if (from >= to) return "";
            uint8 enc = d[from];
            uint8[] raw = d[from + 1:to];
            string? result = null;
            try {
                switch (enc) {
                    case 0:
                        result = convert ((string) raw, raw.length, "UTF-8", "ISO-8859-1");
                        break;
                    case 1:
                        result = convert ((string) raw, raw.length, "UTF-8", "UTF-16");
                        break;
                    case 2:
                        result = convert ((string) raw, raw.length, "UTF-8", "UTF-16BE");
                        break;
                    default:
                        var sb = new StringBuilder ();
                        sb.append_len ((string) raw, raw.length);
                        result = sb.str;
                        break;
                }
            } catch (ConvertError e) {
                return "";
            }
            if (result == null) return "";
            if (!result.validate ()) result = result.make_valid ();
            return result.strip ();
        }

        public Gee.List<Chapter> parse_id3 (uint8[] data) {
            var list = new Gee.ArrayList<Chapter> ();
            if (data.length < 10 || data[0] != 'I' || data[1] != 'D' || data[2] != '3') return list;
            int major = data[3];
            if (major != 3 && major != 4) return list;
            uint8 flags = data[5];
            int size = (int) syncsafe (data, 6);
            if (size <= 0 || 10 + size > data.length) size = data.length - 10;
            uint8[] tag = data[10:10 + size];
            if (major == 3 && (flags & 0x80) != 0) tag = unsync (tag);
            int pos = 0;
            if ((flags & 0x40) != 0 && tag.length >= 4) {
                int ext = major == 4 ? (int) syncsafe (tag, 0) : (int) be32 (tag, 0) + 4;
                if (ext < 0 || ext > tag.length) return list;
                pos = ext;
            }
            read_frames (tag, pos, tag.length, major, list, true);
            normalize (list);
            return list;
        }

        private string read_frames (uint8[] tag, int pos, int limit, int major, Gee.List<Chapter> list, bool top) {
            string title = "";
            while (pos + 10 <= limit) {
                if (tag[pos] == 0) break;
                var id = new StringBuilder ();
                for (int i = 0; i < 4; i++) id.append_c ((char) tag[pos + i]);
                int fsize = major == 4 ? (int) syncsafe (tag, pos + 4) : (int) be32 (tag, pos + 4);
                int body = pos + 10;
                if (fsize <= 0 || body + fsize > limit) break;
                if (top && id.str == "CHAP") {
                    var ch = read_chap (tag, body, body + fsize, major);
                    if (ch != null && list.size < MAX_CHAPTERS) list.add (ch);
                } else if (!top && id.str == "TIT2" && title == "") {
                    title = decode_text (tag, body, body + fsize);
                }
                pos = body + fsize;
            }
            return title;
        }

        private Chapter? read_chap (uint8[] tag, int from, int to, int major) {
            int p = from;
            while (p < to && tag[p] != 0) p++;
            p++;
            if (p + 16 > to) return null;
            uint32 start_ms = be32 (tag, p);
            uint32 end_ms = be32 (tag, p + 4);
            p += 16;
            var ch = new Chapter ();
            ch.start = start_ms / 1000.0;
            ch.end = end_ms == 0xffffffff ? -1 : end_ms / 1000.0;
            ch.title = read_frames (tag, p, to, major, new Gee.ArrayList<Chapter> (), false);
            return ch;
        }

        public Gee.List<Chapter> read_id3_file (string path) throws Error {
            var file = File.new_for_path (path);
            var stream = file.read ();
            uint8[] head = new uint8[10];
            size_t got;
            stream.read_all (head, out got);
            if (got < 10 || head[0] != 'I' || head[1] != 'D' || head[2] != '3') return new Gee.ArrayList<Chapter> ();
            int size = (int) syncsafe (head, 6);
            if (size <= 0 || size > 64 * 1024 * 1024) return new Gee.ArrayList<Chapter> ();
            uint8[] all = new uint8[10 + size];
            Memory.copy (all, head, 10);
            uint8[] rest = new uint8[size];
            stream.read_all (rest, out got);
            Memory.copy ((uint8*) all + 10, rest, got);
            stream.close ();
            return parse_id3 (all[0:10 + (int) got]);
        }
    }
}
