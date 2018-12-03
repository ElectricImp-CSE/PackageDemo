class LocationMonitor {

    _gps          = null;

    _lastLat      = null;
    _lastLng      = null;
    _locCheckedAt = null;

    _geofenceCB   = null;
    _gfCtr        = null;
    _distFromCtr  = null;
    _inBounds     = null;


    // Configures GPS UART
    constructor(configurePixHawk) {
        // Configure class constants
        const GPS_BAUD_RATE    = 9600; // This is the default for ublox, but if it doesn't work try 38400
        const GPS_RX_FIFO_SIZE = 4096;
        // Use to reduce niose, so gps isn't jumping around when asset is not moving
        const LOC_THRESHOLD    = 0.00030;

        HAL.PWR_GATE_EN.configure(DIGITAL_OUT, 1);
        HAL.GPS_UART.setrxfifosize(GPS_RX_FIFO_SIZE);
        // Configure UART
        HAL.GPS_UART.configure(GPS_BAUD_RATE, 8, PARITY_NONE, 1, NO_CTSRTS);
        // Ensure Pixhawk tx line is high and stable
        imp.sleep(0.5);

        // Pixhawk may not be in the correct mode when booted, send command
        // to configure GPS to send NMEA sentences
        // Note this doesn't change the boot state of the pixhawk, so will need
        // to be called on every boot if needed.
        if (configurePixHawk) {
            _sendPixhawkConfigCommand(HAL.GPS_UART, GPS_BAUD_RATE);
        }

        // Initialize GPS UART Driver
        local gpsOpts = { "gspDataReady" : _gpsHandler.bindenv(this),
                          "parseData"    : true,
                          "baudRate"     : GPS_BAUD_RATE };
        _gps = GPSUARTDriver(HAL.GPS_UART, gpsOpts);
    }

    // Returns a table with the last reported "lat" and "lng" and the time when data was last updated "ts"
    function getLocation() {
        return {"lat" : _lastLat, "lng" : _lastLng, "ts" : _locCheckedAt};
    }

    // Returns boolean if geofencing is enabled and there is enough location data to
    // calculate if device is inside designated area, otherwise returns null
    function inBounds() {
        return _inBounds;
    }

    // Enables geofencing given lat and lng center point, distance and callback
    function enableGeofence(distance, ctrLat, ctrLng, cb) {
        _distFromCtr = distance;
        _geofenceCB = cb;

        // use a hardcoded altitude, 30 meters
        local alt = 30.00;
        try {
            local lat = ctrLat.tofloat();
            local lng = ctrLng.tofloat();
            _gfCtr = _getCartesianCoods(lat, lng, alt);
        } catch(e) {
            server.error("Error configuring geofence coordinates: " + e);
        }

    }

    // Disables geofencing
    function disableGeofence() {
        _geofenceCB = null;
        _gfCtr = null;
        _distFromCtr = null;
        _inBounds = null;
    }

    // Handler to process incoming gps data from the GPSUARTDriver
    // Updates the latest lat, lng and time values (returned by getLocation)
    // If geofence is enabled checks if location geofencing
    function _gpsHandler(hasLoc, data) {
        // server.log(data);
        if (hasLoc) {
            // print(data);
            local lat = _gps.getLatitude();
            local lng = _gps.getLongitude();

            // Updated location if it has changed
            if (_locChanged(lat, lng) ) {
                _lastLat = lat;
                _lastLng = lng;
            }
            // Update location received timestamp
            _locCheckedAt = time();

            if ("sentenceId" in data && data.sentenceId == GPS_PARSER_GGA) {
                _checkGeofence(data);
            }

        } else if (!_gps.hasFix() && "numSatellites" in data) {
            // This will log a ton - use to debug only, not in application
            // server.log("GSV data received. Satellites: " + data.numSatellites);
        }
    }

    // Use location threshold to filter out noise when device is not moving
    function _locChanged(lat, lng) {
        local changed = false;

        if (_lastLat == null || _lastLng == null) {
            changed = true;
        } else {
            local latDiff = math.fabs(lat.tofloat() - _lastLat.tofloat());
            local lngDiff = math.fabs(lng.tofloat() - _lastLng.tofloat());
            if (latDiff > LOC_THRESHOLD) changed = true;
            if (lngDiff > LOC_THRESHOLD) changed = true;
        }
        return changed;
    }

    // Check if newCart location data with altitude, latitude, and longitude is within geofence boundries, update inBounds state
    // Trigger registered callback if device has just crossed boundry
    function _checkGeofence(data) {
        // Only calculate if geofence is enabled and we have altitude, latitude and longitude
        if (_geofenceCB == null && (!("altitude" in data) || !("latitude" in data) || !("longitude" in data))) return;

        local dist = _calculateDistance(data);

        if (dist != null) {
            // Check if we are inBounds
            local inBounds = (dist <= _distFromCtr);

            // Trigger callback if device has just crossed boundry
            if (inBounds != _inBounds) {
                _geofenceCB(inBounds);
            }

            // Track previous inBounds state, so we only trigger callback on a change
            _inBounds = inBounds;
        }
    }

    // Return distance from geofence center point if able to calculate
    function _calculateDistance(data) {
        try {
            local lat = data.latitude.tofloat();
            local lng = data.longitude.tofloat();
            local alt = data.altitude.tofloat();

            local newCart = _getCartesianCoods(lat, lng, alt);
            return math.sqrt((newCart.x - _gfCtr.x)*(newCart.x - _gfCtr.x) + (newCart.y - _gfCtr.y)*(newCart.y - _gfCtr.y) + (newCart.z - _gfCtr.z)*(newCart.z - _gfCtr.z));
        } catch(e) {
            // Couldn't calculate
            server.error("Error calculating distance: " + e);
            return;
        }
    }

    // Returns Cartesian Coordinates of given altitude, latitude, and longitude
    function _getCartesianCoods(lat, lng, alt) {
        local latRad = lat * PI / 180;
        local lngRad = lng * PI / 180;
        local cosLat = math.cos(latRad);
        local result = {};

        result.x <- alt * cosLat * math.sin(lngRad);
        result.y <- alt * math.sin(latRad);
        result.z <- alt * cosLat * math.cos(lngRad);

        return result;
    }

    function _sendPixhawkConfigCommand(uart, baudrate) {
        server.log("Configuring pixhawk...");

        // UBX CFG-PRT command values
        local header          = 0xb562;     // Not included in checksum
        local portConfigClass = 0x06;
        local portConfigId    = 0x00;
        local length          = 0x0014;
        local port            = 0x01;       // uart port
        local reserved1       = 0x00;
        local txReady         = 0x0000;     // txready not enabled
        local uartMode        = 0x000008c0; // mode 8 bit, no parity, 1 stop
        local brChars         = (baudrate > 57600) ? format("%c%c%c%c", baudrate, baudrate >> 8, baudrate >> 16, 0) : format("%c%c%c%c", baudrate, baudrate >> 8, 0, 0);
        local inproto         = 0x0003;     // inproto NMEA and UBX
        local outproto        = 0x0002;     // outproto NMEA
        local flags           = 0x0000;     // default timeout
        local reserved2       = 0x0000;

        // Assemble UBX payload
        local payload = format("%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c",
            portConfigClass,
            portConfigId,
            length,
            length >> 8,
            port,
            reserved1,
            txReady,
            txReady >> 8,
            uartMode,
            uartMode >> 8,
            uartMode >> 16,
            uartMode >> 24,
            brChars[0],
            brChars[1],
            brChars[2],
            brChars[3],
            inproto,
            inproto >> 8,
            outproto,
            outproto >> 8,
            flags,
            flags >> 8,
            reserved2,
            reserved2 >> 8);

        // Send UBX CFG-PRT (UBX formatted) to configure input NMEA mode
        uart.write(format("%c%c", header >> 8, header));
        uart.write(payload);
        uart.write(_calcUbxChecksum(payload));
        uart.flush();
        imp.sleep(1);

        // Assemble NMEA payload
        local nmeaCmd = format("$PUBX,41,%d,%04d,%04d,%04d,0*", port, inproto, outproto, baudrate);
        // Send UBX CFG-PRT (NMEA formatted) to configure input NMEA mode
        uart.write(nmeaCmd);
        uart.write(format("%02x", GPSParser._calcCheckSum(nmeaCmd)));
        uart.write("\r\n");
        uart.flush();
        imp.sleep(1);
    }

    function _calcUbxChecksum(pkt) {
        local cka=0, ckb=0;
        foreach(a in pkt) {
            cka += a;
            ckb += cka;
        }
        cka = cka&0xff;
        ckb = ckb&0xff;

        return format("%c%c", cka, ckb);
    }

}