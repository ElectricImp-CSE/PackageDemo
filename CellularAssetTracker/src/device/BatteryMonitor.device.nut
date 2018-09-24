class BatteryMonitor {

    _charger        = null;
    _fuelGauge      = null;
    _fuelGaugeReady = null;

    constructor(configureI2C = false) {
        if (configureI2C) HAL.SENSOR_I2C.configure(I2C_CLOCK_SPEED);
        _charger   = BQ25895M(HAL.SENSOR_I2C, HAL.BATT_CHGR_ADDR);
        _fuelGauge = MAX17055(HAL.SENSOR_I2C, HAL.FUEL_GAUGE_ADDR);

        _fuelGaugeReady = false;
        local fgSettings = {
            "desCap"       : 2000, // mAh
            "senseRes"     : 0.01, // ohms
            "chrgTerm"     : 20,   // mA
            "emptyVTarget" : 3.3,  // V
            "recoveryV"    : 3.88, // V
            "chrgV"        : MAX17055_V_CHRG_4_2,
            "battType"     : MAX17055_BATT_TYPE.LiCoO2
        }

        _charger.enable(4.2, 2000);
        _fuelGauge.init(fgSettings, _initHandler.bindenv(this));
    }

    function getChargeStatus() {
        return (_fuelGaugeReady) ? _fuelGauge.getStateOfCharge() : null;
    }

    function _initHandler(err) {
        if (err != null) {
            server.log("Fuel gauge init error: " + err);
        } else {
            server.log("Fuel gauge initialized.");
            _fuelGaugeReady = true;
        }
    }

}