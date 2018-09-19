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

    _mm         = null;
    _twitter    = null;
    _thresholds = null;
    _webService = null;

    constructor() {
        _loadStoredThresholds();

        _mm = MessageManager();
        // Register handler to sync settings with device on boot
        _mm.on(MM_GET_SETTINGS, _getSettingsHandler.bindenv(this));
        _mm.on(MM_SEND_DATA, sendDataHandler.bindenv(this));

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

        // Send data to webservice
        _webService.sendData(msg.data);

        // Tweet if charlie crossed geofence boundry
        if ("a" in msg.data && msg.data.a != null) {
            if (ALERT_LOCATION in msg.data.a) {
                server.log(msg.data.a[ALERT_LOCATION]["description"]);
                _twitter.geofenceTweet(msg.data.a[ALERT_LOCATION]);
            }
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
}

// RUNTIME
// ---------------------------------------------------
// Start the application
TrackerApplication();
