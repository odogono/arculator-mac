#import <XCTest/XCTest.h>

#include "macos/release_shortcut_logic.h"

@interface ReleaseShortcutLogicTests : XCTestCase
@end

@implementation ReleaseShortcutLogicTests

- (void)testShortcutMatchingRequiresExactModifiersAndMainKey
{
    uint32_t configuredModifiers = ARC_RELEASE_MODIFIER_COMMAND | ARC_RELEASE_MODIFIER_SHIFT;
    int configuredKey = KEYCODE_MACOS(kVK_Delete);

    XCTAssertTrue(
        arc_release_shortcut_matches(configuredModifiers, configuredKey,
                                     configuredModifiers, configuredKey),
        @"Exact modifier and key match should trigger the release shortcut");

    XCTAssertFalse(
        arc_release_shortcut_matches(ARC_RELEASE_MODIFIER_COMMAND, configuredKey,
                                     configuredModifiers, configuredKey),
        @"Missing a configured modifier should not trigger the release shortcut");

    XCTAssertFalse(
        arc_release_shortcut_matches(configuredModifiers | ARC_RELEASE_MODIFIER_OPTION, configuredKey,
                                     configuredModifiers, configuredKey),
        @"Extra modifiers should not trigger the release shortcut");

    XCTAssertFalse(
        arc_release_shortcut_matches(configuredModifiers, KEYCODE_MACOS(kVK_Return),
                                     configuredModifiers, configuredKey),
        @"Wrong main key should not trigger the release shortcut");
}

- (void)testModifierMaskNormalizationUsesOnlySupportedModifiers
{
    NSEventModifierFlags flags = NSEventModifierFlagCommand |
        NSEventModifierFlagControl |
        NSEventModifierFlagCapsLock;
    uint32_t mask = arc_release_shortcut_modifier_mask_from_flags((uint64_t)flags);

    XCTAssertEqual(mask,
                   ARC_RELEASE_MODIFIER_COMMAND | ARC_RELEASE_MODIFIER_CONTROL,
                   @"Only command/control/option/shift should participate in matching");
}

- (void)testSuppressedKeyExpansionCoversBothSidesOfEachModifier
{
    int keys[9] = {0};
    int count = arc_release_shortcut_fill_suppressed_keys(
        ARC_RELEASE_MODIFIER_COMMAND | ARC_RELEASE_MODIFIER_OPTION,
        KEYCODE_MACOS(kVK_Delete),
        keys,
        9);

    XCTAssertEqual(count, 5, @"Command + Option + main key should expand to five suppressed keys");
    XCTAssertEqual(keys[0], KEY_LWIN);
    XCTAssertEqual(keys[1], KEY_RWIN);
    XCTAssertEqual(keys[2], KEY_ALT);
    XCTAssertEqual(keys[3], KEY_ALTGR);
    XCTAssertEqual(keys[4], KEYCODE_MACOS(kVK_Delete));
}

@end
