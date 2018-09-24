class TwitterBot {

    _twitter = null;

    constructor() {
        // Twitter test keys are shared with snackbot_1 (20000c2a690af734)
        const TEST_API_KEY      = "@{TWITTER_TESTER_API_KEY}";
        const TEST_API_SECRET   = "@{TWITTER_TESTER_API_SECRET}";
        const TEST_AUTH_TOKEN   = "@{TWITTER_TESTER_AUTH_TOKEN}";
        const TEST_TOKEN_SECRET = "@{TWITTER_TESTER_TOKEN_SECRET}";

        const CHARLIE_API_KEY      = "@{TWITTER_CHARLIE_API_KEY}";
        const CHARLIE_API_SECRET   = "@{TWITTER_CHARLIE_API_SECRET}";
        const CHARLIE_AUTH_TOKEN   = "@{TWITTER_CHARLIE_AUTH_TOKEN}";
        const CHARLIE_TOKEN_SECRET = "@{TWITTER_CHARLIE_TOKEN_SECRET}";

        _twitter = Twitter(TEST_API_KEY, TEST_API_SECRET, TEST_AUTH_TOKEN, TEST_TOKEN_SECRET);
    }

    function geofenceTweet(alert) {
        // TODO: get acutal twitter messages
        // { "description": "Device crossed geofence boundry. Device inside geofence area.", "type": 6, "trigger": true, "created": 1537397511 }
        local ts = (alert.trigger) ? formatTimestamp(alert.created) : formatTimestamp(alert.resolved);
        // local msg = format("At %s %s", ts, alert.description);
        local message = "#findcharlie is active! Find me here and tweet a picture with #ifoundcharlie to win a prize #DF18 #iot @electricimp @appirio";
        local msg = format("At %s %s", ts, "#findcharlie is active!"); // TB
        server.log("Tweeting: " + msg);
        _twitter.tweet(msg);
    }

    // Converts timestamp to "00:54:51 2017-12-03" format
    function formatTimestamp(ts = null) {
        local d = ts ? date(ts) : date();
        return format("%02d:%02d:%02d %04d-%02d-%02d", d.hour, d.min, d.sec, d.year, d.month + 1, d.day);
    }

}