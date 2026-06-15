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
