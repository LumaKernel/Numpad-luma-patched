#ifndef C_TRACKPAD_H
#define C_TRACKPAD_H
#include <stdbool.h>
#include <stdint.h>

typedef struct { int32_t identifier; float x, y; } TPTouch;
// Valid only for the duration of the callback; callbacks run on a framework thread.
typedef void (*TPCallback)(const TPTouch *touches, int32_t count, double timestamp, void *context);
bool TPInitialize(void);
bool TPStart(TPCallback callback, void *context);
void TPStop(void);
// Main-thread only. Uses a short, weak trackpad actuation at confirmed input.
bool TPHapticClick(void);
// Stronger predefined pulse for entering/leaving the 5 center.
bool TPHapticCenter(void);
void TPHapticShutdown(void);
const char *TPError(void);
// Returns the number of trackpad devices currently known.
int32_t TPDeviceCount(void);
#endif
