namespace Singularity.Apps.Podcasts {

    internal class PodcastsIntents : Object {
        private static bool held = false;

        private static string text(Json.Object args, string key) {
            return args.has_member(key) ? args.get_string_member(key).strip() : "";
        }

        private static string state_id(PlayState s) {
            switch (s) {
                case PlayState.LOADING: return "loading";
                case PlayState.PLAYING: return "playing";
                case PlayState.PAUSED: return "paused";
                default: return "stopped";
            }
        }

        private static string episode_id(Episode e) {
            return e.show_url + "#" + e.key();
        }

        private static Show find_show(PodcastsApp app, string wanted) throws Error {
            if (wanted == "") throw new IOError.INVALID_ARGUMENT("give the show title or feed address");
            var s = app.library.find_show(wanted);
            if (s != null) return s;
            string w = wanted.casefold();
            foreach (var x in app.library.shows) if (x.title.casefold() == w) return x;
            foreach (var x in app.library.shows) if (x.title.casefold().contains(w)) return x;
            throw new IOError.NOT_FOUND("no subscribed show %s; see podcasts_shows", wanted);
        }

        private static Episode find_episode(PodcastsApp app, string id) throws Error {
            int hash = id.last_index_of_char('#');
            if (hash > 0) {
                var e = app.library.find_episode(id.substring(0, hash), id.substring(hash + 1));
                if (e != null) return e;
            }
            string w = id.casefold();
            foreach (var s in app.library.shows) foreach (var e in s.episodes) if (e.title.casefold() == w) return e;
            throw new IOError.NOT_FOUND("no episode %s; take the id from podcasts_episodes", id);
        }

        private static void show(Json.Builder b, Show s) {
            b.begin_object();
            b.set_member_name("title").add_string_value(s.title);
            if (s.author != "") b.set_member_name("author").add_string_value(s.author);
            b.set_member_name("feed").add_string_value(s.feed_url);
            b.set_member_name("episodes").add_int_value(s.episodes.size);
            b.set_member_name("unplayed").add_int_value(s.unplayed());
            if (s.error != "") b.set_member_name("last_error").add_string_value(s.error);
            b.end_object();
        }

        private static void episode(Json.Builder b, PodcastsApp app, Episode e) {
            b.begin_object();
            b.set_member_name("id").add_string_value(episode_id(e));
            b.set_member_name("title").add_string_value(e.title);
            var s = app.library.find_show(e.show_url);
            if (s != null) b.set_member_name("show").add_string_value(s.title);
            if (e.published > 0) b.set_member_name("published").add_string_value(new DateTime.from_unix_local(e.published).format("%F"));
            if (e.duration > 0) b.set_member_name("minutes").add_int_value(e.duration / 60);
            b.set_member_name("played").add_boolean_value(e.played);
            if (e.in_progress()) b.set_member_name("minutes_left").add_int_value(e.remaining() / 60);
            if (e.is_downloaded()) b.set_member_name("downloaded").add_boolean_value(true);
            if (app.queue.contains(e)) b.set_member_name("queued").add_boolean_value(true);
            b.end_object();
        }

        private static void now(Json.Builder b, PodcastsApp app) {
            var p = app.player;
            b.set_member_name("state").add_string_value(state_id(p.state));
            if (p.episode != null) {
                b.set_member_name("episode").add_string_value(p.episode.title);
                b.set_member_name("position_seconds").add_int_value(p.position());
                if (p.duration() > 0) b.set_member_name("duration_seconds").add_int_value(p.duration());
            }
            b.set_member_name("speed").add_double_value(p.rate);
            b.set_member_name("queue").add_int_value(app.queue.items.size);
        }

        private static async void wait(uint ms) {
            Timeout.add(ms, wait.callback);
            yield;
        }

        internal static void start(PodcastsApp app, Episode e) {
            string uri = e.audio_url;
            if (e.is_downloaded()) {
                try {
                    uri = Filename.to_uri(e.download_path);
                } catch (Error err) {
                }
            }
            if (e.played) {
                e.played = false;
                e.position = 0;
            }
            var s = app.library.find_show(e.show_url);
            app.player.preset_rate(s != null && s.speed > 0 ? s.speed : app.default_rate);
            app.queue.remove(e);
            if (!held) {
                held = true;
                app.hold();
            }
            app.player.open(e, uri);
            if (e.position > 0) app.player.seek_to(e.position);
        }

        private static async void search(PodcastsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                string term = text(args, "query");
                if (term == "") throw new IOError.INVALID_ARGUMENT("give what to look for");
                var found = yield Net.search(term, null);
                var b = new Json.Builder();
                b.begin_array();
                int n = 0;
                foreach (var r in found) {
                    if (n++ == 15) break;
                    b.begin_object();
                    b.set_member_name("title").add_string_value(r.title);
                    if (r.author != "") b.set_member_name("author").add_string_value(r.author);
                    if (r.genre != "") b.set_member_name("genre").add_string_value(r.genre);
                    if (r.episodes > 0) b.set_member_name("episodes").add_int_value(r.episodes);
                    b.set_member_name("feed").add_string_value(r.feed_url);
                    b.set_member_name("subscribed").add_boolean_value(app.library.find_show(r.feed_url) != null);
                    b.end_object();
                }
                b.end_array();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, Net.friendly(e));
            } finally {
                app.release();
            }
        }

        private static async void subscribe(PodcastsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                string url = Net.normalize_url(text(args, "feed"));
                if (!Net.looks_like_url(url)) throw new IOError.INVALID_ARGUMENT("give the feed address from podcasts_search");
                var existing = app.library.find_show(url);
                if (existing == null) {
                    var fetched = yield Net.fetch_show(url, null);
                    existing = app.library.find_show(fetched.feed_url);
                    if (existing == null) {
                        app.library.add_show(fetched);
                        app.library.save();
                        existing = fetched;
                    }
                }
                if (new Library(app.library.path).find_show(existing.feed_url) == null) throw new IOError.FAILED("the subscription was not saved");
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("subscribed");
                show(b, existing);
                b.set_member_name("undo").add_string_value("podcasts_unsubscribe with show " + existing.feed_url);
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, Net.friendly(e));
            } finally {
                app.release();
            }
        }

        private static async void refresh(PodcastsApp app, owned Singularity.AppIntentReply reply) {
            app.hold();
            int added = 0;
            var failed = new Gee.ArrayList<string>();
            foreach (var s in app.library.shows) {
                try {
                    var fresh = yield Net.fetch_show(s.feed_url, null);
                    added += app.library.merge(s, fresh);
                    s.error = "";
                } catch (Error e) {
                    s.error = Net.friendly(e).message;
                    failed.add(s.title);
                }
            }
            app.library.save();
            app.library.changed();
            var b = new Json.Builder();
            b.begin_object();
            b.set_member_name("new_episodes").add_int_value(added);
            b.set_member_name("failed").begin_array();
            foreach (string t in failed) b.add_string_value(t);
            b.end_array();
            b.end_object();
            app.release();
            reply(b.get_root(), null);
        }

        private static async void play(PodcastsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                Episode e;
                if (text(args, "episode") != "") {
                    e = find_episode(app, text(args, "episode"));
                } else if (text(args, "show") != "") {
                    var s = find_show(app, text(args, "show"));
                    if (s.episodes.size == 0) throw new IOError.NOT_FOUND("%s has no episodes", s.title);
                    s.sort();
                    e = s.episodes[0];
                } else {
                    var list = app.queue.resolve(app.library);
                    if (list.size == 0) list = app.library.in_progress();
                    if (list.size == 0) throw new IOError.NOT_FOUND("nothing queued or in progress; name an episode or a show");
                    e = list[0];
                }
                if (!e.is_downloaded() && !NetworkMonitor.get_default().network_available) throw new IOError.NETWORK_UNREACHABLE("offline, and the episode is not downloaded");
                start(app, e);
                for (int i = 0; i < 60 && app.player.state == PlayState.LOADING; i++) yield wait(250);
                var b = new Json.Builder();
                b.begin_object();
                now(b, app);
                if (app.player.state != PlayState.PLAYING) b.set_member_name("verified").add_boolean_value(false);
                b.set_member_name("undo").add_string_value("podcasts_control with action pause");
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        private static async void download(PodcastsApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                var e = find_episode(app, text(args, "episode"));
                if (!e.is_downloaded()) {
                    app.downloads.start(e);
                    for (int i = 0; i < 1200 && !e.is_downloaded(); i++) yield wait(500);
                }
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("episode").add_string_value(e.title);
                b.set_member_name("downloaded").add_boolean_value(e.is_downloaded());
                if (!e.is_downloaded()) b.set_member_name("note").add_string_value("still downloading");
                else b.set_member_name("undo").add_string_value("podcasts_delete_download with the same episode");
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        internal static void install(PodcastsApp app) {
            var agent = app.agent;
            agent.add_async_intent("podcasts_search", "Find podcasts to subscribe to, by name or topic.",
                "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"}},\"required\":[\"query\"]}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    search.begin(app, args, (owned) reply);
                });
            agent.add_intent("podcasts_shows", "The podcasts the person subscribes to, with how many episodes are unplayed.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    var b = new Json.Builder();
                    b.begin_array();
                    foreach (var s in app.library.shows) show(b, s);
                    b.end_array();
                    return b.get_root();
                });
            agent.add_intent("podcasts_episodes", "Episodes of one show, or the latest across all shows, or the ones in progress, the queue or downloaded.",
                "{\"type\":\"object\",\"properties\":{\"show\":{\"type\":\"string\"},\"list\":{\"type\":\"string\",\"enum\":[\"latest\",\"in_progress\",\"queue\",\"downloaded\"]},\"unplayed\":{\"type\":\"boolean\"},\"limit\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.READ, (args) => {
                    int limit = args.has_member("limit") ? (int) args.get_int_member("limit").clamp(1, 100) : 15;
                    bool unplayed = args.has_member("unplayed") && args.get_boolean_member("unplayed");
                    Gee.List<Episode> list;
                    if (text(args, "show") != "") {
                        var s = find_show(app, text(args, "show"));
                        s.sort();
                        list = s.episodes;
                    } else {
                        switch (text(args, "list")) {
                            case "in_progress": list = app.library.in_progress(); break;
                            case "queue": list = app.queue.resolve(app.library); break;
                            case "downloaded": list = app.library.downloaded(); break;
                            default: list = app.library.latest(200); break;
                        }
                    }
                    var b = new Json.Builder();
                    b.begin_array();
                    int n = 0;
                    foreach (var e in list) {
                        if (unplayed && e.played) continue;
                        if (n++ == limit) break;
                        episode(b, app, e);
                    }
                    b.end_array();
                    return b.get_root();
                });
            agent.add_async_intent("podcasts_subscribe", "Subscribe to a podcast by its feed address.",
                "{\"type\":\"object\",\"properties\":{\"feed\":{\"type\":\"string\"}},\"required\":[\"feed\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    subscribe.begin(app, args, (owned) reply);
                });
            agent.add_intent("podcasts_unsubscribe", "Unsubscribe from a podcast; its listening progress and downloads are forgotten.",
                "{\"type\":\"object\",\"properties\":{\"show\":{\"type\":\"string\"}},\"required\":[\"show\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    var s = find_show(app, text(args, "show"));
                    if (app.player.episode != null && app.player.episode.show_url == s.feed_url) app.player.stop();
                    foreach (var e in s.episodes) {
                        app.queue.remove(e);
                        if (e.is_downloaded()) app.library.delete_download(e);
                    }
                    app.library.remove_show(s);
                    app.library.save();
                    if (new Library(app.library.path).find_show(s.feed_url) != null) throw new IOError.FAILED("%s is still subscribed", s.title);
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("unsubscribed").add_string_value(s.title);
                    b.end_object();
                    return b.get_root();
                });
            agent.add_async_intent("podcasts_refresh", "Look for new episodes of every subscribed show.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args, reply) => {
                    refresh.begin(app, (owned) reply);
                });
            agent.add_async_intent("podcasts_play", "Play an episode by id, the newest episode of a show, or (with neither) the next in the queue or the one in progress, resuming where it stopped.",
                "{\"type\":\"object\",\"properties\":{\"episode\":{\"type\":\"string\"},\"show\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    play.begin(app, args, (owned) reply);
                });
            agent.add_intent("podcasts_now_playing", "What is playing, where in the episode, the speed and the queue length.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    var b = new Json.Builder();
                    b.begin_object();
                    now(b, app);
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("podcasts_control", "Pause, resume or stop, skip seconds forward or back (negative), jump to a second, or set the speed.",
                "{\"type\":\"object\",\"properties\":{\"action\":{\"type\":\"string\",\"enum\":[\"pause\",\"resume\",\"stop\"]},\"skip_seconds\":{\"type\":\"integer\"},\"seek_seconds\":{\"type\":\"integer\"},\"speed\":{\"type\":\"number\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var p = app.player;
                    double before_rate = p.rate;
                    int before_pos = p.position();
                    bool any = false;
                    switch (text(args, "action")) {
                        case "": break;
                        case "pause": p.pause(); any = true; break;
                        case "resume": p.play(); any = true; break;
                        case "stop": p.stop(); any = true; break;
                        default: throw new IOError.INVALID_ARGUMENT("unknown action %s", text(args, "action"));
                    }
                    if (args.has_member("skip_seconds")) { p.skip((int) args.get_int_member("skip_seconds")); any = true; }
                    if (args.has_member("seek_seconds")) { p.seek_to((int) args.get_int_member("seek_seconds")); any = true; }
                    if (args.has_member("speed")) { p.change_rate(args.get_double_member("speed").clamp(0.5, 3.0)); any = true; }
                    if (!any) throw new IOError.INVALID_ARGUMENT("give an action, skip_seconds, seek_seconds or speed");
                    if (p.episode == null && text(args, "action") != "stop") throw new IOError.NOT_FOUND("nothing is playing");
                    var b = new Json.Builder();
                    b.begin_object();
                    now(b, app);
                    if (args.has_member("speed")) b.set_member_name("undo").add_string_value("podcasts_control with speed %g".printf(before_rate));
                    else if (args.has_member("skip_seconds") || args.has_member("seek_seconds")) b.set_member_name("undo").add_string_value("podcasts_control with seek_seconds %d".printf(before_pos));
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("podcasts_queue", "Add an episode to the end of the queue, or next with next true, or take it out with remove true.",
                "{\"type\":\"object\",\"properties\":{\"episode\":{\"type\":\"string\"},\"next\":{\"type\":\"boolean\"},\"remove\":{\"type\":\"boolean\"}},\"required\":[\"episode\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var e = find_episode(app, text(args, "episode"));
                    bool remove = args.has_member("remove") && args.get_boolean_member("remove");
                    if (remove) app.queue.remove(e);
                    else if (args.has_member("next") && args.get_boolean_member("next")) app.queue.add_next(e);
                    else app.queue.add(e);
                    if (app.queue.contains(e) == remove) throw new IOError.FAILED("the queue did not change");
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("episode").add_string_value(e.title);
                    b.set_member_name("position").add_int_value(remove ? -1 : app.queue.index_of(e) + 1);
                    b.set_member_name("queue").add_int_value(app.queue.items.size);
                    b.set_member_name("undo").add_string_value(remove ? "podcasts_queue with the same episode" : "podcasts_queue with remove true");
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("podcasts_mark_played", "Mark an episode as played, or unplayed with played false.",
                "{\"type\":\"object\",\"properties\":{\"episode\":{\"type\":\"string\"},\"played\":{\"type\":\"boolean\"}},\"required\":[\"episode\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var e = find_episode(app, text(args, "episode"));
                    bool played = !args.has_member("played") || args.get_boolean_member("played");
                    bool before = e.played;
                    app.library.set_played(e, played);
                    app.library.save();
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("episode").add_string_value(e.title);
                    b.set_member_name("played").add_boolean_value(e.played);
                    b.set_member_name("undo").add_string_value("podcasts_mark_played with played %s".printf(before ? "true" : "false"));
                    b.end_object();
                    return b.get_root();
                });
            agent.add_async_intent("podcasts_download", "Download an episode to listen without a connection.",
                "{\"type\":\"object\",\"properties\":{\"episode\":{\"type\":\"string\"}},\"required\":[\"episode\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    download.begin(app, args, (owned) reply);
                });
            agent.add_intent("podcasts_delete_download", "Delete the downloaded file of an episode; it can still be streamed.",
                "{\"type\":\"object\",\"properties\":{\"episode\":{\"type\":\"string\"}},\"required\":[\"episode\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var e = find_episode(app, text(args, "episode"));
                    if (!e.is_downloaded()) throw new IOError.NOT_FOUND("%s is not downloaded", e.title);
                    app.library.delete_download(e);
                    if (e.is_downloaded()) throw new IOError.FAILED("the file is still there");
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("deleted_download").add_string_value(e.title);
                    b.set_member_name("undo").add_string_value("podcasts_download with the same episode");
                    b.end_object();
                    return b.get_root();
                });
        }
    }
}
