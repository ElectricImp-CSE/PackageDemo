HAL <- {
    "NAME"            : "impC001-breakout",
    "VERSION"         : "rev3.0",

    "LED_SPI"         : hardware.spiYJTHU,

    "PWR_GATE_EN"     : hardware.pinYF,

    "SENSOR_I2C"      : hardware.i2cXDC,
    "ACCEL_ADDR"      : 0x32,
    "TEMP_HUMID_ADDR" : 0xBE,
    "ACCEL_INT"       : hardware.pinT,

    "GPS_UART"        : hardware.uartHJKL,

    "USB_EN"          : hardware.pinYM,
    "USB_LOAD_FLAG"   : hardware.pinYN,

    "GROVE_I2C"       : hardware.i2cXDC,
    "GROVE_AD1"       : hardware.pinYP,
    "GROVE_AD2"       : hardware.pinYQ,

    // NOTE: configure gps TX input with pullup before configuring uart (pixhawk limitation)
}