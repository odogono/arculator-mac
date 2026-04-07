#ifndef ARCULATOR_MACOS_DIALOG_UTIL_H
#define ARCULATOR_MACOS_DIALOG_UTIL_H

#import <AppKit/AppKit.h>

#include <string.h>

static inline NSString *arc_nsstring(const char *value)
{
	if (!value)
		return @"";
	return [NSString stringWithUTF8String:value] ?: @"";
}

static inline void arc_copy_string(char *dest, size_t dest_size, NSString *value)
{
	const char *utf8 = value ? [value UTF8String] : "";

	if (!dest || !dest_size)
		return;

	if (!utf8)
		utf8 = "";

	strncpy(dest, utf8, dest_size - 1);
	dest[dest_size - 1] = 0;
}

static inline void arc_show_message(NSString *title, NSString *message)
{
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = title ?: @"Arculator";
	alert.informativeText = message ?: @"";
	[alert addButtonWithTitle:@"OK"];
	[alert runModal];
}

static inline int arc_confirm(NSString *title, NSString *message)
{
	NSAlert *alert = [[NSAlert alloc] init];
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = title ?: @"Arculator";
	alert.informativeText = message ?: @"";
	[alert addButtonWithTitle:@"OK"];
	[alert addButtonWithTitle:@"Cancel"];
	return [alert runModal] == NSAlertFirstButtonReturn;
}

static inline NSString *arc_prompt_text(NSString *title, NSString *message, NSString *default_value, NSInteger max_length)
{
	NSAlert *alert = [[NSAlert alloc] init];
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 24.0)];

	alert.messageText = title ?: @"Arculator";
	alert.informativeText = message ?: @"";
	[field setStringValue:default_value ?: @""];
	[field setMaximumNumberOfLines:1];
	[field setUsesSingleLineMode:YES];
	alert.accessoryView = field;
	[alert addButtonWithTitle:@"OK"];
	[alert addButtonWithTitle:@"Cancel"];

	if ([alert runModal] != NSAlertFirstButtonReturn)
		return nil;

	NSString *value = [[field stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (max_length > 0 && (NSInteger)[value length] > max_length)
		value = [value substringToIndex:(NSUInteger)max_length];
	return value;
}

static inline NSString *arc_choose_open_file(NSString *title, NSArray<NSString *> *file_types, NSString *initial_path)
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.title = title ?: @"Open";
	panel.canChooseDirectories = NO;
	panel.canChooseFiles = YES;
	panel.allowsMultipleSelection = NO;
	if (file_types)
		panel.allowedContentTypes = nil;
	panel.allowedFileTypes = file_types;
	if (initial_path.length)
		panel.directoryURL = [NSURL fileURLWithPath:[initial_path stringByDeletingLastPathComponent]];
	if ([panel runModal] != NSModalResponseOK)
		return nil;
	return panel.URL.path;
}

static inline NSString *arc_choose_save_file(NSString *title, NSString *default_name, NSString *directory, NSArray<NSString *> *file_types)
{
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.title = title ?: @"Save";
	panel.nameFieldStringValue = default_name ?: @"";
	panel.allowedFileTypes = file_types;
	if (directory.length)
		panel.directoryURL = [NSURL fileURLWithPath:directory];
	if ([panel runModal] != NSModalResponseOK)
		return nil;
	return panel.URL.path;
}

static const NSInteger ARC_MODAL_RESPONSE_CONTINUE = NSIntegerMin;

static inline void arc_close_dialog_window(NSWindow *window, NSInteger *result, NSInteger response)
{
	if (result && *result == ARC_MODAL_RESPONSE_CONTINUE)
		*result = response;
	[window close];
}

static inline NSInteger arc_run_dialog_window(NSWindow *window, NSInteger *result)
{
	[window center];
	[window makeKeyAndOrderFront:nil];
	[window orderFrontRegardless];
	[NSApp activateIgnoringOtherApps:YES];

	NSModalSession session = [NSApp beginModalSessionForWindow:window];

	while (*result == ARC_MODAL_RESPONSE_CONTINUE)
	{
		@autoreleasepool {
			[NSApp runModalSession:session];
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
		}
	}

	[NSApp endModalSession:session];
	return *result;
}

#endif
