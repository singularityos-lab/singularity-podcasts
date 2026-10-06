namespace Singularity.Apps.Podcasts {

    public class Outline : Object {
        public string title;
        public string feed_url;
        public string link;

        public Outline (string title, string feed_url, string link = "") {
            this.title = title;
            this.feed_url = feed_url;
            this.link = link;
        }
    }

    namespace Opml {
        public Gee.List<Outline> parse (string data) throws FeedError {
            var list = new Gee.ArrayList<Outline> ();
            Xml.Doc* doc = Xml.Parser.read_memory (data, data.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.RECOVER | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null) throw new FeedError.INVALID (_("The file is not a valid OPML document."));
            Xml.Node* root = doc->get_root_element ();
            if (root == null || root->name.down () != "opml") {
                delete doc;
                throw new FeedError.INVALID (_("The file is not a valid OPML document."));
            }
            collect (root, list);
            delete doc;
            return list;
        }

        private void collect (Xml.Node* n, Gee.List<Outline> list) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "outline") {
                    string url = (c->get_prop ("xmlUrl") ?? c->get_prop ("xmlurl") ?? "").strip ();
                    if (url != "") {
                        bool known = false;
                        foreach (var o in list) if (o.feed_url == url) known = true;
                        if (!known) {
                            string title = (c->get_prop ("title") ?? c->get_prop ("text") ?? "").strip ();
                            list.add (new Outline (title, url, (c->get_prop ("htmlUrl") ?? "").strip ()));
                        }
                    }
                }
                collect (c, list);
            }
        }

        private string esc (string s) {
            return Markup.escape_text (s).replace ("\n", "&#10;");
        }

        public string serialize (Gee.List<Outline> items, string title, DateTime? now = null) {
            var sb = new StringBuilder ();
            sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            sb.append ("<opml version=\"2.0\">\n");
            sb.append ("  <head>\n");
            sb.append ("    <title>%s</title>\n".printf (esc (title)));
            var date = now ?? new DateTime.now_utc ();
            sb.append ("    <dateCreated>%s</dateCreated>\n".printf (date.to_utc ().format ("%a, %d %b %Y %H:%M:%S GMT")));
            sb.append ("  </head>\n");
            sb.append ("  <body>\n");
            foreach (var o in items) {
                sb.append ("    <outline type=\"rss\" text=\"%s\" title=\"%s\" xmlUrl=\"%s\"".printf (esc (o.title), esc (o.title), esc (o.feed_url)));
                if (o.link != "") sb.append (" htmlUrl=\"%s\"".printf (esc (o.link)));
                sb.append ("/>\n");
            }
            sb.append ("  </body>\n");
            sb.append ("</opml>\n");
            return sb.str;
        }
    }
}
