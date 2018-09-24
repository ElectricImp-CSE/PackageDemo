enum TWEET_TYPE {
    ENTER,
    INSIDE,
    EXIT
}

class TwitterBot {

    _twitter      = null;
    _enterTweets  = null;
    _insideTweets = null;
    _exitTweets   = null;

    constructor() {
        // Twitter test keys are shared with snackbot_1 (20000c2a690af734)
        const TEST_API_KEY         = "@{TWITTER_TESTER_API_KEY}";
        const TEST_API_SECRET      = "@{TWITTER_TESTER_API_SECRET}";
        const TEST_AUTH_TOKEN      = "@{TWITTER_TESTER_AUTH_TOKEN}";
        const TEST_TOKEN_SECRET    = "@{TWITTER_TESTER_TOKEN_SECRET}";

        const CHARLIE_API_KEY      = "@{TWITTER_CHARLIE_API_KEY}";
        const CHARLIE_API_SECRET   = "@{TWITTER_CHARLIE_API_SECRET}";
        const CHARLIE_AUTH_TOKEN   = "@{TWITTER_CHARLIE_AUTH_TOKEN}";
        const CHARLIE_TOKEN_SECRET = "@{TWITTER_CHARLIE_TOKEN_SECRET}";

        const MAP_LOCATION_URL     = "https://maps.google.com/?q=%s,%s";
        const NO_LOCATION_FILLER   = "on Howard St."

        const ENTER_TWEET_1  = "#findcharlie is active!  Find me %s and tweet a picture with #ifoundcharlie to win a prize #DF18 #iot @electricimp @appirio. %s";
        const ENTER_TWEET_2  = "#findcharlie and take a selfie %s! Tag with #ifoundcharlie to win a prize from @electricimp and @appirio at #DF18 #iot. %s";

        const INSIDE_TWEET_1 = "Keep looking for #findcharlie %s and tweet a picture with #ifoundcharlie to win a prize #DF18 #iot @electricimp @appirio. %s";

        const EXIT_TWEET_1   = "#findcharlie is inactive for now, but I’ll be back later. Ask @electricimp and @appirio how @salesforce #iot can help solve your asset tracking challenges. #DF18. %s";
        const EXIT_TWEET_2   = "#findcharlie is inactive for now. Ask @electricimp and @appirio how @salesforce #iot can help track and manage your assets. #DF18. %s";

        _enterTweets  = [ENTER_TWEET_1, ENTER_TWEET_2];
        _insideTweets = [ENTER_TWEET_1, ENTER_TWEET_2, INSIDE_TWEET_1];
        _exitTweets   = [EXIT_TWEET_1, EXIT_TWEET_2];

        _twitter = Twitter(TEST_API_KEY, TEST_API_SECRET, TEST_AUTH_TOKEN, TEST_TOKEN_SECRET);
    }

    function geofenceTweet(type, lastLoc = null) {
        // Create a generic tweet, that is the current timestamp
        local tweet = formatTimestamp();

        switch (type) {
            case TWEET_TYPE.ENTER:
                // Get a random tweet index
                local idx = randomNum(_enterTweets.len());
                // Get location link/string
                local locStr = (lastLoc == null) ? NO_LOCATION_FILLER : format(MAP_LOCATION_URL, lastLoc.lat, lastLoc.lng);
                // Update tweet with random selected tweet with timestamp
                tweet = format(_enterTweets[idx], locStr, tweet);
                break;
            case TWEET_TYPE.INSIDE:
                local idx = randomNum(_insideTweets.len());
                // Get location link/string
                local locStr = (lastLoc == null) ? NO_LOCATION_FILLER : format(MAP_LOCATION_URL, lastLoc.lat, lastLoc.lng);
                tweet = format(_insideTweets[idx], locStr, tweet);
                break;
            case TWEET_TYPE.EXIT:
                local idx = randomNum(_exitTweets.len());
                tweet = format(_exitTweets[idx], tweet);
                break;
        }

        server.log("Tweeting: " + tweet);
        _twitter.tweet(tweet);
    }

    // Converts timestamp to "00:54:51 2017-12-03" format
    function formatTimestamp(ts = null) {
        local d = ts ? date(ts) : date();
        return format("%02d:%02d:%02d %04d-%02d-%02d", d.hour, d.min, d.sec, d.year, d.month + 1, d.day);
    }

    function randomNum(max) {
        // Generate a pseudo-random integer between 0 and max (exclusive)
        // ie passing in max of 4 will give you numbers 0, 1, 2, 3
        local num = (1.0 * math.rand() / RAND_MAX) * max;
        return num.tointeger();
    }

}