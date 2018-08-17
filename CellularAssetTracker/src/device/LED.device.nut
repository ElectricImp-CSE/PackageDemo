class LED {

    function __statics__() {
        const NUM_BLINKS_DEFAULT = 5;
        const BRIGHTNESS_DEFAULT = 50;
        const BLINK_RATE_DEFAULT = 0.5;
    }

    static RED    = [BRIGHTNESS_DEFAULT, 0, 0];
    static GREEN  = [0, BRIGHTNESS_DEFAULT, 0];
    static BLUE   = [0, 0, BRIGHTNESS_DEFAULT];
    static YELLOW = [BRIGHTNESS_DEFAULT, BRIGHTNESS_DEFAULT, 0];
    static WHITE  = [BRIGHTNESS_DEFAULT, BRIGHTNESS_DEFAULT, BRIGHTNESS_DEFAULT];
    static OFF    = [0, 0, 0];


    _led          = null;
    _blinkTimer   = null;

    constructor() {
        _led = APA102(HAL.LED_SPI, 1).configure().draw();
    }

    function on(color) {
        _led.fill(color).draw();
    }

    function off() {
        on(OFF);
    }

    function blink(color, numBlinks = null) {
        if (numBlinks == null) {
            numBlinks = NUM_BLINKS_DEFAULT;
        } else if (numBlinks == 0) {
            stopBlink();
            return;
        }

        // Make sure we only have one timer at a time
        if (_blinkTimer != null) {
            stopBlink();
        }

        on(color);
        _blinkTimer = imp.wakeup(BLINK_RATE_DEFAULT, function() {
            off();
            _blinkTimer = imp.wakeup(BLINK_RATE_DEFAULT, function() {
                _blinkTimer = null;
                blink(color, --numBlinks);
            }.bindenv(this))
        }.bindenv(this))
    }

    function stopBlink() {
        if (_blinkTimer != null) {
            imp.cancelwakeup(_blinkTimer);
            _blinkTimer = null;
        }
    }

}