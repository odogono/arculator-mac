//
//  NSApplication+Scripting.mm
//  Arculator
//
//  KVC accessors for AppleScript application-level properties.
//

#import <AppKit/AppKit.h>
#import "EmulatorBridge.h"
#import "ConfigBridge.h"

extern "C" {
#include "arc.h"
}

@implementation NSApplication (ArculatorScripting)

- (NSString *)scriptingEmulationState
{
    switch ([EmulatorBridge sessionState])
    {
        case ARCSessionStateRunning: return @"running";
        case ARCSessionStatePaused:  return @"paused";
        default:                     return @"idle";
    }
}

- (NSString *)scriptingActiveConfig
{
    return [EmulatorBridge activeConfigName];
}

- (NSNumber *)scriptingSpeed
{
    return @(inssec);
}

- (NSArray<NSString *> *)scriptingDiscNames
{
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:4];
    for (int i = 0; i < 4; i++)
    {
        if (discname[i][0] != '\0')
            [names addObject:[NSString stringWithUTF8String:discname[i]] ?: @""];
        else
            [names addObject:@""];
    }
    return names;
}

- (NSArray<NSString *> *)scriptingConfigNames
{
    return [ConfigBridge listConfigNames];
}

@end
