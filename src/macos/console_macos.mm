#import <AppKit/AppKit.h>

#include <pthread.h>
#include <unistd.h>

#include "dialog_util.h"
#include "wx-console.h"

extern "C"
{
#include "debugger.h"
}

static const NSUInteger kConsoleScrollbackMax = 501;

@interface ARCConsoleController : NSObject <NSWindowDelegate, NSTextFieldDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSScrollView *outputScrollView;
@property (nonatomic, strong) NSTextView *outputView;
@property (nonatomic, strong) NSTextField *inputField;
@property (nonatomic, strong) NSMutableArray<NSString *> *history;
@property (nonatomic, assign) NSInteger historyIndex;
@property (nonatomic, strong) NSString *lastInput;
@property (nonatomic, strong) NSString *pendingInput;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) pthread_mutex_t lock;
@end

@implementation ARCConsoleController

- (instancetype)init
{
	self = [super init];
	if (!self)
		return nil;

	_history = [NSMutableArray arrayWithObject:@""];
	_historyIndex = 0;
	_lastInput = @"";
	_pendingInput = nil;
	_enabled = NO;
	pthread_mutex_init(&_lock, NULL);

	NSRect frame = NSMakeRect(0.0, 0.0, 720.0, 480.0);
	self.window = [[NSWindow alloc] initWithContentRect:frame
					      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
							 NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
						backing:NSBackingStoreBuffered
						  defer:NO];
	self.window.title = @"Arculator debugger";
	self.window.delegate = self;

	NSView *content = self.window.contentView;
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12.0, 52.0, 696.0, 416.0)];
	scroll.hasVerticalScroller = YES;
	scroll.hasHorizontalScroller = YES;
	scroll.borderType = NSBezelBorder;
	scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	NSTextView *output = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
	output.editable = NO;
	output.richText = NO;
	output.font = [NSFont userFixedPitchFontOfSize:12.0];
	output.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	scroll.documentView = output;
	[content addSubview:scroll];

	NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0, 12.0, 696.0, 28.0)];
	input.font = [NSFont userFixedPitchFontOfSize:12.0];
	input.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
	input.target = self;
	input.action = @selector(submitInput:);
	input.delegate = self;
	[content addSubview:input];

	self.outputScrollView = scroll;
	self.outputView = output;
	self.inputField = input;
	return self;
}

- (void)dealloc
{
	pthread_mutex_destroy(&_lock);
}

- (void)showWindow
{
	self.enabled = YES;
	[self.window makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
	[self.window makeFirstResponder:self.inputField];
}

- (void)closeWindow
{
	if (!self.enabled)
		return;
	self.enabled = NO;
	[self.window close];
}

- (void)appendOutput:(NSString *)text
{
	if (!self.enabled || !text)
		return;

	NSTextStorage *storage = self.outputView.textStorage;
	[storage appendAttributedString:[[NSAttributedString alloc] initWithString:text]];
	[self.outputView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
}

- (void)submitInput:(id)sender
{
	NSString *value = [self.inputField.stringValue copy];

	pthread_mutex_lock(&_lock);
	if (!self.pendingInput.length)
	{
		if (!value.length)
			value = self.lastInput ?: @"";

		self.pendingInput = value ?: @"";
		self.lastInput = self.pendingInput;

		if (self.history.count >= kConsoleScrollbackMax)
			[self.history removeObjectAtIndex:0];
		if (self.history.count)
			[self.history removeLastObject];
		[self.history addObject:self.pendingInput];
		[self.history addObject:@""];
		self.historyIndex = (NSInteger)self.history.count - 1;
		self.inputField.stringValue = @"";
	}
	pthread_mutex_unlock(&_lock);

	(void)sender;
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
	(void)control;

	if (commandSelector == @selector(moveUp:))
	{
		if (self.historyIndex > 0)
		{
			if (self.historyIndex == (NSInteger)self.history.count - 1)
				self.history[self.historyIndex] = self.inputField.stringValue ?: @"";
			self.historyIndex--;
			self.inputField.stringValue = self.history[(NSUInteger)self.historyIndex];
		}
		return YES;
	}

	if (commandSelector == @selector(moveDown:))
	{
		if ((self.historyIndex + 1) < (NSInteger)self.history.count)
		{
			if (self.historyIndex == (NSInteger)self.history.count - 1)
				self.history[self.historyIndex] = self.inputField.stringValue ?: @"";
			self.historyIndex++;
			self.inputField.stringValue = self.history[(NSUInteger)self.historyIndex];
		}
		return YES;
	}

	(void)textView;
	return NO;
}

- (int)takeInput:(char *)dest
{
	int available = 0;

	pthread_mutex_lock(&_lock);
	if (self.pendingInput.length)
	{
		arc_copy_string(dest, 256, self.pendingInput);
		self.pendingInput = nil;
		available = 1;
	}
	pthread_mutex_unlock(&_lock);
	return available;
}

- (void)setInputEnabled:(BOOL)enabled
{
	self.inputField.enabled = enabled;
	if (enabled)
		[self.window makeFirstResponder:self.inputField];
}

- (void)windowWillClose:(NSNotification *)notification
{
	(void)notification;
	self.enabled = NO;
}

@end

static ARCConsoleController *console_controller = nil;

static ARCConsoleController *console_get_controller(void)
{
	if (!console_controller)
		console_controller = [[ARCConsoleController alloc] init];
	return console_controller;
}

void ShowConsoleWindow(wxWindow *parent)
{
	(void)parent;
	dispatch_async(dispatch_get_main_queue(), ^{
		[console_get_controller() showWindow];
	});
}

void CloseConsoleWindow()
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if (console_controller)
			[console_controller closeWindow];
	});
}

extern "C" void console_output(char *s)
{
	if (!console_controller || !console_controller.enabled)
		return;

	NSString *text = arc_nsstring(s);
	dispatch_async(dispatch_get_main_queue(), ^{
		if (console_controller)
			[console_controller appendOutput:text];
	});
}

extern "C" int console_input_get(char *s)
{
	while (1)
	{
		if (!console_controller || !console_controller.enabled)
			return CONSOLE_INPUT_GET_ERROR_WINDOW_CLOSED;
		if (debugger_in_reset)
			return CONSOLE_INPUT_GET_ERROR_IN_RESET;
		if ([console_controller takeInput:s])
			return 1;
		usleep(50000);
	}
}

extern "C" void console_input_disable()
{
	if (!console_controller || !console_controller.enabled)
		return;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (console_controller)
			[console_controller setInputEnabled:NO];
	});
}

extern "C" void console_input_enable()
{
	if (!console_controller || !console_controller.enabled)
		return;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (console_controller)
			[console_controller setInputEnabled:YES];
	});
}
