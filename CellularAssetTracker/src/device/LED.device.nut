enum LED_BLINK_RATE {
    NORMAL,
    SLOW
}

class LED {

    function __statics__() {
        const BRIGHTNESS_DEFAULT  = 50;
        const DEFAULT_NUM_LEDS    = 61;

        const BLINK_RATE_DEFAULT  = 0.5;
        const BLINK_RATE_SLOW_ON  = 0.25;   // TB
        const BLINK_RATE_SLOW_OFF = 3;      // TB
    }

    static RED    = [BRIGHTNESS_DEFAULT, 0, 0];
    static GREEN  = [0, BRIGHTNESS_DEFAULT, 0];
    static BLUE   = [0, 0, BRIGHTNESS_DEFAULT];
    static YELLOW = [BRIGHTNESS_DEFAULT, BRIGHTNESS_DEFAULT, 0];
    static WHITE  = [BRIGHTNESS_DEFAULT, BRIGHTNESS_DEFAULT, BRIGHTNESS_DEFAULT];
    static OFF    = [0, 0, 0];

    _led          = null;
    _blinkTimer   = null;

    constructor(numLEDs = null) {
        if (numLEDs == null) numLEDs = DEFAULT_NUM_LEDS;
        _led = APA102(HAL.LED_SPI, numLEDs).configure().draw();
    }

    function on(color) {
        _led.fill(color).draw();
    }

    function off() {
        on(OFF);
    }

    function isBlinking() {
        return (_blinkTimer != null);
    }

    function blink(color, rate = LED_BLINK_RATE.NORMAL, numBlinks = null) {
        if (numBlinks == 0) {
            stopBlink();
            return;
        }

        // Set normal blink rate
        local onTime  = BLINK_RATE_DEFAULT;
        local offTime = BLINK_RATE_DEFAULT;

        // Update if rate is set to slow
        if (rate == LED_BLINK_RATE.SLOW) {
            onTime = BLINK_RATE_SLOW_ON;
            offTime = BLINK_RATE_SLOW_OFF;
        }

        // Make sure we only have one timer at a time
        if (_blinkTimer != null) {
            stopBlink();
        }

        // Toggle on then off, decrease numBlinks if needed
        on(color);
        _blinkTimer = imp.wakeup(onTime, function() {
            off();
            _blinkTimer = imp.wakeup(offTime, function() {
                _blinkTimer = null;
                if (numBlinks != null) --numBlinks;
                blink(color, rate, numBlinks);
            }.bindenv(this))
        }.bindenv(this))
    }

    function stopBlink() {
        if (_blinkTimer != null) {
            imp.cancelwakeup(_blinkTimer);
            _blinkTimer = null;
        }
        off();
    }

}