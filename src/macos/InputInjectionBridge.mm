//
//  InputInjectionBridge.mm
//  Arculator
//
//  Key name table, type text, and mouse injection methods.
//

#import "InputInjectionBridge.h"
#import "EmulatorBridge.h"

extern "C" {
#include "plat_input.h"
}

#pragma mark - Key name table

static NSDictionary<NSString *, NSNumber *> *sKeyNameTable;
static dispatch_once_t sKeyNameTableOnce;

static void buildKeyNameTable(void)
{
    sKeyNameTable = @{
        // Letters
        @"a": @(KEY_A), @"b": @(KEY_B), @"c": @(KEY_C), @"d": @(KEY_D),
        @"e": @(KEY_E), @"f": @(KEY_F), @"g": @(KEY_G), @"h": @(KEY_H),
        @"i": @(KEY_I), @"j": @(KEY_J), @"k": @(KEY_K), @"l": @(KEY_L),
        @"m": @(KEY_M), @"n": @(KEY_N), @"o": @(KEY_O), @"p": @(KEY_P),
        @"q": @(KEY_Q), @"r": @(KEY_R), @"s": @(KEY_S), @"t": @(KEY_T),
        @"u": @(KEY_U), @"v": @(KEY_V), @"w": @(KEY_W), @"x": @(KEY_X),
        @"y": @(KEY_Y), @"z": @(KEY_Z),

        // Digits
        @"0": @(KEY_0), @"1": @(KEY_1), @"2": @(KEY_2), @"3": @(KEY_3),
        @"4": @(KEY_4), @"5": @(KEY_5), @"6": @(KEY_6), @"7": @(KEY_7),
        @"8": @(KEY_8), @"9": @(KEY_9),

        // Named keys
        @"escape": @(KEY_ESC), @"esc": @(KEY_ESC),
        @"return": @(KEY_ENTER), @"enter": @(KEY_ENTER),
        @"space": @(KEY_SPACE),
        @"tab": @(KEY_TAB),
        @"backspace": @(KEY_BACKSPACE),
        @"delete": @(KEY_DEL),
        @"insert": @(KEY_INSERT),
        @"home": @(KEY_HOME),
        @"end": @(KEY_END),
        @"pageup": @(KEY_PGUP),
        @"pagedown": @(KEY_PGDN),

        // Arrow keys
        @"up": @(KEY_UP), @"down": @(KEY_DOWN),
        @"left": @(KEY_LEFT), @"right": @(KEY_RIGHT),

        // Modifiers
        @"shift": @(KEY_LSHIFT), @"lshift": @(KEY_LSHIFT), @"rshift": @(KEY_RSHIFT),
        @"control": @(KEY_LCONTROL), @"ctrl": @(KEY_LCONTROL),
        @"lcontrol": @(KEY_LCONTROL), @"rcontrol": @(KEY_RCONTROL),
        @"alt": @(KEY_ALT), @"lalt": @(KEY_ALT),
        @"altgr": @(KEY_ALTGR), @"ralt": @(KEY_ALTGR),
        @"capslock": @(KEY_CAPSLOCK),

        // Function keys
        @"f1": @(KEY_F1), @"f2": @(KEY_F2), @"f3": @(KEY_F3),
        @"f4": @(KEY_F4), @"f5": @(KEY_F5), @"f6": @(KEY_F6),
        @"f7": @(KEY_F7), @"f8": @(KEY_F8), @"f9": @(KEY_F9),
        @"f10": @(KEY_F10), @"f11": @(KEY_F11), @"f12": @(KEY_F12),

        // Punctuation / symbols
        @"minus": @(KEY_MINUS), @"-": @(KEY_MINUS),
        @"equals": @(KEY_EQUALS), @"=": @(KEY_EQUALS),
        @"openbrace": @(KEY_OPENBRACE), @"[": @(KEY_OPENBRACE),
        @"closebrace": @(KEY_CLOSEBRACE), @"]": @(KEY_CLOSEBRACE),
        @"backslash": @(KEY_BACKSLASH), @"\\": @(KEY_BACKSLASH),
        @"semicolon": @(KEY_COLON), @";": @(KEY_COLON),
        @"quote": @(KEY_QUOTE), @"'": @(KEY_QUOTE),
        @"tilde": @(KEY_TILDE), @"`": @(KEY_TILDE),
        @"comma": @(KEY_COMMA), @",": @(KEY_COMMA),
        @"period": @(KEY_STOP), @".": @(KEY_STOP),
        @"slash": @(KEY_SLASH), @"/": @(KEY_SLASH),

        // Numpad
        @"numlock": @(KEY_NUMLOCK), @"scrolllock": @(KEY_SCRLOCK),
        @"num0": @(KEY_0_PAD), @"num1": @(KEY_1_PAD), @"num2": @(KEY_2_PAD),
        @"num3": @(KEY_3_PAD), @"num4": @(KEY_4_PAD), @"num5": @(KEY_5_PAD),
        @"num6": @(KEY_6_PAD), @"num7": @(KEY_7_PAD), @"num8": @(KEY_8_PAD),
        @"num9": @(KEY_9_PAD),
        @"numenter": @(KEY_ENTER_PAD), @"numdel": @(KEY_DEL_PAD),
        @"numplus": @(KEY_PLUS_PAD), @"numminus": @(KEY_MINUS_PAD),
        @"numstar": @(KEY_ASTERISK), @"numslash": @(KEY_SLASH_PAD),

        // Misc
        @"printscreen": @(KEY_PRTSCR), @"pause": @(KEY_PAUSE),
        @"lwin": @(KEY_LWIN), @"rwin": @(KEY_RWIN),
    };
}

#pragma mark - ASCII to keycode table for type text

typedef struct {
    int keycode;
    BOOL needsShift;
} AsciiKeyEntry;

// Maps ASCII 32..126 to (keycode, needsShift)
static const AsciiKeyEntry sAsciiTable[128] = {
    // 0-31: control chars — unused (keycode 0 = unsupported)
    [0 ... 31] = {0, NO},
    // 32: space
    [' '] = {KEY_SPACE, NO},
    // 33-47: punctuation
    ['!'] = {KEY_1, YES},
    ['"'] = {KEY_2, YES},       // UK layout: Shift+2
    ['#'] = {KEY_3, YES},       // UK layout: Shift+3 (not £)
    ['$'] = {KEY_4, YES},
    ['%'] = {KEY_5, YES},
    ['^'] = {KEY_6, YES},
    ['&'] = {KEY_7, YES},
    ['*'] = {KEY_8, YES},
    ['('] = {KEY_9, YES},
    [')'] = {KEY_0, YES},
    ['-'] = {KEY_MINUS, NO},
    ['_'] = {KEY_MINUS, YES},
    ['='] = {KEY_EQUALS, NO},
    ['+'] = {KEY_EQUALS, YES},
    ['['] = {KEY_OPENBRACE, NO},
    ['{'] = {KEY_OPENBRACE, YES},
    [']'] = {KEY_CLOSEBRACE, NO},
    ['}'] = {KEY_CLOSEBRACE, YES},
    ['\\'] = {KEY_BACKSLASH, NO},
    ['|'] = {KEY_BACKSLASH, YES},
    [';'] = {KEY_COLON, NO},
    [':'] = {KEY_COLON, YES},
    ['\''] = {KEY_QUOTE, NO},
    ['@'] = {KEY_QUOTE, YES},   // UK layout: Shift+' = @
    ['`'] = {KEY_TILDE, NO},
    ['~'] = {KEY_TILDE, YES},
    [','] = {KEY_COMMA, NO},
    ['<'] = {KEY_COMMA, YES},
    ['.'] = {KEY_STOP, NO},
    ['>'] = {KEY_STOP, YES},
    ['/'] = {KEY_SLASH, NO},
    ['?'] = {KEY_SLASH, YES},
    // 48-57: digits
    ['0'] = {KEY_0, NO}, ['1'] = {KEY_1, NO}, ['2'] = {KEY_2, NO},
    ['3'] = {KEY_3, NO}, ['4'] = {KEY_4, NO}, ['5'] = {KEY_5, NO},
    ['6'] = {KEY_6, NO}, ['7'] = {KEY_7, NO}, ['8'] = {KEY_8, NO},
    ['9'] = {KEY_9, NO},
    // 65-90: uppercase letters
    ['A'] = {KEY_A, YES}, ['B'] = {KEY_B, YES}, ['C'] = {KEY_C, YES},
    ['D'] = {KEY_D, YES}, ['E'] = {KEY_E, YES}, ['F'] = {KEY_F, YES},
    ['G'] = {KEY_G, YES}, ['H'] = {KEY_H, YES}, ['I'] = {KEY_I, YES},
    ['J'] = {KEY_J, YES}, ['K'] = {KEY_K, YES}, ['L'] = {KEY_L, YES},
    ['M'] = {KEY_M, YES}, ['N'] = {KEY_N, YES}, ['O'] = {KEY_O, YES},
    ['P'] = {KEY_P, YES}, ['Q'] = {KEY_Q, YES}, ['R'] = {KEY_R, YES},
    ['S'] = {KEY_S, YES}, ['T'] = {KEY_T, YES}, ['U'] = {KEY_U, YES},
    ['V'] = {KEY_V, YES}, ['W'] = {KEY_W, YES}, ['X'] = {KEY_X, YES},
    ['Y'] = {KEY_Y, YES}, ['Z'] = {KEY_Z, YES},
    // 97-122: lowercase letters
    ['a'] = {KEY_A, NO}, ['b'] = {KEY_B, NO}, ['c'] = {KEY_C, NO},
    ['d'] = {KEY_D, NO}, ['e'] = {KEY_E, NO}, ['f'] = {KEY_F, NO},
    ['g'] = {KEY_G, NO}, ['h'] = {KEY_H, NO}, ['i'] = {KEY_I, NO},
    ['j'] = {KEY_J, NO}, ['k'] = {KEY_K, NO}, ['l'] = {KEY_L, NO},
    ['m'] = {KEY_M, NO}, ['n'] = {KEY_N, NO}, ['o'] = {KEY_O, NO},
    ['p'] = {KEY_P, NO}, ['q'] = {KEY_Q, NO}, ['r'] = {KEY_R, NO},
    ['s'] = {KEY_S, NO}, ['t'] = {KEY_T, NO}, ['u'] = {KEY_U, NO},
    ['v'] = {KEY_V, NO}, ['w'] = {KEY_W, NO}, ['x'] = {KEY_X, NO},
    ['y'] = {KEY_Y, NO}, ['z'] = {KEY_Z, NO},
    // 127: DEL — unsupported in type text
    [127] = {0, NO},
};

#pragma mark - Generation token for type text cancellation

static int64_t sTypeTextGeneration = 0;
static dispatch_queue_t sTypeTextQueue;
static dispatch_once_t sTypeTextQueueOnce;

static dispatch_queue_t typeTextQueue(void)
{
    dispatch_once(&sTypeTextQueueOnce, ^{
        sTypeTextQueue = dispatch_queue_create("com.arculator.typetext", DISPATCH_QUEUE_SERIAL);
    });
    return sTypeTextQueue;
}

#pragma mark - Implementation

@implementation InputInjectionBridge

+ (int)keycodeForName:(NSString *)keyName
{
    dispatch_once(&sKeyNameTableOnce, ^{ buildKeyNameTable(); });

    NSNumber *code = sKeyNameTable[keyName.lowercaseString];
    return code ? code.intValue : -1;
}

+ (BOOL)injectKeyDown:(NSString *)keyName
{
    int code = [self keycodeForName:keyName];
    if (code < 0)
        return NO;
    input_inject_key(code, 1);
    return YES;
}

+ (BOOL)injectKeyUp:(NSString *)keyName
{
    int code = [self keycodeForName:keyName];
    if (code < 0)
        return NO;
    input_inject_key(code, 0);
    return YES;
}

+ (void)typeText:(NSString *)text
      forCommand:(NSScriptCommand *)command
{
    // Pre-validate: check all characters are supported
    for (NSUInteger i = 0; i < text.length; i++)
    {
        unichar ch = [text characterAtIndex:i];
        if (ch >= 128 || sAsciiTable[ch].keycode == 0)
        {
            [command setScriptErrorNumber:1000];
            [command setScriptErrorString:
                [NSString stringWithFormat:@"Unsupported character '%C' (U+%04X) at position %lu",
                    ch, ch, (unsigned long)i]];
            return;
        }
    }

    // Must be running
    if ([EmulatorBridge sessionState] != ARCSessionStateRunning)
    {
        [command setScriptErrorNumber:1100];
        [command setScriptErrorString:@"Cannot type text: emulation is not running"];
        return;
    }

    // Bump generation to cancel any in-flight sequence
    int64_t generation = ++sTypeTextGeneration;

    [command suspendExecution];

    dispatch_async(typeTextQueue(), ^{
        BOOL shiftHeld = NO;

        for (NSUInteger i = 0; i < text.length; i++)
        {
            // Check cancellation: generation changed or emulation stopped
            if (sTypeTextGeneration != generation)
            {
                if (shiftHeld)
                {
                    input_inject_key(KEY_LSHIFT, 0);
                    shiftHeld = NO;
                }
                input_inject_clear_all_keys();
                [command setScriptErrorNumber:1300];
                [command setScriptErrorString:@"type text cancelled: superseded by new command"];
                [command resumeExecutionWithResult:nil];
                return;
            }

            if ([EmulatorBridge sessionState] != ARCSessionStateRunning)
            {
                if (shiftHeld)
                {
                    input_inject_key(KEY_LSHIFT, 0);
                    shiftHeld = NO;
                }
                input_inject_clear_all_keys();
                [command setScriptErrorNumber:1300];
                [command setScriptErrorString:@"type text cancelled: emulation stopped or paused"];
                [command resumeExecutionWithResult:nil];
                return;
            }

            unichar ch = [text characterAtIndex:i];
            AsciiKeyEntry entry = sAsciiTable[ch];

            // Handle shift transitions
            if (entry.needsShift && !shiftHeld)
            {
                input_inject_key(KEY_LSHIFT, 1);
                shiftHeld = YES;
                [NSThread sleepForTimeInterval:0.020];
            }
            else if (!entry.needsShift && shiftHeld)
            {
                input_inject_key(KEY_LSHIFT, 0);
                shiftHeld = NO;
                [NSThread sleepForTimeInterval:0.020];
            }

            // Key down
            input_inject_key(entry.keycode, 1);
            [NSThread sleepForTimeInterval:0.020];

            // Key up
            input_inject_key(entry.keycode, 0);
            [NSThread sleepForTimeInterval:0.020];
        }

        // Release shift if still held
        if (shiftHeld)
        {
            input_inject_key(KEY_LSHIFT, 0);
            [NSThread sleepForTimeInterval:0.020];
        }

        // Clear all injected keys when done
        input_inject_clear_all_keys();

        [command resumeExecutionWithResult:nil];
    });
}

+ (void)injectMouseMoveDx:(int)dx dy:(int)dy
{
    input_inject_mouse_move(dx, dy);
}

+ (void)injectMouseAbsX:(int)x y:(int)y
{
    input_inject_mouse_abs(x, y);
}

+ (void)injectMouseButtonDown:(int)buttonMask
{
    input_inject_mouse_button(buttonMask, 1);
}

+ (void)injectMouseButtonUp:(int)buttonMask
{
    input_inject_mouse_button(buttonMask, 0);
}

+ (void)clearAllInjectedKeys
{
    input_inject_clear_all_keys();
}

+ (void)clearInjectedMouse
{
    input_inject_clear_mouse();
}

+ (void)clearAllInjectedInput
{
    input_inject_clear_all_keys();
    input_inject_clear_mouse();
}

@end
