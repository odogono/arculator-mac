//
//  AutomationScriptingCommands.mm
//  Arculator
//
//  AppleScript commands: move guest mouse to, clear injected input,
//  capture emulation screenshot, copy emulation screenshot.
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

static BOOL ScriptingScreenshotSessionAvailable(void)
{
    return [EmulatorBridge sessionState] != ARCSessionStateIdle;
}

@interface CaptureEmulationScreenshotCommand : NSScriptCommand
@end

@implementation CaptureEmulationScreenshotCommand

- (id)performDefaultImplementation
{
    NSString *path = self.directParameter;
    if (!path || ![path isKindOfClass:[NSString class]] || path.length == 0)
        return ScriptingError(self, 1000, @"Missing destination file path");

    if (!ScriptingScreenshotSessionAvailable())
        return ScriptingError(self, 1100, @"Cannot capture screenshot: emulation is not active");

    NSString *error = [EmulatorBridge captureScreenshotToPath:path];
    if (error)
        return ScriptingError(self, 1200, error);

    return path;
}

@end

#pragma mark - copy emulation screenshot

@interface CopyEmulationScreenshotCommand : NSScriptCommand
@end

@implementation CopyEmulationScreenshotCommand

- (id)performDefaultImplementation
{
    if (!ScriptingScreenshotSessionAvailable())
        return ScriptingError(self, 1100, @"Cannot copy screenshot: emulation is not active");

    NSString *error = [EmulatorBridge copyScreenshotToPasteboard];
    if (error)
        return ScriptingError(self, 1200, error);

    return nil;
}

@end
