#import <AppKit/AppKit.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "dialog_util.h"
#include "platform_paths.h"
#include "wx-hd_conf.h"
#include "wx-hd_new.h"

@interface ARCHardDiskDialog : NSObject <NSWindowDelegate, NSTextFieldDelegate>
{
@public
	NSInteger modalResult;
}
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextField *pathField;
@property (nonatomic, strong) NSTextField *sizeField;
@property (nonatomic, strong) NSTextField *cylindersField;
@property (nonatomic, strong) NSTextField *headsField;
@property (nonatomic, strong) NSTextField *sectorsField;
@property (nonatomic, assign) BOOL creatingFile;
@property (nonatomic, assign) BOOL confirmed;
@property (nonatomic, assign) BOOL syncing;
@property (nonatomic, assign) int maxCylinders;
@property (nonatomic, assign) int maxHeads;
@property (nonatomic, assign) int minSectors;
@property (nonatomic, assign) int maxSectors;
@property (nonatomic, assign) int sectorSize;
@end

@implementation ARCHardDiskDialog

- (NSTextField *)makeLabel:(NSString *)text
{
	NSTextField *label = [NSTextField labelWithString:text];
	label.alignment = NSTextAlignmentRight;
	label.font = [NSFont systemFontOfSize:13.0];
	[label setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
	return label;
}

- (NSTextField *)makeField
{
	NSTextField *field = [[NSTextField alloc] init];
	field.translatesAutoresizingMaskIntoConstraints = NO;
	field.delegate = self;
	field.font = [NSFont monospacedDigitSystemFontOfSize:13.0 weight:NSFontWeightRegular];
	[field setUsesSingleLineMode:YES];
	[field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	return field;
}

- (instancetype)initWithTitle:(NSString *)title
		 creatingFile:(BOOL)creatingFile
		    sectors:(int)sectors
		      heads:(int)heads
		  cylinders:(int)cylinders
		       path:(NSString *)path
		maxCylinders:(int)maxCylinders
		    maxHeads:(int)maxHeads
		  minSectors:(int)minSectors
		  maxSectors:(int)maxSectors
		   sectorSize:(int)sectorSize
{
	self = [super init];
	if (!self)
		return nil;

	self.creatingFile = creatingFile;
	modalResult = ARC_MODAL_RESPONSE_CONTINUE;
	self.maxCylinders = maxCylinders;
	self.maxHeads = maxHeads;
	self.minSectors = minSectors;
	self.maxSectors = maxSectors;
	self.sectorSize = sectorSize;

	self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 100.0, 100.0)
					      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
						backing:NSBackingStoreBuffered
						  defer:NO];
	self.window.title = title;
	self.window.releasedWhenClosed = NO;
	self.window.delegate = self;

	NSView *content = self.window.contentView;

	NSGridView *grid = [NSGridView gridViewWithNumberOfColumns:2 rows:0];

	if (creatingFile)
	{
		self.pathField = [self makeField];
		self.pathField.font = [NSFont systemFontOfSize:13.0];
		if ([self.pathField.cell isKindOfClass:[NSTextFieldCell class]])
		{
			NSTextFieldCell *cell = (NSTextFieldCell *)self.pathField.cell;
			cell.wraps = NO;
			cell.scrollable = YES;
			cell.usesSingleLineMode = YES;
			cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
		}
		self.pathField.stringValue = path ?: @"";

		NSButton *browse = [NSButton buttonWithTitle:@"Browse\u2026" target:self action:@selector(choosePath:)];
		browse.bezelStyle = NSBezelStyleRounded;
		[browse setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

		NSStackView *pathRow = [NSStackView stackViewWithViews:@[ self.pathField, browse ]];
		pathRow.spacing = 8.0;

		[grid addRowWithViews:@[ [self makeLabel:@"Disc image:"], pathRow ]];
	}

	self.sizeField = [self makeField];
	self.cylindersField = [self makeField];
	self.headsField = [self makeField];
	self.sectorsField = [self makeField];

	[grid addRowWithViews:@[ [self makeLabel:@"Size (MB):"], self.sizeField ]];
	[grid addRowWithViews:@[ [self makeLabel:@"Cylinders:"], self.cylindersField ]];
	[grid addRowWithViews:@[ [self makeLabel:@"Heads:"], self.headsField ]];
	[grid addRowWithViews:@[ [self makeLabel:@"Sectors:"], self.sectorsField ]];

	grid.translatesAutoresizingMaskIntoConstraints = NO;
	grid.rowSpacing = 10.0;
	grid.columnSpacing = 10.0;
	[grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
	[grid columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
	for (NSInteger i = 0; i < grid.numberOfRows; i++)
		[grid rowAtIndex:i].yPlacement = NSGridCellPlacementCenter;

	/* The path row should stretch to fill the column width */
	if (creatingFile)
		[grid cellAtColumnIndex:1 rowIndex:0].xPlacement = NSGridCellPlacementFill;

	CGFloat fieldWidth = 120.0;
	for (NSTextField *f in @[ self.sizeField, self.cylindersField, self.headsField, self.sectorsField ])
		[f.widthAnchor constraintEqualToConstant:fieldWidth].active = YES;

	NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
	cancel.bezelStyle = NSBezelStyleRounded;
	cancel.keyEquivalent = @"\e";

	NSButton *ok = [NSButton buttonWithTitle:@"OK" target:self action:@selector(confirm:)];
	ok.bezelStyle = NSBezelStyleRounded;
	ok.keyEquivalent = @"\r";

	NSStackView *buttonBar = [NSStackView stackViewWithViews:@[ cancel, ok ]];
	buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
	buttonBar.spacing = 8.0;

	[content addSubview:grid];
	[content addSubview:buttonBar];

	CGFloat pad = 20.0;
	[NSLayoutConstraint activateConstraints:@[
		[grid.topAnchor constraintEqualToAnchor:content.topAnchor constant:pad],
		[grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:pad],
		[grid.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],
		[buttonBar.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:pad],
		[buttonBar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-pad],
		[buttonBar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-pad],
	]];

	CGFloat windowWidth = creatingFile ? 460.0 : 340.0;
	[self.window setContentMinSize:NSMakeSize(windowWidth, 0.0)];
	[self.window setContentSize:NSMakeSize(windowWidth, 0.0)];
	[content layoutSubtreeIfNeeded];
	NSSize fitted = NSMakeSize(windowWidth, NSMaxY(grid.frame) + pad + buttonBar.fittingSize.height + pad);
	[self.window setContentSize:fitted];

	self.sectorsField.stringValue = [NSString stringWithFormat:@"%d", sectors];
	self.headsField.stringValue = [NSString stringWithFormat:@"%d", heads];
	self.cylindersField.stringValue = [NSString stringWithFormat:@"%d", cylinders];
	[self updateSizeFromCHS];
	return self;
}

- (void)choosePath:(id)sender
{
	NSString *currentPath = self.pathField.stringValue;
	NSString *selected = arc_choose_save_file(@"New disc image",
						 currentPath.lastPathComponent.length ? currentPath.lastPathComponent : @"disc.hdf",
						 currentPath.stringByDeletingLastPathComponent,
						 @[ @"hdf" ]);
	if (selected)
		self.pathField.stringValue = selected;
	(void)sender;
}

- (void)windowWillClose:(NSNotification *)notification
{
	(void)notification;
	if (modalResult == ARC_MODAL_RESPONSE_CONTINUE)
		modalResult = self.confirmed ? NSModalResponseOK : NSModalResponseCancel;
}

- (int)readInt:(NSTextField *)field
{
	return (int)[field integerValue];
}

- (void)updateSizeFromCHS
{
	if (self.syncing)
		return;
	self.syncing = YES;

	int cylinders = [self readInt:self.cylindersField];
	int heads = [self readInt:self.headsField];
	int sectors = [self readInt:self.sectorsField];

	if (cylinders > self.maxCylinders)
		 cylinders = self.maxCylinders;
	if (heads > self.maxHeads)
		heads = self.maxHeads;
	if (sectors > self.maxSectors)
		sectors = self.maxSectors;
	if (sectors < self.minSectors)
		sectors = self.minSectors;

	self.cylindersField.stringValue = [NSString stringWithFormat:@"%d", cylinders];
	self.headsField.stringValue = [NSString stringWithFormat:@"%d", heads];
	self.sectorsField.stringValue = [NSString stringWithFormat:@"%d", sectors];

	int size = (cylinders * heads * sectors) / (1024 * 1024 / self.sectorSize);
	self.sizeField.stringValue = [NSString stringWithFormat:@"%d", size];
	self.syncing = NO;
}

- (void)updateCHSFromSize
{
	if (self.syncing)
		return;
	self.syncing = YES;

	int size = [self readInt:self.sizeField];
	int maxSize = (self.maxCylinders * self.maxHeads * self.maxSectors) / (1024 * 1024 / self.sectorSize);
	if (size > maxSize)
		size = maxSize;
	if (size < 0)
		size = 0;

	int heads = self.maxHeads;
	int sectors = self.maxSectors;
	int cylinders = (size * (1024 * 1024 / self.sectorSize)) / (self.maxHeads * self.maxSectors);

	self.sizeField.stringValue = [NSString stringWithFormat:@"%d", size];
	self.cylindersField.stringValue = [NSString stringWithFormat:@"%d", cylinders];
	self.headsField.stringValue = [NSString stringWithFormat:@"%d", heads];
	self.sectorsField.stringValue = [NSString stringWithFormat:@"%d", sectors];
	self.syncing = NO;
}

- (void)controlTextDidChange:(NSNotification *)notification
{
	id object = notification.object;
	if (object == self.sizeField)
		[self updateCHSFromSize];
	else
		[self updateSizeFromCHS];
}

- (void)confirm:(id)sender
{
	if (self.creatingFile)
	{
		NSString *path = self.pathField.stringValue;
		if (!path.length)
		{
			arc_show_message(@"Arculator", @"Choose a disc image path first.");
			return;
		}

		FILE *file = fopen(path.fileSystemRepresentation, "wb");
		if (!file)
		{
			arc_show_message(@"Arculator", @"Could not create file");
			return;
		}

		int totalSectors = [self readInt:self.cylindersField] * [self readInt:self.headsField] * [self readInt:self.sectorsField];
		uint8_t sectorBuf[512];
		memset(sectorBuf, 0, sizeof(sectorBuf));
		for (int i = 0; i < totalSectors; i++)
			fwrite(sectorBuf, self.sectorSize, 1, file);
		fclose(file);
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

@end

static void hd_limits(int is_st506, int *max_cylinders, int *max_heads, int *min_sectors, int *max_sectors, int *sector_size)
{
	if (is_st506)
	{
		*max_cylinders = 1024;
		*max_heads = 8;
		*min_sectors = 32;
		*max_sectors = 32;
		*sector_size = 256;
	}
	else
	{
		*max_cylinders = 1024;
		*max_heads = 16;
		*min_sectors = 1;
		*max_sectors = 63;
		*sector_size = 512;
	}
}

int ShowNewHD(wxWindow *parent, int *new_sectors, int *new_heads, int *new_cylinders, char *new_fn, int new_fn_size, bool is_st506)
{
	(void)parent;
	char default_drive_path[1024];
	int max_cylinders = 0;
	int max_heads = 0;
	int min_sectors = 0;
	int max_sectors = 0;
	int sector_size = 0;
	hd_limits(is_st506, &max_cylinders, &max_heads, &min_sectors, &max_sectors, &sector_size);
	platform_path_join_support(default_drive_path, "drives/disc.hdf", sizeof(default_drive_path));

	ARCHardDiskDialog *dialog = [[ARCHardDiskDialog alloc] initWithTitle:@"New hard disc"
						      creatingFile:YES
							 sectors:sector_size == 512 ? 63 : 32
							   heads:sector_size == 512 ? 16 : 8
						       cylinders:sector_size == 512 ? 100 : 615
							    path:arc_nsstring(default_drive_path)
							maxCylinders:max_cylinders
							    maxHeads:max_heads
							  minSectors:min_sectors
							  maxSectors:max_sectors
							   sectorSize:sector_size];
	[dialog.window center];
	NSInteger result = arc_run_dialog_window(dialog.window, &dialog->modalResult);
	if (result != NSModalResponseOK)
		return 0;

	*new_sectors = (int)[dialog.sectorsField integerValue];
	*new_heads = (int)[dialog.headsField integerValue];
	*new_cylinders = (int)[dialog.cylindersField integerValue];
	arc_copy_string(new_fn, (size_t)new_fn_size, dialog.pathField.stringValue);
	return 1;
}

int ShowConfHD(wxWindow *parent, int *new_sectors, int *new_heads, int *new_cylinders, char *new_fn, bool is_st506)
{
	(void)parent;
	int max_cylinders = 0;
	int max_heads = 0;
	int min_sectors = 0;
	int max_sectors = 0;
	int sector_size = 0;
	hd_limits(is_st506, &max_cylinders, &max_heads, &min_sectors, &max_sectors, &sector_size);

	FILE *file = fopen(new_fn, "rb");
	if (!file)
	{
		arc_show_message(@"Arculator", @"Could not access file");
		return 0;
	}

	fseek(file, -1, SEEK_END);
	int filesize = ftell(file) + 1;
	fseek(file, 0, SEEK_SET);

	int log2secsize = 0;
	int density = 0;

	fseek(file, 0xFC0, SEEK_SET);
	log2secsize = getc(file);
	*new_sectors = getc(file);
	*new_heads = getc(file);
	density = getc(file);

	if ((log2secsize != 8 && log2secsize != 9) || !(*new_sectors) || !(*new_heads) || (*new_sectors) > max_sectors || (*new_heads) > max_heads || density != 0)
	{
		fseek(file, 0xDC0, SEEK_SET);
		log2secsize = getc(file);
		*new_sectors = getc(file);
		*new_heads = getc(file);
		density = getc(file);

		if ((log2secsize != 8 && log2secsize != 9) || !(*new_sectors) || !(*new_heads) || (*new_sectors) > max_sectors || (*new_heads) > max_heads || density != 0)
		{
			*new_sectors = max_sectors;
			*new_heads = max_heads;
		}
	}
	else
		filesize -= 512;

	fclose(file);
	*new_cylinders = filesize / (sector_size * *new_sectors * *new_heads);

	ARCHardDiskDialog *dialog = [[ARCHardDiskDialog alloc] initWithTitle:@"Configure hard disc"
						      creatingFile:NO
							 sectors:*new_sectors
							   heads:*new_heads
						       cylinders:*new_cylinders
							    path:nil
							maxCylinders:max_cylinders
							    maxHeads:max_heads
							  minSectors:min_sectors
							  maxSectors:max_sectors
							   sectorSize:sector_size];
	[dialog.window center];
	NSInteger result = arc_run_dialog_window(dialog.window, &dialog->modalResult);
	if (result != NSModalResponseOK)
		return 0;

	*new_sectors = (int)[dialog.sectorsField integerValue];
	*new_heads = (int)[dialog.headsField integerValue];
	*new_cylinders = (int)[dialog.cylindersField integerValue];
	return 1;
}
