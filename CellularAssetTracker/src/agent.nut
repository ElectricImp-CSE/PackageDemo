// Agent/Device Coms
#require "MessageManager.lib.nut:2.1.0"
// Twitter Lib
#require "Twitter.agent.lib.nut:2.0.0"

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
    static BU_TRACKER_ID_RED      = "c0010c2a69f00309";

    _mm         = null;
    _twitter    = null;
    _thresholds = null;
    _webService = null;
    _currCharlieDev = null;
    _battState  = null;

    constructor() {
        _loadStoredThresholds();

        _mm = MessageManager();
        // Register handler to sync settings with device on boot
        _mm.on(MM_GET_SETTINGS, _getSettingsHandler.bindenv(this));
        _mm.on(MM_SEND_DATA, sendDataHandler.bindenv(this));

        // Make sure only the device on Charlie is tweeting
        if (imp.configparams.deviceid == MAIN_TRACKER_ID_YELLOW) {
            _currCharlieDev = true;
        } else {
            _currCharlieDev = false;
        }

        // Creates device if needed/retrieves id, so we can
        // send device data.
        _webService = WebService(commandHandler.bindenv(this));

        // Initialize Twitter library
        _twitter = TwitterBot();

        // Register your HTTP request handler
        // NOTE your agent code can only have ONE handler
        http.onrequest(_requestHandler.bindenv(this));
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

        // Send data to webservice
        _webService.sendData(msg.data, _currCharlieDev);

        // Tweet if main device and charlie crossed geofence boundry
        if (_currCharlieDev && "a" in msg.data && msg.data[ALERTS] != null) {
            if (ALERT_LOCATION in msg.data[ALERTS]) {
                server.log(msg.data.a[ALERT_LOCATION]["description"]);
                _twitter.geofenceTweet(msg.data.a[ALERT_LOCATION]);
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


    function _requestHandler(request, response) {
        // Always use try... catch to trap errors
        try {
            // Check if the variable 'led' was passed into the query
            if (_battState != null && request.method == "GET" && request.path == "/battery") {
                local html = "<h1>Percent of battery remaining: " +_battState[BATTERY_PERCENT] + "%</h1><h1>Remaining cell capacity: " + _battState[BATTERY_CAPACITY] + "mAh</h1>"
                response.send(200, html);
            } else {
                // Send a response back to whoever made the request
                response.send(200, "OK");
            }
        } catch (exp) {
            response.send(500, "Error: " + exp);
        }
    }
}

// RUNTIME
// ---------------------------------------------------
// Start the application
TrackerApplication();
