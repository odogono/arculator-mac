//
//  InputInjectionBridge.h
//  Arculator
//
//  ObjC bridge for injecting keyboard and mouse input into the emulator.
//  Resolves key names to KEY_* constants and wraps the C injection functions.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface InputInjectionBridge : NSObject

// Key injection — key name is case-insensitive (e.g. "a", "shift", "f12")
// Returns NO if the key name is not recognized.
+ (BOOL)injectKeyDown:(NSString *)keyName;
+ (BOOL)injectKeyUp:(NSString *)keyName;

// Async character-by-character text injection.
// Calls completion on finish (or cancellation/error).
// Returns a generation token; a new typeText call cancels any in-flight sequence.
+ (void)typeText:(NSString *)text
      forCommand:(NSScriptCommand *)command;

// Mouse injection
+ (void)injectMouseMoveDx:(int)dx dy:(int)dy;
+ (void)injectMouseAbsX:(int)x y:(int)y;
+ (void)injectMouseButtonDown:(int)buttonMask;
+ (void)injectMouseButtonUp:(int)buttonMask;

// Clear all injected state
+ (void)clearAllInjectedKeys;
+ (void)clearInjectedMouse;
+ (void)clearAllInjectedInput;

// Key name resolution (returns -1 if not found)
+ (int)keycodeForName:(NSString *)keyName;

@end

NS_ASSUME_NONNULL_END
