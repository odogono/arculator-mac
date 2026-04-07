#import <AppKit/AppKit.h>

#include <stdint.h>

#include "dialog_util.h"
#include "wx-joystick-config.h"

extern "C"
{
#include "arc.h"
#include "config.h"
#include "joystick.h"
#include "plat_joystick.h"
}

@interface ARCJoystickConfigDialog : NSObject <NSWindowDelegate>
{
@public
	NSInteger modalResult;
}
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSPopUpButton *devicePopup;
@property (nonatomic, strong) NSMutableArray<NSPopUpButton *> *mappingPopups;
@property (nonatomic, assign) NSInteger selectedDevice;
@property (nonatomic, assign) NSInteger joystickNumber;
@property (nonatomic, assign) NSInteger joystickType;
@property (nonatomic, assign) BOOL confirmed;
@end

@implementation ARCJoystickConfigDialog

- (instancetype)initWithJoystick:(int)joy_nr type:(int)type
{
	self = [super init];
	if (!self)
		return nil;

	self.joystickNumber = joy_nr;
	self.joystickType = type;
	self.mappingPopups = [NSMutableArray array];
	modalResult = ARC_MODAL_RESPONSE_CONTINUE;

	CGFloat rows = 1 + joystick_get_axis_count(type) + joystick_get_button_count(type) + (joystick_get_pov_count(type) * 2);
	CGFloat height = MAX(220.0, 80.0 + rows * 34.0);
	self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 520.0, height)
					      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
						backing:NSBackingStoreBuffered
						  defer:NO];
	self.window.title = @"Configure joystick";
	self.window.releasedWhenClosed = NO;
	self.window.delegate = self;

	NSView *content = self.window.contentView;
	CGFloat y = height - 52.0;

	auto addLabel = ^(NSString *labelText, CGFloat rowY) {
		NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0, rowY, 180.0, 22.0)];
		label.bezeled = NO;
		label.drawsBackground = NO;
		label.editable = NO;
		label.selectable = NO;
		label.stringValue = labelText;
		[content addSubview:label];
	};
	auto addPopup = ^NSPopUpButton *(CGFloat rowY) {
		NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(210.0, rowY - 2.0, 290.0, 26.0)];
		[content addSubview:popup];
		return popup;
	};

	addLabel(@"Device", y);
	self.devicePopup = addPopup(y);
	[self.devicePopup addItemWithTitle:@"None"];
	for (int c = 0; c < joysticks_present; c++)
		[self.devicePopup addItemWithTitle:arc_nsstring(plat_joystick_state[c].name)];
	self.devicePopup.target = self;
	self.devicePopup.action = @selector(deviceChanged:);
	y -= 36.0;

	for (int c = 0; c < joystick_get_axis_count(type); c++)
	{
		addLabel(arc_nsstring(joystick_get_axis_name(type, c)), y);
		[self.mappingPopups addObject:addPopup(y)];
		y -= 36.0;
	}
	for (int c = 0; c < joystick_get_button_count(type); c++)
	{
		addLabel(arc_nsstring(joystick_get_button_name(type, c)), y);
		[self.mappingPopups addObject:addPopup(y)];
		y -= 36.0;
	}
	for (int c = 0; c < joystick_get_pov_count(type) * 2; c++)
	{
		addLabel(arc_nsstring(joystick_get_pov_name(type, c)), y);
		[self.mappingPopups addObject:addPopup(y)];
		y -= 36.0;
	}

	NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(340.0, 14.0, 80.0, 30.0)];
	ok.title = @"OK";
	ok.keyEquivalent = @"\r";
	ok.target = self;
	ok.action = @selector(confirm:);
	[content addSubview:ok];

	NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(428.0, 14.0, 80.0, 30.0)];
	cancel.title = @"Cancel";
	cancel.keyEquivalent = @"\e";
	cancel.target = self;
	cancel.action = @selector(cancel:);
	[content addSubview:cancel];

	self.selectedDevice = joystick_state[joy_nr].plat_joystick_nr;
	[self.devicePopup selectItemAtIndex:self.selectedDevice];
	[self rebuildSelections];
	[self applyExistingMappings];
	return self;
}

- (NSInteger)popupIndexForAxisMapping:(int)mapping device:(int)device
{
	int nr_axes = plat_joystick_state[device - 1].nr_axes;
	if (mapping & POV_X)
		return nr_axes + ((mapping & 3) * 2);
	if (mapping & POV_Y)
		return nr_axes + ((mapping & 3) * 2) + 1;
	return mapping;
}

- (NSInteger)popupIndexForPovMapping:(int)mapping device:(int)device
{
	int nr_povs = plat_joystick_state[device - 1].nr_povs;
	if (mapping & POV_X)
		return (mapping & 3) * 2;
	if (mapping & POV_Y)
		return ((mapping & 3) * 2) + 1;
	return mapping + nr_povs * 2;
}

- (void)applyExistingMappings
{
	if (!self.selectedDevice)
		return;

	NSUInteger popupIndex = 0;
	for (int c = 0; c < joystick_get_axis_count((int)self.joystickType); c++, popupIndex++)
		[self.mappingPopups[popupIndex] selectItemAtIndex:[self popupIndexForAxisMapping:joystick_state[self.joystickNumber].axis_mapping[c] device:(int)self.selectedDevice]];
	for (int c = 0; c < joystick_get_button_count((int)self.joystickType); c++, popupIndex++)
		[self.mappingPopups[popupIndex] selectItemAtIndex:joystick_state[self.joystickNumber].button_mapping[c]];
	for (int c = 0; c < joystick_get_pov_count((int)self.joystickType); c++, popupIndex += 2)
	{
		[self.mappingPopups[popupIndex] selectItemAtIndex:[self popupIndexForPovMapping:joystick_state[self.joystickNumber].pov_mapping[c][0] device:(int)self.selectedDevice]];
		[self.mappingPopups[popupIndex + 1] selectItemAtIndex:[self popupIndexForPovMapping:joystick_state[self.joystickNumber].pov_mapping[c][1] device:(int)self.selectedDevice]];
	}
}

- (void)rebuildSelections
{
	NSUInteger popupIndex = 0;
	int device = (int)self.selectedDevice;

	for (int c = 0; c < joystick_get_axis_count((int)self.joystickType); c++, popupIndex++)
	{
		NSPopUpButton *popup = self.mappingPopups[popupIndex];
		[popup removeAllItems];
		if (!device)
		{
			popup.enabled = NO;
			continue;
		}
		for (int d = 0; d < plat_joystick_state[device - 1].nr_axes; d++)
			[popup addItemWithTitle:arc_nsstring(plat_joystick_state[device - 1].axis[d].name)];
		for (int d = 0; d < plat_joystick_state[device - 1].nr_povs; d++)
		{
			[popup addItemWithTitle:[NSString stringWithFormat:@"%s (X axis)", plat_joystick_state[device - 1].pov[d].name]];
			[popup addItemWithTitle:[NSString stringWithFormat:@"%s (Y axis)", plat_joystick_state[device - 1].pov[d].name]];
		}
		popup.enabled = YES;
		if (popup.numberOfItems > (NSInteger)c)
			[popup selectItemAtIndex:c];
	}

	for (int c = 0; c < joystick_get_button_count((int)self.joystickType); c++, popupIndex++)
	{
		NSPopUpButton *popup = self.mappingPopups[popupIndex];
		[popup removeAllItems];
		if (!device)
		{
			popup.enabled = NO;
			continue;
		}
		for (int d = 0; d < plat_joystick_state[device - 1].nr_buttons; d++)
			[popup addItemWithTitle:arc_nsstring(plat_joystick_state[device - 1].button[d].name)];
		popup.enabled = YES;
		if (popup.numberOfItems > (NSInteger)c)
			[popup selectItemAtIndex:c];
	}

	for (int c = 0; c < joystick_get_pov_count((int)self.joystickType) * 2; c++, popupIndex++)
	{
		NSPopUpButton *popup = self.mappingPopups[popupIndex];
		[popup removeAllItems];
		if (!device)
		{
			popup.enabled = NO;
			continue;
		}
		for (int d = 0; d < plat_joystick_state[device - 1].nr_povs; d++)
		{
			[popup addItemWithTitle:[NSString stringWithFormat:@"%s (X axis)", plat_joystick_state[device - 1].pov[d].name]];
			[popup addItemWithTitle:[NSString stringWithFormat:@"%s (Y axis)", plat_joystick_state[device - 1].pov[d].name]];
		}
		for (int d = 0; d < plat_joystick_state[device - 1].nr_axes; d++)
			[popup addItemWithTitle:arc_nsstring(plat_joystick_state[device - 1].axis[d].name)];
		popup.enabled = YES;
		if (popup.numberOfItems > (NSInteger)c)
			[popup selectItemAtIndex:c];
	}
}

- (void)deviceChanged:(id)sender
{
	self.selectedDevice = self.devicePopup.indexOfSelectedItem;
	[self rebuildSelections];
	[self applyExistingMappings];
	(void)sender;
}

- (int)axisMappingFromPopup:(NSPopUpButton *)popup
{
	int axisSel = (int)popup.indexOfSelectedItem;
	int nrAxes = plat_joystick_state[joystick_state[self.joystickNumber].plat_joystick_nr - 1].nr_axes;
	if (axisSel < nrAxes)
		return axisSel;
	axisSel -= nrAxes;
	return (axisSel & 1) ? (POV_Y | (axisSel >> 1)) : (POV_X | (axisSel >> 1));
}

- (int)povMappingFromPopup:(NSPopUpButton *)popup
{
	int axisSel = (int)popup.indexOfSelectedItem;
	int nrPovs = plat_joystick_state[joystick_state[self.joystickNumber].plat_joystick_nr - 1].nr_povs * 2;
	if (axisSel < nrPovs)
		return (axisSel & 1) ? (POV_Y | (axisSel >> 1)) : (POV_X | (axisSel >> 1));
	return axisSel - nrPovs;
}

- (void)confirm:(id)sender
{
	NSUInteger popupIndex = 0;
	joystick_state[self.joystickNumber].plat_joystick_nr = (int)self.devicePopup.indexOfSelectedItem;

	if (joystick_state[self.joystickNumber].plat_joystick_nr)
	{
		for (int c = 0; c < joystick_get_axis_count((int)self.joystickType); c++, popupIndex++)
			joystick_state[self.joystickNumber].axis_mapping[c] = [self axisMappingFromPopup:self.mappingPopups[popupIndex]];
		for (int c = 0; c < joystick_get_button_count((int)self.joystickType); c++, popupIndex++)
			joystick_state[self.joystickNumber].button_mapping[c] = (int)self.mappingPopups[popupIndex].indexOfSelectedItem;
		for (int c = 0; c < joystick_get_pov_count((int)self.joystickType); c++, popupIndex += 2)
		{
			joystick_state[self.joystickNumber].pov_mapping[c][0] = [self povMappingFromPopup:self.mappingPopups[popupIndex]];
			joystick_state[self.joystickNumber].pov_mapping[c][1] = [self povMappingFromPopup:self.mappingPopups[popupIndex + 1]];
		}
	}

	self.confirmed = YES;
	arc_close_dialog_window(self.window, &modalResult, NSModalResponseOK);
	(void)sender;
}

- (void)cancel:(id)sender
{
	self.confirmed = NO;
	arc_close_dialog_window(self.window, &modalResult, NSModalResponseCancel);
	(void)sender;
}

- (void)windowWillClose:(NSNotification *)notification
{
	(void)notification;
	if (modalResult == ARC_MODAL_RESPONSE_CONTINUE)
		modalResult = self.confirmed ? NSModalResponseOK : NSModalResponseCancel;
}

@end

void ShowConfJoy(wxWindow *parent, int joy_nr, int type)
{
	(void)parent;
	rpclog("joysticks_present=%i\n", joysticks_present);
	ARCJoystickConfigDialog *dialog = [[ARCJoystickConfigDialog alloc] initWithJoystick:joy_nr type:type];
	arc_run_dialog_window(dialog.window, &dialog->modalResult);
}
