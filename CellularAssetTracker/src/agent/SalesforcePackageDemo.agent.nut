// Utility Libraries
#require "Rocky.class.nut:1.2.3"
// Web Integration Library
#require "Salesforce.agent.lib.nut:2.0.0"

// Extends Salesforce Library to handle authorization
class SalesforceOAuth2 extends Salesforce {

    _login = null;

    constructor(consumerKey, consumerSecret, loginServiceBase = null, salesforceVersion = null) {
        _clientId = consumerKey;
        _clientSecret = consumerSecret;

        if ("Rocky" in getroottable()) {
            _login = Rocky();
        } else {
            throw "Unmet dependency: SalesforceOAuth2 requires Rocky";
        }

        if (loginServiceBase != null) _loginServiceBase = loginServiceBase;
        if (salesforceVersion != null) _version = salesforceVersion;

        // Helper so don't have to log in all the time, however if
        // credentials get old they will need to be erased.
        getStoredCredentials();
        defineLoginEndpoint();
    }

    function getStoredCredentials() {
        local persist = server.load();
        local oAuth = {};
        if ("oAuth" in persist) oAuth = persist.oAuth;

        // Load credentials if we have them
        if ("instance_url" in oAuth && "access_token" in oAuth) {
            // Set the credentials in the Salesforce object
            setInstanceUrl(oAuth.instance_url);
            setToken(oAuth.access_token);

            // Log a message
            server.log("Loaded OAuth Credentials!");
        }
    }

    function defineLoginEndpoint() {
        // Define log in endpoint for a GET request to the agent URL
        _login.get("/", function(context) {

            // Check if an OAuth code was passed in
            if (!("code" in context.req.query)) {
                // If it wasn't, redirect to login service
                local location = format(
                    "%s/services/oauth2/authorize?response_type=code&client_id=%s&redirect_uri=%s",
                    _loginServiceBase,
                    _clientId, http.agenturl());
                context.setHeader("Location", location);
                context.send(302, "Found");

                return;
            }

            // Exchange the auth code for inan OAuth token
            getOAuthToken(context.req.query["code"], function(err, resp, respData) {
                if (err) {
                    context.send(400, "Error authenticating (" + err + ").");
                    return;
                }

                // If it was successful, save the data locally
                local persist = { "oAuth" : respData };
                server.save(persist);

                // Set/update the credentials in the Salesforce object
                setInstanceUrl(persist.oAuth.instance_url);
                setToken(persist.oAuth.access_token);

                // Finally - inform the user we're done!
                context.send(200, "Authentication complete - you may now close this window");
            }.bindenv(this));
        }.bindenv(this));
    }

    // OAuth 2.0 methods
    function getOAuthToken(code, cb) {
        // Send request with an authorization code
        _oauthTokenRequest("authorization_code", code, cb);
    }

    function refreshOAuthToken(refreshToken, cb) {
        // Send request with refresh token
        _oauthTokenRequest("refresh_token", refreshToken, cb);
    }

    function _oauthTokenRequest(type, tokenCode, cb = null) {
        // Build the request
        local url = format("%s/services/oauth2/token", _loginServiceBase);
        local headers = { "Content-Type": "application/x-www-form-urlencoded" };
        local data = {
            "grant_type": type,
            "client_id": _clientId,
            "client_secret": _clientSecret,
        };

        // Set the "code" or "refresh_token" parameters based on grant_type
        if (type == "authorization_code") {
            data.code <- tokenCode;
            data.redirect_uri <- http.agenturl();
        } else if (type == "refresh_token") {
            data.refresh_token <- tokenCode;
        } else {
            throw "Unknown grant_type";
        }

        local body = http.urlencode(data);

        http.post(url, headers, body).sendasync(function(resp) {
            local respData = http.jsondecode(resp.body);
            local err = null;

            // If there was an error, set the error code
            if (resp.statuscode != 200) err = data.message;

            // Invoke the callback
            if (cb) {
                imp.wakeup(0, function() {
                    cb(err, resp, respData);
                });
            }
        });
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
        const CONSUMER_KEY = "@{SALESFORCE_CONSUMER_KEY}";
        const CONSUMER_SECRET = "@{SALESFORCE_CONSUMER_SECRET}";
        const EVENT_NAME = "Container__e";

        // URLS from postman???
        // Post data to url: https://gs0.salesforce.com/services/data/v43.0/sobjects/Container__e
        // Create asset url: https://gs0.salesforce.com/services/data/v43.0/sobjects/Asset

        @include "agent/AgentSalesforceComs.agent.nut";
    }

    constructor(_topicListener, clearLoginCreds = false) {
        agentId = split(http.agenturl(), "/").top();
        impDeviceId = imp.configparams.deviceid;

        sendUrl = format("sobjects/%s/", EVENT_NAME);
        force = SalesforceOAuth2(CONSUMER_KEY, CONSUMER_SECRET, null, "v43.0");
        topicListener = _topicListener;

        if (clearLoginCreds) {
            local persist = server.load();
            if ("oAuth" in persist) persist.oAuth = {};
            server.save(persist);
        }

        // TODO:
        // Are we logged in?? (Notify user if we don't have token??)
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

        // Only send the most recent reading to Salesforce
        local last = data.pop();
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

// Assign SalesforceApp class to Webservice variable
// Allows base tracker application to be re-used
// for different web services
local root = getroottable();
WebService <- root.SalesforceApp;