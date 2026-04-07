//
//  ScriptingCommandSupport.h
//  Arculator
//
//  Shared helpers for AppleScript command validation and error reporting.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Error number ranges:
//   1000: invalid arguments (bad key name, bad drive, unsupported character)
//   1100: invalid state (cannot pause while idle, etc.)
//   1200: lookup/file failures (config not found, config already exists)
//   1300: runtime cancellation (type text cancelled)

// Set an AppleScript error on the command and return nil.
static inline id _Nullable ScriptingError(NSScriptCommand *cmd, int code, NSString *message)
{
    [cmd setScriptErrorNumber:code];
    [cmd setScriptErrorString:message];
    return nil;
}

// Validate that a config name is safe for use as a filename.
// Returns nil if valid, or an error message string if invalid.
NSString *_Nullable ScriptingValidateConfigName(NSString *name);

NS_ASSUME_NONNULL_END
