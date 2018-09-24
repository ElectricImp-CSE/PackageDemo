// Web Integration Library
#require "Salesforce.agent.lib.nut:2.0.0"

// GLOBAL VARIABLES AND CONSTANTS
// ---------------------------------------------------

// Shared Message Manager and Data Table Slot Names
@include "shared/AgentDeviceComs.shared.nut";

// WEB SERVICE CLASS
// ---------------------------------------------------
// Class to manage communication with Web Service

// SALESFORCE APPLICATION CLASS
// ---------------------------------------------------
// Class to manage communication with Salesforce Tracker Application
// Dependent on Saleforce Library

class SalesforceApp {

    force         = null;
    sendUrl       = null;
    topicListener = null;

    impDeviceId    = null;
    agentId        = null;

    function __statics__() {
        const SF_VERSION       = "v43.0";
        const CONSUMER_KEY     = "@{SALESFORCE_CONSUMER_KEY}";
        const CONSUMER_SECRET  = "@{SALESFORCE_CONSUMER_SECRET}";
        const USERNAME         = "@{SALESFORCE_USERNAME}";
        const PASSWORD         = "@{SALESFORCE_PASSWORD}";
        const LOGIN_TOKEN      = "@{SALESFORCE_LOGIN_TOKEN}";
        const EVENT_NAME       = "Container__e";
        const ASSET_ID_99C     = "02iB00000009N2KIAU";
        const ASSET_ID_2B2     = "02iB0000000U2BuIAK";
        const ASSET_COLD_CHAIN = "02iB0000000U2DkIAK";

        @include "agent/AgentSalesforceComs.agent.nut";
    }

    constructor(_topicListener) {
        agentId = split(http.agenturl(), "/").top();
        impDeviceId = imp.configparams.deviceid;

        sendUrl = format("sobjects/%s/", EVENT_NAME);
        force = Salesforce(CONSUMER_KEY, CONSUMER_SECRET);
        force.setVersion(SF_VERSION);
        topicListener = _topicListener;

        force.login(USERNAME, PASSWORD, LOGIN_TOKEN, function(err, resp) {
            if (err != null) server.error(err);
        });

        // TODO:
        // Open listeners for incomming messages (BayeuxClient??)
    }

    function sendData(data, mainDevice) {
        // Don't send if we are not logged in
        if (!force.isLoggedIn()) {
            server.error("Not logged into Salesforce. Not sending data: ");
            server.log(http.jsonencode(data));
            return;
        }

        local body = {};
        body[EVENT_NAME_DEVICE_ID] <- impDeviceId;
        // Add asset ID
        body[EVENT_NAME_ASSET_ID] <- (mainDevice) ? ASSET_ID_99C : ASSET_ID_2B2;

        // Only send the most recent reading to Salesforce
        local last = data.r.top();
        if (READING_LAT in last)   body[EVENT_NAME_LAT]      <- last[READING_LAT];
        if (READING_LNG in last)   body[EVENT_NAME_LNG]      <- last[READING_LNG];
        if (READING_TEMP in last)  body[EVENT_NAME_TEMP]     <- last[READING_TEMP];
        if (READING_HUMID in last) body[EVENT_NAME_HUMID]    <- last[READING_HUMID];
        if (READING_MAG in last)   body[EVENT_NAME_MOVEMENT] <- last[READING_MAG];
        if (READING_LX in last)    body[EVENT_NAME_LIGHT]    <- last[READING_LX];

        // Send Salesforce platform event with device readings
        _sendToSF(body, function (err, respData) {
            if (err) {
                // Try parsing error
                try {
                    // ERROR: [ { "message": "Session expired or invalid", "errorCode": "INVALID_SESSION_ID" } ]
                    local error = err[0];
                    if ("errorCode" in error && error.errorCode == "INVALID_SESSION_ID") {
                        // Since login token has expired, delete it
                        setToken(null);
                        server.log(http.jsonencode(err));
                        server.log("Logging into salesforce");
                        // Try to login again, resend data if login successful
                        force.login(USERNAME, PASSWORD, LOGIN_TOKEN, function(loginErr, resp) {
                            if (loginErr != null) {
                                server.error(http.jsonencode(loginErr));
                            } else {
                                server.log("Login successful.");
                                sendData(data);
                            }
                        }.bindenv(this));
                    }
                } catch(e) {
                    server.error(http.jsonencode(err));
                }
            } else {
                server.log("Salesforce readings sent successfully");
            }
        }.bindenv(this));

    }

    // Converts timestamp to "2017-12-03T00:54:51Z" format
    function formatTimestamp(ts = null) {
        local d = ts ? date(ts) : date();
        return format("%04d-%02d-%02dT%02d:%02d:%02dZ", d.year, d.month + 1, d.day, d.hour, d.min, d.sec);
    }

    function _sendToSF(body, cb) {
        server.log("Sending payload to Salesforce: ");
        server.log(http.jsonencode(body));
        force.request("POST", sendUrl, http.jsonencode(body), cb);
    }

}

// Assign SalesforceApp class to Webservice variable
// Allows base tracker application to be re-used
// for different web services
local root = getroottable();
WebService <- root.SalesforceApp;