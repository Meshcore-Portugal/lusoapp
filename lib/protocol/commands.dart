/// MeshCore Companion Radio Protocol — command and response codes.
///
/// These map to the companion radio serial protocol used over
/// Serial/BLE/WiFi between the app and a MeshCore radio.
library;

// ---------------------------------------------------------------------------
// Direction markers
// ---------------------------------------------------------------------------

/// App → Radio direction byte.
const int dirAppToRadio = 0x3C; // '<'

/// Radio → App direction byte.
const int dirRadioToApp = 0x3E; // '>'

// ---------------------------------------------------------------------------
// App → Radio commands
// ---------------------------------------------------------------------------

const int cmdAppStart = 0x01;
const int cmdSendMsg = 0x02;
const int cmdSendChanMsg = 0x03;
const int cmdGetContacts = 0x04;
const int cmdGetDeviceTime = 0x05;
const int cmdSetDeviceTime = 0x06;
const int cmdSendAdvert = 0x07;
const int cmdSetAdvertName = 0x08;
const int cmdAddUpdateContact = 0x09;
const int cmdSyncNext = 0x0A;
const int cmdSetRadioParams = 0x0B;
const int cmdSetTxPower = 0x0C;
const int cmdResetPath = 0x0D;
const int cmdSetAdvertLatLon = 0x0E;
const int cmdRemoveContact = 0x0F;
const int cmdShareContact = 0x10;
const int cmdExportContact = 0x11;
const int cmdImportContact = 0x12;
const int cmdReboot = 0x13;
const int cmdGetBattAndStorage = 0x14;
const int cmdSetTuningParams = 0x15;
const int cmdDeviceQuery = 0x16;
const int cmdSendLogin = 0x1A;
const int cmdSendStatusReq = 0x1B;
const int cmdGetByKey = 0x1E;
const int cmdGetChannel = 0x1F;
const int cmdSetChannel = 0x20;
const int cmdSignData = 0x22;
const int cmdSignFinish = 0x23;
const int cmdSendTracePath = 0x24;
const int cmdSendTelemetryReq = 0x27;
const int cmdSendBinaryReq = 0x32;
const int cmdSendPathDiscoveryReq = 0x34;
const int cmdSendControlData = 0x37;
const int cmdGetStats = 0x38;

// ---------------------------------------------------------------------------
// CMD_GET_STATS sub-types
// ---------------------------------------------------------------------------

/// Core device statistics: battery, uptime, errors, queue length.
const int statsTypeCore = 0;

/// Radio statistics: noise floor, RSSI, SNR, TX/RX airtime.
const int statsTypeRadio = 1;

/// Packet counters: received, sent, flood/direct breakdown, receive errors.
const int statsTypePackets = 2;

// ---------------------------------------------------------------------------
// Radio → App responses
// ---------------------------------------------------------------------------

const int respOk = 0x00;
const int respErr = 0x01;
const int respContactsStart = 0x02;
const int respContact = 0x03;
const int respEndContacts = 0x04;
const int respSelfInfo = 0x05;
const int respSent = 0x06;
const int respContactMsgRecv = 0x07;
const int respChannelMsgRecv = 0x08;
const int respCurrTime = 0x09;
const int respNoMoreMessages = 0x0A;
const int respBattAndStorage = 0x0C;
const int respDeviceInfo = 0x0D;
const int respContactMsgRecvV3 = 0x10;
const int respChannelMsgRecvV3 = 0x11;
const int respChannelInfo = 0x12;
const int respSignature = 0x14;
const int respStats = 0x18;

// ---------------------------------------------------------------------------
// Unsolicited push codes (Radio → App)
// ---------------------------------------------------------------------------

const int pushAdvert = 0x80;
const int pushPathUpdated = 0x81;
const int pushSendConfirmed = 0x82;
const int pushMsgWaiting = 0x83;
const int pushRawData = 0x84;
const int pushLoginSuccess = 0x85;
const int pushLoginFail = 0x86;
const int pushStatusResponse = 0x87;
const int pushLogRxData = 0x88;
const int pushTraceData = 0x89;
const int pushNewAdvert = 0x8A;
const int pushTelemetryResponse = 0x8B;
const int pushBinaryResponse = 0x8C;
const int pushPathDiscoveryResponse = 0x8D;
const int pushControlData = 0x8E;
const int pushContactDeleted = 0x8F;
const int pushContactsFull = 0x90;

// ---------------------------------------------------------------------------
// Contact / Advert types
// ---------------------------------------------------------------------------

const int advTypeNone = 0x00;
const int advTypeChat = 0x01;
const int advTypeRepeater = 0x02;
const int advTypeRoom = 0x03;
const int advTypeSensor = 0x04;

// ---------------------------------------------------------------------------
// Max frame payload
// ---------------------------------------------------------------------------

const int maxPayload = 172;

// ---------------------------------------------------------------------------
// Text type indicator (first byte of message payload)
// ---------------------------------------------------------------------------

const int txtPlain = 0x00;
