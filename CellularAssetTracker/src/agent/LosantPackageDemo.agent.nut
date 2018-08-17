// Agent/Device Coms
#require "MessageManager.lib.nut:2.1.0"
// Losant Library
#require "Losant.agent.lib.nut:1.0.0"

// GLOBAL VARIABLES AND CONSTANTS
// ---------------------------------------------------

// Shared Message Manager and Data Table Slot Names
@include "shared/AgentDeviceComs.shared.nut";

enum WEB_SERVICE_COMMAND_TYPE {
    UPDATE_SETTINGS,
    LOCATE
}

// WEB SERVICE CLASS
// ---------------------------------------------------
// Class to manage communication with Web Service

// LOSANT APPLICATION CLASS
// ---------------------------------------------------
// Class to manage communication with Losant Tracker Application
// Dependent on Losant Library

class LosantApp {

    lsntApp        = null;
    cmdListenerCb  = null;

    lsntDeviceId   = null;
    impDeviceId    = null;
    agentId        = null;

    function __statics__() {
        @include "agent/LosantAuth.agent.nut";

        // Device info
        const DEVICE_NAME_TEMPLATE      = "Tracker_%s";
        const DEVICE_DESCRIPTION        = "Electric Imp Asset Tracker";
        const LOSANT_DEVICE_CLASS       = "standalone";

        @include "agent/AgentLosantComs.agent.nut";
    }

    constructor(_cmdListenerCb) {
        agentId = split(http.agenturl(), "/").top();
        impDeviceId = imp.configparams.deviceid;

        // Use full app key, since command listener requires better device permissions
        lsntApp = Losant(LOSANT_APPLICATION_ID, LOSANT_FULL_APP_API_TOKEN);
        // Check if device with this agent and device id combo exists, create if need
        _getLosantDeviceId();
        cmdListenerCb = _cmdListenerCb;
        openCommandListener();
    }

    function openCommandListener() {
        // If we don't have a callback cancel command stream
        if (cmdListenerCb == null) {
            lsntApp.closeDeviceCommandStream();
            return;
        }
        // If we are not configured try again in 5 sec
        if (lsntDeviceId == null) {
            imp.wakeup(5, openCommandListener.bindenv(this));
            return;
        }

        server.log("Opening streaming listener...");
        lsntApp.openDeviceCommandStream(lsntDeviceId, _commandHandler.bindenv(this), _onStreamError.bindenv(this));
    }

    // Data params is a table with keys readings and alerts -
    //      data.r is always an array
    //      data.a is always a table even if empty
    //      data = { "r" : [...], "a" : {...} }
    function sendData(data) {
        // Check that we have a Losant device configured
        if (lsntDeviceId == null) {
            server.log("Losant device not configured. Not sending data: ");
            server.log(http.jsonencode(data));
            return;
        }

        // Send multiple device state updates
        local payload = [];

        if (READINGS in data) {
            foreach (reading in data[READINGS]) {
                payload.push(_createStateUpdateTable(reading));
            }
        }

        // NOTE: Alerts may want to create a Losant event so alert table has been
        // passed up to this layer. However Losant docs state an app only supports
        // one event creation per second. Due to this limitation event creation from
        // the device will not scale. Added boolean "in range" to state table, so
        // can easily create event logic at the app cloud layer instead.

        server.log("Sending losant payload: ");
        server.log(http.jsonencode(payload));
        lsntApp.sendDeviceState(lsntDeviceId, payload, _sendDeviceStateHandler.bindenv(this));
    }

    // --------------------------------------------
    // Helper to format data sends

    // Takes a single reading table and returns a table formatted for a Losant state update
    function _createStateUpdateTable(reading) {
        local data = {};

        // Payload data keys must match device attribute names
        if (READING_LAT in reading && READING_LNG in reading) {
            data[LOCATION_ATTR] <- format("%s,%s", reading[READING_LAT], reading[READING_LNG]);
        }
        if (READING_TEMP in reading) data[TEMP_ATTR] <- reading[READING_TEMP];
        if (READING_HUMID in reading) data[HUMID_ATTR] <- reading[READING_HUMID];
        if (READING_MAG in reading) data[MAG_ATTR] <- reading[READING_MAG];
        if (READING_LX in reading) data[LX_ATTR] <- reading[READING_LX];
        if (DEV_STATE_IS_LIGHT in reading) data[IS_LIGHT_ATTR] <- reading[DEV_STATE_IS_LIGHT];
        if (DEV_STATE_TEMP_IN_RANGE in reading) data[TEMP_IN_RANGE_ATTR] <- reading[DEV_STATE_TEMP_IN_RANGE];
        if (DEV_STATE_HUMID_IN_RANGE in reading) data[HUMID_IN_RANGE_ATTR] <- reading[DEV_STATE_HUMID_IN_RANGE];
        if (DEV_STATE_IS_MOVING in reading) data[IS_MOVING_ATTR] <- reading[DEV_STATE_IS_MOVING];

        // Create Payload
        local stateUpdate = {
            "data" : data
        };

        // Add timestamp to paylaod
        stateUpdate.time <- (READING_TS in reading) ? lsntApp.createIsoTimeStamp(reading[READING_TS]) : lsntApp.createIsoTimeStamp();

        return stateUpdate;
    }

    // --------------------------------------------
    // Handlers for data and command requests

    function _commandHandler(cmd) {
        // Keys: "name", "time", "payload"
        // server.log(http.jsonencode(cmd));
        // server.log(cmd.name);

        local payload = cmd.payload;

        switch(cmd.name) {
            case CMD_UPDATE_SETTINGS:
                // Note currently the expected setting keys all match the agent/device com names, so we are not checking/adjusting anything here.
                // "payload": { "reportingInt": 900, "movementThresh": 0.05, "humidHigh": 80, "tempHigh": 30 }
                cmdListenerCb && cmdListenerCb(WEB_SERVICE_COMMAND_TYPE.UPDATE_SETTINGS, payload);
                break;
            case CMD_LOCATE:
                cmdListenerCb && cmdListenerCb(WEB_SERVICE_COMMAND_TYPE.LOCATE, payload);
                break;
            default:
                server.log("Unknown command: " + cmd.name);
                server.log(cmd.payload);
        }
    }

    function _onStreamError(error, resp) {
        server.log("Streaming error handler...");
        server.error(error);
        if (lsntApp.isDeviceCommandStreamOpen()) {
            server.log("Response: " + resp);
        } else {
            if ("statuscode" in resp) server.log("Status code: " + resp.statuscode);
            server.log("Response: " + resp);
            // Try reopening listener
            openCommandListener();
        }
    }

    function _sendDeviceStateHandler(res) {
        // TODO: update to only log if send was unsuccessful
        server.log("Send device state handler...");
        server.log("Status code: " + res.statuscode);
        server.log("Response: " + res.body);
    }

    // --------------------------------------------
    // Helpers to register device in Losant

    function _updateDevice(tags) {
        if (lsntDeviceId != null) {
            local deviceInfo = {
                "name"        : format(DEVICE_NAME_TEMPLATE, agentId),
                "description" : DEVICE_DESCRIPTION,
                "deviceClass" : LOSANT_DEVICE_CLASS,
                "tags"        : tags,
                "attributes"  : _createAttrs()
            }
            server.log("Updating device.");
            lsntApp.updateDeviceInfo(lsntDeviceId, deviceInfo, function(res) {
                server.log("Update device status code: " + res.statuscode);
                // server.log(res.body);
            }.bindenv(this))
        } else {
            server.log("Losant device id not retrieved yet. Try again.");
        }
    }

    function _getLosantDeviceId() {
        // Create filter for tags matching this device info,
        // Tags for this app are unique combo of agent and imp device id
        local qparams = lsntApp.createTagFilterQueryParams(_createTags());

        // Check if a device with matching unique tags exists, create one
        // and store losant device id.
        lsntApp.getDevices(_getDevicesHandler.bindenv(this), qparams);
    }

    function _createDevice() {
        // This should be done with caution, it is possible to create multiple devices
        // Each device will be given a unique Losant device id, but will have same agent
        // and imp device ids

        // Only create if we do not have a Losant device id
        if (lsntDeviceId == null) {
            local deviceInfo = {
                "name"        : format(DEVICE_NAME_TEMPLATE, agentId),
                "description" : DEVICE_DESCRIPTION,
                "deviceClass" : LOSANT_DEVICE_CLASS,
                "tags"        : _createTags(),
                "attributes"  : _createAttrs()
            }
            lsntApp.createDevice(deviceInfo, _createDeviceHandler.bindenv(this))
        }
    }

    function _createDeviceHandler(res) {
        // server.log(res.statuscode);
        // server.log(res.body);
        local body = http.jsondecode(res.body);
        if ("deviceId" in body) {
            lsntDeviceId = body.deviceId;
        } else {
            server.error("Device id not found.");
            server.log(res.body);
        }
    }

    function _getDevicesHandler(res) {
        // server.log(res.statuscode);
        // server.log(res.body);
        local body = http.jsondecode(res.body);

        if (res.statuscode == 200 && "count" in body) {
            // Successful request
            switch (body.count) {
                case 0:
                    // No devices found, create device
                    _createDevice();
                    break;
                case 1:
                    // We found the device, store the losDevId
                    if ("items" in body && "deviceId" in body.items[0]) {
                        lsntDeviceId = body.items[0].deviceId;
                        if ("tags" in body.items[0]) {
                            // server.log(http.jsonencode(body.items[0].tags))
                            // Sync attributes, use tags from losant device
                            // (tags will have owner info we do not want to overwrite)
                            _updateDevice(body.items[0].tags);
                        }
                    } else {
                        server.error("Device id not found.");
                        server.log(res.body);
                    }
                    break;
                default:
                    // Log results of filtered query
                    server.error("Found " + body.count + "devices matching the device tags.");

                    // TODO: Delete duplicate devices - look into how to determine which device
                    // is active, so data isn't lost
            }
        } else {
            server.error("List device request failed with status code: " + res.statuscode);
        }
    }

    // --------------------------------------------
    // Helpers to create device attributes and tags

    function _createTags() {
        return [
            {
                "key"   : AGENT_ID_TAG,
                "value" : agentId
            },
            {
                "key"   : DEVICE_ID_TAG,
                "value" : impDeviceId
            },
        ]
    }

    function _createAttrs() {
        return [
            {
                "name"     : LOCATION_ATTR,
                "dataType" : "gps"
            },
            {
                "name"     : TEMP_ATTR,
                "dataType" : "number"
            },
            {
                "name"     : HUMID_ATTR,
                "dataType" : "number"
            },
            {
                "name"     : MAG_ATTR,
                "dataType" : "number"
            },
            {
                "name"     : LX_ATTR,
                "dataType" : "number"
            },
            {
                "name"     : IS_LIGHT_ATTR,
                "dataType" : "boolean"
            },
            {
                "name"     : TEMP_IN_RANGE_ATTR,
                "dataType" : "boolean"
            },
            {
                "name"     : HUMID_IN_RANGE_ATTR,
                "dataType" : "boolean"
            },
            {
                "name"     : IS_MOVING_ATTR,
                "dataType" : "boolean"
            }
        ];
    }
}

// Assign LosantApp class to Webservice variable
// Allows base tracker application to be re-used
// for different web services
local root = getroottable();
WebService <- root.LosantApp;
