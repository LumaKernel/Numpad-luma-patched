#include "CTrackpad.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <stddef.h>
#include <pthread.h>

// ABI of MultitouchSupport's contact record. Kept in C to preserve alignment.
typedef struct { float x, y; } TPPoint;
typedef struct { TPPoint position, velocity; } TPVector;
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier, state, fingerID, handID;
    TPVector normalized;
    float size;
    int32_t reserved1;
    float angle, majorAxis, minorAxis;
    TPVector absolute;
    int32_t reserved2[2];
    float density;
} Contact;
_Static_assert(sizeof(Contact) == 96, "Unexpected contact ABI");
_Static_assert(offsetof(Contact, normalized) == 32, "Unexpected position offset");

typedef int (*FrameCallback)(void *, Contact *, int, double, int);
static void *library;

// Multi-device support: store an array of device pointers.
#define MAX_DEVICES 8
static void *devices[MAX_DEVICES];
static int32_t deviceCount;
static CFArrayRef deviceList; // kept alive so device pointers remain valid

static CFArrayRef (*createList)(void);
static void *(*createDefault)(void);
static void (*registerCallback)(void *, FrameCallback);
static void (*unregisterCallback)(void *, FrameCallback);
static void (*startDevice)(void *, int);
static void (*stopDevice)(void *);
static bool (*isRunning)(void *);
static TPCallback receiver;
static void *receiverContext;
static bool running;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static const char *errorMessage = "";

static int receiveFrame(void *sender, Contact *contacts, int count, double timestamp, int frame) {
    (void)frame;
    (void)sender;
    if (count < 0 || count > 32 || (count && !contacts)) return 0;
    TPTouch touches[32];
    int active = 0;
    for (int i = 0; i < count; i++) {
        if (contacts[i].state == 3 || contacts[i].state == 4) {
            touches[active++] = (TPTouch){contacts[i].identifier,
                contacts[i].normalized.position.x, contacts[i].normalized.position.y};
        }
    }
    pthread_mutex_lock(&lock);
    if (receiver) receiver(touches, active, timestamp, receiverContext);
    pthread_mutex_unlock(&lock);
    return 0;
}

static bool loadLibrary(void) {
    if (library) return true;
    library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    if (!library) { errorMessage = "Could not load the MultitouchSupport framework."; return false; }
    createList = dlsym(library, "MTDeviceCreateList");
    createDefault = dlsym(library, "MTDeviceCreateDefault");
    registerCallback = dlsym(library, "MTRegisterContactFrameCallback");
    unregisterCallback = dlsym(library, "MTUnregisterContactFrameCallback");
    startDevice = dlsym(library, "MTDeviceStart");
    stopDevice = dlsym(library, "MTDeviceStop");
    isRunning = dlsym(library, "MTDeviceIsRunning");
    if (!registerCallback || !unregisterCallback || !startDevice || !stopDevice || !isRunning) {
        errorMessage = "The required trackpad API is unavailable on this version of macOS."; return false;
    }
    return true;
}

bool TPInitialize(void) {
    if (deviceCount > 0) return true;
    if (!loadLibrary()) return false;

    // Try MTDeviceCreateList first (enumerates all trackpads including Bluetooth).
    if (createList) {
        CFArrayRef list = createList();
        if (list) {
            CFIndex count = CFArrayGetCount(list);
            for (CFIndex i = 0; i < count && deviceCount < MAX_DEVICES; i++) {
                void *dev = (void *)CFArrayGetValueAtIndex(list, i);
                if (dev) devices[deviceCount++] = dev;
            }
            // Keep the list alive: device pointers are owned by the CFArray
            // and become invalid if the array is released.
            deviceList = list;
        }
    }

    // Fallback to MTDeviceCreateDefault if MTDeviceCreateList is unavailable or returned nothing.
    if (deviceCount == 0 && createDefault) {
        void *dev = createDefault();
        if (dev) devices[deviceCount++] = dev;
    }

    if (deviceCount == 0) {
        errorMessage = "No trackpad found. Connect a trackpad and try again.";
        return false;
    }
    return true;
}

bool TPStart(TPCallback callback, void *context) {
    if (running) return true;
    if (!TPInitialize()) return false;
    pthread_mutex_lock(&lock);
    receiver = callback; receiverContext = context;
    pthread_mutex_unlock(&lock);

    int32_t started = 0;
    for (int32_t i = 0; i < deviceCount; i++) {
        registerCallback(devices[i], receiveFrame);
        startDevice(devices[i], 0);
        if (isRunning(devices[i])) {
            started++;
        } else {
            // Clean up this device but continue with others.
            unregisterCallback(devices[i], receiveFrame);
            stopDevice(devices[i]);
        }
    }

    if (started == 0) {
        errorMessage = "Could not start receiving trackpad touches. Check the connection and restart NumpadLuma.";
        pthread_mutex_lock(&lock);
        receiver = NULL; receiverContext = NULL;
        pthread_mutex_unlock(&lock);
        return false;
    }
    running = true;
    return true;
}

void TPStop(void) {
    if (!running) return;
    pthread_mutex_lock(&lock);
    receiver = NULL; receiverContext = NULL;
    pthread_mutex_unlock(&lock);
    for (int32_t i = 0; i < deviceCount; i++) {
        stopDevice(devices[i]);
        unregisterCallback(devices[i], receiveFrame);
    }
    running = false;
}
void TPReinitialize(void) {
    if (running) return; // Must stop first
    // Release stale device references.
    if (deviceList) { CFRelease(deviceList); deviceList = NULL; }
    for (int32_t i = 0; i < deviceCount; i++) devices[i] = NULL;
    deviceCount = 0;
    errorMessage = "";
}

const char *TPError(void) { return errorMessage; }
int32_t TPDeviceCount(void) { return deviceCount; }

// AppKit may omit feedback after lift-off. Drive the Force Touch actuator
// directly so release-confirmed taps still receive exactly one short pulse.
// Try all devices that support actuation and use the first one that works.
#define MAX_ACTUATORS 8
static CFTypeRef actuators[MAX_ACTUATORS];
static int32_t actuatorCount;
static CFTypeRef (*createActuator)(uint64_t);
static IOReturn (*openActuator)(CFTypeRef);
static IOReturn (*closeActuator)(CFTypeRef);
static IOReturn (*actuate)(CFTypeRef, int32_t, uint32_t, float, float);

static bool initializeActuators(void) {
    if (actuatorCount > 0) return true;
    if (!TPInitialize()) return false;
    createActuator = dlsym(library, "MTActuatorCreateFromDeviceID");
    openActuator = dlsym(library, "MTActuatorOpen");
    closeActuator = dlsym(library, "MTActuatorClose");
    actuate = dlsym(library, "MTActuatorActuate");
    if (!createActuator || !openActuator || !closeActuator || !actuate) return false;
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("AppleMultitouchDevice"), &iterator) != KERN_SUCCESS) return false;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        CFTypeRef supported = IORegistryEntryCreateCFProperty(service, CFSTR("ActuationSupported"), kCFAllocatorDefault, 0);
        CFTypeRef identifier = IORegistryEntryCreateCFProperty(service, CFSTR("Multitouch ID"), kCFAllocatorDefault, 0);
        if (supported == kCFBooleanTrue && identifier && CFGetTypeID(identifier) == CFNumberGetTypeID()) {
            int64_t deviceID = 0;
            if (CFNumberGetValue((CFNumberRef)identifier, kCFNumberSInt64Type, &deviceID)) {
                CFTypeRef act = createActuator((uint64_t)deviceID);
                if (act && actuatorCount < MAX_ACTUATORS) {
                    actuators[actuatorCount++] = act;
                }
            }
        }
        if (supported) CFRelease(supported);
        if (identifier) CFRelease(identifier);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return actuatorCount > 0;
}

static bool performHaptic(int32_t pattern) {
    if (!initializeActuators()) return false;
    bool anySuccess = false;
    for (int32_t i = 0; i < actuatorCount; i++) {
        if (openActuator(actuators[i]) != kIOReturnSuccess) continue;
        IOReturn result = actuate(actuators[i], pattern, 0, 0.0f, 0.0f);
        closeActuator(actuators[i]);
        if (result == kIOReturnSuccess) anySuccess = true;
    }
    return anySuccess;
}

bool TPHapticClick(void) { return performHaptic(3); }
bool TPHapticCenter(void) { return performHaptic(6); }

void TPHapticShutdown(void) {
    for (int32_t i = 0; i < actuatorCount; i++) {
        if (actuators[i]) { CFRelease(actuators[i]); actuators[i] = NULL; }
    }
    actuatorCount = 0;
}
