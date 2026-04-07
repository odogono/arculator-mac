#import <AppKit/AppKit.h>

#include <map>
#include <stdint.h>
#include <string.h>

#include "dialog_util.h"
#include "wx-podule-config.h"

extern "C"
{
#include "arc.h"
#include "config.h"
#include "podules.h"
}

@interface ARCPoduleConfigDialog : NSObject <NSWindowDelegate, NSTextFieldDelegate>
{
@public
	std::map<int, NSControl *> controlMap;
	std::map<int, int> typeMap;
	char sectionName[20];
	const podule_header_t *podule;
	podule_config_t *config;
	BOOL running;
	int slotNumber;
	const char *prefix;
	BOOL confirmed;
	BOOL inCallback;
	NSInteger modalResult;
}
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSStackView *stackView;
@end

@implementation ARCPoduleConfigDialog

- (instancetype)initWithPodule:(const podule_header_t *)podule
			config:(podule_config_t *)config
		       running:(BOOL)running
		    slotNumber:(int)slotNumber
			 prefix:(const char *)prefix
{
	self = [super init];
	if (!self)
		return nil;

	self->podule = podule;
	self->config = config;
	self->running = running;
	self->slotNumber = slotNumber;
	self->prefix = prefix;
	snprintf(sectionName, sizeof(sectionName), "%s.%i", podule->short_name, slotNumber);
	modalResult = ARC_MODAL_RESPONSE_CONTINUE;

	self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 520.0, 440.0)
					      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
						backing:NSBackingStoreBuffered
						  defer:NO];
	self.window.title = arc_nsstring(config->title ? config->title : "Configure podule");
	self.window.releasedWhenClosed = NO;
	self.window.delegate = self;

	NSView *content = self.window.contentView;
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12.0, 56.0, 496.0, 372.0)];
	scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	scroll.hasVerticalScroller = YES;
	scroll.borderType = NSBezelBorder;

	NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 372.0)];
	stack.orientation = NSUserInterfaceLayoutOrientationVertical;
	stack.alignment = NSLayoutAttributeLeading;
	stack.spacing = 10.0;
	stack.edgeInsets = NSEdgeInsetsMake(10.0, 10.0, 10.0, 10.0);
	scroll.documentView = stack;
	[content addSubview:scroll];
	self.stackView = stack;

	NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(332.0, 14.0, 80.0, 30.0)];
	ok.title = @"OK";
	ok.keyEquivalent = @"\r";
	ok.target = self;
	ok.action = @selector(confirm:);
	[content addSubview:ok];

	NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(420.0, 14.0, 80.0, 30.0)];
	cancel.title = @"Cancel";
	cancel.keyEquivalent = @"\e";
	cancel.target = self;
	cancel.action = @selector(cancel:);
	[content addSubview:cancel];

	[self buildControls];
	return self;
}

- (const char *)itemName:(const podule_config_item_t *)item
{
	static char temp[256];
	if ((item->flags & CONFIG_FLAGS_NAME_PREFIXED) && prefix)
	{
		snprintf(temp, sizeof(temp), "%s%s", prefix, item->name);
		return temp;
	}
	return item->name;
}

- (NSView *)rowWithLabel:(NSString *)labelText control:(NSView *)control
{
	NSStackView *row = [[NSStackView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 460.0, 28.0)];
	row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	row.spacing = 10.0;
	row.alignment = NSLayoutAttributeCenterY;

	NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 180.0, 22.0)];
	label.bezeled = NO;
	label.drawsBackground = NO;
	label.editable = NO;
	label.selectable = NO;
	label.stringValue = labelText ?: @"";
	[row addArrangedSubview:label];
	[row addArrangedSubview:control];
	[control setFrameSize:NSMakeSize(240.0, control.frame.size.height)];
	return row;
}

- (void)buildControls
{
	const podule_config_item_t *item = config->items;
	while (item->type != -1)
	{
		typeMap[item->id] = item->type;

		switch (item->type)
		{
			case CONFIG_STRING:
			{
				NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 24.0)];
				field.delegate = self;
				field.target = self;
				field.action = @selector(textChanged:);
				[self.stackView addArrangedSubview:[self rowWithLabel:arc_nsstring(item->description) control:field]];
				controlMap[item->id] = field;
			}
			break;

			case CONFIG_BINARY:
			{
				NSButton *check = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 24.0)];
				check.buttonType = NSButtonTypeSwitch;
				check.title = arc_nsstring(item->description);
				[self.stackView addArrangedSubview:check];
				controlMap[item->id] = check;
			}
			break;

			case CONFIG_SELECTION:
			case CONFIG_SELECTION_STRING:
			{
				NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 26.0)];
				popup.target = self;
				popup.action = @selector(selectionChanged:);
				[self.stackView addArrangedSubview:[self rowWithLabel:arc_nsstring(item->description) control:popup]];
				controlMap[item->id] = popup;
			}
			break;

			case CONFIG_BUTTON:
			{
				NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 28.0)];
				button.title = arc_nsstring(item->description);
				button.target = self;
				button.action = @selector(buttonPressed:);
				[self.stackView addArrangedSubview:button];
				controlMap[item->id] = button;
			}
			break;
		}

		item++;
	}

	[self syncControlsFromConfig];
}

- (const podule_config_item_t *)itemForControl:(NSControl *)control
{
	for (const podule_config_item_t *item = config->items; item->type != -1; item++)
	{
		auto it = controlMap.find(item->id);
		if (it != controlMap.end() && it->second == control)
			return item;
	}
	return NULL;
}

- (void)syncControlsFromConfig
{
	for (const podule_config_item_t *item = config->items; item->type != -1; item++)
	{
		auto controlIt = controlMap.find(item->id);
		if (controlIt == controlMap.end())
			continue;

		NSControl *control = controlIt->second;
		switch (item->type)
		{
			case CONFIG_STRING:
			{
				const char *value = item->name ? config_get_string(CFG_MACHINE, sectionName, [self itemName:item], item->default_string) : item->default_string;
				((NSTextField *)control).stringValue = arc_nsstring(value);
				control.enabled = !(item->flags & CONFIG_FLAGS_DISABLED);
			}
			break;

			case CONFIG_BINARY:
			{
				int value = config_get_int(CFG_MACHINE, sectionName, [self itemName:item], item->default_int);
				((NSButton *)control).state = value ? NSControlStateValueOn : NSControlStateValueOff;
				control.enabled = !(item->flags & CONFIG_FLAGS_DISABLED);
			}
			break;

			case CONFIG_SELECTION:
			{
				NSPopUpButton *popup = (NSPopUpButton *)control;
				[popup removeAllItems];
				int value = config_get_int(CFG_MACHINE, sectionName, [self itemName:item], item->default_int);
				int index = 0;
				int selected = 0;
				for (podule_config_selection_t *selection = item->selection; selection && selection->description[0]; selection++, index++)
				{
					[popup addItemWithTitle:arc_nsstring(selection->description)];
					if (selection->value == value)
						selected = index;
				}
				[popup selectItemAtIndex:selected];
				control.enabled = !(item->flags & CONFIG_FLAGS_DISABLED);
			}
			break;

			case CONFIG_SELECTION_STRING:
			{
				NSPopUpButton *popup = (NSPopUpButton *)control;
				[popup removeAllItems];
				const char *value = config_get_string(CFG_MACHINE, sectionName, [self itemName:item], item->default_string);
				int index = 0;
				int selected = 0;
				for (podule_config_selection_t *selection = item->selection; selection && selection->description[0]; selection++, index++)
				{
					[popup addItemWithTitle:arc_nsstring(selection->description)];
					if (selection->value_string && !strcmp(value, selection->value_string))
						selected = index;
				}
				[popup selectItemAtIndex:selected];
				control.enabled = !(item->flags & CONFIG_FLAGS_DISABLED);
			}
			break;

			case CONFIG_BUTTON:
			break;
		}
	}
}

- (void)invokeCallbackForItem:(const podule_config_item_t *)item control:(NSControl *)control value:(void *)value
{
	if (!item || !item->function || inCallback)
		return;

	inCallback = YES;
	int changed = item->function((__bridge void *)self, item, value);
	inCallback = NO;
	if (changed)
		[self.window displayIfNeeded];
	(void)control;
}

- (void)textChanged:(id)sender
{
	const podule_config_item_t *item = [self itemForControl:(NSControl *)sender];
	NSTextField *field = (NSTextField *)sender;
	const char *value = field.stringValue.UTF8String ?: "";
	[self invokeCallbackForItem:item control:field value:(void *)value];
}

- (void)selectionChanged:(id)sender
{
	const podule_config_item_t *item = [self itemForControl:(NSControl *)sender];
	NSPopUpButton *popup = (NSPopUpButton *)sender;
	if (!item)
		return;
	if (item->type == CONFIG_SELECTION)
	{
		[self invokeCallbackForItem:item control:popup value:(void *)(uintptr_t)popup.indexOfSelectedItem];
		return;
	}
	const char *value = popup.selectedItem.title.UTF8String ?: "";
	[self invokeCallbackForItem:item control:popup value:(void *)value];
}

- (void)buttonPressed:(id)sender
{
	const podule_config_item_t *item = [self itemForControl:(NSControl *)sender];
	[self invokeCallbackForItem:item control:(NSControl *)sender value:NULL];
}

- (BOOL)changedFromStoredConfig
{
	for (const podule_config_item_t *item = config->items; item->type != -1; item++)
	{
		if (!item->name)
			continue;

		NSControl *control = controlMap[item->id];
		switch (item->type)
		{
			case CONFIG_BINARY:
				if (config_get_int(CFG_MACHINE, sectionName, [self itemName:item], item->default_int) != (((NSButton *)control).state == NSControlStateValueOn))
					return YES;
			break;

			case CONFIG_SELECTION:
			{
				int selected = (int)((NSPopUpButton *)control).indexOfSelectedItem;
				podule_config_selection_t *selection = item->selection;
				for (; selected > 0; selected--)
					selection++;
				if (config_get_int(CFG_MACHINE, sectionName, [self itemName:item], item->default_int) != selection->value)
					return YES;
			}
			break;

			case CONFIG_SELECTION_STRING:
			{
				int selected = (int)((NSPopUpButton *)control).indexOfSelectedItem;
				podule_config_selection_t *selection = item->selection;
				for (; selected > 0; selected--)
					selection++;
				const char *stored = config_get_string(CFG_MACHINE, sectionName, [self itemName:item], item->default_string);
				if (strcmp(stored, selection->value_string))
					return YES;
			}
			break;

			case CONFIG_STRING:
			{
				const char *stored = config_get_string(CFG_MACHINE, sectionName, [self itemName:item], item->default_string);
				const char *current = ((NSTextField *)control).stringValue.UTF8String ?: "";
				if ((!stored && current[0]) || (stored && strcmp(stored, current)))
					return YES;
			}
			break;
		}
	}
	return config->close ? config->close((__bridge void *)self) : NO;
}

- (void)writeBackAndSave
{
	for (const podule_config_item_t *item = config->items; item->type != -1; item++)
	{
		if (!item->name)
			continue;

		NSControl *control = controlMap[item->id];
		switch (item->type)
		{
			case CONFIG_BINARY:
				config_set_int(CFG_MACHINE, sectionName, [self itemName:item], ((NSButton *)control).state == NSControlStateValueOn);
			break;

			case CONFIG_SELECTION:
			{
				int selected = (int)((NSPopUpButton *)control).indexOfSelectedItem;
				podule_config_selection_t *selection = item->selection;
				for (; selected > 0; selected--)
					selection++;
				config_set_int(CFG_MACHINE, sectionName, [self itemName:item], selection->value);
			}
			break;

			case CONFIG_SELECTION_STRING:
			{
				int selected = (int)((NSPopUpButton *)control).indexOfSelectedItem;
				podule_config_selection_t *selection = item->selection;
				for (; selected > 0; selected--)
					selection++;
				config_set_string(CFG_MACHINE, sectionName, [self itemName:item], selection->value_string);
			}
			break;

			case CONFIG_STRING:
			{
				char buffer[256];
				arc_copy_string(buffer, sizeof(buffer), ((NSTextField *)control).stringValue);
				config_set_string(CFG_MACHINE, sectionName, [self itemName:item], buffer);
			}
			break;
		}
	}

	saveconfig();
	if (running)
		arc_reset();
}

- (void)confirm:(id)sender
{
	int changed = [self changedFromStoredConfig];
	if (!changed)
	{
		confirmed = YES;
		arc_close_dialog_window(self.window, &modalResult, NSModalResponseOK);
		return;
	}

	if (running && !arc_confirm(@"Arculator", @"This will reset Arculator!\nOkay to continue?"))
	{
		confirmed = YES;
		arc_close_dialog_window(self.window, &modalResult, NSModalResponseOK);
		return;
	}

	[self writeBackAndSave];
	confirmed = YES;
	arc_close_dialog_window(self.window, &modalResult, NSModalResponseOK);
	(void)sender;
}

- (void)cancel:(id)sender
{
	confirmed = NO;
	arc_close_dialog_window(self.window, &modalResult, NSModalResponseCancel);
	(void)sender;
}

- (void)windowWillClose:(NSNotification *)notification
{
	(void)notification;
	if (modalResult == ARC_MODAL_RESPONSE_CONTINUE)
		modalResult = confirmed ? NSModalResponseOK : NSModalResponseCancel;
}

@end

static ARCPoduleConfigDialog *arc_podule_dialog(void *window_p)
{
	return (__bridge ARCPoduleConfigDialog *)window_p;
}

static NSControl *arc_podule_control(void *window_p, int id, int *type)
{
	ARCPoduleConfigDialog *dialog = arc_podule_dialog(window_p);
	auto typeIt = dialog->typeMap.find(id);
	if (typeIt == dialog->typeMap.end())
		return nil;
	*type = typeIt->second;
	auto controlIt = dialog->controlMap.find(id);
	return controlIt == dialog->controlMap.end() ? nil : controlIt->second;
}

static char podule_temp_string[256];

void *podule_config_get_current(void *window_p, int id)
{
	int type = -1;
	NSControl *control = arc_podule_control(window_p, id, &type);
	if (!control)
		return NULL;

	switch (type)
	{
		case CONFIG_STRING:
			arc_copy_string(podule_temp_string, sizeof(podule_temp_string), ((NSTextField *)control).stringValue);
			return podule_temp_string;

		case CONFIG_SELECTION:
			return (void *)(uintptr_t)((NSPopUpButton *)control).indexOfSelectedItem;

		case CONFIG_SELECTION_STRING:
			arc_copy_string(podule_temp_string, sizeof(podule_temp_string), ((NSPopUpButton *)control).selectedItem.title);
			return podule_temp_string;
	}

	return NULL;
}

void podule_config_set_current(void *window_p, int id, void *val)
{
	int type = -1;
	NSControl *control = arc_podule_control(window_p, id, &type);
	if (!control)
		return;

	switch (type)
	{
		case CONFIG_STRING:
			((NSTextField *)control).stringValue = arc_nsstring((const char *)val);
		break;

		case CONFIG_SELECTION:
			[((NSPopUpButton *)control) selectItemAtIndex:(NSInteger)(uintptr_t)val];
		break;

		case CONFIG_SELECTION_STRING:
			[((NSPopUpButton *)control) selectItemWithTitle:arc_nsstring((const char *)val)];
		break;
	}
}

int podule_config_file_selector(void *window_p, const char *title, const char *default_path, const char *default_fn, const char *default_ext, const char *wildcard, char *dest, int dest_len, int flags)
{
	(void)window_p;
	(void)wildcard;
	NSString *result = nil;
	if (flags & CONFIG_FILESEL_SAVE)
		result = arc_choose_save_file(arc_nsstring(title), arc_nsstring(default_fn), arc_nsstring(default_path), default_ext ? @[ arc_nsstring(default_ext) ] : nil);
	else
		result = arc_choose_open_file(arc_nsstring(title), default_ext ? @[ arc_nsstring(default_ext) ] : nil, arc_nsstring(default_path));
	if (!result)
		return -1;
	arc_copy_string(dest, (size_t)dest_len, result);
	return 0;
}

int podule_config_open(void *window_p, podule_config_t *config, const char *prefix)
{
	ARCPoduleConfigDialog *parent = arc_podule_dialog(window_p);
	ARCPoduleConfigDialog *dialog = [[ARCPoduleConfigDialog alloc] initWithPodule:parent->podule
									 config:config
									running:parent->running
								     slotNumber:parent->slotNumber
									 prefix:prefix];
	if (config->init)
		config->init((__bridge void *)dialog);
	NSInteger result = arc_run_dialog_window(dialog.window, &dialog->modalResult);
	return result == NSModalResponseOK ? 1 : 0;
}

void ShowPoduleConfig(wxWindow *parent, const podule_header_t *podule, podule_config_t *config, bool running, int slot_nr)
{
	(void)parent;
	ARCPoduleConfigDialog *dialog = [[ARCPoduleConfigDialog alloc] initWithPodule:podule
									 config:config
									running:running
								     slotNumber:slot_nr
									 prefix:NULL];
	if (config->init)
		config->init((__bridge void *)dialog);
	arc_run_dialog_window(dialog.window, &dialog->modalResult);
}
