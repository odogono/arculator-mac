//
//  LifecycleScriptingCommands.mm
//  Arculator
//
//  AppleScript commands: start/stop/pause/resume/reset emulation, start config.
//

#import <Foundation/Foundation.h>
#import "EmulatorBridge.h"
#import "ConfigBridge.h"
#import "ScriptingCommandSupport.h"

#pragma mark - start emulation

@interface StartEmulationCommand : NSScriptCommand
@end

@implementation StartEmulationCommand

- (id)performDefaultImplementation
{
    if ([EmulatorBridge sessionState] != ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot start: emulation is already running or paused");

    [EmulatorBridge startEmulation];
    if ([EmulatorBridge sessionState] == ARCSessionStateIdle)
    {
        NSString *error = [EmulatorBridge lastStartError];
        if (error.length > 0)
            return ScriptingError(self, 1200, error);
    }
    return nil;
}

@end

#pragma mark - stop emulation

@interface StopEmulationCommand : NSScriptCommand
@end

@implementation StopEmulationCommand

- (id)performDefaultImplementation
{
    ARCSessionState state = [EmulatorBridge sessionState];
    if (state == ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot stop: emulation is not running");

    [EmulatorBridge stopEmulation];
    return nil;
}

@end

#pragma mark - pause emulation

@interface PauseEmulationCommand : NSScriptCommand
@end

@implementation PauseEmulationCommand

- (id)performDefaultImplementation
{
    ARCSessionState state = [EmulatorBridge sessionState];
    if (state == ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot pause: emulation is not running");
    if (state == ARCSessionStatePaused)
        return ScriptingError(self, 1100, @"Cannot pause: emulation is already paused");

    [EmulatorBridge pauseEmulation];
    return nil;
}

@end

#pragma mark - resume emulation

@interface ResumeEmulationCommand : NSScriptCommand
@end

@implementation ResumeEmulationCommand

- (id)performDefaultImplementation
{
    ARCSessionState state = [EmulatorBridge sessionState];
    if (state == ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot resume: emulation is not running");
    if (state == ARCSessionStateRunning)
        return ScriptingError(self, 1100, @"Cannot resume: emulation is not paused");

    [EmulatorBridge resumeEmulation];
    return nil;
}

@end

#pragma mark - reset emulation

@interface ResetEmulationCommand : NSScriptCommand
@end

@implementation ResetEmulationCommand

- (id)performDefaultImplementation
{
    ARCSessionState state = [EmulatorBridge sessionState];
    if (state == ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot reset: emulation is not running");

    [EmulatorBridge resetEmulation];
    return nil;
}

@end

#pragma mark - start config

@interface StartConfigCommand : NSScriptCommand
@end

@implementation StartConfigCommand

- (id)performDefaultImplementation
{
    NSString *configName = self.directParameter;
    if (!configName || ![configName isKindOfClass:[NSString class]])
        return ScriptingError(self, 1000, @"Missing config name");

    NSString *nameError = ScriptingValidateConfigName(configName);
    if (nameError)
        return ScriptingError(self, 1000, nameError);

    if ([EmulatorBridge sessionState] != ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot start config: emulation is already running or paused");

    if (![ConfigBridge configExists:configName])
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Config not found: '%@'", configName]);

    if (![EmulatorBridge startEmulationForConfig:configName])
    {
        NSString *error = [EmulatorBridge lastStartError];
        if (error.length > 0)
            return ScriptingError(self, 1200, error);
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Failed to load config: '%@'", configName]);
    }

    return nil;
}

@end
