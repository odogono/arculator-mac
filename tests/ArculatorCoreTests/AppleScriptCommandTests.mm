#import <XCTest/XCTest.h>
#import <Carbon/Carbon.h>

#import "macos/EmulatorBridge.h"
#import "macos/ConfigBridge.h"
#import "macos/InputInjectionBridge.h"
#import "macos/ScriptingCommandSupport.h"

// Compile the AppleScript command implementations into this test bundle so the
// tests can exercise the real command objects while stubbing their bridge layer.
#import "../../src/macos/ScriptingCommandSupport.mm"
#import "../../src/macos/LifecycleScriptingCommands.mm"
#import "../../src/macos/ConfigScriptingCommands.mm"
#import "../../src/macos/InputScriptingCommands.mm"
#import "../../src/macos/InternalDriveScriptingCommands.mm"
#import "../../src/macos/AutomationScriptingCommands.mm"

static ARCSessionState gSessionState = ARCSessionStateIdle;
static BOOL gStartEmulationCalled = NO;
static BOOL gStopEmulationCalled = NO;
static BOOL gPauseEmulationCalled = NO;
static BOOL gResumeEmulationCalled = NO;
static BOOL gResetEmulationCalled = NO;
static BOOL gStartEmulationForConfigResult = NO;
static NSString *gLastStartedConfig = nil;
static NSString *gLastStartError = nil;
static int gLastChangedDiscDrive = -1;
static NSString *gLastChangedDiscPath = nil;
static int gLastEjectedDiscDrive = -1;

static NSMutableSet<NSString *> *gExistingConfigs = nil;
static BOOL gLoadConfigResult = NO;
static BOOL gCreateConfigResult = NO;
static NSString *gLastCreatedConfig = nil;
static int gLastCreatedPreset = -1;
static BOOL gCopyConfigResult = NO;
static NSString *gLastCopiedSource = nil;
static NSString *gLastCopiedDestination = nil;

static BOOL gInjectKeyDownResult = NO;
static NSString *gLastKeyDownName = nil;
static NSString *gLastTypedText = nil;
static NSScriptCommand *gLastTypeTextCommand = nil;
static int gLastMouseMoveDx = 0;
static int gLastMouseMoveDy = 0;
static MTKView *gVideoView = nil;

static NSDictionary *gInternalDriveInfo = nil;
static NSString *gSetInternalDriveError = nil;
static int gLastSetDriveIndex = -1;
static NSString *gLastSetDrivePath = nil;
static int gLastSetDriveCyl = 0;
static int gLastSetDriveHpc = 0;
static int gLastSetDriveSpt = 0;
static NSString *gEjectInternalDriveError = nil;
static int gLastEjectDriveIndex = -1;
static NSString *gCreateBlankHDFError = nil;
static NSString *gLastCreatedHDFPath = nil;
static int gLastCreatedHDFCyl = 0;
static int gLastCreatedHDFHpc = 0;
static int gLastCreatedHDFSpt = 0;
static BOOL gLastCreatedHDFIsST506 = NO;
static NSString *gCreateReadyHDFError = nil;
static NSString *gLastReadyHDFPath = nil;
static BOOL gHasTemplate = NO;

static int gLastMouseAbsX = 0;
static int gLastMouseAbsY = 0;
static BOOL gClearAllInjectedInputCalled = NO;
static NSString *gCaptureScreenshotError = nil;
static NSString *gLastScreenshotPath = nil;
static NSString *gCopyScreenshotError = nil;
static BOOL gCopyScreenshotCalled = NO;

static void ResetAppleScriptTestState(void)
{
    gSessionState = ARCSessionStateIdle;
    gStartEmulationCalled = NO;
    gStopEmulationCalled = NO;
    gPauseEmulationCalled = NO;
    gResumeEmulationCalled = NO;
    gResetEmulationCalled = NO;
    gStartEmulationForConfigResult = NO;
    gLastStartedConfig = nil;
    gLastStartError = nil;
    gLastChangedDiscDrive = -1;
    gLastChangedDiscPath = nil;
    gLastEjectedDiscDrive = -1;

    gExistingConfigs = [NSMutableSet set];
    gLoadConfigResult = NO;
    gCreateConfigResult = NO;
    gLastCreatedConfig = nil;
    gLastCreatedPreset = -1;
    gCopyConfigResult = NO;
    gLastCopiedSource = nil;
    gLastCopiedDestination = nil;

    gInjectKeyDownResult = NO;
    gLastKeyDownName = nil;
    gLastTypedText = nil;
    gLastTypeTextCommand = nil;
    gLastMouseMoveDx = 0;
    gLastMouseMoveDy = 0;
    gVideoView = nil;

    gInternalDriveInfo = nil;
    gSetInternalDriveError = nil;
    gLastSetDriveIndex = -1;
    gLastSetDrivePath = nil;
    gLastSetDriveCyl = 0;
    gLastSetDriveHpc = 0;
    gLastSetDriveSpt = 0;
    gEjectInternalDriveError = nil;
    gLastEjectDriveIndex = -1;
    gCreateBlankHDFError = nil;
    gLastCreatedHDFPath = nil;
    gLastCreatedHDFCyl = 0;
    gLastCreatedHDFHpc = 0;
    gLastCreatedHDFSpt = 0;
    gLastCreatedHDFIsST506 = NO;
    gCreateReadyHDFError = nil;
    gLastReadyHDFPath = nil;
    gHasTemplate = NO;

    gLastMouseAbsX = 0;
    gLastMouseAbsY = 0;
    gClearAllInjectedInputCalled = NO;
    gCaptureScreenshotError = nil;
    gLastScreenshotPath = nil;
    gCopyScreenshotError = nil;
    gCopyScreenshotCalled = NO;
}

static NSDictionary<NSString *, id> *UserRecordFieldsFromDescriptor(NSAppleEventDescriptor *descriptor)
{
    NSAppleEventDescriptor *fieldList = [descriptor descriptorForKeyword:keyASUserRecordFields];
    NSMutableDictionary<NSString *, id> *fields = [NSMutableDictionary dictionary];

    for (NSInteger i = 1; i + 1 <= fieldList.numberOfItems; i += 2)
    {
        NSString *key = [fieldList descriptorAtIndex:i].stringValue;
        NSAppleEventDescriptor *valueDescriptor = [fieldList descriptorAtIndex:i + 1];
        if (!key || !valueDescriptor)
            continue;

        if (valueDescriptor.descriptorType == typeSInt32)
            fields[key] = @(valueDescriptor.int32Value);
        else
            fields[key] = valueDescriptor.stringValue ?: @"";
    }

    return fields;
}

@implementation EmulatorBridge

+ (void)startEmulation { gStartEmulationCalled = YES; }
+ (void)stopEmulation { gStopEmulationCalled = YES; }
+ (void)pauseEmulation { gPauseEmulationCalled = YES; }
+ (void)resumeEmulation { gResumeEmulationCalled = YES; }
+ (void)resetEmulation { gResetEmulationCalled = YES; }

+ (BOOL)startEmulationForConfig:(NSString *)configName
{
    gLastStartedConfig = [configName copy];
    return gStartEmulationForConfigResult;
}

+ (NSString *)lastStartError
{
    return gLastStartError;
}

+ (void)changeDisc:(int)drive path:(NSString *)path
{
    gLastChangedDiscDrive = drive;
    gLastChangedDiscPath = [path copy];
}

+ (void)ejectDisc:(int)drive
{
    gLastEjectedDiscDrive = drive;
}

+ (BOOL)isSessionActive
{
    return gSessionState != ARCSessionStateIdle;
}

+ (BOOL)isPaused
{
    return gSessionState == ARCSessionStatePaused;
}

+ (ARCSessionState)sessionState
{
    return gSessionState;
}

+ (NSString *)activeConfigName
{
    return @"";
}

+ (void)setVideoView:(MTKView *)view
{
    gVideoView = view;
}

+ (MTKView *)videoView
{
    return gVideoView;
}

+ (NSString *)captureScreenshotToPath:(NSString *)path
{
    gLastScreenshotPath = [path copy];
    return gCaptureScreenshotError;
}

+ (NSString *)copyScreenshotToPasteboard
{
    gCopyScreenshotCalled = YES;
    return gCopyScreenshotError;
}

+ (BOOL)ensureVideoViewInstalled
{
    return YES;
}

+ (BOOL)saveSnapshotToPath:(NSString *)path error:(NSString **)error
{
    (void)path;
    if (error)
        *error = nil;
    return NO;
}

+ (BOOL)startSnapshotSessionFromPath:(NSString *)path error:(NSString **)error
{
    (void)path;
    if (error)
        *error = nil;
    return NO;
}

+ (BOOL)canSaveSnapshotWithError:(NSString **)error
{
    if (error)
        *error = nil;
    return NO;
}

+ (BOOL)canSaveSnapshot
{
    return NO;
}

@end

@implementation ConfigBridge

+ (NSArray<NSString *> *)listConfigNames
{
    return gExistingConfigs.allObjects;
}

+ (NSString *)configPathForName:(NSString *)name
{
    return [@"/tmp" stringByAppendingPathComponent:name];
}

+ (BOOL)configExists:(NSString *)name
{
    return [gExistingConfigs containsObject:name];
}

+ (BOOL)loadConfigNamed:(NSString *)name
{
    gLastStartedConfig = [name copy];
    return gLoadConfigResult;
}

+ (BOOL)createConfig:(NSString *)name withPresetIndex:(int)presetIndex
{
    gLastCreatedConfig = [name copy];
    gLastCreatedPreset = presetIndex;
    return gCreateConfigResult;
}

+ (BOOL)copyConfig:(NSString *)sourceName to:(NSString *)destName
{
    gLastCopiedSource = [sourceName copy];
    gLastCopiedDestination = [destName copy];
    return gCopyConfigResult;
}

+ (ARCInternalDiskImageState)stateForInternalDiskImageAtPath:(NSString *)path
                                                   cylinders:(int)cylinders
                                                       heads:(int)heads
                                                     sectors:(int)sectors
                                                    isST506:(BOOL)isST506
{
    (void)path;
    (void)cylinders;
    (void)heads;
    (void)sectors;
    (void)isST506;
    return ARCInternalDiskImageStateUnknown;
}

+ (void)showStartupWarningsForLoadedConfigIfNeeded {}

+ (BOOL)renameConfig:(NSString *)oldName to:(NSString *)newName
{
    (void)oldName;
    (void)newName;
    return YES;
}

+ (BOOL)deleteConfig:(NSString *)name
{
    return [gExistingConfigs containsObject:name];
}

+ (ARCSettingMutability)mutabilityForSetting:(NSString *)settingKey
{
    (void)settingKey;
    return ARCSettingMutabilityStop;
}

+ (NSDictionary *)internalDriveInfoForIndex:(int)index
{
    (void)index;
    return gInternalDriveInfo ?: @{};
}

+ (NSString *)setInternalDriveIndex:(int)index
                               path:(NSString *)path
                          cylinders:(int)cylinders
                              heads:(int)heads
                            sectors:(int)sectors
{
    gLastSetDriveIndex = index;
    gLastSetDrivePath = [path copy];
    gLastSetDriveCyl = cylinders;
    gLastSetDriveHpc = heads;
    gLastSetDriveSpt = sectors;
    return gSetInternalDriveError;
}

+ (NSString *)ejectInternalDriveIndex:(int)index
{
    gLastEjectDriveIndex = index;
    return gEjectInternalDriveError;
}

+ (NSString *)createBlankHDFAtPath:(NSString *)path
                         cylinders:(int)cylinders
                             heads:(int)heads
                           sectors:(int)sectors
                           isST506:(BOOL)isST506
{
    gLastCreatedHDFPath = [path copy];
    gLastCreatedHDFCyl = cylinders;
    gLastCreatedHDFHpc = heads;
    gLastCreatedHDFSpt = sectors;
    gLastCreatedHDFIsST506 = isST506;
    return gCreateBlankHDFError;
}

+ (NSString *)createReadyHDFAtPath:(NSString *)path
                         cylinders:(int)cylinders
                             heads:(int)heads
                           sectors:(int)sectors
                           isST506:(BOOL)isST506
{
    gLastReadyHDFPath = [path copy];
    gLastCreatedHDFCyl = cylinders;
    gLastCreatedHDFHpc = heads;
    gLastCreatedHDFSpt = sectors;
    gLastCreatedHDFIsST506 = isST506;
    return gCreateReadyHDFError;
}

+ (BOOL)hasTemplateForCylinders:(int)cylinders
                          heads:(int)heads
                        sectors:(int)sectors
                        isST506:(BOOL)isST506
{
    (void)cylinders;
    (void)heads;
    (void)sectors;
    (void)isST506;
    return gHasTemplate;
}

+ (NSString *)templatePathForCylinders:(int)cylinders
                                 heads:(int)heads
                               sectors:(int)sectors
                               isST506:(BOOL)isST506
{
    (void)cylinders;
    (void)heads;
    (void)sectors;
    (void)isST506;
    return gHasTemplate ? @"/tmp/template.hdf" : nil;
}

@end

@implementation InputInjectionBridge

+ (BOOL)injectKeyDown:(NSString *)keyName
{
    gLastKeyDownName = [keyName copy];
    return gInjectKeyDownResult;
}

+ (BOOL)injectKeyUp:(NSString *)keyName
{
    return [self injectKeyDown:keyName];
}

+ (void)typeText:(NSString *)text forCommand:(NSScriptCommand *)command
{
    gLastTypedText = [text copy];
    gLastTypeTextCommand = command;
}

+ (void)injectMouseMoveDx:(int)dx dy:(int)dy
{
    gLastMouseMoveDx = dx;
    gLastMouseMoveDy = dy;
}

+ (void)injectMouseAbsX:(int)x y:(int)y
{
    gLastMouseAbsX = x;
    gLastMouseAbsY = y;
}

+ (void)injectMouseButtonDown:(int)buttonMask
{
    (void)buttonMask;
}

+ (void)injectMouseButtonUp:(int)buttonMask
{
    (void)buttonMask;
}

+ (void)clearAllInjectedKeys {}
+ (void)clearInjectedMouse {}

+ (void)clearAllInjectedInput
{
    gClearAllInjectedInputCalled = YES;
}

+ (int)keycodeForName:(NSString *)keyName
{
    (void)keyName;
    return -1;
}

@end

@interface AppleScriptCommandTests : XCTestCase
@end

@implementation AppleScriptCommandTests

- (void)setUp
{
    [super setUp];
    ResetAppleScriptTestState();
}

- (NSScriptCommand *)commandNamed:(NSString *)className
                   directParameter:(id)directParameter
                         arguments:(NSDictionary<NSString *, id> *)arguments
{
    Class commandClass = NSClassFromString(className);
    XCTAssertNotNil(commandClass, @"Expected %@ to be available", className);

    NSScriptCommand *command = [[commandClass alloc] init];
    command.directParameter = directParameter;
    command.arguments = arguments;
    return command;
}

- (void)testConfigNameValidationAcceptsSupportedCharacters
{
    XCTAssertNil(ScriptingValidateConfigName(@"A3010 Demo_Config+(1).v2"));
}

- (void)testConfigNameValidationRejectsBlankTraversalAndInvalidCharacters
{
    XCTAssertEqualObjects(ScriptingValidateConfigName(@"   "), @"Config name cannot be empty");
    XCTAssertEqualObjects(ScriptingValidateConfigName(@"../evil"), @"Config name cannot contain '..'");

    NSString *message = ScriptingValidateConfigName(@"bad/name");
    XCTAssertTrue([message containsString:@"invalid character '/'"]);
}

- (void)testStartEmulationStartsOnlyFromIdle
{
    NSScriptCommand *command = [self commandNamed:@"StartEmulationCommand"
                                   directParameter:nil
                                         arguments:nil];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertTrue(gStartEmulationCalled);

    ResetAppleScriptTestState();
    gSessionState = ARCSessionStateRunning;

    command = [self commandNamed:@"StartEmulationCommand" directParameter:nil arguments:nil];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 1100);
    XCTAssertEqualObjects(command.scriptErrorString,
        @"Cannot start: emulation is already running or paused");
    XCTAssertFalse(gStartEmulationCalled);
}

- (void)testStartConfigChecksExistenceAndStartsRequestedConfig
{
    NSScriptCommand *command = [self commandNamed:@"StartConfigCommand"
                                   directParameter:@"Missing Config"
                                         arguments:nil];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 1200);
    XCTAssertEqualObjects(command.scriptErrorString, @"Config not found: 'Missing Config'");

    ResetAppleScriptTestState();
    [gExistingConfigs addObject:@"A3010"];
    gStartEmulationForConfigResult = YES;

    command = [self commandNamed:@"StartConfigCommand"
                  directParameter:@"A3010"
                        arguments:nil];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqualObjects(gLastStartedConfig, @"A3010");
}

- (void)testStartConfigSurfacesBridgeStartError
{
    [gExistingConfigs addObject:@"Template IDE"];
    gStartEmulationForConfigResult = NO;
    gLastStartError = @"Cannot start emulation because no emulator window/view is available";

    NSScriptCommand *command = [self commandNamed:@"StartConfigCommand"
                                   directParameter:@"Template IDE"
                                         arguments:nil];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 1200);
    XCTAssertEqualObjects(command.scriptErrorString, gLastStartError);
}

- (void)testCreateConfigPassesPresetArgumentToBridge
{
    gCreateConfigResult = YES;

    NSScriptCommand *command = [self commandNamed:@"CreateConfigCommand"
                                   directParameter:@"New Machine"
                                         arguments:@{@"withPreset": @3}];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqualObjects(gLastCreatedConfig, @"New Machine");
    XCTAssertEqual(gLastCreatedPreset, 3);
}

- (void)testCopyConfigPrefixesDestinationValidationErrors
{
    NSScriptCommand *command = [self commandNamed:@"CopyConfigCommand"
                                   directParameter:@"Source"
                                         arguments:@{@"to": @"../evil"}];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 1000);
    XCTAssertEqualObjects(command.scriptErrorString,
        @"Destination: Config name cannot contain '..'");
}

- (void)testChangeDiscRejectsBadDriveAndForwardsValidRequests
{
    NSScriptCommand *command = [self commandNamed:@"ChangeDiscCommand"
                                   directParameter:@"/tmp/test.adf"
                                         arguments:@{@"drive": @9}];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 1000);
    XCTAssertEqualObjects(command.scriptErrorString,
        @"Invalid drive number 9 (must be 0-3)");

    ResetAppleScriptTestState();
    gSessionState = ARCSessionStateRunning;

    command = [self commandNamed:@"ChangeDiscCommand"
                  directParameter:@"/tmp/test.adf"
                        arguments:@{@"drive": @2}];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqual(gLastChangedDiscDrive, 2);
    XCTAssertEqualObjects(gLastChangedDiscPath, @"/tmp/test.adf");
}

- (void)testInjectKeyDownRequiresRunningSessionAndKnownKey
{
    NSScriptCommand *command = [self commandNamed:@"InjectKeyDownCommand"
                                   directParameter:@"space"
                                         arguments:nil];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 1100);
    XCTAssertEqualObjects(command.scriptErrorString,
        @"Cannot inject key: emulation is not running");

    ResetAppleScriptTestState();
    gSessionState = ARCSessionStateRunning;
    gInjectKeyDownResult = NO;

    command = [self commandNamed:@"InjectKeyDownCommand"
                  directParameter:@"mystery"
                        arguments:nil];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 1000);
    XCTAssertEqualObjects(command.scriptErrorString, @"Unknown key name: 'mystery'");

    ResetAppleScriptTestState();
    gSessionState = ARCSessionStateRunning;
    gInjectKeyDownResult = YES;

    command = [self commandNamed:@"InjectKeyDownCommand"
                  directParameter:@"space"
                        arguments:nil];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqualObjects(gLastKeyDownName, @"space");
}

- (void)testTypeTextSkipsEmptyStringsAndDelegatesNonEmptyText
{
    NSScriptCommand *command = [self commandNamed:@"TypeTextCommand"
                                   directParameter:@""
                                         arguments:nil];
    [command performDefaultImplementation];

    XCTAssertNil(gLastTypedText);

    command = [self commandNamed:@"TypeTextCommand"
                  directParameter:@"*fx"
                        arguments:nil];
    [command performDefaultImplementation];

    XCTAssertEqualObjects(gLastTypedText, @"*fx");
    XCTAssertEqual(gLastTypeTextCommand, command);
}

- (void)testInjectMouseMoveRequiresDxAndDy
{
    gSessionState = ARCSessionStateRunning;

    NSScriptCommand *command = [self commandNamed:@"InjectMouseMoveCommand"
                                   directParameter:nil
                                         arguments:@{@"dx": @4}];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 1000);
    XCTAssertEqualObjects(command.scriptErrorString, @"Missing dx or dy parameter");

    command = [self commandNamed:@"InjectMouseMoveCommand"
                  directParameter:nil
                        arguments:@{@"dx": @4, @"dy": @-2}];
    [command performDefaultImplementation];

    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqual(gLastMouseMoveDx, 4);
    XCTAssertEqual(gLastMouseMoveDy, -2);
}

#pragma mark - Internal drive command tests

- (void)testInternalDriveInfoRejectsBadDriveNumber
{
    NSScriptCommand *command = [self commandNamed:@"InternalDriveInfoCommand"
                                   directParameter:@3
                                         arguments:nil];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 1000);

    gInternalDriveInfo = @{@"path": @"/tmp/test.hdf", @"imageState": @"blank raw"};
    command = [self commandNamed:@"InternalDriveInfoCommand"
                  directParameter:@4
                        arguments:nil];
    id result = [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertTrue([result isKindOfClass:[NSAppleEventDescriptor class]]);
    NSDictionary *fields = UserRecordFieldsFromDescriptor(result);
    XCTAssertEqualObjects(fields[@"path"], @"/tmp/test.hdf");
    XCTAssertEqualObjects(fields[@"imageState"], @"blank raw");
}

- (void)testSetInternalDriveRequiresIdleAndValidParams
{
    gSessionState = ARCSessionStateRunning;
    NSScriptCommand *command = [self commandNamed:@"SetInternalDriveCommand"
                                   directParameter:@4
                                         arguments:@{@"path": @"/tmp/test.hdf",
                                                     @"cylinders": @100,
                                                     @"heads": @16,
                                                     @"sectors": @63}];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 1100);

    ResetAppleScriptTestState();
    command = [self commandNamed:@"SetInternalDriveCommand"
                  directParameter:@4
                        arguments:@{@"path": @"/tmp/test.hdf",
                                    @"cylinders": @100,
                                    @"heads": @16,
                                    @"sectors": @63}];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqual(gLastSetDriveIndex, 0);
    XCTAssertEqualObjects(gLastSetDrivePath, @"/tmp/test.hdf");
    XCTAssertEqual(gLastSetDriveCyl, 100);
}

- (void)testEjectInternalDriveRequiresIdleState
{
    gSessionState = ARCSessionStateRunning;
    NSScriptCommand *command = [self commandNamed:@"EjectInternalDriveCommand"
                                   directParameter:@5
                                         arguments:nil];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 1100);

    ResetAppleScriptTestState();
    command = [self commandNamed:@"EjectInternalDriveCommand"
                  directParameter:@5
                        arguments:nil];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqual(gLastEjectDriveIndex, 1);
}

- (void)testCreateHardDiscImageValidatesAndForwards
{
    NSScriptCommand *command = [self commandNamed:@"CreateHardDiscImageCommand"
                                   directParameter:@""
                                         arguments:@{@"cylinders": @100,
                                                     @"heads": @16,
                                                     @"sectors": @63}];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 1000);

    command = [self commandNamed:@"CreateHardDiscImageCommand"
                  directParameter:@"/tmp/new.hdf"
                        arguments:@{@"cylinders": @100,
                                    @"heads": @16,
                                    @"sectors": @63,
                                    @"controller": @"st506"}];
    id result = [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqualObjects(gLastCreatedHDFPath, @"/tmp/new.hdf");
    XCTAssertTrue(gLastCreatedHDFIsST506);
    XCTAssertTrue([result isKindOfClass:[NSAppleEventDescriptor class]]);
    NSDictionary *fields = UserRecordFieldsFromDescriptor(result);
    XCTAssertEqualObjects(fields[@"controller"], @"st506");

    ResetAppleScriptTestState();
    command = [self commandNamed:@"CreateHardDiscImageCommand"
                  directParameter:@"/tmp/new.hdf"
                        arguments:@{@"cylinders": @100,
                                    @"heads": @16,
                                    @"sectors": @63}];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertFalse(gLastCreatedHDFIsST506);
}

- (void)testCreateHardDiscImageReadyMode
{
    NSScriptCommand *command = [self commandNamed:@"CreateHardDiscImageCommand"
                                   directParameter:@"/tmp/ready.hdf"
                                         arguments:@{@"cylinders": @101,
                                                     @"heads": @16,
                                                     @"sectors": @63,
                                                     @"initialization": @"ready"}];
    id result = [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqualObjects(gLastReadyHDFPath, @"/tmp/ready.hdf");
    XCTAssertEqual(gLastCreatedHDFCyl, 101);
    XCTAssertNil(gLastCreatedHDFPath);
    XCTAssertTrue([result isKindOfClass:[NSAppleEventDescriptor class]]);
    NSDictionary *fields = UserRecordFieldsFromDescriptor(result);
    XCTAssertEqualObjects(fields[@"initialization"], @"ready");

    ResetAppleScriptTestState();
    command = [self commandNamed:@"CreateHardDiscImageCommand"
                  directParameter:@"/tmp/blank.hdf"
                        arguments:@{@"cylinders": @100,
                                    @"heads": @16,
                                    @"sectors": @63,
                                    @"initialization": @"blank"}];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqualObjects(gLastCreatedHDFPath, @"/tmp/blank.hdf");
    XCTAssertNil(gLastReadyHDFPath);

    ResetAppleScriptTestState();
    command = [self commandNamed:@"CreateHardDiscImageCommand"
                  directParameter:@"/tmp/bad.hdf"
                        arguments:@{@"cylinders": @100,
                                    @"heads": @16,
                                    @"sectors": @63,
                                    @"initialization": @"invalid"}];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 1000);
}

#pragma mark - Automation command tests

- (void)testMoveGuestMouseToRequiresRunningAndXY
{
    NSScriptCommand *command = [self commandNamed:@"MoveGuestMouseToCommand"
                                   directParameter:nil
                                         arguments:@{@"x": @100, @"y": @200}];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 1100);

    gSessionState = ARCSessionStateRunning;
    command = [self commandNamed:@"MoveGuestMouseToCommand"
                  directParameter:nil
                        arguments:@{@"x": @100}];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 1000);

    command = [self commandNamed:@"MoveGuestMouseToCommand"
                  directParameter:nil
                        arguments:@{@"x": @100, @"y": @200}];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqual(gLastMouseAbsX, 100);
    XCTAssertEqual(gLastMouseAbsY, 200);
}

- (void)testClearInjectedInputCallsBridge
{
    NSScriptCommand *command = [self commandNamed:@"ClearInjectedInputCommand"
                                   directParameter:nil
                                         arguments:nil];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertTrue(gClearAllInjectedInputCalled);
}

- (void)testCaptureScreenshotRequiresActiveSessionAndPath
{
    NSScriptCommand *command = [self commandNamed:@"CaptureEmulationScreenshotCommand"
                                   directParameter:@"/tmp/screenshot.png"
                                         arguments:nil];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 1100);

    gSessionState = ARCSessionStateRunning;
    command = [self commandNamed:@"CaptureEmulationScreenshotCommand"
                  directParameter:@""
                        arguments:nil];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 1000);

    command = [self commandNamed:@"CaptureEmulationScreenshotCommand"
                  directParameter:@"/tmp/screenshot.png"
                        arguments:nil];
    id result = [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqualObjects(gLastScreenshotPath, @"/tmp/screenshot.png");
    XCTAssertEqualObjects(result, @"/tmp/screenshot.png");

    gSessionState = ARCSessionStatePaused;
    command = [self commandNamed:@"CaptureEmulationScreenshotCommand"
                  directParameter:@"/tmp/paused-screenshot.png"
                        arguments:nil];
    result = [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertEqualObjects(gLastScreenshotPath, @"/tmp/paused-screenshot.png");
    XCTAssertEqualObjects(result, @"/tmp/paused-screenshot.png");
}

- (void)testCopyScreenshotRequiresActiveSession
{
    NSScriptCommand *command = [self commandNamed:@"CopyEmulationScreenshotCommand"
                                   directParameter:nil
                                         arguments:nil];
    [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 1100);
    XCTAssertFalse(gCopyScreenshotCalled);

    gSessionState = ARCSessionStatePaused;
    command = [self commandNamed:@"CopyEmulationScreenshotCommand"
                  directParameter:nil
                        arguments:nil];
    id result = [command performDefaultImplementation];
    XCTAssertEqual(command.scriptErrorNumber, 0);
    XCTAssertTrue(gCopyScreenshotCalled);
    XCTAssertNil(result);
}

@end
