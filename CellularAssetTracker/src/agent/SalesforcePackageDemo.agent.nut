// Web Integration Library
#require "Salesforce.agent.lib.nut:2.0.0"

// Extends Salesforce Library to handle authorization
class SalesforceSoapLogin extends Salesforce {

    // Note we do not get back a userUrl, so getUser function will not work!!!

    _loginService = "/services/Soap/u/43.0";
    _version  = "v43.0";
    _restPath = "/services/apexrest";

    function login(username, password, securityToken, cb = null) {

        local url = format("%s%s", _loginServiceBase, _loginService);
        local headers = {
            "Content-Type" : "text/xml",
            "SOAPAction" : "Required"
        };
        local body = "<se:Envelope xmlns:se=\"http://schemas.xmlsoap.org/soap/envelope/\">\n    <se:Header/>\n    <se:Body>\n        <login xmlns=\"urn:partner.soap.sforce.com\">\n            <username>"+username+"</username>\n            <password>"+password+""+securityToken+"</password>\n        </login>\n    </se:Body>\n</se:Envelope>";

        local request = http.post(url, headers, body);
        request.sendasync(_loginRespFactory(cb))
    }

    function _loginRespFactory(cb) {
        return function(resp) {
            local body = resp.body;
            local err = null;
            local data = resp;

            if (resp.statuscode == 200) {
                try {
                    // Session id
                    _token = _parseXML(body, "<sessionId>", "</sessionId>");
                    // Full serverUrl
                    _instanceUrl = _parseXML(body, "<serverUrl>", "</serverUrl>");
                    // Parse to get the base serverUrl
                    local end = _instanceUrl.find(_loginService);
                    _instanceUrl = _instanceUrl.slice(0, end);
                } catch(e) {
                    err = "Login request parsing error " + e;
                }
            } else {
                err = "Login request failed";
            }

            if (cb != null) {
                cb(err, data);
            } else if (err != null) {
                throw err;
            }
        }.bindenv(this)
    }

    function _parseXML(data, startTag, endTag) {
        try {
            local start = data.find(startTag);
            local end = data.find(endTag);
            if (start == null || end == null) throw "XML Tag not found";

            return data.slice((start + startTag.len()), end);
        } catch(e) {
            throw e;
        }
    }

}

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
// Dependent on Saleforce Library, Rocky Library

class SalesforceApp {

    force   = null;
    sendUrl = null;
    topicListener = null;

    impDeviceId    = null;
    agentId        = null;

    function __statics__() {
        // const CONSUMER_KEY = "@{SALESFORCE_CONSUMER_KEY}";
        // const CONSUMER_SECRET = "@{SALESFORCE_CONSUMER_SECRET}";
        const USERNAME    = "@{SALESFORCE_USERNAME}";
        const PASSWORD    = "@{SALESFORCE_PASSWORD}";
        const LOGIN_TOKEN = "@{SALESFORCE_LOGIN_TOKEN}";
        const EVENT_NAME  = "Container__e";

        @include "agent/AgentSalesforceComs.agent.nut";
    }

    constructor(_topicListener) {
        agentId = split(http.agenturl(), "/").top();
        impDeviceId = imp.configparams.deviceid;

        sendUrl = format("sobjects/%s/", EVENT_NAME);
        force = SalesforceSoapLogin(null, null);
        topicListener = _topicListener;

        force.login(USERNAME, PASSWORD, LOGIN_TOKEN, function(err, resp) {
            if (err != null) server.error(err);
        });

        // TODO:
        // Open listeners for incomming messages (BayeuxClient??)
    }

    function sendData(data) {
        // Don't send if we are not logged in
        if (!force.isLoggedIn()) {
            server.error("Not logged into Salesforce. Not sending data: ");
            server.log(http.jsonencode(data));
            return;
        }

        local body = {};
        body[EVENT_NAME_DEVICE_ID] <- impDeviceId;
        body[EVENT_NAME_ASSET_ID]  <- impDeviceId;

        // Only send the most recent reading to Salesforce
        local last = data.r.pop();
        if (READING_LAT in last)   body[EVENT_NAME_LAT]      <- last[READING_LAT];
        if (READING_LNG in last)   body[EVENT_NAME_LNG]      <- last[READING_LNG];
        if (READING_TEMP in last)  body[EVENT_NAME_TEMP]     <- last[READING_TEMP];
        if (READING_HUMID in last) body[EVENT_NAME_HUMID]    <- last[READING_HUMID];
        if (READING_MAG in last)   body[EVENT_NAME_MOVEMENT] <- last[READING_MAG];
        if (READING_LX in last)    body[EVENT_NAME_LIGHT]    <- last[READING_LX];


        server.log("Sending payload to Salesforce: ");
        server.log(http.jsonencode(body));

        // Send Salesforce platform event with device readings
        force.request("POST", sendUrl, http.jsonencode(body), function (err, respData) {
            if (err) {
                server.error(http.jsonencode(err));
            }
            else {
                server.log("Salesforce readings sent successfully");
            }
        }.bindenv(this));

    }

    // Converts timestamp to "2017-12-03T00:54:51Z" format
    function formatTimestamp(ts = null) {
        local d = ts ? date(ts) : date();
        return format("%04d-%02d-%02dT%02d:%02d:%02dZ", d.year, d.month + 1, d.day, d.hour, d.min, d.sec);
    }

}

// // Assign SalesforceApp class to Webservice variable
// // Allows base tracker application to be re-used
// // for different web services
// local root = getroottable();
// WebService <- root.SalesforceApp;