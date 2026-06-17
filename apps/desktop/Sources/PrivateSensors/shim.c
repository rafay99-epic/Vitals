#include "include/PrivateSensors.h"
// HID + SMC declarations are provided by IOKit.framework at link time.

// ---------------------------------------------------------------------------
// IOReport "Energy Model" power sampling.
//
// IOReport ships no link-time stub, so it is resolved with dlopen at runtime.
// All CoreFoundation ownership lives here in C — the handle retains exactly the
// subscription, the subscribed-channel dictionary, and the previous sample, and
// releases them in destroy(). Swift only ever sees plain doubles.
// ---------------------------------------------------------------------------

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct IOReportSubscriptionRefOpaque *IOReportSubscriptionRef;

typedef CFMutableDictionaryRef (*copy_channels_fn)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
typedef IOReportSubscriptionRef (*create_subscription_fn)(void *, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*create_samples_fn)(IOReportSubscriptionRef, CFMutableDictionaryRef, CFTypeRef);
typedef CFDictionaryRef (*create_delta_fn)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef void (*iterate_fn)(CFDictionaryRef, int (^)(CFDictionaryRef));
typedef CFStringRef (*channel_name_fn)(CFDictionaryRef);
typedef int64_t (*simple_value_fn)(CFDictionaryRef, int);

typedef struct {
    create_samples_fn      create_samples;
    create_delta_fn        create_delta;
    iterate_fn             iterate;
    channel_name_fn        get_name;
    channel_name_fn        get_unit;
    simple_value_fn        get_value;
    IOReportSubscriptionRef subscription;
    CFMutableDictionaryRef  channels;     // subscribed channels, reused every sample
    CFDictionaryRef         previous;     // last full sample (energy counters)
    uint64_t                previous_ns;  // when `previous` was taken
} SoCPowerHandle;

static uint64_t now_ns(void) {
    return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
}

void *vitals_socpower_create(void) {
    // The symbols live in libIOReport.dylib (not a standalone framework on disk).
    void *lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW);
    if (!lib) return NULL;

    copy_channels_fn        copy_channels      = (copy_channels_fn)        dlsym(lib, "IOReportCopyChannelsInGroup");
    create_subscription_fn  create_subscription= (create_subscription_fn) dlsym(lib, "IOReportCreateSubscription");
    create_samples_fn       create_samples     = (create_samples_fn)      dlsym(lib, "IOReportCreateSamples");
    create_delta_fn         create_delta       = (create_delta_fn)        dlsym(lib, "IOReportCreateSamplesDelta");
    iterate_fn              iterate            = (iterate_fn)             dlsym(lib, "IOReportIterate");
    channel_name_fn         get_name           = (channel_name_fn)        dlsym(lib, "IOReportChannelGetChannelName");
    channel_name_fn         get_unit           = (channel_name_fn)        dlsym(lib, "IOReportChannelGetUnitLabel");
    simple_value_fn         get_value          = (simple_value_fn)        dlsym(lib, "IOReportSimpleGetIntegerValue");

    if (!copy_channels || !create_subscription || !create_samples || !create_delta ||
        !iterate || !get_name || !get_unit || !get_value) {
        return NULL;  // partial/renamed export — treat the whole feature as unavailable
    }

    CFMutableDictionaryRef desired = copy_channels(CFSTR("Energy Model"), NULL, 0, 0, 0);
    if (!desired) return NULL;

    CFMutableDictionaryRef subscribed = NULL;
    IOReportSubscriptionRef subscription = create_subscription(NULL, desired, &subscribed, 0, NULL);
    CFRelease(desired);  // the subscription holds its own copy via `subscribed`
    if (!subscription || !subscribed) {
        if (subscription) CFRelease(subscription);
        if (subscribed) CFRelease(subscribed);
        return NULL;
    }

    SoCPowerHandle *h = calloc(1, sizeof(SoCPowerHandle));
    if (!h) {
        CFRelease(subscription);
        CFRelease(subscribed);
        return NULL;
    }
    h->create_samples = create_samples;
    h->create_delta   = create_delta;
    h->iterate        = iterate;
    h->get_name       = get_name;
    h->get_unit       = get_unit;
    h->get_value      = get_value;
    h->subscription   = subscription;
    h->channels       = subscribed;
    return h;
}

// Joules per unit for the labels IOReport uses on the Energy Model.
static double joules_per_unit(CFStringRef unit) {
    if (!unit) return 0;
    char buf[16] = {0};
    if (!CFStringGetCString(unit, buf, sizeof buf, kCFStringEncodingUTF8)) return 0;
    if (strcmp(buf, "mJ") == 0) return 1e-3;
    if (strcmp(buf, "uJ") == 0 || strcmp(buf, "\xC2\xB5J") == 0) return 1e-6;  // "uJ" / "µJ"
    if (strcmp(buf, "nJ") == 0) return 1e-9;
    if (strcmp(buf, "J") == 0)  return 1.0;
    return 0;  // unknown unit → don't fabricate a magnitude
}

int vitals_socpower_sample(void *handle, VitalsSoCPower *out) {
    SoCPowerHandle *h = (SoCPowerHandle *)handle;
    out->valid = 0;
    out->cpu_watts = out->gpu_watts = out->ane_watts = 0;
    if (!h) return 0;

    CFDictionaryRef current = h->create_samples(h->subscription, h->channels, NULL);
    if (!current) return 0;
    uint64_t current_ns = now_ns();

    if (!h->previous) {  // first sample: nothing to diff against yet
        h->previous = current;
        h->previous_ns = current_ns;
        return 0;
    }

    double seconds = (double)(current_ns - h->previous_ns) / 1e9;
    if (seconds <= 0) {  // clock went backwards or no time passed — skip cleanly
        CFRelease(h->previous);
        h->previous = current;
        h->previous_ns = current_ns;
        return 0;
    }

    CFDictionaryRef delta = h->create_delta(h->previous, current, NULL);
    if (delta) {
        // Accumulate energy (joules) per rail, then divide by elapsed time.
        // Captured as a pointer — blocks can't capture a C array by reference.
        double joules_storage[3] = {0, 0, 0};  // [0]=CPU [1]=GPU [2]=ANE
        double *joules = joules_storage;
        channel_name_fn get_name = h->get_name;
        channel_name_fn get_unit = h->get_unit;
        simple_value_fn get_value = h->get_value;
        h->iterate(delta, ^int(CFDictionaryRef ch) {
            CFStringRef name = get_name(ch);
            if (!name) return 0;
            char n[64] = {0};
            if (!CFStringGetCString(name, n, sizeof n, kCFStringEncodingUTF8)) return 0;

            int rail = -1;
            if (strcmp(n, "CPU Energy") == 0) {
                rail = 0;
            } else if (strcmp(n, "GPU") == 0) {
                rail = 1;
            } else if (strncmp(n, "ANE", 3) == 0) {
                // "ANE", or per-engine "ANE0"/"ANE1"… — never "ANExxx_SRAM".
                const char *rest = n + 3;
                int digits_only = 1;
                for (const char *p = rest; *p; p++) {
                    if (*p < '0' || *p > '9') { digits_only = 0; break; }
                }
                if (digits_only) rail = 2;
            }
            if (rail < 0) return 0;

            double scale = joules_per_unit(get_unit(ch));
            if (scale > 0) joules[rail] += (double)get_value(ch, 0) * scale;
            return 0;  // kIOReportIterOk — continue
        });
        CFRelease(delta);

        out->cpu_watts = joules[0] / seconds;
        out->gpu_watts = joules[1] / seconds;
        out->ane_watts = joules[2] / seconds;
        out->valid = 1;
    }

    CFRelease(h->previous);
    h->previous = current;
    h->previous_ns = current_ns;
    return out->valid;
}

void vitals_socpower_destroy(void *handle) {
    SoCPowerHandle *h = (SoCPowerHandle *)handle;
    if (!h) return;
    if (h->previous) CFRelease(h->previous);
    if (h->channels) CFRelease(h->channels);
    if (h->subscription) CFRelease(h->subscription);
    free(h);
}

// ---------------------------------------------------------------------------
// NVMe SSD SMART read (see PrivateSensors.h). Uses Apple's own NVMe SMART
// user-client interface; all IOKit/CF lifetimes are owned here.
// ---------------------------------------------------------------------------

#include <IOKit/IOKitLib.h>
#include <IOKit/IOKitKeys.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>

int vitals_nvme_smart_read(VitalsDiskSMART *out) {
    memset(out, 0, sizeof(*out));

    // Match by the public "NVMe SMART Capable" property rather than a device
    // class, so this isn't tied to a particular controller (Apple Silicon
    // publishes it on an IOEmbeddedNVMeBlockDevice). No match → no SMART here.
    CFMutableDictionaryRef sub = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!sub) return 0;
    CFDictionarySetValue(sub, CFSTR(kIOPropertyNVMeSMARTCapableKey), kCFBooleanTrue);
    CFMutableDictionaryRef match = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (!match) { CFRelease(sub); return 0; }
    CFDictionarySetValue(match, CFSTR(kIOPropertyMatchKey), sub);
    CFRelease(sub);

    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, match); // consumes `match`
    if (svc == IO_OBJECT_NULL) return 0;

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        svc, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS || !plugin) return 0;

    IONVMeSMARTInterface **smart = NULL;
    HRESULT qr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart);
    if (qr != 0 || !smart) { IODestroyPlugInInterface(plugin); return 0; }

    NVMeSMARTData d;
    memset(&d, 0, sizeof(d));
    IOReturn rr = (*smart)->SMARTReadData(smart, &d);
    int ok = (rr == kIOReturnSuccess);
    if (ok) {
        out->valid                    = 1;
        out->critical_warning         = d.CRITICAL_WARNING;
        out->temperature_k            = d.TEMPERATURE;
        out->available_spare          = d.AVAILABLE_SPARE;
        out->available_spare_threshold = d.AVAILABLE_SPARE_THRESHOLD;
        out->percentage_used          = d.PERCENTAGE_USED;
        out->data_units_written       = d.DATA_UNITS_WRITTEN[0]; // low 64 bits
        out->data_units_read          = d.DATA_UNITS_READ[0];
        out->power_cycles             = d.POWER_CYCLES[0];
        out->power_on_hours           = d.POWER_ON_HOURS[0];
        out->unsafe_shutdowns         = d.UNSAFE_SHUTDOWNS[0];
        out->media_errors             = d.MEDIA_ERRORS[0];
    }

    (*smart)->Release(smart);
    IODestroyPlugInInterface(plugin);
    return ok;
}

// ---------------------------------------------------------------------------
// Crash capture (see PrivateSensors.h). Strictly async-signal-safe: the handler
// only calls open/write/close, backtrace(), and raise() — all on POSIX's
// async-signal-safe list — over fixed buffers, with no malloc, stdio, or locks.
//
// It deliberately does NOT call backtrace_symbols_fd: that symbolicates via
// dladdr(), which takes the dyld lock and can malloc — so a crash that already
// holds those (a libmalloc abort from heap corruption, or a fault inside dyld)
// would deadlock the handler and the process would hang instead of dying. We
// write the raw return addresses instead, and re-raise to SIG_DFL so the OS
// crash reporter produces the fully symbolicated report regardless.
// ---------------------------------------------------------------------------

#include <signal.h>
#include <execinfo.h>
#include <fcntl.h>
#include <unistd.h>

static char  vitals_crash_log_path[1024];
static void *vitals_crash_frames[128];

static const char *vitals_signal_name(int sig) {
    switch (sig) {
        case SIGSEGV: return "SIGSEGV";
        case SIGABRT: return "SIGABRT";
        case SIGILL:  return "SIGILL";
        case SIGTRAP: return "SIGTRAP";
        case SIGFPE:  return "SIGFPE";
        case SIGBUS:  return "SIGBUS";
        default:      return "SIGNAL";
    }
}

static void vitals_write_str(int fd, const char *s) {
    size_t len = 0;
    while (s[len] != '\0') len++;
    if (len > 0) { ssize_t r = write(fd, s, len); (void)r; }
}

// Writes a pointer as "0x" + 16 hex digits + newline, using only write() — no
// snprintf (which is not guaranteed async-signal-safe).
static void vitals_write_addr(int fd, unsigned long value) {
    static const char hex[] = "0123456789abcdef";
    char buf[19];
    buf[0] = '0';
    buf[1] = 'x';
    for (int i = 0; i < 16; i++) {
        buf[2 + i] = hex[(value >> ((15 - i) * 4)) & 0xf];
    }
    buf[18] = '\n';
    ssize_t r = write(fd, buf, sizeof(buf));
    (void)r;
}

static void vitals_crash_handler(int sig) {
    int fd = open(vitals_crash_log_path, O_WRONLY | O_APPEND | O_CREAT, 0644);
    if (fd >= 0) {
        vitals_write_str(fd, "\n===== VITALS-SIGNAL-CRASH ");
        vitals_write_str(fd, vitals_signal_name(sig));
        vitals_write_str(fd, " =====\n");
        vitals_write_str(fd, "return addresses (symbolicate with the OS crash report):\n");
        int n = backtrace(vitals_crash_frames, 128);
        for (int i = 0; i < n; i++) {
            vitals_write_addr(fd, (unsigned long)vitals_crash_frames[i]);
        }
        vitals_write_str(fd, "===== END-CRASH =====\n");
        close(fd);
    }
    // Restore the default disposition and re-raise so the OS still records it.
    signal(sig, SIG_DFL);
    raise(sig);
}

void vitals_install_crash_handlers(const char *log_path) {
    strncpy(vitals_crash_log_path, log_path, sizeof(vitals_crash_log_path) - 1);
    vitals_crash_log_path[sizeof(vitals_crash_log_path) - 1] = '\0';

    int sigs[] = { SIGSEGV, SIGABRT, SIGILL, SIGTRAP, SIGFPE, SIGBUS };
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = vitals_crash_handler;
    sigemptyset(&sa.sa_mask);
    // RESETHAND: after we re-raise, the default handler runs. NODEFER: allow a
    // fault inside the handler to terminate rather than deadlock.
    sa.sa_flags = SA_RESETHAND | SA_NODEFER;
    for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) {
        sigaction(sigs[i], &sa, NULL);
    }
}
