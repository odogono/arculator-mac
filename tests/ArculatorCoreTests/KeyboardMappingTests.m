#import <XCTest/XCTest.h>
#include "keyboard_macos.h"

@interface KeyboardMappingTests : XCTestCase
@end

@implementation KeyboardMappingTests

- (void)testKeyAIsNonZero
{
	/* Historical regression: kVK_ANSI_A == 0x00 on macOS.
	   Without the KEYCODE_MACOS_BIAS, KEY_A would be 0, which the
	   emulator treats as "no key". */
	XCTAssertNotEqual(KEY_A, 0, @"KEY_A must not be zero");
}

- (void)testBiasArithmetic
{
	XCTAssertEqual(KEYCODE_MACOS_BIAS, 1, @"Bias should be 1");
	XCTAssertEqual(KEY_A, kVK_ANSI_A + KEYCODE_MACOS_BIAS,
		@"KEY_A should equal kVK_ANSI_A + bias");
	XCTAssertEqual(KEY_A, 1, @"KEY_A should be 1 (0 + 1)");
}

- (void)testRoundTripBias
{
	/* KEYCODE_MACOS_TO_RAW(KEYCODE_MACOS(raw)) == raw for all raw codes. */
	int testCodes[] = {
		kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_Z, kVK_Space,
		kVK_Return, kVK_Escape, kVK_Tab, kVK_Delete,
		kVK_F1, kVK_F12, kVK_UpArrow, kVK_DownArrow
	};
	for (int i = 0; i < (int)(sizeof(testCodes) / sizeof(testCodes[0])); i++) {
		int raw = testCodes[i];
		int biased = KEYCODE_MACOS(raw);
		int roundTripped = KEYCODE_MACOS_TO_RAW(biased);
		XCTAssertEqual(roundTripped, raw,
			@"Round trip failed for raw 0x%02X: got 0x%02X", raw, roundTripped);
	}
}

- (void)testModifierKeysAreNonZeroAndDistinct
{
	XCTAssertNotEqual(KEY_LSHIFT, 0);
	XCTAssertNotEqual(KEY_LCONTROL, 0);
	XCTAssertNotEqual(KEY_ALT, 0);
	XCTAssertNotEqual(KEY_RSHIFT, 0);
	XCTAssertNotEqual(KEY_RCONTROL, 0);
	XCTAssertNotEqual(KEY_ALTGR, 0);

	/* All modifier keys should be distinct. */
	XCTAssertNotEqual(KEY_LSHIFT, KEY_RSHIFT);
	XCTAssertNotEqual(KEY_LCONTROL, KEY_RCONTROL);
	XCTAssertNotEqual(KEY_ALT, KEY_ALTGR);
	XCTAssertNotEqual(KEY_LSHIFT, KEY_LCONTROL);
	XCTAssertNotEqual(KEY_LSHIFT, KEY_ALT);
}

- (void)testKeypadKeysAreNonZero
{
	XCTAssertNotEqual(KEY_0_PAD, 0);
	XCTAssertNotEqual(KEY_1_PAD, 0);
	XCTAssertNotEqual(KEY_2_PAD, 0);
	XCTAssertNotEqual(KEY_3_PAD, 0);
	XCTAssertNotEqual(KEY_4_PAD, 0);
	XCTAssertNotEqual(KEY_5_PAD, 0);
	XCTAssertNotEqual(KEY_6_PAD, 0);
	XCTAssertNotEqual(KEY_7_PAD, 0);
	XCTAssertNotEqual(KEY_8_PAD, 0);
	XCTAssertNotEqual(KEY_9_PAD, 0);
}

- (void)testLetterKeysAreDistinct
{
	int letters[] = { KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G,
		KEY_H, KEY_I, KEY_J, KEY_K, KEY_L, KEY_M, KEY_N, KEY_O,
		KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W,
		KEY_X, KEY_Y, KEY_Z };
	int count = sizeof(letters) / sizeof(letters[0]);

	for (int i = 0; i < count; i++) {
		XCTAssertNotEqual(letters[i], 0,
			@"Letter key index %d must not be zero", i);
		for (int j = i + 1; j < count; j++) {
			XCTAssertNotEqual(letters[i], letters[j],
				@"Letter keys at indices %d and %d must be distinct", i, j);
		}
	}
}

@end
