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
#define VITALS_SMC_CMD_WRITE_KEY 6
#define VITALS_SMC_CMD_GET_KEY_INFO 9

// ---------------------------------------------------------------------------
// SoC power, via IOReport's "Energy Model" group. IOReport is a private
// framework with no link-time stub, so we resolve it with dlopen at runtime
// (see shim.c) — if that fails, sampling reports "unavailable" rather than
// crashing. The model accumulates per-rail energy counters; we sample the
// delta between two reads and divide by the elapsed wall time to get watts.
// Each channel carries its own unit label (mJ / uJ / nJ), honoured exactly so
// the watt figures are real, never assumed. CPU/GPU/ANE are the aggregate SoC
// rails — the same accounting `powermetrics` reports, with no root required.
//
// Every field below is filled only when a real delta was measured; `valid`
// stays 0 on the first sample (no prior counter to diff against) and whenever
// IOReport is missing, so callers can render an honest "—".
// ---------------------------------------------------------------------------

typedef struct {
    int    valid;       // 1 once a delta has been computed
    double cpu_watts;   // CPU rail (E+P clusters), 0 if the channel is absent
    double gpu_watts;   // GPU rail
    double ane_watts;   // Apple Neural Engine rail
} VitalsSoCPower;

// Opens an IOReport subscription on the Energy Model. Returns an opaque handle,
// or NULL if IOReport is unavailable. Create once and reuse — the subscription
// and the previous sample live inside the handle.
void *_Nullable vitals_socpower_create(void);

// Samples the rails since the previous call. Returns 1 and fills `out` when a
// delta was measured, 0 otherwise (first call, or unavailable). Cheap: one
// IOReport sample plus a dictionary diff.
int vitals_socpower_sample(void *_Nonnull handle, VitalsSoCPower *_Nonnull out);

// Releases the subscription and any retained samples.
void vitals_socpower_destroy(void *_Nullable handle);

// ---------------------------------------------------------------------------
// NVMe SSD SMART (the drive's Health Information log), via the IOKit NVMe SMART
// user client. The interface, UUIDs and data struct come from Apple's own SDK
// header (NVMeSMARTLibExternal.h), so the layout is exact — no guessing. The
// read is read-only and needs no root. The device is found by the public
// "NVMe SMART Capable" IORegistry property (class-agnostic, as Apple's header
// recommends), so it degrades honestly to `valid == 0` on a Mac/VM that doesn't
// expose it. All CoreFoundation/IOKit ownership stays in C; Swift sees only
// plain scalars. The 128-bit NVMe counters are returned as their low 64 bits
// (the real magnitude for these fields). One data unit = 512000 bytes.
// ---------------------------------------------------------------------------

typedef struct {
    int      valid;                     // 1 when the SMART log was read
    uint8_t  critical_warning;          // bitfield; 0 = healthy
    uint16_t temperature_k;             // composite temperature, in Kelvin
    uint8_t  available_spare;           // % remaining
    uint8_t  available_spare_threshold; // % at which the drive warns
    uint8_t  percentage_used;           // wear — the drive's own estimate (0–100+)
    uint64_t data_units_written;        // × 512000 = total bytes written (endurance)
    uint64_t data_units_read;
    uint64_t power_cycles;
    uint64_t power_on_hours;
    uint64_t unsafe_shutdowns;
    uint64_t media_errors;
    // TRIM (NVMe Dataset Management / Deallocate) support. This is NOT a SMART
    // field — it comes from the Identify Controller ONCS bitfield, the same
    // source system_profiler reports "TRIM Support" from. Read on the same user
    // client after the SMART log. `trim_known` is 0 when the drive/VM refused the
    // Identify command, so the caller shows "Unknown" rather than guessing "No".
    uint8_t  trim_known;                // 1 when Identify Controller was read
    uint8_t  trim_supported;            // 1 when ONCS bit 2 (Dataset Management) is set
    uint16_t oncs;                      // raw Optional NVM Command Support bitfield
} VitalsDiskSMART;

// Reads the internal SSD's SMART health log. Returns 1 and fills `out` on
// success, 0 otherwise (no SMART-capable device, or the read failed). Cheap
// (a single user-client call), but call infrequently — SMART changes over days.
int vitals_nvme_smart_read(VitalsDiskSMART *_Nonnull out);

// ---------------------------------------------------------------------------
// Crash capture. Installs handlers for the fatal signals (SIGSEGV, SIGABRT,
// SIGILL, SIGTRAP, SIGFPE, SIGBUS). Implemented in C because a signal handler
// must be async-signal-safe — it can only call a small allow-list of functions
// (open/write/backtrace_symbols_fd), which rules out Swift String/JSON/malloc.
//
// On a fatal signal the handler appends a plain-text crash block (a marker line
// naming the signal, then the symbolicated backtrace) to `log_path`, restores
// the default disposition, and re-raises so the OS still produces its own crash
// report. The block is intentionally NOT JSON — the in-app console skips it, but
// it travels in the emailed log so the backtrace reaches the developer. On the
// next launch Swift scans for the marker and surfaces a readable fault entry.
//
// `log_path` is copied internally; pass the resolved vitals.log path. Call once,
// only from the GUI process (never the fan daemon or a CLI invocation).
void vitals_install_crash_handlers(const char *_Nonnull log_path);

#endif
