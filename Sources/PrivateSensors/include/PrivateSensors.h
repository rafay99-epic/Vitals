#ifndef PRIVATE_SENSORS_H
#define PRIVATE_SENSORS_H

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <libproc.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// The HID event-system client is public API, but reading an event's value is
// not. These three declarations (stable for years, used by every open-source
// macOS monitor) are the only private surface we touch — they let us read the
// temperature sensor events on Apple Silicon.
// ---------------------------------------------------------------------------

typedef struct CF_BRIDGED_TYPE(id) __IOHIDEvent * IOHIDEventRef;

// The simple client from the public header cannot see the AppleVendor sensor
// services; only a full client created this way (with matching) can.
IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator) CF_RETURNS_RETAINED;
void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef _Nonnull client, CFDictionaryRef _Nonnull match);

IOHIDEventRef _Nullable IOHIDServiceClientCopyEvent(IOHIDServiceClientRef _Nonnull service, int64_t type, int32_t options, int64_t timestamp) CF_RETURNS_RETAINED;
double IOHIDEventGetFloatValue(IOHIDEventRef _Nonnull event, int32_t field);

// kIOHIDEventTypeTemperature; the float value field is (type << 16).
#define VITALS_HID_EVENT_TEMPERATURE 15
#define VITALS_HID_USAGE_PAGE_APPLE_VENDOR 0xff00
#define VITALS_HID_USAGE_TEMPERATURE_SENSOR 5

// ---------------------------------------------------------------------------
// AppleSMC parameter struct (fan speeds etc.). Defined here in C so the
// memory layout matches what the kernel driver expects exactly.
// ---------------------------------------------------------------------------

typedef struct {
    uint8_t  major;
    uint8_t  minor;
    uint8_t  build;
    uint8_t  reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t       key;
    SMCVersion     vers;
    SMCPLimitData  pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t        result;
    uint8_t        status;
    uint8_t        data8;
    uint32_t       data32;
    uint8_t        bytes[32];
} SMCParamStruct;

#define VITALS_SMC_SELECTOR_YPC_EVENT 2
#define VITALS_SMC_CMD_READ_KEY 5
#define VITALS_SMC_CMD_GET_KEY_INFO 9

#endif
