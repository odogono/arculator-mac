//
//  AutomationScriptingCommands.mm
//  Arculator
//
//  AppleScript commands: move guest mouse to, clear injected input,
//  capture emulation screenshot.
//

#import <Foundation/Foundation.h>
#import "EmulatorBridge.h"
#import "InputInjectionBridge.h"
#import "ScriptingCommandSupport.h"

#pragma mark - move guest mouse to

@interface MoveGuestMouseToCommand : NSScriptCommand
@end

@implementation MoveGuestMouseToCommand

- (id)performDefaultImplementation
{
    if ([EmulatorBridge sessionState] != ARCSessionStateRunning)
        return ScriptingError(self, 1100, @"Cannot move guest mouse: emulation is not running");

    NSNumber *xNum = [self.evaluatedArguments objectForKey:@"x"];
    NSNumber *yNum = [self.evaluatedArguments objectForKey:@"y"];

    if (!xNum || !yNum)
        return ScriptingError(self, 1000, @"Missing x or y parameter");

    [InputInjectionBridge injectMouseAbsX:xNum.intValue y:yNum.intValue];
    return nil;
}

@end

#pragma mark - clear injected input

@interface ClearInjectedInputCommand : NSScriptCommand
@end

@implementation ClearInjectedInputCommand

- (id)performDefaultImplementation
{
    [InputInjectionBridge clearAllInjectedInput];
    return nil;
}

@end

#pragma mark - capture emulation screenshot

@interface CaptureEmulationScreenshotCommand : NSScriptCommand
@end

@implementation CaptureEmulationScreenshotCommand

- (id)performDefaultImplementation
{
    NSString *path = self.directParameter;
    if (!path || ![path isKindOfClass:[NSString class]] || path.length == 0)
        return ScriptingError(self, 1000, @"Missing destination file path");

    if ([EmulatorBridge sessionState] != ARCSessionStateRunning)
        return ScriptingError(self, 1100, @"Cannot capture screenshot: emulation is not running");

    NSString *error = [EmulatorBridge captureScreenshotToPath:path];
    if (error)
        return ScriptingError(self, 1200, error);

    return path;
}

@end
