// Message Manager Msg Names
const MM_GET_SETTINGS    = "getSettings";
const MM_UPDATE_SETTINGS = "updateSettings";
const MM_LOCATE          = "locate";
const MM_SEND_DATA       = "sendData";

// Shared Agent/Device Table Keys
// Reading table
const READINGS                 = "r";
const READING_TS               = "ts";
const READING_TEMP             = "temp";
const READING_HUMID            = "humid";
const READING_MAG              = "mag";
const READING_LAT              = "lat";
const READING_LNG              = "lng";
const READING_LX               = "lx";
const DEV_STATE_IS_LIGHT       = "isLight";
const DEV_STATE_TEMP_IN_RANGE  = "tInRange";
const DEV_STATE_HUMID_IN_RANGE = "hInRange";
const DEV_STATE_IS_MOVING      = "isMoving";
// Alerts table
const ALERTS                   = "a";
const ALERT_TEMP               = "tAlert";
const ALERT_HUMID              = "hAlert";
const ALERT_MOVE               = "mAlert";
const ALERT_LIGHT              = "lxAlert";
const ALERT_TYPE               = "type";
const ALERT_DESCRIPTION        = "description";
const ALERT_TRIGGER            = "trigger";
const ALERT_CREATED            = "created";
const ALERT_RESOLVED           = "resolved";
// Threshold settings table
const THRESH_TEMP_HIGH  = "tempHigh";
const THRESH_TEMP_LOW   = "tempLow";
const THRESH_HUMID_HIGH = "humidHigh";
const THRESH_HUMID_LOW  = "humidLow";
const THRESH_MOVEMENT   = "movementThresh";
const REPORTING_INT     = "reportingInt";

// Alert type identifiers
enum ALERT_TYPE_ID {
    TEMP_HIGH,
    TEMP_LOW,
    HUMID_HIGH,
    HUMID_LOW,
    MOVE,
    LIGHT
}