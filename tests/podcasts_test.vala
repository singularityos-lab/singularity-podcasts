using Singularity.Apps.Podcasts;

string fixture (string name) {
    string data;
    try {
        FileUtils.get_contents (Path.build_filename (Environment.get_variable ("PODCASTS_FIXTURES"), name), out data);
    } catch (Error e) {
        assert_not_reached ();
    }
    return data;
}

int64 utc (int y, int mo, int d, int h, int mi, int s) {
    return new DateTime.utc (y, mo, d, h, mi, s).to_unix ();
}

void test_rss () {
    Show show;
    try {
        show = Feed.parse (fixture ("rss.xml"), "https://example.org/orbit/feed.xml");
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (show.title == "The Orbit & Beyond");
    assert (show.author == "Space Club");
    assert (show.link == "https://example.org/orbit");
    assert (show.image_url == "https://example.org/orbit/cover.jpg");
    assert (show.description == "Weekly talk about space.\n\nSecond paragraph.");
    assert (show.episodes.size == 2);
    var e2 = show.episodes[0];
    var e1 = show.episodes[1];
    assert (e2.guid == "orbit-2" && e1.guid == "orbit-1");
    assert (e1.title == "Episode 1: Launch");
    assert (e1.audio_url == "https://example.org/orbit/1.mp3");
    assert (e1.mime == "audio/mpeg" && e1.size == 12345678);
    assert (e1.duration == 3723);
    assert (e1.published == utc (2024, 1, 1, 8, 0, 0));
    assert (e1.show_url == "https://example.org/orbit/feed.xml");
    assert (e1.description == "We talk about rockets & fuel.\n\n• One\n• Two\n\nCafé é A\nLine two");
    assert (!e1.description.contains ("alert"));
    assert (e2.duration == 754);
    assert (e2.published == utc (2024, 1, 9, 8, 30, 0));
    assert (e2.image_url == "https://example.org/orbit/2.jpg");
    assert (e2.description == "Plain escaped text");
}

void test_atom () {
    Show show;
    try {
        show = Feed.parse (fixture ("atom.xml"), "https://example.com/feed.atom");
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (show.title == "Atomic Talk");
    assert (show.author == "Ada");
    assert (show.description == "Short conversations.");
    assert (show.link == "https://example.com/");
    assert (show.image_url == "https://example.com/logo.png");
    assert (show.episodes.size == 2);
    var second = show.episodes[0];
    var first = show.episodes[1];
    assert (first.title == "First & Best");
    assert (first.guid == "urn:uuid:1");
    assert (first.audio_url == "https://example.com/1.ogg" && first.mime == "audio/ogg" && first.size == 2048);
    assert (first.link == "https://example.com/1");
    assert (first.published == utc (2023, 5, 6, 7, 8, 9));
    assert (first.duration == 725);
    assert (first.description == "Hello world");
    assert (second.published == utc (2023, 6, 1, 10, 0, 0));
    assert (second.description == "Just text.");
}

void test_not_a_feed () {
    bool thrown = false;
    try {
        Feed.parse ("<html><head><link rel=\"alternate\" type=\"application/rss+xml\" href=\"/feed.xml\"></head><body>Hi</body></html>", "https://x.org/");
    } catch (FeedError e) {
        thrown = e is FeedError.NOT_A_FEED;
    }
    assert (thrown);
    thrown = false;
    try {
        Feed.parse ("", "https://x.org/");
    } catch (FeedError e) {
        thrown = true;
    }
    assert (thrown);
    assert (Feed.find_alternate ("<html><link rel=\"stylesheet\" href=\"a.css\"><link type=\"application/rss+xml\" rel=\"alternate\" href=\"/feed?a=1&amp;b=2\"></html>") == "/feed?a=1&b=2");
    assert (Feed.find_alternate ("<html></html>") == null);
}

void test_dates () {
    assert (Feed.parse_rfc822 ("Wed, 02 Oct 2002 13:00:00 GMT") == utc (2002, 10, 2, 13, 0, 0));
    assert (Feed.parse_rfc822 ("Wed, 02 Oct 2002 15:00:00 +0200") == utc (2002, 10, 2, 13, 0, 0));
    assert (Feed.parse_rfc822 ("02 Oct 2002 08:00:00 EST") == utc (2002, 10, 2, 13, 0, 0));
    assert (Feed.parse_rfc822 ("Sat, 5 June 2021 09:15 -05:30") == utc (2021, 6, 5, 14, 45, 0));
    assert (Feed.parse_rfc822 ("2021-06-05T09:15:00Z") == utc (2021, 6, 5, 9, 15, 0));
    assert (Feed.parse_rfc822 ("nonsense") == 0);
    assert (Feed.parse_iso8601 ("2020-02-29") == utc (2020, 2, 29, 0, 0, 0));
    assert (Feed.parse_iso8601 ("2020-02-29T10:00:00-01:00") == utc (2020, 2, 29, 11, 0, 0));
    assert (Feed.parse_iso8601 ("") == 0);
}

void test_duration () {
    assert (Feed.parse_duration ("1:02:03") == 3723);
    assert (Feed.parse_duration ("12:05") == 725);
    assert (Feed.parse_duration ("3600") == 3600);
    assert (Feed.parse_duration ("90.7") == 90);
    assert (Feed.parse_duration (" 00:45 ") == 45);
    assert (Feed.parse_duration ("") == 0);
    assert (Feed.parse_duration ("abc") == 0);
    assert (Feed.parse_duration ("1:2:3:4") == 0);
}

void test_html () {
    assert (Sanitize.to_text ("") == "");
    assert (Sanitize.to_text ("Plain\ntext  with   spaces") == "Plain\ntext with spaces");
    assert (Sanitize.to_text ("<p>One</p><p>Two<br>Three</p>") == "One\n\nTwo\nThree");
    assert (Sanitize.to_text ("<style>p{}</style><!-- hidden --><div>A &lt;tag&gt; &quot;q&quot; &#39;s&#39;</div>") == "A <tag> \"q\" 's'");
    assert (Sanitize.to_text ("Tom &amp; Jerry&nbsp;&nbsp;show") == "Tom & Jerry show");
    assert (Sanitize.decode_entities ("&unknown; &#xZZ; & alone") == "&unknown; &#xZZ; & alone");
    assert (Sanitize.decode_entities ("&#128512;") == "\xf0\x9f\x98\x80");
}

void test_opml () {
    Gee.List<Outline> list;
    try {
        list = Opml.parse (fixture ("subscriptions.opml"));
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (list.size == 2);
    assert (list[0].title == "The Orbit & Beyond" && list[0].feed_url == "https://example.org/orbit/feed.xml" && list[0].link == "https://example.org/orbit");
    assert (list[1].title == "Atomic Talk" && list[1].feed_url == "https://example.com/feed.atom");
    list.add (new Outline ("Quotes \"<&>\"\nnewline", "https://e.org/f?a=1&b=2"));
    string text = Opml.serialize (list, "Podcasts", new DateTime.utc (2024, 1, 2, 3, 4, 5));
    assert (text.contains ("<dateCreated>Tue, 02 Jan 2024 03:04:05 GMT</dateCreated>"));
    Gee.List<Outline> again;
    try {
        again = Opml.parse (text);
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (again.size == 3);
    for (int i = 0; i < 3; i++) {
        assert (again[i].title == list[i].title);
        assert (again[i].feed_url == list[i].feed_url);
        assert (again[i].link == list[i].link);
    }
    bool thrown = false;
    try {
        Opml.parse ("<rss/>");
    } catch (FeedError e) {
        thrown = true;
    }
    assert (thrown);
}

void test_itunes () {
    var parser = new Json.Parser ();
    try {
        parser.load_from_data (fixture ("itunes.json"));
    } catch (Error e) {
        assert_not_reached ();
    }
    var list = ITunes.parse (parser.get_root ());
    assert (list.size == 2);
    assert (list[0].title == "Science Hour" && list[0].author == "Radio Lab");
    assert (list[0].feed_url == "https://feeds.example.com/science");
    assert (list[0].artwork == "https://img.example.com/600.jpg");
    assert (list[0].genre == "Science" && list[0].episodes == 250);
    assert (list[1].title == "Only Track Name" && list[1].artwork == "https://img.example.com/o100.jpg");
    string url = ITunes.search_url (" rock & roll ", "IT");
    assert (url.has_prefix ("https://itunes.apple.com/search?"));
    assert (url.contains ("term=rock%20%26%20roll"));
    assert (url.has_suffix ("&country=it"));
    assert (!ITunes.search_url ("x").contains ("country"));
}

void test_format () {
    assert (Format.clock (0) == "0:00");
    assert (Format.clock (65) == "1:05");
    assert (Format.clock (725) == "12:05");
    assert (Format.clock (3723) == "1:02:03");
    assert (Format.clock (-5) == "0:00");
    assert (Format.length (0) == "");
    assert (Format.length (20) == "Under a minute");
    assert (Format.length (45 * 60) == "45 min");
    assert (Format.length (3600) == "1 hr");
    assert (Format.length (3723) == "1 hr 2 min");
    assert (Format.remaining (600) == "10 min left");
    assert (Format.speed (1.0) == "1x");
    assert (Format.speed (1.25) == "1.25x");
    assert (Format.speed (1.5) == "1.5x");
    var now = new DateTime.local (2024, 3, 15, 12, 0, 0);
    assert (Format.date (new DateTime.local (2024, 3, 15, 8, 0, 0).to_unix (), now) == "Today");
    assert (Format.date (new DateTime.local (2024, 3, 14, 23, 0, 0).to_unix (), now) == "Yesterday");
    assert (Format.date (new DateTime.local (2024, 3, 12, 9, 0, 0).to_unix (), now) == "Tuesday");
    assert (Format.date (new DateTime.local (2024, 1, 2, 9, 0, 0).to_unix (), now) == "2 January");
    assert (Format.date (new DateTime.local (2023, 1, 2, 9, 0, 0).to_unix (), now) == "2 January 2023");
    assert (Format.date (0, now) == "");
    assert (Net.looks_like_url ("example.com/feed"));
    assert (Net.looks_like_url ("https://a.b/c"));
    assert (!Net.looks_like_url ("science news"));
    assert (!Net.looks_like_url ("radiolab"));
    assert (Net.normalize_url ("feed://x.org/rss") == "https://x.org/rss");
    assert (Net.normalize_url ("x.org/rss") == "https://x.org/rss");
    assert (Net.normalize_url (" http://x.org ") == "http://x.org");
}

void test_library () {
    string dir;
    try {
        dir = DirUtils.make_tmp ("podcasts-test-XXXXXX");
    } catch (Error e) {
        assert_not_reached ();
    }
    string path = Path.build_filename (dir, "library.json");
    var lib = new Library (path);
    assert (lib.shows.size == 0);
    Show show;
    try {
        show = Feed.parse (fixture ("rss.xml"), "https://example.org/orbit/feed.xml");
    } catch (Error e) {
        assert_not_reached ();
    }
    lib.add_show (show);
    var e1 = lib.find_episode (show.feed_url, "orbit-1");
    assert (e1 != null);
    e1.position = 120;
    string dl = Path.build_filename (dir, "1.mp3");
    try {
        FileUtils.set_contents (dl, "x");
    } catch (Error e) {
        assert_not_reached ();
    }
    e1.download_path = dl;
    lib.find_episode (show.feed_url, "orbit-2").played = true;
    lib.last_refresh = 42;
    assert (lib.save ());

    var back = new Library (path);
    assert (back.shows.size == 1 && back.last_refresh == 42);
    var s = back.shows[0];
    assert (s.title == "The Orbit & Beyond" && s.image_url == show.image_url && s.description == show.description);
    assert (s.episodes.size == 2);
    var b1 = back.find_episode (s.feed_url, "orbit-1");
    assert (b1.position == 120 && !b1.played && b1.is_downloaded () && b1.in_progress ());
    assert (b1.description == e1.description && b1.duration == 3723 && b1.published == e1.published);
    assert (back.find_episode (s.feed_url, "orbit-2").played);
    assert (back.in_progress ().size == 1 && back.downloaded ().size == 1);
    assert (back.latest ()[0].guid == "orbit-2");

    Show fresh;
    try {
        fresh = Feed.parse (fixture ("rss.xml").replace ("orbit-2", "orbit-3"), s.feed_url);
    } catch (Error e) {
        assert_not_reached ();
    }
    int added = back.merge (s, fresh);
    assert (added == 1);
    assert (s.episodes.size == 2);
    assert (back.find_episode (s.feed_url, "orbit-2") == null);
    assert (back.find_episode (s.feed_url, "orbit-1").position == 120);
    assert (!back.find_episode (s.feed_url, "orbit-3").played);

    back.remove_show (s);
    assert (!FileUtils.test (dl, FileTest.EXISTS));
    assert (new Library (path).shows.size == 0);
    FileUtils.remove (path);
    DirUtils.remove (dir);
}

uint8[] fixture_bytes (string name) {
    uint8[] data;
    try {
        FileUtils.get_data (Path.build_filename (Environment.get_variable ("PODCASTS_FIXTURES"), name), out data);
    } catch (Error e) {
        assert_not_reached ();
    }
    return data;
}

void test_npt () {
    assert (Chapters.parse_npt ("00:00:00.000") == 0);
    assert (Chapters.parse_npt ("00:01:30.500") == 90.5);
    assert (Chapters.parse_npt ("1:02:03") == 3723);
    assert (Chapters.parse_npt ("12:00") == 720);
    assert (Chapters.parse_npt ("45.25") == 45.25);
    assert (Chapters.parse_npt ("") < 0);
    assert (Chapters.parse_npt ("bogus") < 0);
    assert (Chapters.parse_npt ("1:75:00") < 0);
    assert (Chapters.parse_npt ("1:2:3:4") < 0);
    assert (Chapters.parse_npt ("-5") < 0);
    assert (Chapters.parse_npt ("1.2.3") < 0);
}

void test_chapters_json () {
    Gee.List<Chapter> list;
    try {
        list = Chapters.parse_json (fixture ("chapters.json"));
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (list.size == 4);
    assert (list[0].title == "Welcome" && list[0].start == 0 && list[0].end == 95.5);
    assert (list[1].title == "News & Notes" && list[1].url == "https://example.org/news" && list[1].image == "https://example.org/news.jpg");
    assert (list[1].end == 300);
    assert (list[2].title == "Interview" && list[2].start == 300 && list[2].end == 400);
    assert (list[3].title == "Wrap Up" && list[3].start == 720 && list[3].end == -1);
    assert (Chapters.index_at (list, 0) == 0);
    assert (Chapters.index_at (list, 95.4) == 0);
    assert (Chapters.index_at (list, 95.5) == 1);
    assert (Chapters.index_at (list, 500) == 2);
    assert (Chapters.index_at (list, 10000) == 3);
    assert (Chapters.index_at (new Gee.ArrayList<Chapter> (), 5) == -1);
    bool thrown = false;
    try {
        Chapters.parse_json ("{\"chapters\": 5}");
    } catch (Error e) {
        thrown = true;
    }
    assert (thrown);
    thrown = false;
    try {
        Chapters.parse_json ("not json");
    } catch (Error e) {
        thrown = true;
    }
    assert (thrown);
    try {
        var untitled = Chapters.parse_json ("{\"chapters\": [{\"startTime\": 10}, {\"startTime\": 20, \"title\": \"B\"}]}");
        assert (untitled.size == 2 && untitled[0].title == "Chapter 1");
    } catch (Error e) {
        assert_not_reached ();
    }
}

void test_chapters_feed () {
    Show show;
    try {
        show = Feed.parse (fixture ("chapters-feed.xml"), "https://example.org/chapters.xml");
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (show.episodes.size == 3);
    var unsafe_link = show.episodes[0];
    var podlove = show.episodes[1];
    var index = show.episodes[2];
    assert (index.chapters_url == "https://example.org/c1.json" && index.chapters.size == 0);
    assert (unsafe_link.chapters_url == "");
    assert (podlove.chapters.size == 3);
    assert (podlove.chapters[0].title == "Intro" && podlove.chapters[0].end == 90.5);
    assert (podlove.chapters[1].title == "Topic & Guests" && podlove.chapters[1].start == 90.5 && podlove.chapters[1].url == "https://example.org/topic");
    assert (podlove.chapters[2].title == "Late" && podlove.chapters[2].start == 3723);

    var copy = Episode.from_json (podlove.to_json ());
    assert (copy.chapters.size == 3 && copy.chapters[1].title == "Topic & Guests" && copy.chapters[1].start == 90.5);
    var icopy = Episode.from_json (index.to_json ());
    assert (icopy.chapters_url == "https://example.org/c1.json" && !icopy.chapters_fetched);

    var lib = new Library (Path.build_filename (Environment.get_tmp_dir (), "chapters-lib-unused.json"));
    var target = new Show ();
    target.feed_url = show.feed_url;
    var old = new Episode ();
    old.guid = "c-1";
    old.audio_url = "https://example.org/c1.mp3";
    old.chapters_url = "https://example.org/old.json";
    old.chapters_fetched = true;
    old.chapters.add (new Chapter ());
    target.episodes.add (old);
    lib.merge (target, show);
    var merged = target.episodes[2];
    assert (merged == old);
    assert (merged.chapters_url == "https://example.org/c1.json" && !merged.chapters_fetched && merged.chapters.size == 0);
}

void test_chapters_id3 () {
    var v4 = Chapters.parse_id3 (fixture_bytes ("chapters-v24.id3"));
    assert (v4.size == 3);
    assert (v4[0].title == "Opening" && v4[0].start == 0 && v4[0].end == 60);
    assert (v4[1].title == "Über Guests" && v4[1].start == 60 && v4[1].end == 125);
    assert (v4[2].title == "Caffè Talk" && v4[2].start == 125 && v4[2].end == -1);
    var v3 = Chapters.parse_id3 (fixture_bytes ("chapters-v23.id3"));
    assert (v3.size == 2);
    assert (v3[0].title == "First" && v3[1].title == "Second" && v3[1].start == 30 && v3[1].end == 90);
    assert (Chapters.parse_id3 ("ID3".data).size == 0);
    assert (Chapters.parse_id3 ({ 'I', 'D', '3', 2, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }).size == 0);
    uint8[] truncated = fixture_bytes ("chapters-v24.id3")[0:60];
    assert (Chapters.parse_id3 (truncated).size <= 1);
    string path = Path.build_filename (Environment.get_variable ("PODCASTS_FIXTURES"), "chapters-v24.id3");
    try {
        var from_file = Chapters.read_id3_file (path);
        assert (from_file.size == 3 && from_file[2].title == "Caffè Talk");
        assert (Chapters.read_id3_file (Path.build_filename (Environment.get_variable ("PODCASTS_FIXTURES"), "rss.xml")).size == 0);
    } catch (Error e) {
        assert_not_reached ();
    }
}

Episode ep (string show, string guid) {
    var e = new Episode ();
    e.show_url = show;
    e.guid = guid;
    e.audio_url = "https://example.org/" + guid + ".mp3";
    return e;
}

void test_queue () {
    string dir;
    try {
        dir = DirUtils.make_tmp ("podcasts-queue-XXXXXX");
    } catch (Error e) {
        assert_not_reached ();
    }
    string path = Path.build_filename (dir, "queue.json");
    var q = new PlayQueue (path);
    int changes = 0;
    q.changed.connect (() => changes++);
    var a = ep ("s1", "a");
    var b = ep ("s1", "b");
    var c = ep ("s2", "c");
    var d = ep ("s2", "d");
    assert (q.add (a) && q.add (b) && q.add (c));
    assert (!q.add (a));
    assert (q.items.size == 3 && changes == 3);
    q.add_next (d);
    assert (q.items[0].key == "d" && q.items.size == 4);
    q.add_next (c);
    assert (q.items[0].key == "c" && q.items[1].key == "d" && q.items.size == 4);
    assert (q.move (0, 3));
    assert (q.items[3].key == "c" && q.items[0].key == "d");
    assert (!q.move (2, 2) && !q.move (9, 0));
    assert (q.move (3, -5) && q.items[0].key == "c");
    assert (q.remove (b) && !q.remove (b));
    assert (q.index_of (a) == 2);
    var again = new PlayQueue (path);
    assert (again.items.size == 3 && again.items[0].key == "c" && again.items[1].key == "d" && again.items[2].key == "a");
    var first = again.pop ();
    assert (first.show_url == "s2" && first.key == "c" && again.items.size == 2);
    assert (new PlayQueue (path).items.size == 2);

    var lib = new Library (Path.build_filename (dir, "library.json"));
    var show = new Show ();
    show.feed_url = "s2";
    show.title = "Two";
    show.episodes.add (d);
    lib.shows.add (show);
    assert (again.resolve (lib).size == 1);
    assert (again.prune (lib) && again.items.size == 1 && again.items[0].key == "d");
    assert (!again.prune (lib));
    again.clear ();
    assert (new PlayQueue (path).items.size == 0 && again.pop () == null);

    try {
        FileUtils.set_contents (path, "{\"queue\": [{\"show\": \"x\", \"episode\": \"1\"}, {\"show\": \"x\", \"episode\": \"1\"}, {\"show\": \"\", \"episode\": \"2\"}, 7, {\"show\": \"y\", \"episode\": \"3\"}]}");
    } catch (Error e) {
        assert_not_reached ();
    }
    var parsed = new PlayQueue (path);
    assert (parsed.items.size == 2 && parsed.items[1].show_url == "y");
    try {
        FileUtils.set_contents (path, "[broken");
    } catch (Error e) {
        assert_not_reached ();
    }
    var broken = new PlayQueue (path);
    assert (broken.items.size == 0 && broken.error != "");
    FileUtils.remove (path);
    FileUtils.remove (Path.build_filename (dir, "library.json"));
    DirUtils.remove (dir);
}

void test_show_settings () {
    var s = new Show ();
    s.feed_url = "https://example.org/f.xml";
    s.speed = 1.5;
    s.trim_silence = 1;
    s.voice_boost = 0;
    var copy = Show.from_json (s.to_json ());
    assert (copy.speed == 1.5 && copy.trim_silence == 1 && copy.voice_boost == 0);
    var plain = Show.from_json (new Show ().to_json ());
    assert (plain.speed == 0 && plain.trim_silence == -1 && plain.voice_boost == -1);
    var o = s.to_json ();
    o.set_double_member ("speed", 9.0);
    o.set_int_member ("trim_silence", 7);
    var clamped = Show.from_json (o);
    assert (clamped.speed == 0 && clamped.trim_silence == 1);
}

void test_sleep_timer () {
    var t = new SleepTimer (false);
    int expired = 0;
    t.expired.connect (() => expired++);
    int64 start = 500 * TimeSpan.SECOND;
    t.start_minutes (30, start);
    assert (t.remaining (start) == 1800);
    assert (!t.update (start + 29 * TimeSpan.MINUTE));
    assert (Math.fabs (t.level - 1.0) < 0.0001);
    assert (!t.update (start + 30 * TimeSpan.MINUTE - 10 * TimeSpan.SECOND));
    assert (Math.fabs (t.level - 1.0 / 3.0) < 0.001);
    assert (t.update (start + 30 * TimeSpan.MINUTE));
    assert (expired == 1 && !t.active && t.level == 1.0);

    double left = 100;
    t.start_track (SleepMode.END_OF_CHAPTER, () => left);
    assert (t.mode == SleepMode.END_OF_CHAPTER && t.remaining () == 100);
    assert (!t.update (0));
    left = 15;
    assert (!t.update (0) && Math.fabs (t.level - 0.5) < 0.001);
    left = -1;
    assert (!t.update (0) && t.level == 1.0 && t.remaining () == -1);
    left = 0.1;
    assert (t.update (0) && expired == 2 && !t.active);

    left = 5;
    t.start_track (SleepMode.END_OF_EPISODE, () => left);
    left = 0;
    assert (!t.update (0) && t.active && t.level == 0.0);
    t.finish ();
    assert (expired == 3 && !t.active && t.level == 1.0);
    t.start_track (SleepMode.MINUTES, () => left);
    assert (!t.active);
    t.start_minutes (10);
    t.cancel ();
    t.finish ();
    assert (expired == 3);
    assert (SleepTimer.format (59) == "0:59" && SleepTimer.format (3600) == "1:00:00");
}

string[] factories (Gst.Element bin) {
    string[] names = {};
    var it = ((Gst.Bin) bin).iterate_sorted ();
    Value v = Value (typeof (Gst.Element));
    var order = new Gee.ArrayList<string> ();
    while (it.next (out v) == Gst.IteratorResult.OK) {
        var e = (Gst.Element) v.get_object ();
        order.insert (0, e.get_factory ().get_name ());
        v.unset ();
    }
    foreach (string n in order) names += n;
    return names;
}

void test_effects_plan () {
    string[] plain = Effects.plan (false, false, true);
    assert (plain.length == 2 && plain[1] == "scaletempo");
    string[] trim = Effects.plan (true, false, true);
    assert (trim[0] == "audioconvert" && trim[1] == "capsfilter" && trim[2] == "removesilence" && trim[trim.length - 1] == "scaletempo");
    string[] fallback = Effects.plan (true, false, false);
    assert (fallback[0] == "level");
    string[] both = Effects.plan (true, true, true);
    assert (both.length == 9);
    assert (both[4] == "equalizer-nbands" && both[5] == "audiodynamic" && both[6] == "volume");

    bool level;
    Gst.Element bin;
    try {
        bin = Effects.build (true, true, out level);
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (!level);
    string[] built = factories (bin);
    assert (built.length == both.length);
    for (int i = 0; i < built.length; i++) assert (built[i] == both[i]);
    var trim_el = Effects.find (bin, "trim");
    bool remove, squash;
    int threshold;
    trim_el.get ("remove", out remove, "squash", out squash, "threshold", out threshold);
    assert (remove && squash && threshold == Effects.TRIM_THRESHOLD_DB);
    var eq = Effects.find (bin, "voice-eq");
    uint bands;
    eq.get ("num-bands", out bands);
    assert (bands == Effects.VOICE_FREQS.length);
    var band = ((Gst.ChildProxy) eq).get_child_by_index (2);
    double freq, gain;
    band.get ("freq", out freq, "gain", out gain);
    assert (freq == Effects.VOICE_FREQS[2] && gain == Effects.VOICE_GAINS[2]);
    var comp = Effects.find (bin, "voice-compressor");
    Value mode = Value (typeof (int));
    comp.get_property ("mode", ref mode);
    assert (bin.get_static_pad ("sink") != null && bin.get_static_pad ("src") != null);
    try {
        var none = Effects.build (false, false, out level);
        assert (factories (none).length == 2);
    } catch (Error e) {
        assert_not_reached ();
    }
}

int64 run_through (bool trim) {
    var pipeline = new Gst.Pipeline (null);
    var concat = Gst.ElementFactory.make ("concat", null);
    pipeline.add (concat);
    int[] waves = { 0, 4, 0 };
    int[] buffers = { 40, 60, 40 };
    for (int i = 0; i < waves.length; i++) {
        var src = Gst.ElementFactory.make ("audiotestsrc", null);
        src.set ("wave", waves[i], "num-buffers", buffers[i], "samplesperbuffer", 2205, "volume", 0.5);
        var caps = Gst.ElementFactory.make ("capsfilter", null);
        caps.set ("caps", Gst.Caps.from_string ("audio/x-raw,format=S16LE,rate=44100,channels=1"));
        pipeline.add_many (src, caps);
        src.link (caps);
        caps.link (concat);
    }
    bool level;
    Gst.Element effects;
    try {
        effects = Effects.build (trim, false, out level);
    } catch (Error e) {
        assert_not_reached ();
    }
    var sink = Gst.ElementFactory.make ("fakesink", null);
    sink.set ("sync", false);
    pipeline.add_many (effects, sink);
    concat.link (effects);
    effects.link (sink);
    int64 total = 0;
    effects.get_static_pad ("src").add_probe (Gst.PadProbeType.BUFFER, (pad, info) => {
        var buf = info.get_buffer ();
        if (buf.duration != Gst.CLOCK_TIME_NONE) total += (int64) buf.duration;
        return Gst.PadProbeReturn.OK;
    });
    pipeline.set_state (Gst.State.PLAYING);
    var msg = pipeline.get_bus ().timed_pop_filtered (20 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
    assert (msg != null && msg.type == Gst.MessageType.EOS);
    pipeline.set_state (Gst.State.NULL);
    return total;
}

void test_effects_trim () {
    int64 plain = run_through (false);
    int64 trimmed = run_through (true);
    Test.message ("untrimmed %lld ms, trimmed %lld ms", plain / Gst.MSECOND, trimmed / Gst.MSECOND);
    assert (plain > 6900 * Gst.MSECOND && plain < 7100 * Gst.MSECOND);
    assert (trimmed < 4600 * Gst.MSECOND);
    assert (trimmed > 3500 * Gst.MSECOND);
}

void test_silence_skipper () {
    var s = new SilenceSkipper ();
    assert (s.feed (-10, 0) == -1);
    assert (s.feed (-60, 1 * Gst.SECOND) == -1);
    assert (s.feed (-60, 1 * Gst.SECOND + 300 * Gst.MSECOND) == -1);
    assert (s.feed (-60, 1 * Gst.SECOND + 700 * Gst.MSECOND) == 2200 * Gst.MSECOND);
    assert (s.feed (-60, 2200 * Gst.MSECOND) == -1);
    assert (s.feed (-20, 2300 * Gst.MSECOND) == -1);
    assert (s.feed (-60, 2400 * Gst.MSECOND) == -1);
    assert (s.feed (-60, 2 * Gst.SECOND) == -1);
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    Gst.init (ref args);
    Environment.set_variable ("TZ", "UTC", true);
    Test.init (ref args);
    Test.add_func ("/podcasts/rss", test_rss);
    Test.add_func ("/podcasts/atom", test_atom);
    Test.add_func ("/podcasts/not-a-feed", test_not_a_feed);
    Test.add_func ("/podcasts/dates", test_dates);
    Test.add_func ("/podcasts/duration", test_duration);
    Test.add_func ("/podcasts/html", test_html);
    Test.add_func ("/podcasts/opml", test_opml);
    Test.add_func ("/podcasts/itunes", test_itunes);
    Test.add_func ("/podcasts/format", test_format);
    Test.add_func ("/podcasts/library", test_library);
    Test.add_func ("/podcasts/npt", test_npt);
    Test.add_func ("/podcasts/chapters-json", test_chapters_json);
    Test.add_func ("/podcasts/chapters-feed", test_chapters_feed);
    Test.add_func ("/podcasts/chapters-id3", test_chapters_id3);
    Test.add_func ("/podcasts/queue", test_queue);
    Test.add_func ("/podcasts/show-settings", test_show_settings);
    Test.add_func ("/podcasts/sleep-timer", test_sleep_timer);
    Test.add_func ("/podcasts/effects-plan", test_effects_plan);
    Test.add_func ("/podcasts/effects-trim", test_effects_trim);
    Test.add_func ("/podcasts/silence-skipper", test_silence_skipper);
    return Test.run ();
}
