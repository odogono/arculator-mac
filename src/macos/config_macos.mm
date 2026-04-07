#import <AppKit/AppKit.h>

#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <vector>

#include "dialog_util.h"
#include "wx-config.h"
#include "wx-config_sel.h"
#include "wx-hd_conf.h"
#include "wx-hd_new.h"
#include "wx-joystick-config.h"
#include "wx-podule-config.h"

extern "C"
{
#include "arc.h"
#include "arm.h"
#include "config.h"
#include "fpa.h"
#include "joystick.h"
#include "memc.h"
#include "platform_paths.h"
#include "podules.h"
#include "st506.h"
}

enum
{
	CPU_ARM2 = 0,
	CPU_ARM250,
	CPU_ARM3_20,
	CPU_ARM3_25,
	CPU_ARM3_26,
	CPU_ARM3_30,
	CPU_ARM3_33,
	CPU_ARM3_35,
	CPU_ARM3_24,
	CPU_ARM3_36,
	CPU_ARM3_40,
	CPU_MAX
};

static const char *cpu_names[] = {
	"ARM2", "ARM250", "ARM3 @ 20 MHz", "ARM3 @ 25 MHz", "ARM3 @ 26 MHz", "ARM3 @ 30 MHz",
	"ARM3 @ 33 MHz", "ARM3 @ 35 MHz", "ARM3 @ 24 MHz", "ARM3 @ 36 MHz", "ARM3 @ 40 MHz"
};

enum
{
	CPU_MASK_ARM2    = (1 << CPU_ARM2),
	CPU_MASK_ARM250  = (1 << CPU_ARM250),
	CPU_MASK_ARM3_20 = (1 << CPU_ARM3_20),
	CPU_MASK_ARM3_25 = (1 << CPU_ARM3_25),
	CPU_MASK_ARM3_26 = (1 << CPU_ARM3_26),
	CPU_MASK_ARM3_30 = (1 << CPU_ARM3_30),
	CPU_MASK_ARM3_33 = (1 << CPU_ARM3_33),
	CPU_MASK_ARM3_35 = (1 << CPU_ARM3_35),
	CPU_MASK_ARM3_24 = (1 << CPU_ARM3_24),
	CPU_MASK_ARM3_36 = (1 << CPU_ARM3_36),
	CPU_MASK_ARM3_40 = (1 << CPU_ARM3_40)
};

#define CPU_ARM2_AND_LATER (CPU_MASK_ARM2 | CPU_MASK_ARM3_20 | CPU_MASK_ARM3_25 | CPU_MASK_ARM3_26 | CPU_MASK_ARM3_30 | CPU_MASK_ARM3_33 | CPU_MASK_ARM3_35 | CPU_MASK_ARM3_36 | CPU_MASK_ARM3_40)
#define CPU_ARM250_ONLY (CPU_MASK_ARM250)
#define CPU_ARM3_25_AND_LATER (CPU_MASK_ARM3_25 | CPU_MASK_ARM3_26 | CPU_MASK_ARM3_30 | CPU_MASK_ARM3_33 | CPU_MASK_ARM3_35 | CPU_MASK_ARM3_36 | CPU_MASK_ARM3_40)
#define CPU_ARM3_26_AND_LATER (CPU_MASK_ARM3_26 | CPU_MASK_ARM3_30 | CPU_MASK_ARM3_33 | CPU_MASK_ARM3_35 | CPU_MASK_ARM3_36 | CPU_MASK_ARM3_40)
#define CPU_ARM3_33_AND_LATER (CPU_MASK_ARM3_33 | CPU_MASK_ARM3_35 | CPU_MASK_ARM3_36 | CPU_MASK_ARM3_40)
#define CPU_ARM3_24_ONLY (CPU_MASK_ARM3_24)

enum
{
	FPU_NONE = 0,
	FPU_FPPC,
	FPU_FPA10
};

enum
{
	MEMC_MEMC1 = 0,
	MEMC_MEMC1A_8,
	MEMC_MEMC1A_12,
	MEMC_MEMC1A_16,
	MEMC_MEMC1A_20,
	MEMC_MEMC1A_24
};

static const char *memc_names[] = {
	"MEMC1", "MEMC1a (8 MHz)", "MEMC1a (12 MHz)", "MEMC1a (16 MHz - overclocked)",
	"MEMC1a (20 MHz - overclocked)", "MEMC1a (24 MHz - overclocked)"
};

enum
{
	MEMC_MASK_MEMC1     = (1 << MEMC_MEMC1),
	MEMC_MASK_MEMC1A_8  = (1 << MEMC_MEMC1A_8),
	MEMC_MASK_MEMC1A_12 = (1 << MEMC_MEMC1A_12),
	MEMC_MASK_MEMC1A_16 = (1 << MEMC_MEMC1A_16),
	MEMC_MASK_MEMC1A_20 = (1 << MEMC_MEMC1A_20),
	MEMC_MASK_MEMC1A_24 = (1 << MEMC_MEMC1A_24)
};

#define MEMC_MIN_MEMC1 (MEMC_MASK_MEMC1 | MEMC_MASK_MEMC1A_8 | MEMC_MASK_MEMC1A_12 | MEMC_MASK_MEMC1A_16 | MEMC_MASK_MEMC1A_20 | MEMC_MASK_MEMC1A_24)
#define MEMC_MIN_MEMC1A (MEMC_MASK_MEMC1A_8 | MEMC_MASK_MEMC1A_12 | MEMC_MASK_MEMC1A_16 | MEMC_MASK_MEMC1A_20 | MEMC_MASK_MEMC1A_24)
#define MEMC_MIN_MEMC1A_12 (MEMC_MASK_MEMC1A_12 | MEMC_MASK_MEMC1A_16 | MEMC_MASK_MEMC1A_20 | MEMC_MASK_MEMC1A_24)

enum
{
	IO_OLD = 0,
	IO_OLD_ST506,
	IO_NEW
};

enum
{
	MEM_512K = 0,
	MEM_1M,
	MEM_2M,
	MEM_4M,
	MEM_8M,
	MEM_12M,
	MEM_16M
};

static const char *mem_names[] = { "512 kB", "1 MB", "2 MB", "4 MB", "8 MB", "12 MB", "16 MB" };

enum
{
	MEM_MASK_512K = (1 << MEM_512K),
	MEM_MASK_1M   = (1 << MEM_1M),
	MEM_MASK_2M   = (1 << MEM_2M),
	MEM_MASK_4M   = (1 << MEM_4M),
	MEM_MASK_8M   = (1 << MEM_8M),
	MEM_MASK_12M  = (1 << MEM_12M),
	MEM_MASK_16M  = (1 << MEM_16M)
};

#define MEM_MIN_512K (MEM_MASK_512K | MEM_MASK_1M | MEM_MASK_2M | MEM_MASK_4M | MEM_MASK_8M | MEM_MASK_16M)
#define MEM_MIN_1M (MEM_MASK_1M | MEM_MASK_2M | MEM_MASK_4M | MEM_MASK_8M | MEM_MASK_16M)
#define MEM_MIN_2M (MEM_MASK_2M | MEM_MASK_4M | MEM_MASK_8M | MEM_MASK_16M)
#define MEM_MIN_4M (MEM_MASK_4M | MEM_MASK_8M | MEM_MASK_12M | MEM_MASK_16M)
#define MEM_1M_4M (MEM_MASK_1M | MEM_MASK_2M | MEM_MASK_4M)
#define MEM_2M_4M (MEM_MASK_2M | MEM_MASK_4M)
#define MEM_4M_ONLY (MEM_MASK_4M)

static const char *rom_names[] = {
	"Arthur 0.30", "Arthur 1.20", "RISC OS 2.00", "RISC OS 2.01", "RISC OS 3.00",
	"RISC OS 3.10", "RISC OS 3.11", "RISC OS 3.19", "Arthur 1.20 (A500)",
	"RISC OS 2.00 (A500)", "RISC OS 3.10 (A500)"
};

enum
{
	ROM_ARTHUR_030_MASK = (1 << ROM_ARTHUR_030),
	ROM_ARTHUR_120_MASK = (1 << ROM_ARTHUR_120),
	ROM_RISCOS_200_MASK = (1 << ROM_RISCOS_200),
	ROM_RISCOS_201_MASK = (1 << ROM_RISCOS_201),
	ROM_RISCOS_300_MASK = (1 << ROM_RISCOS_300),
	ROM_RISCOS_310_MASK = (1 << ROM_RISCOS_310),
	ROM_RISCOS_311_MASK = (1 << ROM_RISCOS_311),
	ROM_RISCOS_319_MASK = (1 << ROM_RISCOS_319),
	ROM_ARTHUR_120_A500_MASK = (1 << ROM_ARTHUR_120_A500),
	ROM_RISCOS_200_A500_MASK = (1 << ROM_RISCOS_200_A500),
	ROM_RISCOS_310_A500_MASK = (1 << ROM_RISCOS_310_A500)
};

#define ROM_ALL (ROM_ARTHUR_030_MASK | ROM_ARTHUR_120_MASK | ROM_RISCOS_200_MASK | ROM_RISCOS_201_MASK | ROM_RISCOS_300_MASK | ROM_RISCOS_310_MASK | ROM_RISCOS_311_MASK | ROM_RISCOS_319_MASK)
#define ROM_RISCOS (ROM_RISCOS_200_MASK | ROM_RISCOS_201_MASK | ROM_RISCOS_300_MASK | ROM_RISCOS_310_MASK | ROM_RISCOS_311_MASK | ROM_RISCOS_319_MASK)
#define ROM_RISCOS201 (ROM_RISCOS_201_MASK | ROM_RISCOS_300_MASK | ROM_RISCOS_310_MASK | ROM_RISCOS_311_MASK | ROM_RISCOS_319_MASK)
#define ROM_RISCOS3 (ROM_RISCOS_300_MASK | ROM_RISCOS_310_MASK | ROM_RISCOS_311_MASK | ROM_RISCOS_319_MASK)
#define ROM_RISCOS31 (ROM_RISCOS_310_MASK | ROM_RISCOS_311_MASK | ROM_RISCOS_319_MASK)
#define ROM_A500 (ROM_ARTHUR_120_A500_MASK | ROM_RISCOS_200_A500_MASK | ROM_RISCOS_310_A500_MASK)

static const char *monitor_names[] = { "Standard", "Multisync", "VGA", "High res mono", "LCD" };

enum
{
	MONITOR_STANDARD_MASK  = (1 << MONITOR_STANDARD),
	MONITOR_MULTISYNC_MASK = (1 << MONITOR_MULTISYNC),
	MONITOR_VGA_MASK       = (1 << MONITOR_VGA),
	MONITOR_MONO_MASK      = (1 << MONITOR_MONO),
	MONITOR_LCD_MASK       = (1 << MONITOR_LCD)
};

#define MONITOR_ALL (MONITOR_STANDARD_MASK | MONITOR_MULTISYNC_MASK | MONITOR_VGA_MASK | MONITOR_MONO_MASK)
#define MONITOR_NO_MONO (MONITOR_STANDARD_MASK | MONITOR_MULTISYNC_MASK | MONITOR_VGA_MASK)
#define MONITOR_LCD_A4 (MONITOR_STANDARD_MASK | MONITOR_MULTISYNC_MASK | MONITOR_VGA_MASK | MONITOR_LCD_MASK)

enum
{
	PODULE_NONE = 0,
	PODULE_16BIT,
	PODULE_8BIT,
	PODULE_NET
};

typedef struct machine_preset_t
{
	const char *name;
	const char *config_name;
	const char *description;
	int machine_type;
	unsigned int allowed_cpu_mask;
	unsigned int allowed_mem_mask;
	unsigned int allowed_memc_mask;
	unsigned int allowed_romset_mask;
	unsigned int allowed_monitor_mask;
	int default_cpu, default_mem, default_memc, io;
	int podule_type[4];
	bool has_5th_column;
} machine_preset_t;

static const machine_preset_t presets[] = {
	{"Archimedes 305", "a305", "ARM2, 512kB RAM, MEMC1, Old IO, Arthur", MACHINE_TYPE_NORMAL, CPU_ARM2_AND_LATER, MEM_MIN_512K, MEMC_MIN_MEMC1, ROM_ALL, MONITOR_NO_MONO, CPU_ARM2, MEM_512K, MEMC_MEMC1, IO_OLD, {PODULE_16BIT, PODULE_16BIT, PODULE_16BIT, PODULE_16BIT}, 0},
	{"Archimedes 310", "a310", "ARM2, 1MB RAM, MEMC1, Old IO, Arthur", MACHINE_TYPE_NORMAL, CPU_ARM2_AND_LATER, MEM_MIN_1M, MEMC_MIN_MEMC1, ROM_ALL, MONITOR_NO_MONO, CPU_ARM2, MEM_1M, MEMC_MEMC1, IO_OLD, {PODULE_16BIT, PODULE_16BIT, PODULE_16BIT, PODULE_16BIT}, 0},
	{"Archimedes 440", "a440", "ARM2, 4MB RAM, MEMC1, Old IO + ST-506 HD, Arthur", MACHINE_TYPE_NORMAL, CPU_ARM2_AND_LATER, MEM_MIN_4M, MEMC_MIN_MEMC1, ROM_ALL, MONITOR_ALL, CPU_ARM2, MEM_4M, MEMC_MEMC1, IO_OLD_ST506, {PODULE_16BIT, PODULE_16BIT, PODULE_16BIT, PODULE_16BIT}, 0},
	{"Archimedes 410/1", "a410/1", "ARM2, 1MB RAM, MEMC1A, Old IO + ST-506 HD, RISC OS 2", MACHINE_TYPE_NORMAL, CPU_ARM2_AND_LATER, MEM_MIN_1M, MEMC_MIN_MEMC1A, ROM_RISCOS, MONITOR_ALL, CPU_ARM2, MEM_1M, MEMC_MEMC1A_8, IO_OLD_ST506, {PODULE_16BIT, PODULE_16BIT, PODULE_16BIT, PODULE_16BIT}, 0},
	{"Archimedes 420/1", "a420/1", "ARM2, 2MB RAM, MEMC1A, Old IO + ST-506 HD, RISC OS 2", MACHINE_TYPE_NORMAL, CPU_ARM2_AND_LATER, MEM_MIN_2M, MEMC_MIN_MEMC1A, ROM_RISCOS, MONITOR_ALL, CPU_ARM2, MEM_2M, MEMC_MEMC1A_8, IO_OLD_ST506, {PODULE_16BIT, PODULE_16BIT, PODULE_16BIT, PODULE_16BIT}, 0},
	{"Archimedes 440/1", "a440/1", "ARM2, 4MB RAM, MEMC1A, Old IO + ST-506 HD, RISC OS 2", MACHINE_TYPE_NORMAL, CPU_ARM2_AND_LATER, MEM_MIN_4M, MEMC_MIN_MEMC1A, ROM_RISCOS, MONITOR_ALL, CPU_ARM2, MEM_4M, MEMC_MEMC1A_8, IO_OLD_ST506, {PODULE_16BIT, PODULE_16BIT, PODULE_16BIT, PODULE_16BIT}, 0},
	{"A3000", "a3000", "ARM2, 1MB RAM, MEMC1A, Old IO, RISC OS 2", MACHINE_TYPE_NORMAL, CPU_ARM2_AND_LATER, MEM_MIN_1M, MEMC_MIN_MEMC1A, ROM_RISCOS, MONITOR_NO_MONO, CPU_ARM2, MEM_1M, MEMC_MEMC1A_8, IO_OLD, {PODULE_16BIT, PODULE_8BIT, PODULE_NONE, PODULE_NONE}, 0},
	{"Archimedes 540", "a540", "ARM3/26, 4MB RAM, MEMC1A, Old IO, RISC OS 2.01", MACHINE_TYPE_NORMAL, CPU_ARM3_26_AND_LATER, MEM_MIN_4M, MEMC_MIN_MEMC1A_12, ROM_RISCOS201, MONITOR_ALL, CPU_ARM3_26, MEM_4M, MEMC_MEMC1A_12, IO_OLD, {PODULE_16BIT, PODULE_16BIT, PODULE_16BIT, PODULE_16BIT}, 0},
	{"A5000", "a5000", "ARM3/25, 1MB RAM, MEMC1A, New IO, RISC OS 3.0", MACHINE_TYPE_NORMAL, CPU_ARM3_25_AND_LATER, MEM_MIN_1M, MEMC_MIN_MEMC1A_12, ROM_RISCOS3, MONITOR_NO_MONO, CPU_ARM3_25, MEM_2M, MEMC_MEMC1A_12, IO_NEW, {PODULE_16BIT, PODULE_16BIT, PODULE_16BIT, PODULE_16BIT}, 1},
	{"A4", "a4", "ARM3/24, 2MB RAM, MEMC1A, New IO, RISC OS 3.0", MACHINE_TYPE_A4, CPU_ARM3_24_ONLY, MEM_2M_4M, MEMC_MIN_MEMC1A_12, ROM_RISCOS3, MONITOR_LCD_A4, CPU_ARM3_24, MEM_2M, MEMC_MEMC1A_12, IO_NEW, {PODULE_NONE, PODULE_NONE, PODULE_NONE, PODULE_NONE}, 1},
	{"A3010", "a3010", "ARM250, 1MB RAM, MEMC1A, New IO, RISC OS 3.1", MACHINE_TYPE_NORMAL, CPU_ARM250_ONLY, MEM_1M_4M, MEMC_MIN_MEMC1A_12, ROM_RISCOS31, MONITOR_NO_MONO, CPU_ARM250, MEM_1M, MEMC_MEMC1A_12, IO_NEW, {PODULE_NONE, PODULE_8BIT, PODULE_NONE, PODULE_NONE}, 0},
	{"A3020", "a3020", "ARM250, 2MB RAM, MEMC1A, New IO, RISC OS 3.1", MACHINE_TYPE_NORMAL, CPU_ARM250_ONLY, MEM_2M_4M, MEMC_MIN_MEMC1A_12, ROM_RISCOS31, MONITOR_NO_MONO, CPU_ARM250, MEM_2M, MEMC_MEMC1A_12, IO_NEW, {PODULE_NET, PODULE_8BIT, PODULE_NONE, PODULE_NONE}, 0},
	{"A4000", "a4000", "ARM250, 2MB RAM, MEMC1A, New IO, RISC OS 3.1", MACHINE_TYPE_NORMAL, CPU_ARM250_ONLY, MEM_2M_4M, MEMC_MIN_MEMC1A_12, ROM_RISCOS31, MONITOR_NO_MONO, CPU_ARM250, MEM_2M, MEMC_MEMC1A_12, IO_NEW, {PODULE_NET, PODULE_8BIT, PODULE_NONE, PODULE_NONE}, 0},
	{"A5000a", "a5000a", "ARM3/33, 4MB RAM, MEMC1A, New IO, RISC OS 3.1", MACHINE_TYPE_NORMAL, CPU_ARM3_33_AND_LATER, MEM_MIN_4M, MEMC_MIN_MEMC1A_12, ROM_RISCOS31, MONITOR_NO_MONO, CPU_ARM3_33, MEM_4M, MEMC_MEMC1A_12, IO_NEW, {PODULE_16BIT, PODULE_16BIT, PODULE_16BIT, PODULE_16BIT}, 1},
	{"A500 (prototype)", "a500", "ARM2, 4MB RAM, MEMC1, Old IO + ST-506 HD, Arthur", MACHINE_TYPE_NORMAL, CPU_ARM2_AND_LATER, MEM_4M_ONLY, MEMC_MIN_MEMC1, ROM_A500, MONITOR_ALL, CPU_ARM2, MEM_4M, MEMC_MEMC1, IO_OLD_ST506, {PODULE_16BIT, PODULE_16BIT, PODULE_16BIT, PODULE_16BIT}, 0},
	{ "", NULL, NULL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, {0, 0, 0, 0}, 0 }
};

static int preset_from_display_name(const char *name)
{
	for (int c = 0; presets[c].name[0]; c++)
	{
		if (!strcmp(presets[c].name, name))
			return c;
	}
	return 0;
}

static int preset_from_config_name(const char *name)
{
	for (int c = 0; presets[c].name[0]; c++)
	{
		if (!strcmp(presets[c].config_name, name))
			return c;
	}
	return 0;
}

static int index_for_name(const char *const *names, int count, const char *name)
{
	for (int c = 0; c < count; c++)
	{
		if (!strcmp(names[c], name))
			return c;
	}
	return 0;
}

static NSString *config_path_for_name(NSString *config_name)
{
	char path[512];
	platform_path_machine_config(path, sizeof(path), config_name.UTF8String);
	return arc_nsstring(path);
}

static NSArray<NSString *> *list_config_names(void)
{
	char config_dir[512];
	platform_path_configs_dir(config_dir, sizeof(config_dir));
	NSMutableArray<NSString *> *names = [NSMutableArray array];
	NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:arc_nsstring(config_dir) error:nil];

	for (NSString *file in files)
	{
		if ([[file pathExtension] isEqualToString:@"cfg"])
			[names addObject:[file stringByDeletingPathExtension]];
	}

	[names sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	return names;
}

static int preset_allowed_by_rom(int preset)
{
	return (romset_available_mask & presets[preset].allowed_romset_mask) != 0;
}

@interface ARCConfigSelectionDialog : NSObject <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>
{
	int resultCode;
	NSInteger modalResult;
}
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSString *> *configNames;
@end

@implementation ARCConfigSelectionDialog

- (instancetype)init
{
	self = [super init];
	if (!self)
		return nil;

	self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 560.0, 360.0)
					      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
						backing:NSBackingStoreBuffered
						  defer:NO];
	self.window.title = @"Select Configuration";
	self.window.releasedWhenClosed = NO;
	self.window.delegate = self;
	resultCode = -1;
	modalResult = ARC_MODAL_RESPONSE_CONTINUE;

	NSView *content = self.window.contentView;
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20.0, 70.0, 360.0, 260.0)];
	scroll.hasVerticalScroller = YES;
	scroll.borderType = NSBezelBorder;
	self.tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"config"];
	column.title = @"Configurations";
	column.width = 340.0;
	[self.tableView addTableColumn:column];
	self.tableView.headerView = nil;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.target = self;
	self.tableView.doubleAction = @selector(openSelected:);
	scroll.documentView = self.tableView;
	[content addSubview:scroll];

	struct { NSString *title; SEL action; CGFloat x; } buttonDefs[] = {
		{ @"Open", @selector(openSelected:), 420.0 },
		{ @"Cancel", @selector(cancel:), 420.0 },
		{ @"New", @selector(createConfig:), 250.0 },
		{ @"Rename", @selector(renameConfig:), 250.0 },
		{ @"Copy", @selector(copyConfig:), 250.0 },
		{ @"Delete", @selector(deleteConfig:), 250.0 },
		{ @"Configure", @selector(configureConfig:), 250.0 },
	};
	CGFloat y = 300.0;
	for (const auto &def : buttonDefs)
	{
		NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(def.x, y, 110.0, 28.0)];
		button.title = def.title;
		button.target = self;
		button.action = def.action;
		[content addSubview:button];
		y -= 36.0;
	}

	[self reloadConfigsPreservingSelection:nil];
	return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return self.configNames.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	(void)tableColumn;
	NSTextField *field = [tableView makeViewWithIdentifier:@"cell" owner:self];
	if (!field)
	{
		field = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 22.0)];
		field.identifier = @"cell";
		field.bezeled = NO;
		field.drawsBackground = NO;
		field.editable = NO;
		field.selectable = NO;
	}
	field.stringValue = self.configNames[(NSUInteger)row];
	return field;
}

- (NSString *)selectedConfigName
{
	NSInteger row = self.tableView.selectedRow;
	return (row >= 0 && row < (NSInteger)self.configNames.count) ? self.configNames[(NSUInteger)row] : nil;
}

- (BOOL)ensureSelection
{
	if (self.configNames.count == 0)
		return NO;
	if (self.tableView.selectedRow < 0)
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	return self.tableView.selectedRow >= 0;
}

- (void)reloadConfigsPreservingSelection:(NSString *)selection
{
	self.configNames = [list_config_names() mutableCopy];
	[self.tableView reloadData];
	NSString *target = selection ?: self.selectedConfigName;
	if (target)
	{
		NSUInteger index = [self.configNames indexOfObject:target];
		if (index != NSNotFound)
			[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
	}
	if (self.tableView.selectedRow < 0 && self.configNames.count)
		[self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}

- (BOOL)loadSelectedConfig
{
	NSString *selection = [self selectedConfigName];
	if (!selection.length)
		return NO;
	arc_copy_string(machine_config_file, sizeof(machine_config_file), config_path_for_name(selection));
	arc_copy_string(machine_config_name, sizeof(machine_config_name), selection);
	return YES;
}

- (void)openSelected:(id)sender
{
	if (![self ensureSelection])
	{
		if (arc_confirm(@"Arculator", @"No machine configurations exist yet. Create one now?"))
			[self createConfig:nil];
		return;
	}

	if ([self loadSelectedConfig])
	{
		resultCode = 0;
		arc_close_dialog_window(self.window, &modalResult, NSModalResponseOK);
	}
	(void)sender;
}

- (void)cancel:(id)sender
{
	resultCode = -1;
	arc_close_dialog_window(self.window, &modalResult, NSModalResponseCancel);
	(void)sender;
}

- (void)createConfig:(id)sender
{
	NSString *configName = arc_prompt_text(@"New config", @"Enter name:", @"", 64);
	if (!configName.length)
		return;
	if ([[NSFileManager defaultManager] fileExistsAtPath:config_path_for_name(configName)])
	{
		arc_show_message(@"Arculator", @"A configuration with that name already exists");
		return;
	}

	int preset = ShowPresetList();
	if (preset == -1)
		return;

	arc_copy_string(machine_config_file, sizeof(machine_config_file), config_path_for_name(configName));
	arc_copy_string(machine_config_name, sizeof(machine_config_name), configName);
	loadconfig();
	ShowConfigWithPreset(preset);
	[self reloadConfigsPreservingSelection:configName];
	(void)sender;
}

- (void)renameConfig:(id)sender
{
	if (![self ensureSelection])
	{
		arc_show_message(@"Arculator", @"Select a configuration first.");
		return;
	}
	NSString *oldName = [self selectedConfigName];
	NSString *newName = arc_prompt_text(@"Rename config", @"Enter name:", oldName, 64);
	if (!newName.length)
		return;
	if ([[NSFileManager defaultManager] fileExistsAtPath:config_path_for_name(newName)])
	{
		arc_show_message(@"Arculator", @"A configuration with that name already exists");
		return;
	}
	[[NSFileManager defaultManager] moveItemAtPath:config_path_for_name(oldName) toPath:config_path_for_name(newName) error:nil];
	[self reloadConfigsPreservingSelection:newName];
	(void)sender;
}

- (void)copyConfig:(id)sender
{
	if (![self ensureSelection])
	{
		arc_show_message(@"Arculator", @"Select a configuration first.");
		return;
	}
	NSString *oldName = [self selectedConfigName];
	NSString *newName = arc_prompt_text(@"Copy config", @"Enter name:", oldName, 64);
	if (!newName.length)
		return;
	if ([[NSFileManager defaultManager] fileExistsAtPath:config_path_for_name(newName)])
	{
		arc_show_message(@"Arculator", @"A configuration with that name already exists");
		return;
	}
	[[NSFileManager defaultManager] copyItemAtPath:config_path_for_name(oldName) toPath:config_path_for_name(newName) error:nil];
	[self reloadConfigsPreservingSelection:newName];
	(void)sender;
}

- (void)deleteConfig:(id)sender
{
	if (![self ensureSelection])
	{
		arc_show_message(@"Arculator", @"Select a configuration first.");
		return;
	}
	NSString *name = [self selectedConfigName];
	if (!arc_confirm(@"Arculator", [NSString stringWithFormat:@"Are you sure you want to delete %@?", name]))
		return;
	[[NSFileManager defaultManager] removeItemAtPath:config_path_for_name(name) error:nil];
	[self reloadConfigsPreservingSelection:nil];
	(void)sender;
}

- (void)configureConfig:(id)sender
{
	if (![self loadSelectedConfig])
	{
		arc_show_message(@"Arculator", @"Select a configuration first.");
		return;
	}
	loadconfig();
	ShowConfig(false);
	[self reloadConfigsPreservingSelection:arc_nsstring(machine_config_name)];
	(void)sender;
}

- (void)windowWillClose:(NSNotification *)notification
{
	(void)notification;
	if (modalResult == ARC_MODAL_RESPONSE_CONTINUE)
		modalResult = NSModalResponseCancel;
}

- (int)runDialog
{
	[self.window center];
	arc_run_dialog_window(self.window, &modalResult);
	return resultCode;
}

@end

@interface ARCMachineConfigDialog : NSObject <NSWindowDelegate, NSTextFieldDelegate>
{
	int configPreset;
	int configCpu;
	int configMem;
	int configMemc;
	int configFpu;
	int configIo;
	int configRom;
	int configMonitor;
	uint32_t configUniqueId;
	char configPodules[4][16];
	BOOL running;
	BOOL suppressUpdates;
	BOOL isA3010;
	NSInteger modalResult;
	NSString *hdFns[2];
	NSWindow *window;
	NSTextField *machineDescriptionLabel;
	NSPopUpButton *machinePopup;
	NSPopUpButton *cpuPopup;
	NSPopUpButton *memoryPopup;
	NSPopUpButton *memcPopup;
	NSPopUpButton *fpuPopup;
	NSPopUpButton *osPopup;
	NSPopUpButton *monitorPopup;
	NSPopUpButton *joyPopup;
	NSPopUpButton *podulePopups[4];
	NSButton *poduleButtons[4];
	NSTextField *poduleLabels[4];
	NSTextField *uniqueIdField;
	NSTextField *hdPathFields[2];
	NSTextField *hdCylinderFields[2];
	NSTextField *hdHeadFields[2];
	NSTextField *hdSectorFields[2];
	NSTextField *hdSizeFields[2];
	NSTextField *fifthColumnField;
	NSButton *supportRomCheck;
}
@end

@implementation ARCMachineConfigDialog

- (NSWindow *)window
{
	return window;
}

- (instancetype)initWithRunning:(BOOL)isRunning preset:(int)preset usePreset:(BOOL)usePreset
{
	self = [super init];
	if (!self)
		return nil;

	running = isRunning;
	if (usePreset)
	{
		configPreset = preset;
		configCpu = presets[preset].default_cpu;
		configMem = presets[preset].default_mem;
		configMemc = presets[preset].default_memc;
		configFpu = FPU_NONE;
		configIo = presets[preset].io;
		configMonitor = MONITOR_MULTISYNC;
		configRom = (preset != 14) ? ROM_RISCOS_311 : ROM_RISCOS_310_A500;
		if (configIo == IO_NEW)
		{
			srand((unsigned int)time(NULL));
			configUniqueId = (uint32_t)(rand() ^ (rand() << 16));
		}
		strncpy(configPodules[0], "arculator_rom", sizeof(configPodules[0]) - 1);
		configPodules[0][sizeof(configPodules[0]) - 1] = 0;
		configPodules[1][0] = 0;
		configPodules[2][0] = 0;
		configPodules[3][0] = 0;
	}
	else
	{
		configPreset = preset_from_config_name(machine);
		configCpu = arm_cpu_type;
		configFpu = fpaena ? (fpu_type ? FPU_FPPC : FPU_FPA10) : FPU_NONE;
		configMemc = memc_type;
		configIo = fdctype ? IO_NEW : (st506_present ? IO_OLD_ST506 : IO_OLD);
		configMonitor = monitor_type;
		configUniqueId = unique_id;
		configRom = romset;
		memcpy(configPodules, podule_names, sizeof(configPodules));

		switch (memsize)
		{
			case 512: configMem = MEM_512K; break;
			case 1024: configMem = MEM_1M; break;
			case 2048: configMem = MEM_2M; break;
			case 4096: configMem = MEM_4M; break;
			case 8192: configMem = MEM_8M; break;
			case 12288: configMem = MEM_12M; break;
			default: configMem = MEM_16M; break;
		}
	}

	hdFns[0] = arc_nsstring(hd_fn[0]);
	hdFns[1] = arc_nsstring(hd_fn[1]);
	modalResult = ARC_MODAL_RESPONSE_CONTINUE;

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 720.0, 760.0)
					       styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
						 backing:NSBackingStoreBuffered
						   defer:NO];
	window.title = @"Configure Arculator";
	window.releasedWhenClosed = NO;
	window.delegate = self;

	NSView *content = window.contentView;
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12.0, 56.0, 696.0, 680.0)];
	scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	scroll.hasVerticalScroller = YES;
	scroll.borderType = NSBezelBorder;
	[content addSubview:scroll];

	NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 676.0, 1200.0)];
	scroll.documentView = form;

	auto addLabel = ^NSTextField *(NSString *labelText, CGFloat x, CGFloat y, CGFloat width) {
		NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, width, 22.0)];
		label.bezeled = NO;
		label.drawsBackground = NO;
		label.editable = NO;
		label.selectable = NO;
		label.stringValue = labelText;
		[form addSubview:label];
		return label;
	};
	auto addPopup = ^NSPopUpButton *(CGFloat x, CGFloat y, CGFloat width, SEL action) {
		NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, y - 2.0, width, 26.0)];
		popup.target = self;
		popup.action = action;
		[form addSubview:popup];
		return popup;
	};
	auto addField = ^NSTextField *(CGFloat x, CGFloat y, CGFloat width, SEL action) {
		NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y - 2.0, width, 24.0)];
		field.delegate = self;
		if (action)
		{
			field.target = self;
			field.action = action;
		}
		[form addSubview:field];
		return field;
	};
	auto addButton = ^NSButton *(NSString *title, CGFloat x, CGFloat y, CGFloat width, SEL action) {
		NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, y - 2.0, width, 26.0)];
		button.title = title;
		button.target = self;
		button.action = action;
		[form addSubview:button];
		return button;
	};

	CGFloat y = 1140.0;
	addLabel(@"Machine", 20.0, y, 140.0);
	machinePopup = addPopup(180.0, y, 220.0, @selector(machineChanged:));
	y -= 34.0;
	machineDescriptionLabel = addLabel(@"", 20.0, y, 620.0);
	y -= 40.0;
	addLabel(@"CPU", 20.0, y, 140.0);
	cpuPopup = addPopup(180.0, y, 220.0, @selector(cpuChanged:));
	addLabel(@"Memory", 420.0, y, 100.0);
	memoryPopup = addPopup(520.0, y, 140.0, @selector(memoryChanged:));
	y -= 34.0;
	addLabel(@"MEMC", 20.0, y, 140.0);
	memcPopup = addPopup(180.0, y, 220.0, @selector(memcChanged:));
	addLabel(@"FPU", 420.0, y, 100.0);
	fpuPopup = addPopup(520.0, y, 140.0, @selector(fpuChanged:));
	y -= 34.0;
	addLabel(@"OS", 20.0, y, 140.0);
	osPopup = addPopup(180.0, y, 220.0, @selector(osChanged:));
	addLabel(@"Monitor", 420.0, y, 100.0);
	monitorPopup = addPopup(520.0, y, 140.0, @selector(monitorChanged:));
	y -= 34.0;
	addLabel(@"Unique ID", 20.0, y, 140.0);
	uniqueIdField = addField(180.0, y, 120.0, @selector(uniqueIdChanged:));
	y -= 34.0;
	addLabel(@"Joystick interface", 20.0, y, 140.0);
	joyPopup = addPopup(180.0, y, 220.0, nil);
	addButton(@"Joy 1", 420.0, y, 80.0, @selector(configureJoy1:));
	addButton(@"Joy 2", 510.0, y, 80.0, @selector(configureJoy2:));
	y -= 44.0;

	for (int slot = 0; slot < 4; slot++)
	{
		poduleLabels[slot] = addLabel(@"", 20.0, y, 140.0);
		podulePopups[slot] = addPopup(180.0, y, 300.0, @selector(poduleChanged:));
		podulePopups[slot].tag = slot;
		poduleButtons[slot] = addButton(@"Configure", 500.0, y, 100.0, @selector(configurePodule:));
		poduleButtons[slot].tag = slot;
		y -= 34.0;
	}

	y -= 12.0;
	for (int drive = 0; drive < 2; drive++)
	{
		addLabel([NSString stringWithFormat:@"HD %d", drive + 4], 20.0, y, 60.0);
		hdPathFields[drive] = addField(80.0, y, 320.0, nil);
		addButton(@"Select", 420.0, y, 70.0, drive == 0 ? @selector(selectHd4:) : @selector(selectHd5:));
		addButton(@"New", 500.0, y, 60.0, drive == 0 ? @selector(newHd4:) : @selector(newHd5:));
		addButton(@"Eject", 570.0, y, 60.0, drive == 0 ? @selector(ejectHd4:) : @selector(ejectHd5:));
		y -= 34.0;
		addLabel(@"Cyl", 80.0, y, 30.0);
		hdCylinderFields[drive] = addField(115.0, y, 60.0, nil);
		addLabel(@"Heads", 190.0, y, 45.0);
		hdHeadFields[drive] = addField(240.0, y, 50.0, nil);
		addLabel(@"Sectors", 305.0, y, 55.0);
		hdSectorFields[drive] = addField(365.0, y, 50.0, nil);
		addLabel(@"MB", 430.0, y, 25.0);
		hdSizeFields[drive] = addField(460.0, y, 70.0, nil);
		y -= 42.0;
	}

	addLabel(@"5th Column ROM", 20.0, y, 140.0);
	fifthColumnField = addField(180.0, y, 300.0, nil);
	addButton(@"Browse", 500.0, y, 100.0, @selector(selectFifthColumn:));
	y -= 34.0;
	supportRomCheck = [[NSButton alloc] initWithFrame:NSMakeRect(180.0, y - 2.0, 220.0, 24.0)];
	supportRomCheck.buttonType = NSButtonTypeSwitch;
	supportRomCheck.title = @"Enable support ROM";
	[form addSubview:supportRomCheck];

	NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(540.0, 14.0, 80.0, 30.0)];
	ok.title = @"OK";
	ok.keyEquivalent = @"\r";
	ok.target = self;
	ok.action = @selector(confirm:);
	[content addSubview:ok];
	NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(628.0, 14.0, 80.0, 30.0)];
	cancel.title = @"Cancel";
	cancel.keyEquivalent = @"\e";
	cancel.target = self;
	cancel.action = @selector(cancel:);
	[content addSubview:cancel];

	[self populateFixedValues];
	[self syncUiFromState];
	return self;
}

- (void)populateFixedValues
{
	[fifthColumnField setStringValue:arc_nsstring(_5th_column_fn)];
	supportRomCheck.state = support_rom_enabled ? NSControlStateValueOn : NSControlStateValueOff;

	for (int drive = 0; drive < 2; drive++)
	{
		hdPathFields[drive].stringValue = hdFns[drive];
		hdCylinderFields[drive].stringValue = [NSString stringWithFormat:@"%d", hd_cyl[drive]];
		hdHeadFields[drive].stringValue = [NSString stringWithFormat:@"%d", hd_hpc[drive]];
		hdSectorFields[drive].stringValue = [NSString stringWithFormat:@"%d", hd_spt[drive]];
		int size = (hd_cyl[drive] * hd_hpc[drive] * hd_spt[drive] * ((configIo == IO_NEW) ? 512 : 256)) / (1024 * 1024);
		hdSizeFields[drive].stringValue = [NSString stringWithFormat:@"%d", size];
	}
}

- (void)selectPopup:(NSPopUpButton *)popup withCString:(const char *)title fallback:(NSInteger)fallback
{
	NSInteger index = [popup indexOfItemWithTitle:arc_nsstring(title)];
	[popup selectItemAtIndex:index != -1 ? index : fallback];
}

- (void)syncUiFromState
{
	suppressUpdates = YES;

	[machinePopup removeAllItems];
	for (int c = 0; presets[c].name[0]; c++)
	{
		if (preset_allowed_by_rom(c))
			[machinePopup addItemWithTitle:arc_nsstring(presets[c].name)];
	}
	[self selectPopup:machinePopup withCString:presets[configPreset].name fallback:0];

	[cpuPopup removeAllItems];
	for (int c = 0; c < CPU_MAX; c++)
		if (presets[configPreset].allowed_cpu_mask & (1U << c))
			[cpuPopup addItemWithTitle:arc_nsstring(cpu_names[c])];
	[self selectPopup:cpuPopup withCString:cpu_names[configCpu] fallback:0];

	[memoryPopup removeAllItems];
	for (int c = 0; c < 7; c++)
		if (presets[configPreset].allowed_mem_mask & (1U << c))
			[memoryPopup addItemWithTitle:arc_nsstring(mem_names[c])];
	[self selectPopup:memoryPopup withCString:mem_names[configMem] fallback:0];

	[memcPopup removeAllItems];
	for (int c = 0; c < 6; c++)
		if (presets[configPreset].allowed_memc_mask & (1U << c))
			[memcPopup addItemWithTitle:arc_nsstring(memc_names[c])];
	[self selectPopup:memcPopup withCString:memc_names[configMemc] fallback:0];

	[fpuPopup removeAllItems];
	[fpuPopup addItemWithTitle:@"None"];
	if (configCpu == CPU_ARM2 && configMemc != MEMC_MEMC1)
		[fpuPopup addItemWithTitle:@"FPPC"];
	if (configCpu != CPU_ARM2 && configCpu != CPU_ARM250)
		[fpuPopup addItemWithTitle:@"FPA10"];
	[fpuPopup selectItemAtIndex:configFpu ? 1 : 0];

	[osPopup removeAllItems];
	for (int c = 0; c < ROM_MAX; c++)
		if ((romset_available_mask & (1 << c)) && (presets[configPreset].allowed_romset_mask & (1U << c)))
			[osPopup addItemWithTitle:arc_nsstring(rom_names[c])];
	[self selectPopup:osPopup withCString:rom_names[configRom] fallback:0];

	[monitorPopup removeAllItems];
	for (int c = 0; c < 5; c++)
		if (presets[configPreset].allowed_monitor_mask & (1U << c))
			[monitorPopup addItemWithTitle:arc_nsstring(monitor_names[c])];
	[self selectPopup:monitorPopup withCString:monitor_names[configMonitor] fallback:0];

	machineDescriptionLabel.stringValue = arc_nsstring(presets[configPreset].description);
	isA3010 = !strcmp(presets[configPreset].config_name, "a3010");

	[joyPopup removeAllItems];
	[joyPopup addItemWithTitle:@"None"];
	for (int c = 0; joystick_get_name(c); c++)
	{
		if (strcmp(joystick_get_config_name(c), "a3010") || isA3010)
			[joyPopup addItemWithTitle:arc_nsstring(joystick_get_name(c))];
	}
	NSString *joyName = @"None";
	for (int c = 0; joystick_get_name(c); c++)
		if (!strcmp(joystick_if, joystick_get_config_name(c)))
			joyName = arc_nsstring(joystick_get_name(c));
	[joyPopup selectItemWithTitle:joyName];

	for (int slot = 0; slot < 4; slot++)
	{
		int slotType = presets[configPreset].podule_type[slot];
		if (slotType == PODULE_8BIT)
			poduleLabels[slot].stringValue = [NSString stringWithFormat:@"Minipodule %d :", slot];
		else if (slotType == PODULE_NONE)
			poduleLabels[slot].stringValue = [NSString stringWithFormat:@"Podule %d (N/A)", slot];
		else if (slotType == PODULE_NET)
			poduleLabels[slot].stringValue = [NSString stringWithFormat:@"Network %d :", slot];
		else
			poduleLabels[slot].stringValue = [NSString stringWithFormat:@"Podule %d :", slot];

		[podulePopups[slot] removeAllItems];
		[podulePopups[slot] addItemWithTitle:@"None"];
		if (slotType != PODULE_NONE)
		{
			podulePopups[slot].enabled = YES;
			for (int c = 0; podule_get_name(c); c++)
			{
				uint32_t flags = podule_get_flags(c);
				if ((!(flags & (PODULE_FLAGS_8BIT | PODULE_FLAGS_NET)) && slotType == PODULE_16BIT) ||
				    ((flags & PODULE_FLAGS_8BIT) && slotType == PODULE_8BIT) ||
				    ((flags & PODULE_FLAGS_NET) && slotType == PODULE_NET))
					[podulePopups[slot] addItemWithTitle:arc_nsstring(podule_get_name(c))];
			}
			NSString *selected = @"None";
			for (int c = 0; podule_get_name(c); c++)
				if (!strcmp(configPodules[slot], podule_get_short_name(c)))
					selected = arc_nsstring(podule_get_name(c));
			[podulePopups[slot] selectItemWithTitle:selected];
		}
		else
		{
			podulePopups[slot].enabled = NO;
			[podulePopups[slot] selectItemAtIndex:0];
		}

		const podule_header_t *podule = podule_find(configPodules[slot]);
		poduleButtons[slot].enabled = (slotType != PODULE_NONE && podule && podule->config);
	}

	uniqueIdField.enabled = configIo == IO_NEW;
	uniqueIdField.stringValue = [NSString stringWithFormat:@"%08x", configUniqueId];
	fifthColumnField.enabled = presets[configPreset].has_5th_column;
	supportRomCheck.enabled = configRom >= ROM_RISCOS_300;
	suppressUpdates = NO;
}

- (void)machineChanged:(id)sender
{
	if (suppressUpdates)
		return;
	configPreset = preset_from_display_name(machinePopup.selectedItem.title.UTF8String);
	configCpu = presets[configPreset].default_cpu;
	configMem = presets[configPreset].default_mem;
	configMemc = presets[configPreset].default_memc;
	configIo = presets[configPreset].io;
	[self syncUiFromState];
	(void)sender;
}

- (void)cpuChanged:(id)sender
{
	if (suppressUpdates)
		return;
	configCpu = index_for_name(cpu_names, CPU_MAX, cpuPopup.selectedItem.title.UTF8String);
	if (configCpu == CPU_ARM2)
	{
		if (configFpu != FPU_NONE)
			configFpu = FPU_FPPC;
	}
	else
	{
		if (configFpu != FPU_NONE)
			configFpu = FPU_FPA10;
		if (configMemc == MEMC_MEMC1)
			configMemc = MEMC_MEMC1A_8;
	}
	[self syncUiFromState];
	(void)sender;
}

- (void)memoryChanged:(id)sender { if (!suppressUpdates) configMem = index_for_name(mem_names, 7, memoryPopup.selectedItem.title.UTF8String); (void)sender; }
- (void)memcChanged:(id)sender { if (!suppressUpdates) configMemc = index_for_name(memc_names, 6, memcPopup.selectedItem.title.UTF8String); (void)sender; }
- (void)fpuChanged:(id)sender { if (!suppressUpdates) configFpu = (int)fpuPopup.indexOfSelectedItem; (void)sender; }
- (void)osChanged:(id)sender { if (!suppressUpdates) { configRom = index_for_name(rom_names, ROM_MAX, osPopup.selectedItem.title.UTF8String); [self syncUiFromState]; } (void)sender; }
- (void)monitorChanged:(id)sender { if (!suppressUpdates) configMonitor = index_for_name(monitor_names, 5, monitorPopup.selectedItem.title.UTF8String); (void)sender; }

- (void)uniqueIdChanged:(id)sender
{
	NSString *value = uniqueIdField.stringValue;
	NSMutableString *filtered = [NSMutableString string];
	configUniqueId = 0;
	for (NSUInteger c = 0; c < value.length; c++)
	{
		unichar ch = [value characterAtIndex:c];
		if ((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F'))
		{
			[filtered appendFormat:@"%C", ch];
			configUniqueId <<= 4;
			configUniqueId |= (ch >= '0' && ch <= '9') ? (uint32_t)(ch - '0') :
					  (ch >= 'A' && ch <= 'F') ? (uint32_t)((ch - 'A') + 10) :
								     (uint32_t)((ch - 'a') + 10);
		}
	}
	uniqueIdField.stringValue = filtered;
	(void)sender;
}

- (void)poduleChanged:(id)sender
{
	NSPopUpButton *popup = (NSPopUpButton *)sender;
	int slot = (int)popup.tag;
	NSString *selected = popup.selectedItem.title;
	if ([selected isEqualToString:@"None"])
		configPodules[slot][0] = 0;
	else
	{
		for (int i = 0; podule_get_name(i); i++)
		{
			if (!strcmp(selected.UTF8String, podule_get_name(i)))
			{
				strncpy(configPodules[slot], podule_get_short_name(i), sizeof(configPodules[slot]) - 1);
				configPodules[slot][sizeof(configPodules[slot]) - 1] = 0;
				if (podule_get_flags(i) & PODULE_FLAGS_UNIQUE)
				{
					for (int c = 0; c < 4; c++)
						if (c != slot && !strcmp(configPodules[c], configPodules[slot]))
							configPodules[c][0] = 0;
				}
				break;
			}
		}
	}
	[self syncUiFromState];
}

- (void)configurePodule:(id)sender
{
	int slot = (int)((NSButton *)sender).tag;
	const podule_header_t *podule = podule_find(configPodules[slot]);
	if (podule && podule->config)
		ShowPoduleConfig(NULL, podule, podule->config, running, slot);
}

- (void)configureJoystickNumber:(int)joyNr
{
	NSString *selected = joyPopup.selectedItem.title ?: @"None";
	int joyType = 0;
	for (int c = 0; joystick_get_name(c); c++)
		if (!strcmp(selected.UTF8String, joystick_get_name(c)))
			joyType = c;
	ShowConfJoy(NULL, joyNr, joyType);
}

- (void)configureJoy1:(id)sender { [self configureJoystickNumber:0]; (void)sender; }
- (void)configureJoy2:(id)sender { [self configureJoystickNumber:1]; (void)sender; }

- (void)updateHdUiForDrive:(int)drive path:(const char *)path sectors:(int)sectors heads:(int)heads cylinders:(int)cylinders
{
	int size = (cylinders * heads * sectors * ((configIo != IO_NEW) ? 256 : 512)) / (1024 * 1024);
	hdPathFields[drive].stringValue = arc_nsstring(path);
	hdSectorFields[drive].stringValue = [NSString stringWithFormat:@"%d", sectors];
	hdHeadFields[drive].stringValue = [NSString stringWithFormat:@"%d", heads];
	hdCylinderFields[drive].stringValue = [NSString stringWithFormat:@"%d", cylinders];
	hdSizeFields[drive].stringValue = [NSString stringWithFormat:@"%d", size];
}

- (void)selectHd:(int)drive
{
	NSString *path = arc_choose_open_file(@"Select a disc image", @[ @"hdf" ], hdPathFields[drive].stringValue);
	if (!path)
		return;
	char newFn[256];
	int sectors = 0;
	int heads = 0;
	int cylinders = 0;
	arc_copy_string(newFn, sizeof(newFn), path);
	if (ShowConfHD(NULL, &sectors, &heads, &cylinders, newFn, configIo != IO_NEW))
		[self updateHdUiForDrive:drive path:newFn sectors:sectors heads:heads cylinders:cylinders];
}

- (void)newHd:(int)drive
{
	char newFn[256];
	int sectors = 0;
	int heads = 0;
	int cylinders = 0;
	if (ShowNewHD(NULL, &sectors, &heads, &cylinders, newFn, sizeof(newFn), configIo != IO_NEW))
		[self updateHdUiForDrive:drive path:newFn sectors:sectors heads:heads cylinders:cylinders];
}

- (void)ejectHd:(int)drive
{
	hdPathFields[drive].stringValue = @"";
}

- (void)selectHd4:(id)sender { [self selectHd:0]; (void)sender; }
- (void)selectHd5:(id)sender { [self selectHd:1]; (void)sender; }
- (void)newHd4:(id)sender { [self newHd:0]; (void)sender; }
- (void)newHd5:(id)sender { [self newHd:1]; (void)sender; }
- (void)ejectHd4:(id)sender { [self ejectHd:0]; (void)sender; }
- (void)ejectHd5:(id)sender { [self ejectHd:1]; (void)sender; }

- (void)selectFifthColumn:(id)sender
{
	NSString *path = arc_choose_open_file(@"Select a 5th Column ROM image", @[ @"bin", @"rom" ], fifthColumnField.stringValue);
	if (path)
		fifthColumnField.stringValue = path;
	(void)sender;
}

- (void)applyStateToGlobals
{
	switch (configMemc)
	{
		case MEMC_MEMC1: memc_is_memc1 = 1; arm_mem_speed = 8; break;
		case MEMC_MEMC1A_8: memc_is_memc1 = 0; arm_mem_speed = 8; break;
		case MEMC_MEMC1A_12: memc_is_memc1 = 0; arm_mem_speed = 12; break;
		default: memc_is_memc1 = 0; arm_mem_speed = 16; break;
	}
	memc_type = configMemc;

	switch (configCpu)
	{
		case CPU_ARM2: arm_has_swp = arm_has_cp15 = 0; arm_cpu_speed = arm_mem_speed; break;
		case CPU_ARM250: arm_has_swp = 1; arm_has_cp15 = 0; arm_cpu_speed = arm_mem_speed; break;
		case CPU_ARM3_20: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 20; break;
		case CPU_ARM3_24: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 24; break;
		case CPU_ARM3_25: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 25; break;
		case CPU_ARM3_26: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 26; break;
		case CPU_ARM3_30: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 30; break;
		case CPU_ARM3_33: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 33; break;
		case CPU_ARM3_35: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 35; break;
		case CPU_ARM3_36: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 36; break;
		default: arm_has_swp = arm_has_cp15 = 1; arm_cpu_speed = 40; break;
	}
	arm_cpu_type = configCpu;

	fpaena = (configFpu == FPU_NONE) ? 0 : 1;
	fpu_type = (configCpu >= CPU_ARM3_20) ? 0 : 1;
	fdctype = (romset == ROM_ARTHUR_120_A500 || romset == ROM_RISCOS_200_A500 || romset == ROM_RISCOS_310_A500) ? FDC_WD1793_A500 : (configIo >= IO_NEW ? 1 : 0);
	st506_present = (fdctype == FDC_WD1770 || fdctype == FDC_WD1793_A500) ? 1 : 0;

	switch (configMem)
	{
		case MEM_512K: memsize = 512; break;
		case MEM_1M: memsize = 1024; break;
		case MEM_2M: memsize = 2048; break;
		case MEM_4M: memsize = 4096; break;
		case MEM_8M: memsize = 8192; break;
		case MEM_12M: memsize = 12288; break;
		default: memsize = 16384; break;
	}

	romset = configRom;
	monitor_type = configMonitor;
	arc_copy_string(hd_fn[0], sizeof(hd_fn[0]), hdPathFields[0].stringValue);
	arc_copy_string(hd_fn[1], sizeof(hd_fn[1]), hdPathFields[1].stringValue);
	hd_cyl[0] = (int)hdCylinderFields[0].integerValue;
	hd_hpc[0] = (int)hdHeadFields[0].integerValue;
	hd_spt[0] = (int)hdSectorFields[0].integerValue;
	hd_cyl[1] = (int)hdCylinderFields[1].integerValue;
	hd_hpc[1] = (int)hdHeadFields[1].integerValue;
	hd_spt[1] = (int)hdSectorFields[1].integerValue;
	memcpy(podule_names, configPodules, sizeof(configPodules));
	unique_id = configUniqueId;
	strcpy(joystick_if, "none");
	for (int c = 0; joystick_get_name(c); c++)
		if (!strcmp(joyPopup.selectedItem.title.UTF8String, joystick_get_name(c)))
			strcpy(joystick_if, joystick_get_config_name(c));
	strncpy(machine, presets[configPreset].config_name, sizeof(machine) - 1);
	machine[sizeof(machine) - 1] = 0;
	arc_copy_string(_5th_column_fn, sizeof(_5th_column_fn), fifthColumnField.stringValue);
	support_rom_enabled = (supportRomCheck.state == NSControlStateValueOn);
	saveconfig();
	if (running)
		arc_reset();
}

- (void)confirm:(id)sender
{
	if (running && !arc_confirm(@"Arculator", @"This will reset Arculator!\nOkay to continue?"))
		return;
	[self applyStateToGlobals];
	arc_close_dialog_window(window, &modalResult, NSModalResponseOK);
	(void)sender;
}

- (void)cancel:(id)sender
{
	arc_close_dialog_window(window, &modalResult, NSModalResponseCancel);
	(void)sender;
}

- (void)windowWillClose:(NSNotification *)notification
{
	(void)notification;
	if (modalResult == ARC_MODAL_RESPONSE_CONTINUE)
		modalResult = NSModalResponseCancel;
}

- (int)runDialog
{
	[window center];
	NSInteger result = arc_run_dialog_window(window, &modalResult);
	return result == NSModalResponseOK ? 0 : -1;
}

@end

int ShowConfigSelection()
{
	ARCConfigSelectionDialog *dialog = [[ARCConfigSelectionDialog alloc] init];
	return [dialog runDialog];
}

int ShowPresetList()
{
	while (1)
	{
		NSAlert *alert = [[NSAlert alloc] init];
		NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 26.0)];
		for (int c = 0; presets[c].name[0]; c++)
			[popup addItemWithTitle:arc_nsstring(presets[c].name)];
		alert.messageText = @"Arculator";
		alert.informativeText = @"Please select a machine type";
		alert.accessoryView = popup;
		[alert addButtonWithTitle:@"OK"];
		[alert addButtonWithTitle:@"Cancel"];
		if ([alert runModal] != NSAlertFirstButtonReturn)
			return -1;
		int preset = (int)popup.indexOfSelectedItem;
		if (preset_allowed_by_rom(preset))
			return preset;
		arc_show_message(@"Arculator", @"You do not have any of the ROM versions required for this machine");
	}
}

int ShowConfig(bool running)
{
	ARCMachineConfigDialog *dialog = [[ARCMachineConfigDialog alloc] initWithRunning:running preset:0 usePreset:NO];
	return [dialog runDialog];
}

void ShowConfigWithPreset(int preset)
{
	ARCMachineConfigDialog *dialog = [[ARCMachineConfigDialog alloc] initWithRunning:NO preset:preset usePreset:YES];
	[dialog runDialog];
}
