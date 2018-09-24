// Agent/Device Coms
#require "MessageManager.lib.nut:2.1.0"
// Twitter Lib
#require "Twitter.agent.lib.nut:2.0.0"
// Rocky For incoming req
#require "rocky.class.nut:2.0.1"

// Select which web service and include here. These files
// include a library require statement and must be included
// before any other code.
@include "agent/SalesforcePackageDemo.agent.nut";

// Twitter Wrapper Class
@include "agent/TwitterBot.agent.nut";

// TRACKER APPLICATION CLASS
// ---------------------------------------------------
// Class to manage agent/device coms, agent storage, and
// initializes webservice class

class TrackerApplication {

    static MAIN_TRACKER_ID_YELLOW = "c0010c2a69f0099c";
    static BU_TRACKER_ID_RED      = "c0010c2a69f002b2";
    static TWEET_TIMER_SEC        = 300;

    _mm         = null;
    _twitter    = null;
    _api        = null;

    _thresholds      = null;
    _webService      = null;
    _currCharlieDev  = null;
    _battState       = null;
    _ledBlinkState   = null;
    _twitterBotTimer = null;
    _lastLoc         = null;

    constructor() {
        _loadStoredThresholds();

        _mm = MessageManager();
        // Register handler to sync settings with device on boot
        _mm.on(MM_GET_SETTINGS, _getSettingsHandler.bindenv(this));
        _mm.on(MM_SEND_DATA, sendDataHandler.bindenv(this));

        _api = Rocky();
        _api.get("/battery", _battReqHandler.bindenv(this));
        _api.get("/leds/on", _ledOnReqHandler.bindenv(this));
        _api.get("/leds/off", _ledOffReqHandler.bindenv(this));
        _api.post("/leds", _ledReqHandler.bindenv(this));

        // Make sure only the device on Charlie is tweeting
        if (imp.configparams.deviceid == MAIN_TRACKER_ID_YELLOW) {
            _currCharlieDev = true;
        } else {
            _currCharlieDev = false;
        }

        _ledBlinkState = LED_BLINK_STATE.ON;

        // Creates device if needed/retrieves id, so we can
        // send device data.
        _webService = WebService(commandHandler.bindenv(this));

        // Initialize Twitter library
        _twitter = TwitterBot();
    }

    function commandHandler(cmd, payload) {
        switch (cmd) {
            case WEB_SERVICE_COMMAND_TYPE.UPDATE_SETTINGS:
                updateThresholds(payload);
                break;
            case WEB_SERVICE_COMMAND_TYPE.LOCATE:
                _mm.send(MM_LOCATE, payload);
                break;
        }
    }

    function checkThresholds(thresholds) {
        local keys = [
            THRESH_TEMP_HIGH,
            THRESH_TEMP_LOW,
            THRESH_HUMID_HIGH,
            THRESH_HUMID_LOW,
            THRESH_MOVEMENT,
            REPORTING_INT
        ]
        local checked = {};
        foreach (k, v in thresholds) {
            if (keys.find(k) != null) {
                checked[k] <- v;
            } else {
                server.log("Threshold value not recognized: " + k);
            }
        }
        return checked;
    }

    function updateThresholds(thresholds) {
        // Double check that keys are the expected
        thresholds = checkThresholds(thresholds);
        // Store settings in agent storage
        _updateStoredThresholds(thresholds);
        // Send new thresholds/settings to device
        _mm.send(MM_UPDATE_SETTINGS, thresholds);
    }

    function sendDataHandler(msg, reply) {
        server.log("Received data from device...");
        server.log(http.jsonencode(msg.data));

        // Send readings if we have any
        if (READINGS in msg.data && msg.data[READINGS].len() > 0) {

            // Grab latest reading
            local last = msg.data[READINGS].top();

            // Grab lat known location
            if (READING_LAT in last) {
                _lastLoc = {
                    "lat" : last[READING_LAT],
                    "lng" : last[READING_LNG]
                }
            }

            // Send data to webservice
            _webService.sendData(last, _currCharlieDev);
        }

        // Tweet if main device and charlie crossed geofence boundry
        // "a": {
        //     "locAlert": {
        //         "description": "Device crossed geofence boundry. Device inside geofence area.",
        //         "type": 6,
        //         "trigger": true,
        //         "created": 1537819749
        //     }
        // }
        if (_currCharlieDev && "a" in msg.data && msg.data[ALERTS] != null) {
            if (ALERT_LOCATION in msg.data[ALERTS]) {
                local alert = msg.data.a[ALERT_LOCATION];
                server.log(alert["description"]);
                if ("resolved" in alert) {
                    // Just exited geofence area
                    if (_twitterBotTimer != null) {
                        imp.cancelwakeup(_twitterBotTimer);
                        _twitterBotTimer = null;
                    }
                    _lastLoc = null;
                    _twitter.geofenceTweet(TWEET_TYPE.EXIT);
                } else {
                    _twitter.geofenceTweet(TWEET_TYPE.ENTER, _lastLoc);
                    _twitterBotTimer = imp.wakeup(TWEET_TIMER_SEC, function() {
                        _twitter.geofenceTweet(TWEET_TYPE.INSIDE, _lastLoc);
                    }.bindenv(this));
                }
            }
        }

        if (BATTERY in msg.data) {
            _battState = msg.data[BATTERY]
            server.log("Remaining cell capacity: " + _battState[BATTERY_CAPACITY] + "mAh");
            server.log("Percent of battery remaining: " + _battState[BATTERY_PERCENT] + "%");
        }
    }

    function _getSettingsHandler(msg, reply) {
        reply(_thresholds);
    }

    function _loadStoredThresholds() {
        local persist = server.load();
        _thresholds = ("thresholds" in persist) ? persist.thresholds : {};
    }

    function _updateStoredThresholds(newThresholds) {
        foreach (k, v in newThresholds) {
            // Add/Update thresholds
            _thresholds[k] <- v;
        }
        server.save({"thresholds" : _thresholds});
    }

    function _battReqHandler(context) {
        if (_battState != null) {
            local html = "<h1>Percent of battery remaining: " + _battState[BATTERY_PERCENT] + "%</h1><h1>Remaining cell capacity: " + _battState[BATTERY_CAPACITY] + "mAh</h1>"
                context.send(200, html);
        } else {
            // Send a response back to whoever made the request
            context.send(200, "<h1>No Battery Info available</h1>");
        }
    }

    function _ledOnReqHandler(context) {
        server.log("Turning LED's on.");
        _ledBlinkState = LED_BLINK_STATE.ON;
        _mm.send(MM_LED_STATE, _ledBlinkState);
        context.send(200, "Ok");
    }

    function _ledOffReqHandler(context) {
        server.log("Turning LED's off.");
        _ledBlinkState = LED_BLINK_STATE.OFF;
        _mm.send(MM_LED_STATE, _ledBlinkState);
        context.send(200, "Ok");
    }

    // expects {"state" : 0} or {"state" : 1}
    function _ledReqHandler(context) {
        context.send(200, "Ok");
        if ("state" in context.req.body) {
            local state = context.req.body.state;
            if (typeof state == "string") {
                state = state.tointeger();
            }
            _ledBlinkState = state;
            server.log("LED Blink state: " + _ledBlinkState);
            _mm.send(MM_LED_STATE, _ledBlinkState);
        }
    }
}

// RUNTIME
// ---------------------------------------------------
// Start the application
TrackerApplication();
