//
//  ConfigEditorBridge.mm
//  Arculator
//
//  ObjC++ implementation wrapping modal dialog functions for Swift access.
//

#import "ConfigEditorBridge.h"

extern "C" {
#include "arc.h"
#include "config.h"
#include "podules.h"
#include "podule_api.h"
#include "joystick.h"
}

// Include the wx-style headers to get the correct C++ mangled signatures
#include "wx-hd_new.h"
#include "wx-hd_conf.h"
#include "wx-podule-config.h"
#include "wx-joystick-config.h"

@implementation ARCHDDialogResult
@end

@implementation ConfigEditorBridge

+ (void)showPoduleConfigForShortName:(NSString *)shortName running:(BOOL)running slot:(int)slot
{
	const podule_header_t *podule = podule_find([shortName UTF8String]);
	if (podule && podule->config)
		ShowPoduleConfig(NULL, podule, podule->config, running, slot);
}

+ (nullable ARCHDDialogResult *)showConfHDWithPath:(NSString *)path isST506:(BOOL)isST506
{
	char newFn[512];
	strlcpy(newFn, [path UTF8String], sizeof(newFn));
	int sectors = 0, heads = 0, cylinders = 0;

	if (!ShowConfHD(NULL, &sectors, &heads, &cylinders, newFn, isST506))
		return nil;

	ARCHDDialogResult *result = [[ARCHDDialogResult alloc] init];
	result.path = [NSString stringWithUTF8String:newFn];
	result.cylinders = cylinders;
	result.heads = heads;
	result.sectors = sectors;
	return result;
}

+ (nullable ARCHDDialogResult *)showNewHDWithST506:(BOOL)isST506
{
	char newFn[512];
	newFn[0] = '\0';
	int sectors = 0, heads = 0, cylinders = 0;

	if (!ShowNewHD(NULL, &sectors, &heads, &cylinders, newFn, sizeof(newFn), isST506))
		return nil;

	ARCHDDialogResult *result = [[ARCHDDialogResult alloc] init];
	result.path = [NSString stringWithUTF8String:newFn];
	result.cylinders = cylinders;
	result.heads = heads;
	result.sectors = sectors;
	return result;
}

+ (void)showJoystickConfigForPlayer:(int)playerIndex type:(int)joystickType
{
	ShowConfJoy(NULL, playerIndex, joystickType);
}

+ (int)joystickTypeIndexForConfigName:(NSString *)configName
{
	for (int c = 0; joystick_get_name(c); c++)
	{
		if (strcmp([configName UTF8String], joystick_get_config_name(c)) == 0)
			return c;
	}
	return 0;
}

@end
