/*
 * Arculator.h
 */

#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>


@class ArculatorApplication;



/*
 * Standard Suite
 */

// The application's top-level scripting object.
@interface ArculatorApplication : SBApplication

@property (copy, readonly) NSString *name;  // The name of the application.
@property (copy, readonly) NSString *emulationState;  // Current emulation state: idle, running, or paused.
@property (copy, readonly) NSString *activeConfig;  // Name of the currently loaded configuration.
@property (readonly) NSInteger speed;  // Emulation speed as a percentage (100 = realtime).
@property (copy, readonly) NSArray<NSString *> *discNames;  // List of disc filenames for the four floppy drives.
@property (copy, readonly) NSArray<NSString *> *configNames;  // Sorted list of available configuration names.

- (void) quit;  // Quit the application.
- (void) startEmulation;  // Start emulation with the currently loaded configuration.
- (void) stopEmulation;  // Stop the running emulation session.
- (void) pauseEmulation;  // Pause a running emulation session.
- (void) resumeEmulation;  // Resume a paused emulation session.
- (void) resetEmulation;  // Reset the emulated machine.
- (void) startConfig:(NSString *)x;  // Load a named configuration and start emulation.
- (void) loadConfig:(NSString *)x;  // Load a named configuration without starting emulation.
- (void) createConfig:(NSString *)x withPreset:(NSInteger)withPreset;  // Create a new configuration file.
- (void) copyConfig:(NSString *)x to:(NSString *)to NS_RETURNS_NOT_RETAINED;  // Copy an existing configuration to a new name.
- (void) deleteConfig:(NSString *)x;  // Delete a configuration file.
- (void) changeDisc:(NSString *)x drive:(NSInteger)drive;  // Insert a disc image into a floppy drive.
- (void) ejectDiscDrive:(NSInteger)drive;  // Eject the disc from a floppy drive.
- (void) injectKeyDown:(NSString *)x;  // Press a key down in the emulated machine.
- (void) injectKeyUp:(NSString *)x;  // Release a key in the emulated machine.
- (void) typeText:(NSString *)x;  // Type a string character by character into the emulated machine.
- (void) injectMouseMoveDx:(NSInteger)dx dy:(NSInteger)dy;  // Inject relative mouse movement.
- (void) injectMouseDownButton:(NSInteger)button;  // Press a mouse button in the emulated machine.
- (void) injectMouseUpButton:(NSInteger)button;  // Release a mouse button in the emulated machine.

@end

