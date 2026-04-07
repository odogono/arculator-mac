//
//  ConfigScriptingCommands.mm
//  Arculator
//
//  AppleScript commands: load/create/copy/delete config, change/eject disc.
//

#import <Foundation/Foundation.h>
#import "EmulatorBridge.h"
#import "ConfigBridge.h"
#import "ScriptingCommandSupport.h"

#pragma mark - load config

@interface LoadConfigCommand : NSScriptCommand
@end

@implementation LoadConfigCommand

- (id)performDefaultImplementation
{
    NSString *configName = self.directParameter;
    if (!configName || ![configName isKindOfClass:[NSString class]])
        return ScriptingError(self, 1000, @"Missing config name");

    NSString *nameError = ScriptingValidateConfigName(configName);
    if (nameError)
        return ScriptingError(self, 1000, nameError);

    if ([EmulatorBridge sessionState] != ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot load config: emulation is running");

    if (![ConfigBridge configExists:configName])
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Config not found: '%@'", configName]);

    if (![ConfigBridge loadConfigNamed:configName])
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Failed to load config: '%@'", configName]);

    return nil;
}

@end

#pragma mark - create config

@interface CreateConfigCommand : NSScriptCommand
@end

@implementation CreateConfigCommand

- (id)performDefaultImplementation
{
    NSString *configName = self.directParameter;
    if (!configName || ![configName isKindOfClass:[NSString class]])
        return ScriptingError(self, 1000, @"Missing config name");

    NSString *nameError = ScriptingValidateConfigName(configName);
    if (nameError)
        return ScriptingError(self, 1000, nameError);

    if ([EmulatorBridge sessionState] != ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot create config while emulation is active");

    if ([ConfigBridge configExists:configName])
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Config already exists: '%@'", configName]);

    NSNumber *presetNum = [self.evaluatedArguments objectForKey:@"withPreset"];
    int preset = presetNum ? presetNum.intValue : 0;

    if (![ConfigBridge createConfig:configName withPresetIndex:preset])
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Failed to create config: '%@'", configName]);

    return nil;
}

@end

#pragma mark - copy config

@interface CopyConfigCommand : NSScriptCommand
@end

@implementation CopyConfigCommand

- (id)performDefaultImplementation
{
    NSString *sourceName = self.directParameter;
    if (!sourceName || ![sourceName isKindOfClass:[NSString class]])
        return ScriptingError(self, 1000, @"Missing source config name");

    NSString *destName = [self.evaluatedArguments objectForKey:@"to"];
    if (!destName || ![destName isKindOfClass:[NSString class]])
        return ScriptingError(self, 1000, @"Missing destination config name ('to' parameter)");

    NSString *sourceError = ScriptingValidateConfigName(sourceName);
    if (sourceError)
        return ScriptingError(self, 1000, [NSString stringWithFormat:@"Source: %@", sourceError]);

    NSString *destError = ScriptingValidateConfigName(destName);
    if (destError)
        return ScriptingError(self, 1000, [NSString stringWithFormat:@"Destination: %@", destError]);

    if ([EmulatorBridge sessionState] != ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot copy config while emulation is active");

    if (![ConfigBridge configExists:sourceName])
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Source config not found: '%@'", sourceName]);

    if ([ConfigBridge configExists:destName])
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Destination config already exists: '%@'", destName]);

    if (![ConfigBridge copyConfig:sourceName to:destName])
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Failed to copy config '%@' to '%@'", sourceName, destName]);

    return nil;
}

@end

#pragma mark - delete config

@interface DeleteConfigCommand : NSScriptCommand
@end

@implementation DeleteConfigCommand

- (id)performDefaultImplementation
{
    NSString *configName = self.directParameter;
    if (!configName || ![configName isKindOfClass:[NSString class]])
        return ScriptingError(self, 1000, @"Missing config name");

    NSString *nameError = ScriptingValidateConfigName(configName);
    if (nameError)
        return ScriptingError(self, 1000, nameError);

    if ([EmulatorBridge sessionState] != ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot delete config while emulation is active");

    if (![ConfigBridge configExists:configName])
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Config not found: '%@'", configName]);

    if (![ConfigBridge deleteConfig:configName])
        return ScriptingError(self, 1200,
            [NSString stringWithFormat:@"Failed to delete config: '%@'", configName]);

    return nil;
}

@end

#pragma mark - change disc

@interface ChangeDiscCommand : NSScriptCommand
@end

@implementation ChangeDiscCommand

- (id)performDefaultImplementation
{
    NSString *path = self.directParameter;
    if (!path || ![path isKindOfClass:[NSString class]])
        return ScriptingError(self, 1000, @"Missing disc image path");

    NSNumber *driveNum = [self.evaluatedArguments objectForKey:@"drive"];
    int drive = driveNum ? driveNum.intValue : 0;

    if (drive < 0 || drive > 3)
        return ScriptingError(self, 1000,
            [NSString stringWithFormat:@"Invalid drive number %d (must be 0-3)", drive]);

    ARCSessionState state = [EmulatorBridge sessionState];
    if (state == ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot change disc: emulation is not running");

    [EmulatorBridge changeDisc:drive path:path];
    return nil;
}

@end

#pragma mark - eject disc

@interface EjectDiscCommand : NSScriptCommand
@end

@implementation EjectDiscCommand

- (id)performDefaultImplementation
{
    NSNumber *driveNum = [self.evaluatedArguments objectForKey:@"drive"];
    int drive = driveNum ? driveNum.intValue : 0;

    if (drive < 0 || drive > 3)
        return ScriptingError(self, 1000,
            [NSString stringWithFormat:@"Invalid drive number %d (must be 0-3)", drive]);

    ARCSessionState state = [EmulatorBridge sessionState];
    if (state == ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot eject disc: emulation is not running");

    [EmulatorBridge ejectDisc:drive];
    return nil;
}

@end
