class MovementMonitor {

    _accel             = null;
    _movementThresh    = null;
    _lastMag           = null;
    _movementCB        = null;
    _isMoving          = null;

    // Configure class constants
    function _statics_() {
        const DEFAULT_MOVEMENT_THRESHOLD = 0.1;
        const ACCEL_DATA_RATE            = 100;
        // How often to check for movement when device is still
        const STILL_CHECK_SEC            = 0.05;
        // How often to check for movement when device is in motion
        const MOVING_CHECK_SEC           = 3;
        const ACCEL_INT_DURATION         = 5;
    }

    constructor(configureI2C = false) {
        if (configureI2C) HAL.SENSOR_I2C.configure(I2C_CLOCK_SPEED);
        _accel = LIS3DH(HAL.SENSOR_I2C, HAL.ACCEL_ADDR);
        _accel.setDataRate(ACCEL_DATA_RATE);

        _isMoving = false;
        if (_movementThresh == null) _movementThresh = DEFAULT_MOVEMENT_THRESHOLD;
    }

    function takeReading() {
        return Promise(function(resolve, reject) {
            // Get an accel reading and calculate magnitude
            _accel.getAccel(function(result) {
                local mag = null;
                if (!("error" in result)) mag = calculateMagnitude(result);
                return resolve({"magnitude" : mag, "isMoving" : _isMoving});
            }.bindenv(this))
        }.bindenv(this))
    }

    function setThreshold(newThreshold) {
        _movementThresh = newThreshold;
    }

    function setMovementHandler(handler) {
        _movementCB = handler;
    }

    function calculateMagnitude(reading) {
        return math.sqrt(reading.x*reading.x + reading.y*reading.y + reading.z*reading.z);
    }

    // To be used if interrupt is not configured to detect movement
    function startMovementChecker() {
        local movementCheckTime = STILL_CHECK_SEC;
        takeReading()
            .then(function(results) {
                local msg = "No movement handler registered/accel data encountered an error, movement not checked.";
                if (_movementCB != null && results.magnitude != null) {
                    // We have a reading update movement state
                    _isMoving = checkMovement(results.magnitude);
                    // Current movement state is different than previous state
                    // Trigger alert callback
                    if (results.isMoving != _isMoving) {
                        _movementCB(_isMoving, results.magnitude);
                    }

                    // Update debug message
                    if (_isMoving) {
                        msg = "Device moving";
                        // Wait longer between movement checks if we detect movement
                        movementCheckTime = MOVING_CHECK_SEC;
                    } else {
                        msg = "Device still";
                    }
                }
                return msg;
            }.bindenv(this))
            .finally(function(msg) {
                // // This log is overwhelming, so leave commented out unless debugging!!!
                // server.log(msg)
                // Schedule the next check
                imp.wakeup(movementCheckTime, startMovementChecker.bindenv(this));
            }.bindenv(this));
    }

    function enableInterrupt(enable) {
        // Configure interrupt pin
        // HAL.ACCEL_INT.configure(DIGITAL_IN_WAKEUP, intHandler.bindenv(this)); // not a wake pin???
        HAL.ACCEL_INT.configure(DIGITAL_IN, intHandler.bindenv(this));
        _accel.configureInterruptLatching(true);
        // TODO: configure interrupt to detect movemnt (this is not the way to do it!!)
        // Configure Accel interrupt
        // local opts = LIS3DH_X_HIGH | LIS3DH_Y_HIGH | LIS3DH_Z_HIGH;
        // _accel.configureInertialInterrupt(enable, _movementThresh, ACCEL_INT_DURATION, opts);
        _accel.getInterruptTable();
    }

    function intHandler() {
        local pinState = HAL.ACCEL_INT.read();
        // server.log("In intHandler: " + pinState);
        // TODO: Check this conditional works on wake from sleep
        if (pinState == 0) return;
        // Clear interrupt
        local intResults = _accel.getInterruptTable();
        if (_movementCB != null) _movementCB(MOVEMENT_ALERT);
    }

    function checkMovement(newMag) {
        if (_lastMag == null) _lastMag = newMag;

        local isMoving = (_lastMag > (newMag + _movementThresh) || _lastMag < (newMag - _movementThresh));
        _lastMag = newMag;

        return isMoving;
    }
}