//
//  Arculator-Bridging-Header.h
//  Arculator
//
//  Bridging header to expose C/ObjC symbols to Swift.
//

#ifndef Arculator_Bridging_Header_h
#define Arculator_Bridging_Header_h

#include "arc.h"
#include "config.h"
#include "emulation_control.h"
#include "disc.h"
#include "platform_paths.h"
#include "plat_video.h"
#include "sound.h"
#include "video.h"
#include "podules.h"
#include "romload.h"
#include "plat_input.h"
#include "plat_joystick.h"
#include "platform_shell.h"
#include "arm.h"
#include "memc.h"
#include "fpa.h"
#include "joystick.h"
#include "podule_api.h"

#import "ArcMetalView.h"
#import "EmulatorBridge.h"
#import "ConfigBridge.h"
#import "MachinePresetBridge.h"
#import "NewWindowBridge.h"
#import "ConfigEditorBridge.h"

#endif
