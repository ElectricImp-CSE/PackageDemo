// Cellular Asset Tracking Application Device Code
// ---------------------------------------------------

// LIBRARIES
// ---------------------------------------------------
// Libraries must be required before all other code

// Temperature Humidity sensor Library
#require "HTS221.device.lib.nut:2.0.1"
// Accelerometer Library - movement/impact
#require "LIS3DH.device.lib.nut:2.0.2"
// GPS Location Libraries
#require "GPSParser.device.lib.nut:1.0.0"
#require "GPSUARTDriver.device.lib.nut:1.1.0"
// LED Library
#require "APA102.device.lib.nut:2.0.0"
// Agent/Device Coms
#require "MessageManager.lib.nut:2.1.0"
// Library to help with asynchonous programming
#require "promise.class.nut:3.0.1"

// Add Battery Charger and Fuel Gauge libraries
#require "BQ25895M.device.lib.nut:1.0.0"
#require "MAX17055.device.lib.nut:1.0.1"

#require "PrettyPrinter.class.nut:1.0.1"
#require "JSONEncoder.class.nut:1.0.0"

// HARDWARE ABSTRACTION LAYER
// ---------------------------------------------------
// HAL's are tables that map human readable names to
// the hardware objects used in the application.

// impC001-breakout HAL
@include "device/Breakout_4_2.HAL.nut";

// GLOBAL VARIABLES AND CONSTANTS
// ---------------------------------------------------

// Shared Message Manager and Data Table Slot Names
@include "shared/AgentDeviceComs.shared.nut";

I2C_CLOCK_SPEED <- CLOCK_SPEED_400_KHZ;

pp <- PrettyPrinter(null, false);
print <- pp.print.bindenv(pp);

// ENVIRONMENTAL SENSOR MONITORING CLASS
// ---------------------------------------------------
// Class to manage temperature/humidity sensor, Light level

@include "device/EnvMonitor.device.nut";

// MOVEMENT MONITORING CLASS
// ---------------------------------------------------
// Class to manage accelerometer
// TODO: Update to use interrupt for movement/impact check, for low power application

@include "device/MovementMonitor.device.nut";

// LOCATION MONITORING CLASS
// ---------------------------------------------------
// Class to manage GPS

@include "device/LocationMonitor.device.nut";

// LED CONTROL CLASS
// ---------------------------------------------------
// Class to control User RGB LED

@include "device/LED.device.nut";

// BATTERY MONITORING CLASS
// ---------------------------------------------------
// Class to manage Battery Charger and Fuel Gauge

@include "device/BatteryMonitor.device.nut";

// TRACKER APPLICATION CLASS
// ---------------------------------------------------
// Class to manage tracker application

enum TRACKER_LOCATION {
    EI_OFFICE,
    HOWARD,
    SF_TEST
}

class TrackerApplication {

    // Use to test GPS if we don't have the hardware
    static STUB_LOC_DATA = false;
    // Lat/lng for Specified locals
    static LOC_LAT_IMP_HQ  = "37.395447";
    static LOC_LNG_IMP_HQ  = "-122.102142";
    static LOC_LAT_TB_BWAY = "37.795661";   // TB: Broadway
    static LOC_LNG_TB_BWAY = "-122.426654"; // TB
    static LOC_LAT_HOWARD  = "37.784599";   // TB: Howard Street
    static LOC_LNG_HOWARD  = "-122.401007"; // TB

    // Geofence radius in meters
    static GEOFENCE_RADIUS = 100;

    _mm              = null;
    _envMon          = null;
    _moveMon         = null;
    _locMon          = null;
    _battMon         = null;
    _led             = null;

    _geofenceLat     = null;
    _geofenceLng     = null;
    _blink           = null;
    _ledBlinkState   = null;

    _debug           = null;
    _reportingInt    = null;
    _nextConnectTime = null;
    _readingTimer    = null;
    _ready           = null;
    _data            = [];
    _alerts          = {};

    // Configure class constants
    function _statics_() {
        // Send data to SF every 3 min
        const DEFAULT_REPORTING_INT_SEC  = 180;
        // Take readings every 30 sec
        const READING_INTERVAL_SEC       = 30;
        // On reboot, give agent time send stored settings
        const AGENT_DEV_SYNC_TIMEOUT_SEC = 5;
        // Time out used to determine is location data is stale
        const LOCATION_TIMEOUT_SEC       = 60;

        const TEMP_HIGH_ALERT_DESC       = "Temperature above threshold";
        const TEMP_LOW_ALERT_DESC        = "Temperature below threshold";
        const HUMID_HIGH_ALERT_DESC      = "Humidity above threshold";
        const HUMID_LOW_ALERT_DESC       = "Humidity below threshold";
        const MOVE_ALERT_DESC            = "Movement detected";
        const LIGHT_ALERT_DESC           = "Light level above threshold";
        const LOCATION_ALERT_DESC        = "Device crossed geofence boundry. %s";
    }

    constructor(location, debug = false) {
        _debug = debug;
        _ready = false;

        HAL.PWR_GATE_EN.configure(DIGITAL_OUT, 1);

        switch (location) {
            case TRACKER_LOCATION.HOWARD:
                _geofenceLat = LOC_LAT_HOWARD;
                _geofenceLng = LOC_LNG_HOWARD;
                break;
            case TRACKER_LOCATION.SF_TEST:
                _geofenceLat = LOC_LAT_TB_BWAY;
                _geofenceLng = LOC_LNG_TB_BWAY;
                break;
            case TRACKER_LOCATION.EI_OFFICE:
                _geofenceLat = LOC_LAT_IMP_HQ;
                _geofenceLng = LOC_LNG_IMP_HQ;
                break;
        }

        // Initialize sensors
        initializeMonitors();
        // Initialize LED
        _led = LED();

        // Initialize Message Manager and handlers
        local settingsHandlers = {
            "onReply" : getSettingsReplyHandler.bindenv(this),
            "onFail"  : getSettingsFailHandler.bindenv(this)
        }
        _mm = MessageManager();
        // Register Update handler
        _mm.on(MM_UPDATE_SETTINGS, updateHandler.bindenv(this));
        // Register Locate handler
        _mm.on(MM_LOCATE, locateHandler.bindenv(this));
        // Register LED master switch
        _mm.on(MM_LED_STATE, upateLEDBlinkState.bindenv(this));
        // Get settings from agent, then initialize monitors
        _mm.send(MM_GET_SETTINGS, null, settingsHandlers);
    }

    function logNetInfo() {
        local netData = imp.net.info();
        if ("active" in netData) {
            local type = netData.interface[netData.active].type;

            // We have an active network connection
            if (type == "cell") {
                // The imp is on a cellular connection
                server.log("cellular RSSI " + netData.interface[netData.active].rssi);
                server.log("cellinfo " + netData.interface[netData.active].cellinfo);
            }
        }
    }

    // Start tracker application
    function run() {
        // Wait til we get settings from agent before starting readings loop
        if (!_ready) {
            imp.wakeup(AGENT_DEV_SYNC_TIMEOUT_SEC, run.bindenv(this));
            return;
        }
        log("Tracker ready...");

        _ledBlinkState = LED_BLINK_STATE.ON;
        // Start LEDs blinking yellow at a slow rate, until we have a location
        blinkOutsideGeofence();

        // Start readings loop
        takeReadings();

        // // Enable movement tracking
        // _moveMon.setMovementHandler(movementHanlder.bindenv(this));
        // // TODO: Replace movement checker with configure interrupt to conserve power
        // _moveMon.startMovementChecker();

        // Enable geofencing
        _locMon.enableGeofence(GEOFENCE_RADIUS, _geofenceLat, _geofenceLng, geofenceAlertHandler.bindenv(this))
    }

    function geofenceAlertHandler(inBounds) {
        // Change in
        log("Geofence handler triggered...");
        takeReadings(null, null, inBounds);
    }

    function movementHanlder(isMoving, magnitude = null) {
        log("Movement handler triggered...")
        takeReadings(isMoving, magnitude);
    }

    function takeReadings(isMoving = null, magnitude = null, inBounds = null) {
        // Make sure only one reading timer is running
        if (_readingTimer != null) {
            imp.cancelwakeup(_readingTimer);
            _readingTimer = null;
        }

        log("Taking readings...");
        // Take readings from sensors, exclude accel reading if movement was just detected
        local series = (magnitude == null) ? [_envMon.takeTempHumidReading(), _envMon.takeLightReading(), _moveMon.takeReading()] : [_envMon.takeTempHumidReading(), _envMon.takeLightReading()];
        Promise.all(series)
            .then(function(results) {
                log("Processing reading results.");

                local reading = {};
                reading[READING_TS] <- time();
                // Flag used to determine if alerts should be sent
                // Currently alerts are sent when the alert condition
                // is first noted and when the alert condition is resolved.
                // Alert info will remain in the alert table, will not be sent
                // to the agent again. All alerts with resolved timestamps will
                // be removed from the table after they are sent.
                // Note: The full alert table is sent when any alert is created,
                // so agent may need to track alerts if resending same alert to
                // server is an issue.
                local alertUpdate = false;

                // Add location to stored
                if (STUB_LOC_DATA) {
                    // Add stub location data
                    reading[READING_LAT] <- _geofenceLat;
                    reading[READING_LNG] <- _geofenceLng;
                } else {
                    // Add location if GPS is reporting data
                    local loc = _locMon.getLocation();
                    if (loc.lat != null) {
                        // Only add if data is not stale
                        if (reading[READING_TS] - loc.ts < LOCATION_TIMEOUT_SEC) {
                            reading[READING_LAT] <- loc.lat;
                            reading[READING_LNG] <- loc.lng;
                        } else if (inBounds) {
                            // If no GPS data available, then reset inBounds variable to false
                            inBounds = false;
                        }

                    }
                }

                // Add temperature to reading and update alert table if needed
                if ("temperature" in results[0]) {
                    reading[READING_TEMP] <- results[0].temperature;

                    // Check if temp is in range
                    local alertType = _envMon.checkTemp(reading[READING_TEMP]);
                    // Add temp range flag to reading
                    reading[DEV_STATE_TEMP_IN_RANGE] <- (alertType == null);

                    // // Update alert table to send alert
                    // if (reading[DEV_STATE_TEMP_IN_RANGE] && ALERT_TEMP in _alerts) {
                    //     // Update a temp alert with resolved timestamp
                    //     _alerts[ALERT_TEMP][ALERT_RESOLVED] <- reading[READING_TS];
                    //      // Set connect flag to update stage change
                    //     alertUpdate = true;
                    // } else if (!reading[DEV_STATE_TEMP_IN_RANGE] && (!(ALERT_TEMP in _alerts) || _alerts[ALERT_TEMP][ALERT_TYPE] != alertType)) {
                    //     // Temp is out of range and no alert for this condition has been issued, create alert
                    //     local alert = {};
                    //     alert[ALERT_TYPE]        <- alertType;
                    //     alert[ALERT_TRIGGER]     <- reading[READING_TEMP];
                    //     alert[ALERT_CREATED]     <- reading[READING_TS];
                    //     alert[ALERT_DESCRIPTION] <- (alertType == ALERT_TYPE_ID.TEMP_HIGH) ? TEMP_HIGH_ALERT_DESC : TEMP_LOW_ALERT_DESC;
                    //     // Add alert to _alerts table
                    //     _alerts[ALERT_TEMP]  <- alert;
                    //     // Set connect flag to update stage change
                    //     alertUpdate = true;
                    // }
                }

                // Add humidity to reading and update alert table if needed
                if ("humidity" in results[0]) {
                    reading[READING_HUMID] <- results[0].humidity;

                    // Check if humidity is in range
                    local alertType = _envMon.checkHumid(reading[READING_HUMID]);
                    // Add humid range flag to reading
                    reading[DEV_STATE_HUMID_IN_RANGE] <- (alertType == null);

                    // // Update alert table to send alert
                    // if (reading[DEV_STATE_HUMID_IN_RANGE] && ALERT_HUMID in _alerts) {
                    //     // Update a humid alert with resolved timestamp
                    //     _alerts[ALERT_HUMID][ALERT_RESOLVED] <- reading[READING_TS];
                    //     // Set connect flag to update stage change
                    //     alertUpdate = true;
                    // } else if (!reading[DEV_STATE_HUMID_IN_RANGE] && (!(ALERT_HUMID in _alerts) || _alerts[ALERT_HUMID] != alertType)) {
                    //     // Temp is out of range and no alert for this condition has been issued, create alert
                    //     local alert = {};
                    //     alert[ALERT_TYPE]        <- alertType;
                    //     alert[ALERT_TRIGGER]     <- reading[READING_HUMID];
                    //     alert[ALERT_CREATED]     <- reading[READING_TS];
                    //     alert[ALERT_DESCRIPTION] <- (alertType == ALERT_TYPE_ID.HUMID_HIGH) ? HUMID_HIGH_ALERT_DESC : HUMID_LOW_ALERT_DESC;
                    //     // Add alert to _alerts table
                    //     _alerts[ALERT_HUMID] <- alert;
                    //     // Set connect flag to update stage change
                    //     alertUpdate = true;
                    // }
                }

                // Add Light Level to reading
                if ("lxLevel" in results[1] && "isLight" in results[1]) {
                    reading[READING_LX] <- results[1].lxLevel;
                    reading[DEV_STATE_IS_LIGHT] <- results[1].isLight;

                    // // Report light level alerts
                    // if (reading[DEV_STATE_IS_LIGHT] && !(ALERT_LIGHT in _alerts)) {
                    //     // If light is above threshold trigger alert
                    //     local alert = {};
                    //     alert[ALERT_TYPE]        <- ALERT_TYPE_ID.LIGHT;
                    //     alert[ALERT_TRIGGER]     <- reading[READING_LX];
                    //     alert[ALERT_CREATED]     <- reading[READING_TS];
                    //     alert[ALERT_DESCRIPTION] <- LIGHT_ALERT_DESC;
                    //     // Add alert to _alerts table
                    //     _alerts[ALERT_LIGHT] <- alert;
                    //     // Set connect flag to update stage change
                    //     alertUpdate = true;
                    // } else if (!reading[DEV_STATE_IS_LIGHT] && (ALERT_LIGHT in _alerts)) {
                    //     // Clear light alert
                    //     _alerts[ALERT_LIGHT][ALERT_RESOLVED] <- reading[READING_TS];
                    //     alertUpdate = true;
                    // }

                }

                // Add accelerometer data
                if (magnitude != null) {
                    // Movement callback was called, update device state and force connection
                    reading[READING_MAG] <- magnitude;
                    reading[DEV_STATE_IS_MOVING] <- isMoving;

                    // // Report movement alerts
                    // alertUpdate = true;
                    // // Update alert table
                    // if (isMoving && !(ALERT_MOVE in _alerts)) {
                    //     local alert = {};
                    //     alert[ALERT_TYPE]        <- ALERT_TYPE_ID.MOVE;
                    //     alert[ALERT_TRIGGER]     <- magnitude;
                    //     alert[ALERT_CREATED]     <- reading[READING_TS];
                    //     alert[ALERT_DESCRIPTION] <- MOVE_ALERT_DESC;
                    //     _alerts[ALERT_MOVE]      <- alert;
                    // } else if (!isMoving && ALERT_MOVE in _alerts) {
                    //     // Clear a movement alert
                    //     _alerts[ALERT_MOVE][ALERT_RESOLVED] <- reading[READING_TS];
                    // }

                } else if (results[2] != null) {
                    // Update state with values from reading
                    reading[READING_MAG] <- results[2].magnitude;
                    reading[DEV_STATE_IS_MOVING] <- results[2].isMoving;
                }

                if (inBounds != null) {
                    // Add location info to readings
                    reading[DEV_STATE_IS_IN_BOUNDS] <- inBounds;

                    // Update alert table
                    if (inBounds && !(ALERT_LOCATION in _alerts)) {
                        // Toggle alert flag
                        alertUpdate = true;

                        // Add new alert to alerts table
                        local alert = {};
                        alert[ALERT_TYPE]        <- ALERT_TYPE_ID.LOCATION;
                        alert[ALERT_TRIGGER]     <- inBounds;
                        alert[ALERT_CREATED]     <- reading[READING_TS];
                        alert[ALERT_DESCRIPTION] <- format(LOCATION_ALERT_DESC, (inBounds) ? "Device inside geofence area." : "Device outside geofence area.");
                        _alerts[ALERT_LOCATION]  <- alert;
                        // Start LEDs blinking blue at normal rate
                        blinkInsideGeofence();
                    } else if (!inBounds && ALERT_LOCATION in _alerts) {
                        // Toggle alert flag
                        alertUpdate = true;

                        // Update alert to resolved, after message is sent to
                        // agent it will be cleared a alert table
                        _alerts[ALERT_LOCATION][ALERT_RESOLVED] <- reading[READING_TS];
                        // Start LEDs blinking yellow at a slow rate
                        blinkOutsideGeofence();
                    }
                } else {
                    // Add location info to readings
                    local inBounds = _locMon.inBounds();
                    if (inBounds != null) {
                        reading[DEV_STATE_IS_IN_BOUNDS] <- inBounds;
                    }
                }

                // Store data
                _data.push(reading);
                log("Readings stored.");

                // Send data if it is time, force a send if alerts have been updated
                return checkTimeToSend(alertUpdate);
            }.bindenv(this))
            .finally(function(msg) {
                log(msg);
                // Schedule the next reading
                _readingTimer = imp.wakeup(READING_INTERVAL_SEC, takeReadings.bindenv(this));
            }.bindenv(this))
    }

    function checkTimeToSend(alertUpdated) {
        local msg = "Not time to send data.";
        if (_data.len() > 0 && (alertUpdated || timeToConnect())) {
            msg = "Sending data.";
            local payload = {};
            // Always send readings
            payload[READINGS] <- _data;
            // Only send alert table if there has been an update to the alert
            payload[ALERTS]   <- (alertUpdated) ? _alerts : null;
            // Send battery status
            local bStatus = _battMon.getChargeStatus();
            if (bStatus != null) payload[BATTERY] <- bStatus;
            // Send data, use ACK handler to delete sent data/alerts after delivery
            _mm.send(MM_SEND_DATA, payload, {"onAck" : sendReadingsAckHandler.bindenv(this)});
            // TODO: Add onFail to make sure we don't run out of memory if we aren't able to
            // connect for a long time.
            setNextConnectTime();
        }
        return msg;
    }

    function timeToConnect() {
        // Return a boolean - if it is time to connect based on the current time
        return (time() >= _nextConnectTime);
    }

    function setNextConnectTime(lastConnection = null) {
        if (_reportingInt == null) _reportingInt = DEFAULT_REPORTING_INT_SEC;
        // Update the local nextConnectTime variable
        if (lastConnection == null) lastConnection = time();
        _nextConnectTime = lastConnection + _reportingInt;
    }

    function sendReadingsAckHandler(msg) {
        // The agent has received the readings

        // Clear stored data we just sent
        _data = [];

        // Clear all alerts that have been resolved
        foreach(alert, info in _alerts) {
            if (ALERT_RESOLVED in info) delete _alerts[alert];
        }

        // Note: data array and alerts table will continue to update while trying to
        // send. There is a very small edge case that results in a single data update
        // being lost when data has been added right after the send completes, but just
        // before the ack is called. This should be very rare, but may need to look into
        // covering this edge case.
    }

    function getSettingsReplyHandler(msg, resp) {
        updateSettings(resp);
        _ready   = true;
    }

    function getSettingsFailHandler(msg, reason, retry) {
        // Just use default settings
        if (_reportingInt == null) _reportingInt = DEFAULT_REPORTING_INT_SEC;
        _ready   = true;
    }


    function upateLEDBlinkState(msg, reply) {
        // Update blinkstate
        _ledBlinkState = msg.data;
        // Start or stop blinking based on state
        _blink();
    }

    function updateHandler(msg, reply) {
        updateSettings(msg.data);
    }

    function initializeMonitors() {
        HAL.SENSOR_I2C.configure(I2C_CLOCK_SPEED);
        _envMon  = EnvMonitor();
        _moveMon = MovementMonitor();
        _locMon  = LocationMonitor(false);
        _battMon = BatteryMonitor();
    }

    function updateSettings(settings) {
        // Debug logging
        log("Stored settings from agent: ");
        log(settings);

        if (REPORTING_INT in settings) {
            // Update reporting interval
            _reportingInt = settings[REPORTING_INT];
            // Update next connection time based on new reporting interval and last report time
            local lastReport = (_nextConnectTime == null) ? time() : (_nextConnectTime - settings[REPORTING_INT]);
            setNextConnectTime(lastReport);
        }
        if (THRESH_MOVEMENT in settings) _moveMon.setThreshold(settings[THRESH_MOVEMENT]);
        _envMon.setThresholds(settings);
    }

    function locateHandler(msg, reply) {
        // Blink LED 5 times
        // NOTE: THIS WILL STEP ON GEO-FENCE
        //       If geofence blink is happening
        //       blink a different color,
        //       then start blinking geofence
        //       notice agian
        if (_led.isBlinking()) {
            _led.blink(LED.RED, LED_BLINK_RATE.NORMAL, 5);
            imp.wakeup(20, function() {
                if (_blink != null) _blink();
            }.bindenv(this))
        }
    }

    function blinkInsideGeofence() {
        // Store blink state in start function
        _blink = blinkInsideGeofence;
        // Blink LEDs
        if (_ledBlinkState) {
            _led.blink(LED.BLUE);
        } else {
            _led.stopBlink();
        }
    }

    function blinkOutsideGeofence() {
        // Store blink state in start function
        _blink = blinkOutsideGeofence;
        // Blink LEDs
        if (_ledBlinkState) {
            _led.blink(LED.YELLOW, LED_BLINK_RATE.SLOW);
        } else {
            _led.stopBlink();
        }
    }

    function log(msg) {
        if (_debug && server.isconnected()) {
            (typeof msg == "string") ? server.log(msg) : print(msg);
        }
    }

}

// RUNTIME
// ---------------------------------------------------
// Initialize the tracker app and start monitoring

server.log(imp.getsoftwareversion());
// Keep this workaround for light level to work until upgraded to 39.16
imp.enableblinkup(true);

server.log("Starting Tracker application.");
local debugLogging = true;
// Initialize with geofence location and debug logging flag
tracker <- TrackerApplication(TRACKER_LOCATION.EI_OFFICE, debugLogging);
// Log net info
tracker.logNetInfo();
// Start application
tracker.run();
