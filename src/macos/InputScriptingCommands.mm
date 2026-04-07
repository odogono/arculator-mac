//
//  InputScriptingCommands.mm
//  Arculator
//
//  AppleScript commands: inject key down/up, type text, inject mouse move/down/up.
//

#import <Foundation/Foundation.h>
#import "EmulatorBridge.h"
#import "InputInjectionBridge.h"
#import "ScriptingCommandSupport.h"

#pragma mark - inject key down

@interface InjectKeyDownCommand : NSScriptCommand
@end

@implementation InjectKeyDownCommand

- (id)performDefaultImplementation
{
    NSString *keyName = self.directParameter;
    if (!keyName || ![keyName isKindOfClass:[NSString class]])
        return ScriptingError(self, 1000, @"Missing key name");

    if ([EmulatorBridge sessionState] != ARCSessionStateRunning)
        return ScriptingError(self, 1100, @"Cannot inject key: emulation is not running");

    if (![InputInjectionBridge injectKeyDown:keyName])
        return ScriptingError(self, 1000,
            [NSString stringWithFormat:@"Unknown key name: '%@'", keyName]);

    return nil;
}

@end

#pragma mark - inject key up

@interface InjectKeyUpCommand : NSScriptCommand
@end

@implementation InjectKeyUpCommand

- (id)performDefaultImplementation
{
    NSString *keyName = self.directParameter;
    if (!keyName || ![keyName isKindOfClass:[NSString class]])
        return ScriptingError(self, 1000, @"Missing key name");

    if ([EmulatorBridge sessionState] != ARCSessionStateRunning)
        return ScriptingError(self, 1100, @"Cannot inject key: emulation is not running");

    if (![InputInjectionBridge injectKeyUp:keyName])
        return ScriptingError(self, 1000,
            [NSString stringWithFormat:@"Unknown key name: '%@'", keyName]);

    return nil;
}

@end

#pragma mark - type text

@interface TypeTextCommand : NSScriptCommand
@end

@implementation TypeTextCommand

- (id)performDefaultImplementation
{
    NSString *text = self.directParameter;
    if (!text || ![text isKindOfClass:[NSString class]])
        return ScriptingError(self, 1000, @"Missing text to type");

    if (text.length == 0)
        return nil;

    // typeText:forCommand: handles state validation, suspend/resume, and errors
    [InputInjectionBridge typeText:text forCommand:self];
    return nil;
}

@end

#pragma mark - inject mouse move

@interface InjectMouseMoveCommand : NSScriptCommand
@end

@implementation InjectMouseMoveCommand

- (id)performDefaultImplementation
{
    if ([EmulatorBridge sessionState] != ARCSessionStateRunning)
        return ScriptingError(self, 1100, @"Cannot inject mouse: emulation is not running");

    NSNumber *dxNum = [self.evaluatedArguments objectForKey:@"dx"];
    NSNumber *dyNum = [self.evaluatedArguments objectForKey:@"dy"];

    if (!dxNum || !dyNum)
        return ScriptingError(self, 1000, @"Missing dx or dy parameter");

    [InputInjectionBridge injectMouseMoveDx:dxNum.intValue dy:dyNum.intValue];
    return nil;
}

@end

#pragma mark - inject mouse down

@interface InjectMouseDownCommand : NSScriptCommand
@end

@implementation InjectMouseDownCommand

- (id)performDefaultImplementation
{
    if ([EmulatorBridge sessionState] != ARCSessionStateRunning)
        return ScriptingError(self, 1100, @"Cannot inject mouse: emulation is not running");

    NSNumber *buttonNum = [self.evaluatedArguments objectForKey:@"button"];
    int button = buttonNum ? buttonNum.intValue : 1;

    [InputInjectionBridge injectMouseButtonDown:button];
    return nil;
}

@end

#pragma mark - inject mouse up

@interface InjectMouseUpCommand : NSScriptCommand
@end

@implementation InjectMouseUpCommand

- (id)performDefaultImplementation
{
    if ([EmulatorBridge sessionState] != ARCSessionStateRunning)
        return ScriptingError(self, 1100, @"Cannot inject mouse: emulation is not running");

    NSNumber *buttonNum = [self.evaluatedArguments objectForKey:@"button"];
    int button = buttonNum ? buttonNum.intValue : 1;

    [InputInjectionBridge injectMouseButtonUp:button];
    return nil;
}

@end
