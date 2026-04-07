//
//  ScriptingCommandSupport.mm
//  Arculator
//
//  Shared state/config validation for AppleScript commands.
//

#import "ScriptingCommandSupport.h"

NSString *ScriptingValidateConfigName(NSString *name)
{
    // Trim whitespace
    NSString *trimmed = [name stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (trimmed.length == 0)
        return @"Config name cannot be empty";

    // Reject path traversal
    if ([trimmed rangeOfString:@".."].location != NSNotFound)
        return @"Config name cannot contain '..'";

    // Allow only: ASCII letters, digits, space, _ - + . ( )
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-+.()"];
    NSCharacterSet *disallowed = [allowed invertedSet];

    NSRange bad = [trimmed rangeOfCharacterFromSet:disallowed];
    if (bad.location != NSNotFound)
    {
        unichar ch = [trimmed characterAtIndex:bad.location];
        return [NSString stringWithFormat:@"Config name contains invalid character '%C' (U+%04X)", ch, ch];
    }

    return nil;
}
