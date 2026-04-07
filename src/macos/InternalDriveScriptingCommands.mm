//
//  InternalDriveScriptingCommands.mm
//  Arculator
//
//  AppleScript commands: internal drive info, set internal drive,
//  eject internal drive, create hard disc image.
//

#import <Foundation/Foundation.h>
#import "EmulatorBridge.h"
#import "ConfigBridge.h"
#import "ScriptingCommandSupport.h"

static int driveIndexFromNumber(int driveNumber)
{
    // User-facing drive numbers are 4 and 5; internal indices are 0 and 1.
    if (driveNumber == 4) return 0;
    if (driveNumber == 5) return 1;
    return -1;
}

// Validates the direct parameter as a drive number (4 or 5) and returns the internal index.
// On failure, sets the script error and returns -1.
static int validatedDriveIndex(NSScriptCommand *cmd)
{
    NSNumber *driveNum = cmd.directParameter;
    if (!driveNum || ![driveNum isKindOfClass:[NSNumber class]])
    {
        ScriptingError(cmd, 1000, @"Missing drive number (4 or 5)");
        return -1;
    }

    int index = driveIndexFromNumber(driveNum.intValue);
    if (index < 0)
        ScriptingError(cmd, 1000,
            [NSString stringWithFormat:@"Invalid drive number %d (must be 4 or 5)", driveNum.intValue]);

    return index;
}

#pragma mark - internal drive info

@interface InternalDriveInfoCommand : NSScriptCommand
@end

@implementation InternalDriveInfoCommand

- (id)performDefaultImplementation
{
    int index = validatedDriveIndex(self);
    if (index < 0)
        return nil;

    return [ConfigBridge internalDriveInfoForIndex:index];
}

@end

#pragma mark - set internal drive

@interface SetInternalDriveCommand : NSScriptCommand
@end

@implementation SetInternalDriveCommand

- (id)performDefaultImplementation
{
    int index = validatedDriveIndex(self);
    if (index < 0)
        return nil;

    if ([EmulatorBridge sessionState] != ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot set internal drive: emulation must be idle");

    NSDictionary *args = self.evaluatedArguments;
    NSString *path = args[@"path"];
    NSNumber *cylinders = args[@"cylinders"];
    NSNumber *heads = args[@"heads"];
    NSNumber *sectors = args[@"sectors"];

    if (!path || !cylinders || !heads || !sectors)
        return ScriptingError(self, 1000, @"Missing required parameter (path, cylinders, heads, sectors)");

    NSString *error = [ConfigBridge setInternalDriveIndex:index
                                                    path:path
                                               cylinders:cylinders.intValue
                                                   heads:heads.intValue
                                                 sectors:sectors.intValue];
    if (error)
        return ScriptingError(self, 1000, error);

    return nil;
}

@end

#pragma mark - eject internal drive

@interface EjectInternalDriveCommand : NSScriptCommand
@end

@implementation EjectInternalDriveCommand

- (id)performDefaultImplementation
{
    int index = validatedDriveIndex(self);
    if (index < 0)
        return nil;

    if ([EmulatorBridge sessionState] != ARCSessionStateIdle)
        return ScriptingError(self, 1100, @"Cannot eject internal drive: emulation must be idle");

    NSString *error = [ConfigBridge ejectInternalDriveIndex:index];
    if (error)
        return ScriptingError(self, 1000, error);

    return nil;
}

@end

#pragma mark - create hard disc image

@interface CreateHardDiscImageCommand : NSScriptCommand
@end

@implementation CreateHardDiscImageCommand

- (id)performDefaultImplementation
{
    NSString *path = self.directParameter;
    if (!path || ![path isKindOfClass:[NSString class]] || path.length == 0)
        return ScriptingError(self, 1000, @"Missing destination path");

    NSDictionary *args = self.evaluatedArguments;
    NSNumber *cylinders = args[@"cylinders"];
    NSNumber *heads = args[@"heads"];
    NSNumber *sectors = args[@"sectors"];

    if (!cylinders || !heads || !sectors)
        return ScriptingError(self, 1000, @"Missing required geometry parameter (cylinders, heads, sectors)");

    NSString *controller = args[@"controller"];
    BOOL isST506 = NO;
    if (controller)
    {
        NSString *lower = [controller lowercaseString];
        if ([lower isEqualToString:@"st506"])
            isST506 = YES;
        else if (![lower isEqualToString:@"ide"])
            return ScriptingError(self, 1000,
                [NSString stringWithFormat:@"Unknown controller kind '%@' (must be 'ide' or 'st506')", controller]);
    }

    NSString *initialization = args[@"initialization"];
    BOOL ready = NO;
    if (initialization)
    {
        NSString *lower = [initialization lowercaseString];
        if ([lower isEqualToString:@"ready"])
            ready = YES;
        else if (![lower isEqualToString:@"blank"])
            return ScriptingError(self, 1000,
                [NSString stringWithFormat:@"Unknown initialization mode '%@' (must be 'blank' or 'ready')", initialization]);
    }

    NSString *error;
    if (ready)
    {
        error = [ConfigBridge createReadyHDFAtPath:path
                                         cylinders:cylinders.intValue
                                             heads:heads.intValue
                                           sectors:sectors.intValue
                                           isST506:isST506];
    }
    else
    {
        error = [ConfigBridge createBlankHDFAtPath:path
                                         cylinders:cylinders.intValue
                                             heads:heads.intValue
                                           sectors:sectors.intValue
                                           isST506:isST506];
    }

    if (error)
        return ScriptingError(self, 1200, error);

    return @{
        @"path": path,
        @"cylinders": cylinders,
        @"heads": heads,
        @"sectors": sectors,
        @"controller": isST506 ? @"st506" : @"ide",
        @"initialization": ready ? @"ready" : @"blank"
    };
}

@end
