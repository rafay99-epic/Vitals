#ifndef PRIVATE_SENSORS_H
#define PRIVATE_SENSORS_H

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <libproc.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// The HID event-system client is public API, but reading an event's value is
// not. These private declarations (stable for years, used by every open-source
// macOS monitor) read the temperature sensor events on Apple Silicon.
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
// AppleSMC parameter struct. Defined in C so the layout matches what the
// kernel driver expects exactly.
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
#define VITALS_SMC_CMD_WRITE_KEY 6
#define VITALS_SMC_CMD_GET_KEY_INFO 9

// ---------------------------------------------------------------------------
// SoC power via IOReport's "Energy Model" group, the same accounting
// `powermetrics` uses, without root. IOReport has no link-time stub, so it is
// resolved with dlopen at runtime; failure means "unavailable", not a crash.
// Watts = energy-counter delta between two reads / elapsed time. Each channel
// carries its own unit label (mJ / uJ / nJ), which is honoured exactly.
// ---------------------------------------------------------------------------

typedef struct {
    int    valid;       // 0 on the first sample and when IOReport is missing
    double cpu_watts;   // CPU rail (E+P clusters), 0 if the channel is absent
    double gpu_watts;   // GPU rail
    double ane_watts;   // Apple Neural Engine rail
} VitalsSoCPower;

// Returns an opaque handle, or NULL if IOReport is unavailable. Create once and
// reuse: the subscription and previous sample live inside the handle.
void *_Nullable vitals_socpower_create(void);

// Returns 1 and fills `out` when a delta was measured, 0 otherwise.
int vitals_socpower_sample(void *_Nonnull handle, VitalsSoCPower *_Nonnull out);

// Releases the subscription and any retained samples.
void vitals_socpower_destroy(void *_Nullable handle);

// ---------------------------------------------------------------------------
// NVMe SMART health log via the IOKit NVMe SMART user client. Layout comes from
// Apple's SDK header (NVMeSMARTLibExternal.h). Read-only, no root. The device is
// found by the public "NVMe SMART Capable" property (class-agnostic, as the
// header recommends). All CF/IOKit ownership stays in C. The 128-bit NVMe
// counters are returned as their low 64 bits.
// ---------------------------------------------------------------------------

typedef struct {
    int      valid;                     // 1 when the SMART log was read
    uint8_t  critical_warning;          // bitfield; 0 = healthy
    uint16_t temperature_k;             // composite temperature, in Kelvin
    uint8_t  available_spare;           // % remaining
    uint8_t  available_spare_threshold; // % at which the drive warns
    uint8_t  percentage_used;           // wear estimate, can exceed 100
    uint64_t data_units_written;        // × 512000 = bytes
    uint64_t data_units_read;
    uint64_t power_cycles;
    uint64_t power_on_hours;
    uint64_t unsafe_shutdowns;
    uint64_t media_errors;
    // TRIM is not a SMART field: it comes from the Identify Controller ONCS
    // bitfield. `trim_known` is 0 when the drive refused Identify.
    uint8_t  trim_known;                // 1 when Identify Controller was read
    uint8_t  trim_supported;            // 1 when ONCS bit 2 (Dataset Management) is set
} VitalsDiskSMART;

// Returns 1 and fills `out` on success, 0 when there's no SMART-capable device
// or the read failed. One user-client call.
int vitals_nvme_smart_read(VitalsDiskSMART *_Nonnull out);

// ---------------------------------------------------------------------------
// Crash capture for SIGSEGV, SIGABRT, SIGILL, SIGTRAP, SIGFPE, SIGBUS. In C
// because a signal handler must be async-signal-safe, which rules out Swift
// strings, JSON, and malloc.
//
// On a fatal signal the handler appends a plain-text block (a marker line naming
// the signal, then raw return addresses) to `log_path`, restores the default
// disposition, and re-raises so the OS still writes its own crash report. The
// block is not JSON; LogExport and CrashReporter find it by its markers.
//
// `log_path` is copied internally. Call once, only from the GUI process (never
// the `--fan-daemon` path or a CLI invocation).
void vitals_install_crash_handlers(const char *_Nonnull log_path);

#endif
