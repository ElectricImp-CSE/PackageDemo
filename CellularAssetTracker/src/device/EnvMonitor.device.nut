class EnvMonitor {

    _th    = null;

    _tempThreshHigh  = null;
    _tempThreshLow   = null;
    _humidThreshHigh = null;
    _humidThreshLow  = null;

    // Configure class constants
    function _statics_() {
        const DEFAULT_TEMP_THRESHOLD_HIGH  = 8.8;
        const DEFAULT_TEMP_THRESHOLD_LOW   = -20;
        const DEFAULT_HUMID_THRESHOLD_HIGH = 60;
        const DEFAULT_HUMID_THRESHOLD_LOW  = 0;
        const DEFAULT_LX_THRESHOLD         = 3000;
        const NUM_LX_READS                 = 5;
        const LX_READ_TIMER_SEC            = 0.05;
    }

    constructor(configureI2C = false) {
        if (configureI2C) HAL.SENSOR_I2C.configure(I2C_CLOCK_SPEED);
        _th = HTS221(HAL.SENSOR_I2C, HAL.TEMP_HUMID_ADDR);
        _th.setMode(HTS221_MODE.ONE_SHOT);

        if (_tempThreshHigh == null)  _tempThreshHigh  = DEFAULT_TEMP_THRESHOLD_HIGH;
        if (_tempThreshLow == null)   _tempThreshLow   = DEFAULT_TEMP_THRESHOLD_LOW;
        if (_humidThreshHigh == null) _humidThreshHigh = DEFAULT_HUMID_THRESHOLD_HIGH;
        if (_humidThreshLow == null)  _humidThreshLow  = DEFAULT_HUMID_THRESHOLD_LOW;
    }

    function setThresholds(thresholds) {
        if (THRESH_TEMP_HIGH in thresholds)  _tempThreshHigh  = thresholds[THRESH_TEMP_HIGH];
        if (THRESH_TEMP_LOW in thresholds)   _tempThreshLow   = thresholds[THRESH_TEMP_LOW];
        if (THRESH_HUMID_HIGH in thresholds) _humidThreshHigh = thresholds[THRESH_HUMID_HIGH];
        if (THRESH_HUMID_LOW in thresholds)  _humidThreshLow  = thresholds[THRESH_HUMID_LOW];
    }

    function takeTempHumidReading() {
        return Promise(function(resolve, reject) {
            _th.read(function(result) {
                return resolve(result);
            }.bindenv(this))
        }.bindenv(this))
    }

    function takeLightReading() {
        return Promise(function(resolve, reject) {
            _readLightLevel(NUM_LX_READS, 0, function(result) {
                return resolve({"lxLevel" : result, "isLight" : (result > DEFAULT_LX_THRESHOLD)});
            }.bindenv(this))
        }.bindenv(this))
    }

    function checkTemp(temp) {
        local alert = null;
        if (temp > _tempThreshHigh) alert = ALERT_TYPE_ID.TEMP_HIGH;
        if (temp < _tempThreshLow)  alert = ALERT_TYPE_ID.TEMP_LOW;
        return alert;
    }

    function checkHumid(humid) {
        local alert = null;
        if (humid > _humidThreshHigh) alert = ALERT_TYPE_ID.HUMID_HIGH;
        if (humid < _humidThreshLow)  alert = ALERT_TYPE_ID.HUMID_LOW;
        return alert;
    }

    function _readLightLevel(numSamples, total, cb) {
        // Take another reading
        total += hardware.lightlevel();

        if (--numSamples == 0) {
            // End loop and pass average reading to callback
            cb(total / NUM_LX_READS);
        } else {
            // Schedule next reading
            imp.wakeup(LX_READ_TIMER_SEC, function() {
                _readLightLevel(numSamples, total, cb);
            }.bindenv(this))
        }
    }
}