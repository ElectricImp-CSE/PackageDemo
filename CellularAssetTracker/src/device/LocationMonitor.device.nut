class LocationMonitor {

    _gps          = null;

    _lastLat      = null;
    _lastLng      = null;
    _locCheckedAt = null;

    _geofenceCB   = null;
    _gfCtr        = null;
    _distFromCtr  = null;
    _inBounds     = null;

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
        local gpsOpts = { "gspDataReady" : gpsHandler.bindenv(this),
                          "parseData"    : true,
                          "baudRate"     : GPS_BAUD_RATE };
        _gps = GPSUARTDriver(HAL.GPS_UART, gpsOpts);
    }

    function getLocation() {
        return {"lat" : _lastLat, "lng" : _lastLng, "ts" : _locCheckedAt};
    }

    function gpsHandler(hasLoc, data) {
        // server.log(data);
        if (hasLoc) {
            // print(data);
            local lat = _gps.getLatitude();
            local lng = _gps.getLongitude();

            // Updated location if it has changed
            if (locChanged(lat, lng) ) {
                _lastLat = lat;
                _lastLng = lng;
            }
            // Update location received timestamp
            _locCheckedAt = time();

            if ("sentenceId" in data && data.sentenceId == GPS_PARSER_GGA) {
                calculateDistance(data);
            }

        } else if (!_gps.hasFix() && "numSatellites" in data) {
            // This will log a ton - use to debug only, not in application
            // server.log("GSV data received. Satellites: " + data.numSatellites);
        }
    }

    function inBounds() {
        return _inBounds;
    }

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

    function disableGeofence() {
        _geofenceCB = null;
        _gfCtr = null;
        _distFromCtr = null;
        _inBounds = null;
    }

    // Use location threshold to filter out noise when not moving
    function locChanged(lat, lng) {
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

    function calculateDistance(data) {
        // Only calculate if we have altitude, latitude and longitude
        if (!("altitude" in data) || !("latitude" in data) || !("longitude" in data)) return;

        try {
            local lat = data.latitude.tofloat();
            local lng = data.longitude.tofloat();
            local alt = data.altitude.tofloat();

            local new  = _getCartesianCoods(lat, lng, alt);
            local dist = math.sqrt((new.x - _gfCtr.x)*(new.x - _gfCtr.x) + (new.y - _gfCtr.y)*(new.y - _gfCtr.y) + (new.z - _gfCtr.z)*(new.z - _gfCtr.z));

            // server.log("New distance: " + dist + " M");
            local inBounds = (dist <= _distFromCtr);
            if (_geofenceCB != null && inBounds != _inBounds) {
                _geofenceCB(inBounds);
            }
            // Track previous state, so we only trigger callback on a change
            _inBounds = inBounds;
        } catch (e) {
            // Couldn't calculate
            server.error("Error calculating distance: " + e);
        }
    }

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