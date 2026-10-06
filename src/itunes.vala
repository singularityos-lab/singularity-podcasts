namespace Singularity.Apps.Podcasts {

    public class SearchResult : Object {
        public string title = "";
        public string author = "";
        public string feed_url = "";
        public string artwork = "";
        public string genre = "";
        public int episodes;
    }

    namespace ITunes {
        public string search_url (string term, string country = "") {
            string url = "https://itunes.apple.com/search?media=podcast&entity=podcast&limit=40&term=" + Uri.escape_string (term.strip (), null, false);
            if (country.length == 2) url += "&country=" + country.down ();
            return url;
        }

        public Gee.List<SearchResult> parse (Json.Node root) {
            var list = new Gee.ArrayList<SearchResult> ();
            if (root.get_node_type () != Json.NodeType.OBJECT) return list;
            var o = root.get_object ();
            if (!o.has_member ("results")) return list;
            foreach (var n in o.get_array_member ("results").get_elements ()) {
                if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                var r = n.get_object ();
                string feed = r.get_string_member_with_default ("feedUrl", "");
                if (feed == "") continue;
                var s = new SearchResult ();
                s.feed_url = feed;
                s.title = r.get_string_member_with_default ("collectionName", r.get_string_member_with_default ("trackName", ""));
                s.author = r.get_string_member_with_default ("artistName", "");
                s.artwork = r.get_string_member_with_default ("artworkUrl600", r.get_string_member_with_default ("artworkUrl100", ""));
                s.genre = r.get_string_member_with_default ("primaryGenreName", "");
                s.episodes = (int) r.get_int_member_with_default ("trackCount", 0);
                if (s.title == "") s.title = _("Untitled Podcast");
                list.add (s);
            }
            return list;
        }
    }
}
