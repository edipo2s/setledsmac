
/*  setleds for Mac
 https://github.com/damieng/setledsmac
 Copyright 2015-2017 Damien Guard. GPL 2 licenced.

 Monitor mode added by Raj Perera - https://github.com/rajiteh/setledsmac-monitor
 Keyboard event sniffer code is from https://github.com/objective-see/sniffMK
 */

#include "main.h"

Boolean verbose = false;
const char * nameMatch;
static CFMachPortRef eventTap = NULL;

int main(int argc, const char * argv[])
{
    printf("SetLEDs version 0.2 + Monitor - Based on https://github.com/damieng/setledsmac\n");
    parseOptions(argc, argv);
    printf("\n");
    return 0;
}

void parseOptions(int argc, const char * argv[])
{
    if (argc == 1) {
        explainUsage();
        exit(1);
    }
    
    
    
    Boolean nextIsName = false;
    Boolean monitorMode = false;
    
    LedState changes[] = { NoChange, NoChange, NoChange, NoChange };
    
    for (int i = 1; i < argc; i++) {
        if (strcasecmp(argv[i], "monitor") == 0)
            monitorMode = true;
        else if (strcasecmp(argv[i], "-v") == 0)
            verbose = true;
        else if(strcasecmp(argv[i], "-name") == 0)
            nextIsName = true;
        
        // Numeric lock
        else if (strcasecmp(argv[i], "+num") == 0)
            changes[kHIDUsage_LED_NumLock] = On;
        else if (strcasecmp(argv[i], "-num") == 0)
            changes[kHIDUsage_LED_NumLock] = Off;
        else if (strcasecmp(argv[i], "^num") == 0)
            changes[kHIDUsage_LED_NumLock] = Toggle;
        
        // Caps lock
        else if (strcasecmp(argv[i], "+caps") == 0)
            changes[kHIDUsage_LED_CapsLock] = On;
        else if (strcasecmp(argv[i], "-caps") == 0)
            changes[kHIDUsage_LED_CapsLock] = Off;
        else if (strcasecmp(argv[i], "^caps") == 0)
            changes[kHIDUsage_LED_CapsLock] = Toggle;
        
        // Scroll lock
        else if (strcasecmp(argv[i], "+scroll") == 0)
            changes[kHIDUsage_LED_ScrollLock] = On;
        else if (strcasecmp(argv[i], "-scroll") == 0)
            changes[kHIDUsage_LED_ScrollLock] = Off;
        else if (strcasecmp(argv[i], "^scroll") == 0)
            changes[kHIDUsage_LED_ScrollLock] = Toggle;
        
        else {
            if (nextIsName) {
                nameMatch = argv[i];
                nextIsName = false;
            }
            else {
                fprintf(stderr, "Unknown option %s\n\n", argv[i]);
                explainUsage();
                exit(1);
            }
        }
    }
    
    if (monitorMode)
        startMonitor();
    else
        setAllKeyboards(changes);
}


void startMonitor()
{
    CGEventMask eventMask = 0;
    CFRunLoopSourceRef runLoopSource = NULL;
    
    printf("Starting in monitor mode.\n");
    
    @autoreleasepool {
        //init event mask with mouse events
        // ->add 'CGEventMaskBit(kCGEventMouseMoved)' for mouse move events
        eventMask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventFlagsChanged);
    
        eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, 0, eventMask, eventCallback, NULL);
        if(NULL == eventTap)
        {
            fprintf(stderr, "ERROR: failed to create event tap\n");
            goto bail;
        }
    
        printf("Created event tap.\n");
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CGEventTapEnable(eventTap, true);
        printf("Event tab enabled, starting monitor.\n");
    
        //go, go, go
        CFRunLoopRun();
    }
    
    
bail:
    
    //release event tap
    if(NULL != eventTap)
    {
        CFRelease(eventTap);
        eventTap = NULL;
    }
    
    if(NULL != runLoopSource)
    {
        CFRelease(runLoopSource);
        runLoopSource = NULL;
    }
    
}

Boolean isKeyboardDevice(IOHIDDeviceRef device)
{
    return IOHIDDeviceConformsTo(device, kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard);
}

bool isNumLockEnabled(IOHIDDeviceRef device, CFDictionaryRef keyboardDictionary, int led)
{
    CFStringRef deviceNameRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    if (!deviceNameRef) return false;
    
    const char * deviceName = CFStringGetCStringPtr(deviceNameRef, kCFStringEncodingUTF8);
    
    if (nameMatch && fnmatch(nameMatch, deviceName, 0) != 0)
        return false;
    
    // printf("\nDevice: \"%s\" ", deviceName));
    
    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(device, keyboardDictionary, kIOHIDOptionsTypeNone);
    bool missingState = false;
    if (elements) {
        for (CFIndex elementIndex = 0; elementIndex < CFArrayGetCount(elements); elementIndex++) {
            IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, elementIndex);
            
            if (element && kHIDPage_LEDs == IOHIDElementGetUsagePage(element)) {
                uint32_t ledElement = IOHIDElementGetUsage(element);
                
                if (ledElement > maxLeds || ledElement != led) break;
                
                // Get current keyboard led status
                IOHIDValueRef currentValue = 0;
                IOHIDDeviceGetValue(device, element, &currentValue);
                
                if (currentValue == 0x00) {
                    missingState = true;
                } else {
                    long current = IOHIDValueGetIntegerValue(currentValue);
                    CFRelease(currentValue);
                    
                    return current == 0;
                }
            }
        }
        CFRelease(elements);
    }
    
    // printf("\n");
    if (missingState) {
        printf("\nSome state could not be determined. Please try running as root/sudo.\n");
    }
    return false;
}

bool isAnyLedEnabled(int led)
{
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) {
        fprintf(stderr, "ERROR: Failed to create IOHID manager.\n");
        return false;
    }
    
    CFDictionaryRef keyboard = getKeyboardDictionary();
    if (!keyboard) {
        fprintf(stderr, "ERROR: Failed to get dictionary usage page for kHIDUsage_GD_Keyboard.\n");
        return false;
    }
    
    IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(manager, keyboard);
    
    bool enabled = false;
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    if (devices) {
        CFIndex deviceCount = CFSetGetCount(devices);
        if (deviceCount == 0) {
            fprintf(stderr, "ERROR: Could not find any keyboard devices.\n");
        }
        else {
            // Loop through all keyboards attempting to get or display led state
            IOHIDDeviceRef *deviceRefs = malloc(sizeof(IOHIDDeviceRef) * deviceCount);
            if (deviceRefs) {
                CFSetGetValues(devices, (const void **) deviceRefs);
                for (CFIndex deviceIndex = 0; deviceIndex < deviceCount; deviceIndex++)
                if (isKeyboardDevice(deviceRefs[deviceIndex])) {
                    if (isNumLockEnabled(deviceRefs[deviceIndex], keyboard, led)) {
                        enabled = true;
                    }
                }
                
                free(deviceRefs);
            }
        }
        
        CFRelease(devices);
    }
    
    CFRelease(keyboard);
    return enabled;
}

//callback for mouse/keyboard events
CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    
    if(kCGEventTapDisabledByTimeout == type)
    {
        CGEventTapEnable(eventTap, true);
        fprintf(stderr, "Event tap timed out: restarting tap");
        return event;
    }
    
    CGKeyCode keyCode = 0;
    keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    
    if(kCGEventKeyDown == type && isAnyLedEnabled((int)kHIDUsage_LED_NumLock))
    {
        switch (keyCode)
        {
            case 0x41:  // period
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x75, true); // Delete
            case 0x52:  // keypad_0
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x83, true); // Launchpad
            case 0x53:  // keypad_1
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x77, true); // End
            case 0x54:  // keypad_2
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x7d, true); // Down Arrow
            case 0x55:  // keypad_3
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x79, true); // Page Down
            case 0x56:  // keypad_4
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x7b, true); // Left Arrow
            case 0x57:  // keypad_5
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x31, true); // Space
            case 0x58:  // keypad_6
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x7c, true); // Right Arrow
            case 0x59:  // keypad_7
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x73, true); // Home
            case 0x5b:  // keypad_8
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x7e, true); // Up Arrow
            case 0x5c:  // keypad_9
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x74, true); // Page Up
        }
    }
    
    if(kCGEventKeyUp == type)
    {
        LedState changes[] = { NoChange, NoChange, NoChange, NoChange };
        
        switch (keyCode)
        {
            case 0x41:  // period
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x75, false); // Delete
            case 0x52:  // keypad_0
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x83, false); // Launchpad
            case 0x53:  // keypad_1
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x77, false); // End
            case 0x54:  // keypad_2
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x7d, false); // Down Arrow
            case 0x55:  // keypad_3
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x79, false); // Page Down
            case 0x56:  // keypad_4
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x7b, false); // Left Arrow
            case 0x57:  // keypad_5
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x31, false); // Space
            case 0x58:  // keypad_6
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x7c, false); // Right Arrow
            case 0x59:  // keypad_7
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x73, false); // Home
            case 0x5b:  // keypad_8
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x7e, false); // Up Arrow
            case 0x5c:  // keypad_9
                return CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x74, false); // Page Up
        }
    
        switch (keyCode)
        {
            case 0x39:
                changes[kHIDUsage_LED_CapsLock] = Toggle;
                break;
            case 0x47:
                changes[kHIDUsage_LED_NumLock] = Toggle;
                break;
            case 0x6b:
                changes[kHIDUsage_LED_ScrollLock] = Toggle;
                break;
            default:
                return event;
                
        }
        setAllKeyboards(changes);
    }
    return event;
}

void explainUsage()
{
    printf("Usage:\tsetleds [monitor] [-v] [-name wildcard] [[+|-|^][ num | caps | scroll]]\n"
           "Thus,\tsetleds +caps -num ^scroll\n"
           "will set CapsLock, clear NumLock and toggle ScrollLock.\n"
           "Any leds changed are reported for each keyboard.\n"
           "Specify -v to shows state of all leds.\n"
           "Specify -name to match keyboard name with a wildcard\n"
           "Use the \"monitor\" sub command to run continously and toggle LEDs on keypress.");
}

void setKeyboard(IOHIDDeviceRef device, CFDictionaryRef keyboardDictionary, LedState changes[])
{
    CFStringRef deviceNameRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    if (!deviceNameRef) return;
    
    const char * deviceName = CFStringGetCStringPtr(deviceNameRef, kCFStringEncodingUTF8);
    
    if (nameMatch && fnmatch(nameMatch, deviceName, 0) != 0)
        return;
    
    // printf("\nDevice: \"%s\" ", deviceName));
    
    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(device, keyboardDictionary, kIOHIDOptionsTypeNone);
    bool missingState = false;
    if (elements) {
        for (CFIndex elementIndex = 0; elementIndex < CFArrayGetCount(elements); elementIndex++) {
            IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, elementIndex);
            
            if (element && kHIDPage_LEDs == IOHIDElementGetUsagePage(element)) {
                uint32_t led = IOHIDElementGetUsage(element);
                
                if (led > maxLeds) break;
                
                // Get current keyboard led status
                IOHIDValueRef currentValue = 0;
                IOHIDDeviceGetValue(device, element, &currentValue);
                
                if (currentValue == 0x00) {
                    missingState = true;
                    // printf("?%s ", ledNames[led - 1]);
                } else {
                    long current = IOHIDValueGetIntegerValue(currentValue);
                    CFRelease(currentValue);
                    
                    // Should we try to set the led?
                    if (changes[led] != NoChange && changes[led] != current) {
                        LedState newState = changes[led];
                        if (newState == Toggle) {
                            newState = current == 0 ? On : Off;
                        }
                        IOHIDValueRef newValue = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, newState);
                        if (newValue) {
                            // IOReturn changeResult = IOHIDDeviceSetValue(device, element, newValue);
                            IOHIDDeviceSetValue(device, element, newValue);
                            
                            // Was the change successful?
                            // if (kIOReturnSuccess == changeResult) {
                            //    printf("%s%s ", stateSymbol[newState], ledNames[led - 1]);
                            // }
                            CFRelease(newValue);
                        }
                    } else if (verbose) {
                        printf("Device: %s %s%s ", deviceName, stateSymbol[current], ledNames[led - 1]);
                    }
                }
            }
        }
        CFRelease(elements);
    }
    
    // printf("\n");
    if (missingState) {
        printf("\nSome state could not be determined. Please try running as root/sudo.\n");
    }
}

void setAllKeyboards(LedState changes[])
{
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) {
        fprintf(stderr, "ERROR: Failed to create IOHID manager.\n");
        return;
    }
    
    CFDictionaryRef keyboard = getKeyboardDictionary();
    if (!keyboard) {
        fprintf(stderr, "ERROR: Failed to get dictionary usage page for kHIDUsage_GD_Keyboard.\n");
        return;
    }
    
    IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(manager, keyboard);
    
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    if (devices) {
        CFIndex deviceCount = CFSetGetCount(devices);
        if (deviceCount == 0) {
            fprintf(stderr, "ERROR: Could not find any keyboard devices.\n");
        }
        else {
            // Loop through all keyboards attempting to get or display led state
            IOHIDDeviceRef *deviceRefs = malloc(sizeof(IOHIDDeviceRef) * deviceCount);
            if (deviceRefs) {
                CFSetGetValues(devices, (const void **) deviceRefs);
                for (CFIndex deviceIndex = 0; deviceIndex < deviceCount; deviceIndex++)
                    if (isKeyboardDevice(deviceRefs[deviceIndex]))
                        setKeyboard(deviceRefs[deviceIndex], keyboard, changes);
                
                free(deviceRefs);
            }
        }
        
        CFRelease(devices);
    }
    
    CFRelease(keyboard);
}

CFMutableDictionaryRef getKeyboardDictionary()
{
    CFMutableDictionaryRef result = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    if (!result) return result;
    
    UInt32 inUsagePage = kHIDPage_GenericDesktop;
    UInt32 inUsage = kHIDUsage_GD_Keyboard;
    
    CFNumberRef page = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &inUsagePage);
    if (page) {
        CFDictionarySetValue(result, CFSTR(kIOHIDDeviceUsageKey), page);
        CFRelease(page);
        
        CFNumberRef usage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &inUsage);
        if (usage) {
            CFDictionarySetValue(result, CFSTR(kIOHIDDeviceUsageKey), usage);
            CFRelease(usage);
        }
    }
    return result;
}
