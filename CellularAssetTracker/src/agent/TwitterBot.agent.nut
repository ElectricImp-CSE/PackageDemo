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

    function geofenceTweet(inBounds) {
        // TODO: get acutal twitter messages
        local msg = (inBounds) ? "Find Charlie he is in the geofence" : "Charlie has left the area";
        _twitter.tweet(msg);
    }

}