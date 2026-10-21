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
static void *library, *device;
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
    (void)sender; (void)frame;
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

bool TPInitialize(void) {
    if (device) return true;
    if (!library) library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    if (!library) { errorMessage = "MultitouchSupport 프레임워크를 불러올 수 없습니다."; return false; }
    createDefault = dlsym(library, "MTDeviceCreateDefault");
    registerCallback = dlsym(library, "MTRegisterContactFrameCallback");
    unregisterCallback = dlsym(library, "MTUnregisterContactFrameCallback");
    startDevice = dlsym(library, "MTDeviceStart");
    stopDevice = dlsym(library, "MTDeviceStop");
    isRunning = dlsym(library, "MTDeviceIsRunning");
    if (!createDefault || !registerCallback || !unregisterCallback || !startDevice || !stopDevice || !isRunning) {
        errorMessage = "이 macOS 버전에서 필요한 트랙패드 API를 찾을 수 없습니다."; return false;
    }
    device = createDefault();
    if (!device) { errorMessage = "트랙패드를 찾을 수 없습니다. 트랙패드를 연결한 뒤 다시 시도하세요."; return false; }
    // The default device is retained for this process's lifetime.
    return true;
}

bool TPStart(TPCallback callback, void *context) {
    if (running) return true;
    if (!TPInitialize()) return false;
    pthread_mutex_lock(&lock);
    receiver = callback; receiverContext = context;
    pthread_mutex_unlock(&lock);
    registerCallback(device, receiveFrame);
    startDevice(device, 0);
    running = true;
    if (!isRunning(device)) {
        errorMessage = "트랙패드 터치 수신을 시작하지 못했습니다. 연결을 확인하고 앱을 다시 실행하세요.";
        TPStop(); return false;
    }
    return true;
}

void TPStop(void) {
    if (!running) return;
    pthread_mutex_lock(&lock);
    receiver = NULL; receiverContext = NULL;
    pthread_mutex_unlock(&lock);
    stopDevice(device);
    unregisterCallback(device, receiveFrame);
    running = false;
}
const char *TPError(void) { return errorMessage; }

// AppKit may omit feedback after lift-off. Drive the Force Touch actuator
// directly so release-confirmed taps still receive exactly one short pulse.
static CFTypeRef actuator;
static CFTypeRef (*createActuator)(uint64_t);
static IOReturn (*openActuator)(CFTypeRef);
static IOReturn (*closeActuator)(CFTypeRef);
static IOReturn (*actuate)(CFTypeRef, int32_t, uint32_t, float, float);

static bool initializeActuator(void) {
    if (actuator) return true;
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
                actuator = createActuator((uint64_t)deviceID);
            }
        }
        if (supported) CFRelease(supported);
        if (identifier) CFRelease(identifier);
        IOObjectRelease(service);
        if (actuator) break;
    }
    IOObjectRelease(iterator);
    return actuator != NULL;
}

static bool performHaptic(int32_t pattern) {
    if (!initializeActuator()) return false;
    if (openActuator(actuator) != kIOReturnSuccess) {
        TPHapticShutdown(); return false;
    }
    // Predefined pulse; no custom waveform or continuous vibration.
    IOReturn result = actuate(actuator, pattern, 0, 0.0f, 0.0f);
    IOReturn closed = closeActuator(actuator);
    if (result != kIOReturnSuccess || closed != kIOReturnSuccess) {
        TPHapticShutdown(); return false;
    }
    return true;
}

bool TPHapticClick(void) { return performHaptic(3); }
bool TPHapticCenter(void) { return performHaptic(6); }

void TPHapticShutdown(void) {
    if (actuator) { CFRelease(actuator); actuator = NULL; }
}
