namespace Singularity.Apps.Podcasts {

    public class Net {
        private static Soup.Session? session;

        public static Soup.Session get () {
            if (session == null) {
                session = new Soup.Session ();
                session.user_agent = "SingularityPodcasts/0.1 (+https://github.com/singularityos-lab)";
                session.timeout = 30;
            }
            return session;
        }

        public static string normalize_url (string raw) {
            string s = raw.strip ();
            if (s.has_prefix ("feed://")) s = "https://" + s.substring (7);
            else if (s.has_prefix ("itpc://") || s.has_prefix ("pcast://")) s = "https://" + s.substring (s.index_of ("://") + 3);
            else if (!s.contains ("://")) s = "https://" + s;
            return s;
        }

        public static bool looks_like_url (string raw) {
            string s = raw.strip ();
            if (s == "" || s.contains (" ")) return false;
            if (s.contains ("://")) return true;
            int dot = s.index_of (".");
            return dot > 0 && dot < s.length - 2;
        }

        public static Error friendly (Error e) {
            if (e is IOError.CANCELLED) return e;
            if (!NetworkMonitor.get_default ().network_available) return new IOError.NETWORK_UNREACHABLE (_("You are offline. Connect to the internet and try again."));
            if (e is ResolverError) return new IOError.HOST_NOT_FOUND (_("The server could not be found. Check the address and your connection."));
            if (e is IOError.TIMED_OUT) return new IOError.TIMED_OUT (_("The server took too long to answer."));
            if (e is IOError.CONNECTION_REFUSED || e is IOError.NETWORK_UNREACHABLE || e is IOError.HOST_UNREACHABLE) return new IOError.FAILED (_("The server could not be reached."));
            if (e is TlsError) return new IOError.FAILED (_("The secure connection to the server failed."));
            return e;
        }

        public static async Bytes fetch (string url, Cancellable? cancel = null, out string final_url = null) throws Error {
            final_url = url;
            Soup.Message? msg = null;
            if (Uri.peek_scheme (url) == "http" || Uri.peek_scheme (url) == "https") msg = new Soup.Message ("GET", url);
            if (msg == null) throw new IOError.INVALID_ARGUMENT (_("This is not a valid web address."));
            Bytes bytes;
            try {
                bytes = yield get ().send_and_read_async (msg, Priority.DEFAULT, cancel);
            } catch (Error e) {
                throw friendly (e);
            }
            if (msg.status_code == 404 || msg.status_code == 410) throw new IOError.NOT_FOUND (_("Nothing was found at this address (HTTP %u).").printf (msg.status_code));
            if (msg.status_code == 401 || msg.status_code == 403) throw new IOError.PERMISSION_DENIED (_("The server refused access (HTTP %u).").printf (msg.status_code));
            if (msg.status_code < 200 || msg.status_code >= 300) throw new IOError.FAILED (_("The server answered with an error (HTTP %u).").printf (msg.status_code));
            var uri = msg.get_uri ();
            if (uri != null) final_url = uri.to_string ();
            return bytes;
        }

        public static string text_of (Bytes bytes) {
            unowned uint8[] d = bytes.get_data ();
            if (d == null || d.length == 0) return "";
            var sb = new StringBuilder.sized (d.length + 1);
            sb.append_len ((string) d, d.length);
            return sb.str;
        }

        public static async Show fetch_show (string url, Cancellable? cancel = null) throws Error {
            string final_url;
            var bytes = yield fetch (url, cancel, out final_url);
            string data = text_of (bytes);
            try {
                return Feed.parse (data, url);
            } catch (FeedError e) {
                if (!(e is FeedError.NOT_A_FEED) && !data.down ().contains ("<html")) throw e;
                string? alt = Feed.find_alternate (data);
                if (alt == null) throw new FeedError.NOT_A_FEED (_("This address is not a podcast feed."));
                string resolved = alt;
                try {
                    resolved = Uri.resolve_relative (final_url, alt, UriFlags.NONE);
                } catch (Error re) {
                }
                var again = yield fetch (resolved, cancel);
                return Feed.parse (text_of (again), resolved);
            }
        }

        public static async Gee.List<Chapter> fetch_chapters (string url, Cancellable? cancel = null) throws Error {
            var bytes = yield fetch (url, cancel);
            if (bytes.get_size () > 4 * 1024 * 1024) throw new IOError.FAILED (_("The chapters file is too large."));
            return Chapters.parse_json (text_of (bytes));
        }

        public static async Gee.List<SearchResult> search (string term, Cancellable? cancel = null) throws Error {
            string country = "";
            string lang = Intl.get_language_names ()[0];
            int us = lang.index_of ("_");
            if (us > 0 && lang.length >= us + 3) country = lang.substring (us + 1, 2);
            var bytes = yield fetch (ITunes.search_url (term, country), cancel);
            var parser = new Json.Parser ();
            try {
                parser.load_from_data ((string) bytes.get_data (), (ssize_t) bytes.get_size ());
            } catch (Error e) {
                throw new IOError.FAILED (_("The search service sent an unexpected answer."));
            }
            return ITunes.parse (parser.get_root ());
        }
    }
}
