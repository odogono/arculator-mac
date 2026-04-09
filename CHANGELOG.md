# Changelog

## (unreleased)

- macOS: Show configured floppy drive count in sidebar instead of hardware default

- macOS: Add `Copy Screenshot` menu item to capture the current emulator frame to the system clipboard
- macOS: Refactor Metal screenshot capture for shared file and clipboard export paths
- macOS: Fix clipboard screenshots appearing blank by writing bitmap data with correct alpha handling
- macOS: Fix copied screenshot geometry for doubled-scanline output
- AppleScript: Add `copy emulation screenshot` command and allow screenshot commands while emulation is paused

- core: Add snapshot chunk management with version tracking
- core: Add snapshot summary generation for save file metadata
- macOS: Add snapshot browser UI with model and view controllers
- macOS: Add EmulatorBridge snapshot state synchronization
- macOS: Add NewWindowBridge for window management
- testing: Add snapshot summary tests for metadata generation

- macOS: Add App Settings panel with configurable keyboard shortcuts for pause/reset
- macOS: Add ShortcutRecorderView for recording custom keyboard shortcuts
- macOS: Add sidebar item for App Settings in preferences

- core: Add snapshot save/load system with per-subsystem serialization
- core: Add arc_init_from_snapshot() API for loading saved machine state
- core: Add platform shell utilities for snapshot operations
- core: Add floppy disc quiescence detection for consistent snapshot state
- macOS: Add shell integration for snapshot menu items
- testing: Add snapshot format tests and UI tests for snapshot functionality

- AppleScript: Return user record descriptors from `internal drive info` and `create hard disc image` commands for better AppleScript compatibility
- AppleScript: Surface start errors from `start` and `start config` commands via `lastStartError`
- core: Add null check for `rlog` in `fatal()` and `error()` to prevent crashes when logging is unavailable
- macOS: Add compressed `.hdf.zlib` template support with zlib decompression for ready disk images
- macOS: Improve screenshot capture to use `screencapture` fallback and Metal texture capture when window-based capture fails
- macOS: Add `ensureVideoViewInstalled` check before starting emulation to provide clearer error messages
- macOS: Change default IDE disk cylinders from 100 to 101 for proper legacy header compatibility

- AppleScript: Add full AppleScript support with .sdef dictionary definition
- AppleScript: Add lifecycle commands (start/stop/pause/resume/reset/start config)
- AppleScript: Add config management commands (load/create/copy/delete config, change/eject disc)
- AppleScript: Add input injection commands (inject key down/up, type text, inject mouse move/down/up)
- core: Add input injection overlay system in input_snapshot for script-driven key/mouse injection
- core: Add input injection platform abstraction (plat_input.h wrappers)
- macOS: Add InputInjectionBridge for key name resolution and type text implementation
- macOS: Add ScriptingCommandSupport for shared argument and state validation
- macOS: Add NSApplication+Scripting.mm for AppleScript property accessors
- testing: Add AppleScript command tests for lifecycle, config, and input injection
- testing: Add CMOS and config load tests

- core: Add `platform_path_drives_dir()` for drives storage location
- macOS: Refactor hard disk dialog to use modern AppKit Auto Layout (NSGridView, NSStackView)
- macOS: Add default drive path suggestion in new hard disk dialog
- macOS: Pass configModel to sidebar for drive count awareness
- macOS: Show correct number of disc slots in running controls based on machine IO type

- core: Add test seam APIs - `platform_paths_init_test()`, `platform_paths_reset()`, `cmos_get_ram_ptr()`, `video_renderer_begin_close()`
- core: Fix potential null pointer dereference in `dumpregs()`
- core: Add null check in `cmos_save()` to handle failed file opens gracefully

- testing: Add headless XCTest bundle target (ArculatorCoreTests) for core emulator testing
- testing: Add XCUITests for config rename, duplicate, delete, and persistence across relaunch
- testing: Add XCUITests for disc slot attach/eject and mutability gating
- testing: Add accessibility identifiers throughout SwiftUI views for UI test automation
- testing: Remove legacy AppleScript-based GUI smoke tests (`run_macos_gui_smoke_test.sh`, `macos_gui_smoke_test.applescript`, `run_macos_session1_check.sh`, `macos_session1_check.applescript`)

- macOS: Replace wxWidgets-based config dialog with native SwiftUI UI (MainSplitViewController, SidebarView, ConfigEditorView, etc.)
- macOS: Add machine preset system with Swift bridge (MachinePresets.swift, MachinePresetBridge.mm)
- macOS: Add macOS keycode bias mechanism for virtual key code handling
- macOS: Improve CMOS loading to restore bundled defaults when saved state is empty
- macOS: Add video view management API (arc_set_video_view, arc_get_video_view)
- macOS: Add UI test target (ArculatorUITests)
- macOS: Add subtitle support in window title bar
- macOS: Generate Xcode project with Swift support, bridging header, and SwiftUI framework
- macOS: Remove legacy config_macos.mm in favor of SwiftUI implementation

- core: Add emulation control command queue for thread-safe command handling
- core: Add input snapshot functionality
- core: Add platform paths module for cross-platform path handling
- core: Add platform shell utilities

- macOS: Add GameController joystick support via joystick_gamecontroller.m
- macOS: Add CoreAudio sound output via sound_out_coreaudio.m

- SDL2: Major refactor of wx-sdl2.c for thread-safe main thread operations on macOS
- SDL2: Improve SDL2 input handling with better mouse capture semantics

- docs: Add PHASE0_INVENTORY.md and PORTING_PLAN.md documentation

## v2.3 (unreleased)

- Fix append_filename() to work reliably
- Use SDL_CFLAGS rather than substituting result from sdl2-config --cflags
- Resyncked with Sarah's latest and re-applied changed to build on both mac x86_64 and mac M1,2,3
- Patch to have arculator building on Apple macOS for x86_64 and Apple Silicon M1,2 and 3
- Restore fork README.md
- Change binding to release mouse on mac

- all: Update version number to v2.2

- build: Fix typo to allow wx-resources creation
- build: Add black level option to arculator.xrc

- disc: Fix disc_poll() prototype
- disc: HFEv3 improvements

- docs: Update Readme-LINUX.txt
- docs: Update readme.txt for v2.2
- docs: Fix typos in readme.txt

- macOS support: Add #ifdef **APPLE** guards for macOS build compatibility

- sound: Don't play any disc noise when disabled
- sound: Fix missing include in sound_sdl2.c
- sound: Wrap sound pointer at 512kb

- video: Add configurable black level

## v2.1 (2021-09-05)

- Update version number to v2.1, and update readme.txt and changes.txt.
- Update version number in Readme-LINUX.txt.
- Ignore ID mark when in the middle of a disc data read. Fixes protection in some TBA games (Cyber Ape, Mirror Image).
- Colourcard doesn't appear to have IRQ enable bit in control register. Fixes missing vsync IRQ in 16 bpp modes.
- Bodge to fix cursor position in Colourcard 16bpp modes.
- Add ADC emulation to AKA10 podule emulation. Currently implements joysticks, as currently no podule joystick configuration it's hardwired to joystick 0.
- Dummy 6522 IFR implementation on AKA10 podule. !65Host now starts with AKA10 present.
- Add 6522 VIA emulation to AKA10 podule.
- Add 6522 emulation to AKA12 podule.
- Add podule config callbacks for CONFIG_SELECTION.
- Add joystick configuration for AKA10.
- Added Morley A3000 User and Analogue Port emulation.
- Add Risc Developments High Density Floppy Controller emulation. As part of this, rework floppy code a bit to allow for multiple controllers in one system (with only one connected to the disc subsystem). Also fix podule FIQs.
- Add HFE v3 support.
- Disc code cleanup.
- Pass sector offset to ADF/IMG code instead of deriving sector offset from sector size.
- Unify all raw sector disc formats.
- IDE IRQ enable bit is shared between both drives.
- Add Ethernet III emulation
- Auto-generate missing morley_uap Makefile
- roms/podules/zidefs_a3k/roms.txt: mis-cased file
- Remove some unused variables
- Convert identation to tabs
- Improve input latency by one frame
- Fix off-by-ones in CMOS day/month
- Allow building with autoconf 2.69

- aeh50: Fix documentation
- aeh50: Fix pointer issue when closing ne2000 device

- aeh50/aeh54: Add error checking for network creation failure
- aeh50/aeh54: Fix memory leak if podule init fails due to missing ROM

- aeh54: Remove unnecessary winbase.h include

- aka31: Clear SBIC interrupt when a new command is submitted
- aka31: Add AKA32 as discrete variant of AKA31 SCSI podule

- al: Call al_close() on exit

- arm: Optimisations to run_dma()
- arm: Optimisations to shift and cache related code
- arm: Split opcode handling out of switch statement into separate functions
- arm: Some cleanup and refactor of data processing instructions
- arm: Rework LDR/STR instructions
- arm: More unused variable cleanup
- arm: Don't check for mode change on every instruction
- arm: More tweaks to execarm()
- arm: Fix timing on MEMC1 MUL & MLA
- arm: Fix data processing instruction decode
- arm: Fix flag setting for register specified ROR with count of 0

- Makefile: Remove obsolete compiler optimisation flags
- build: Fix autotools makefiles for AKA10 and Morley User/Analogue Port podules
- build: Auto generate PC Card makefile
- build: Auto generate AEH50 and AEH54 makefiles
- build: Add Windows support to Makefile.am
- build: Fix podules on Windows when building with autotools
- build: Install arculator.exe on Windows when using autotools

- cdrom: Recognise /dev/sr\* as possible CD-ROM devices on Linux

- cmos: Add POSIX time/date functionality for non-Windows platforms

- colourcard: Use control bit 7 as IRQ enable

- config: Improvements to string handling for newer GCC versions
- config: Add higher performance overclock options
- config: Fix podule selection on some platforms
- config: Fix "loses precision" error in podule_config_set_current()
- config: Fix handling of NULL sections on some compilers

- configure: Fix build flags
- configure: Respect user-provided CFLAGS

- debug: Add command to save memory to disc

- debugger: Add initial debugger
- debugger: Add SWI name decoding
- debugger: Break out of debugger if hard reset is in progress
- debugger: Hack to prevent UI freezing when changing/ejecting disc with debugger active
- debugger: More UI lockup hacks
- debugger: Add commands to write to memory
- debugger: Add scrollback to debugger window
- debugger: Fix signed/unsigned comparison in scrollback code
- debugger: Fix address masking on write byte command
- debugger: Fix concurrency issues in console UI
- debugger: Fix console font on non-Windows platforms
- debugger: Set console UI focus to input field when enabling input
- debugger: Add write breakpoints and watchpoints
- debugger: Stop disassembler from trying to decode shifts for MUL & MLA
- debugger: Add commands to clear write breakpoints and watchpoints

- disc: Add SCP disc image support

- docs: Add initial Readme-NETWORKING.txt
- docs: Improvements to Readme-NETWORKING.txt

- extrom: Remove FPE400 and MODE 99 module

- hostfs: Print debug through rpclog() rather than stderr

- ide: Reset onboard IDE on machine hard reset
- ide: Add range checks to read/write/verify/format commands
- ide: Fix max sectors calculation for secondary drive

- ioc: Reading IRQA raw status should return bit 7 as set

- main: Guard setting of SDL_HINT_WINDOWS_DISABLE_THREAD_NAMING

- mem: Reset refresh timestamp on CPU reset
- mem: Apply CPU permissions on IO areas
- mem: Add support for 12 MB configuration
- mem: Clean up duplicate mempoint arrays
- mem: Some more minor memory related tweaks
- mem: Remove need to mask off addresses when accessing memory

- net: Don't leak received packets

- pccard: Fix multiple definition errors on compilation with newer GCC versions

- podules: Add Acorn Ethernet II (AEH50) emulation
- podules: Add PCAP support to network podules
- podules: Add support for multiple podules implemented in a single library
- podules: Fix up MING/W makefiles
- podules: Ignore hidden directories while scanning
- podules: Add PODULE_FLAGS_NET and bump version number to 1.1
- podules: Add validation of version and flags in podule header
- podules: Add Design IT Ethernet 200 network interface emulation
- podules: Show user visible error on podule initialisation failure
- podules: Add dummy placeholder for Risc Development HDFC podule ROM

- riscdev_hdfc: Fix build warnings

- slirp: If no nameservers found in resolv.conf, use localhost for DNS

- sound: Fix incorrect offset in log->lin conversion table
- sound: Use SDL for audio instead of OpenAL

- st506: Do proper bounds checks on C/H/S values
- st506: Use more realistic intersector timing
- st506: Better naming for status and error defines
- st506: Read/write/check commands should report updated parameters
- st506: Return "not ready" error for disconnected drives

- ui: More string handling fixes
- ui: Add support for network podules to the config dialogue
- ui: Fix A440 description in config dialogue
- ui: Error dialogs now run on the UI thread
- ui: Add stdint.h to wx-hd_new.cc and wx-joystick-config.cc
- ui: Fix parsing of some menu IDs
- ui: Add SSD/DSD file types to the disc image file selector

- video: Fix non-functioning video output scaling on non-Windows platforms

- win: 64-bit \_findfirst fixes

## v2.0

- Disable unfinished JFD support for v2.0.
- Only load icon on Windows.
- Implement OS X podule loader.
- #define around absence of fopen64 et al on OS X.
- Add dummy MIDI and audio in code. Lark and MIDI Max podules can be built on OS X.
- Added initial OS X CD-ROM code. Probably broken.
- configure.ac changes to get OS X podules building.
- Added ZIDEFS compatible podule.
- Remove old linux and macos Makefiles; these platforms should use autoconf instead.
- Add RELEASE_BUILD guards around most fatal() calls.
- Handle bad IDE commands instead of bailing out.
- Change exit() calls to fatal(), and guard with !RELEASE_BUILD.
- Update HostFS to version from RPCemu 0.9.2.
- Add HostFS module source.
- Add missing header to hostfs-unix.c.
- Skip all hidden files when loading ROMs.
- Swap video_render_close() and SDL_DestroyWindow() in non-Windows port to avoid use-after-free.
- Remove resizeable window option in total cop out due to crashes on Windows 10.
- Filled out documentation a bit.
- Remove ROM directories for Eterna arcade games, as these are not supported in this version.
- Update outdated credit in source files.
- Remove old dead native Windows code.
- Couple more additions to compatibility list.
- Add DEBUG_LOG guarding to podule logging.
- Updated version number to v2.0.
- Update configure.ac version number to v2.0.
- Add --enable-release-build to configure.ac.
- Set DEBUG_LOG in configure.ac when making debug build.
- Fix build issues in wx-sdl2.c.
- Regenerate autoconf/automake files.
- Add Readme-LINUX.txt.
- Add better default CMOS images.
- Update changes.txt.
- Pick up the configured MIDI in/out device - can now play back and capture via real hardware, rather than just the Mirosoft GM software synth. (Tested with two USB<>MIDI adaptors, MIDI keyboard). Issues with playback - notes are missed. This does not appear to bea "RISC OS" issue (MWLite works fine with real Eagle MIDI card). Suspect some kind of emulated 16550 buffer overrun - bug only happens when MIDI commands sent frequently.
- First attempt at fixing MIDI playback issue - always use midiOutLongMsg instead of mixing with midiOutShortMsg as the latter is allegedly known flaky with some hardware. Didn't fix it for me, but committing anyway as I think the code's a little cleaner.
- This seems to fix playback of "non-trivial" MIDI on all tested examples. Played various complex XG stuff to XG synth perfectly. Issue was lack of support for repeated "running status" commands. Only tested on Windows - ALSA code fix is presented as a "should work" as it's sufficiently trivial.
- Add config name as optional command line parameter.
- Add A500 prototype emulation. This has been tested with the available Arthur 1.2 and RISC OS 2.0 ROM images. Currently the altered floppy and hard drive controllers, and the different audio sample format are emulated. The seperate RTC chip and keyboard are not yet emulated.
- Implement IDE IRQ disable bit. This fixes an issue which can cause data corruption when the drive is accessed while a long running IRQ/event handler is executing with IRQs enabled.
- Fix sector wrapping on ADF images; fixes "disc not understood" errors when switching from high to double density floppy.
- Don't allow out-of-bounds accesses to the ROM array during ROM loading.
- Implement A500 RTC.
- Fix A500 memory selection in config dialog.
- Add A500 keyboard emulation.
- Add initial A4 emulation. BMU is (partially) implemented, LCD ASIC is a dummy to allow the Portable module to initialise.
- Add initial A4 LCD emulation.
- Fix 24 MHz ARM3 for A4. Also restore original CPU type order as so to not break existing configs.
- Blank LCD display if it hasn't been updated for a while (eg LC ASIC not programmed yet).
- Zero out LC ASIC registers on init.
- Add Colour Card emulation.
- Add placeholder ROM directory for Colour Card.
- Added State Machine G16 emulation.
- Refactor APD & FDI code to share FM/MFM processing code
- Added initial HFE disc image support.
- Fix HFE single density.
- Fix high density track buffer in MFM code
- Force load of current track on load of HFE image.
- Refactoring in disc_mfm_common, fixes index signal on empty tracks.
- Bad CRC on a sector header should cause sector to be skipped by read data command, rather than throwing a header CRC error.
- Some MFM code refactoring
- APD/HFE/FDI code now handles a single bitstream of data at high density, downsampling to single/double as required, rather than keeping three bitstreams in memory.
- Support 500 kbit/s HFE images
- HFE images always store two sides
- Add write support for HFE images
- Fix some unused variable warnings
- Fix disc sector range check on DOS-formatted discs. Fixes "sector not found" error when accessing last sector on a disc.
- Add support for 1.68MB DOS discs (used by Windows 95).
- Add initial Aleph One 386/486PC Expansion Card emulation. Uses PCem for 386-side emulation, libco (https://github.com/higan-emu/libco) for cothreads.
- Add non-Windows PC card makefiles. Also change name of PIC structure in PCem code.
- Timing fixes - ARM3 sync to FCLK now syncs correctly, last_cycle_length for MEMC1 is now not always 0.
- Implement IOC timers 2 & 3.
- Clear prefetch & data abort flags on ARM reset. Fixes occasional lockup when changing machine.
- Fix vertical offset for fixed border mode.
- Add support for 8-bit minipodules. Implement limitations on machines with less than 4 podule slots. Add 8-bit versions of Arculator support ROM podule and ZIDEFS IDE controller.
- Actually fix vertical offset for fixed border mode.
- Update labels on podule controls to reflect podules available on current selected machine.
- Add configurable 5th column ROM emulation.
- Fix IDE status flags. Fixes Wizzo IDE 5th column ROM.
- Allow 5th column ROM up to 128kb; the maximum available on A5000.
- Change Arculator support ROMs from a podule to a extension ROM (at a non-standard address, to not conflict with 5th column ROMs). Removed podule as the only use would have been for RISC OS 2 (which doesn't support extension ROMs), and HostFS doesn't work on RO2.
- Remove accidental minipodule from A4.
- Configuration manager: allow double click to start a configuration.
- Send WM_CLOSE message on File->Exit.
- Add Acorn AKA12 user port / MIDI mini podule emulation.
- Add AKA05 ROM board emulation.
- Increase size of text control in podule config dialogues.
- Add AKA10/15 IO/MIDI podule.
- Added Acorn AKA16 MIDI Podule.
- Detangle SCSI code from AKA31 podule and make more generic.
- Add A500 RISC OS 3.10 support.
- Add directories for A500 ROMs.
- Add Oak 16-bit SCSI Interface emulation.
- Add ICS A3000 IDE Interface (v5) emulation.
- Fix unused variable.
- Fix emulator crash when branching to 0.
- Add ROM placeholders for a3inv5 and zidefs podules.
- Add automake files for new podules.
- Fix paths in AKA31 Makefile.am
- Force reload of current track on loading an ADF, APD or FDI image (HFE already does this). Fixes disc change on Arthur.
- Link PC Card DLL with GCC instead of dllwrap; the latter seems to sometimes produce DLLs that crash on startup.
- Change AKA31 user-visible name to match other Acorn podules.
- Add placeholder text file for G16.
- Fix initial ROM selection when creating a new A500 machine.
- Fix default CMOS for A500 running RISC OS 3.10.
- Disable logging on AKA12 & Oak SCSI Podules.
- Add X11 workaround for segfault on some X systems. Change from pdjstone
- Fix multiple definition of arm3cp.

## v0.99

- Add v0.99 source
- Better emulation timing. ARM2/250 should be much closer to real system speed now (ARM3 is a bit off). MEMC1 emulation (basically MEMC1A emulation but a bit slower). Working FPA emulation. Re-written floppy disc emulation. Better FDI support. Preliminary JFD support. Disc drive noise. Replaced ArculFS with HostFS from RPCemu. ST-506 hard disc emulation for pre-IDE machines. Tweaked keyboard/mouse emulation. Podule emulation. Now licenced under GPLv2. Probably some other stuff I forgot.
- Added support for MEMC podules. Podules now reset on startup.
- Fixed DMA mapping for 82c711 FDC
- Added initial AKA31 SCSI podule emulation. Emulates single (incomplete) SCSI hard drive of ~250MB on ID 0.
- Fix crash when switching OS.
- Masked page register on AKA31.
- Implemented AKA31 reset. Fixed AKA31 memory mapping. Implemented SCSI TEST_UNIT_READY command. WD339c93a reset now causes IRQ.
- Made initial changes to get things running on Linux.
- Added support for loading shared libraries containing podule support on Linux. Changed the default CPU configuration to an ARM 3 system that should also use MEMC 1a.
- Added backplane IRQ status register.
- Moved the keyboard initialisation call into the main file. Ensured that any directory changes are undone after podules are looked for.
- No longer set the CPU explicitly.
- Improvements to ARM2 instruction timings.
- Fix Windows Menu key used to emulate middle mouse button.
- SWP now generates undefined instruction exception on ARM2.
- Fixed synchronisation between emulator and GUI thread when hard resetting or changing memory size.
- Re-enabled window size changing on Windows.
- MEMC Video DMA enable bit now has effect on timing.
- Preliminary ARM3 cache emulation.
- Temporarily disable Poizone to work around crash on startup.
- Support arbitary ratios between (ARM3) CPU and memory clocks. Better emulation of video DMA and refresh.
- Improved IOC timers.
- LDM/STM do not write back base when base is R15 - Scorpius demo now works.
- New machine configure dialogue.
- Address exceptions now don't crash ARM3 cache emulation code.
- Changes to video code : - Changed video positioning code, demos that move the screen around (!RasterMan) now work properly - Removed the 16-bit video code, as it's not very relevant in 2016... - Fixed crash when changing monitor type - General cleanup
- Fixed bug in STRT - RISC OS 3 self test can now run. Re-enabled self test in celebration.
- Tentative fix for broken floppy disk image loading at start-up.
- Added a Makefile for GNU/Linux.
- Add GPLv2 COPYING
- Ported to SDL. All functionality should be present except for joystick emulation and disc drive noise.
- Added some missing #includes.
- If Arculator expansion ROM is not present, then return 0xff instead of 0. Fixes !SICK.
- Only enable line doubling below 350 lines.
- Rework blitting and border drawing code. Three display options are now supported : - No borders - self explanatory - Native borders - borders drawn by VIDC; frequently none - TV mode - display geometry to match TV resolution monitors. Should only be used with monitortype 0 Also cleaned up video code a bit.
- Temporarily fixed A3010 joystick read to no directions and no buttons.
- Fixed config file path on first config load.
- Set FPA enable on config load.
- Improved FPA timing.
- Fixed FPA Nearest rounding mode.
- Fix display and border disabling. Fix border displaying when video DMA enabled. Fixes POST colours.
- Added missing video.h.
- Changed a few inline functions to static inline.
- Remove dependency on ALut.
- Clean up makefile a bit.
- Some variable type cleanup in arm.c.
- Fixed compiler warnings. Enabled -Wall -Werror in makefile.
- Fixed load path for ARCROM.
- Added missing header files.
- Added .hgignore to exclude hostfs and build files from 'hg status'
- Add #include directives necessary for compilation on macOS
- Add various logging aliases, to enable turning logging on and off for individual functions.
- Fixed a couple of build errors.
- Tidy up CMOS logging and remove unused variables
- Deduplicate memory-related symbols and log specific situations in mem.c
- Fix a bunch of const correctness warnings in config.c
- Remove unused FDI definitions
- Add externs, and add braces and do {} while (0) to writememb/writememl for macro safety
- Convert most function declarations in arc.h to extern
- More extern/const/type warning fixes, plus not defining bool if already defined
- Moved disc definitions into disc.c
- Disable mousehack
- Rename window to sdl_main_window
- Move memc symbols into memc.c, and enable some more logging
- Move IOC struct definition into ioc.c, and tidy some variables/logging
- Mouse logging, and moved ml,mr,mt,mb definition into keyboard.c
- Port romload.c from \_findfirst/\_findnext to opendir/readdir
- romload.c uses \_findfirst/\_findnext on Windows, opendir/readdir on other systems.
- Fix all remaining duplicate variable definitions
- arm.c timing and documentation; also added braces around a couple of suspicious function calls
- Arculator now runs on macOS :)
- Disable podules on macOS/Linux (they still need Allegro), and deduplicate podule header files
- Add macOS Makefile
- Remove reference to old podules-linux.h
- Change podules-win.h references to use podules.h instead
- Calculate rotatelookup table with 64-bit math to fix shifter overflow breakage
- Fixed OpenAL includes for MacOS. Enable openal-soft linking in Makefile.macos.
- Remove direct.h include from hostfs.c.
- romload.c now ignores .DS_Store
- Document VIDC operations; auto-resize window on macOS/Linux; clear buffer after blitting to avoid ghosting on mode change.
- Add fullscreen support for macOS, and properly tidy up after ourselves on exit.
- FPU improvements - added experimental FPPC emulation, also fault on FPA instructions when disabled in FPU status register.
- Fix IOC Power On interrupt bit clearing. DEL/R power-on keys now work.
- Added better default CMOS files.
- Don't cause an error when cyclesperline_display < 0.
- Fix build error in soundopenal.c with some OpenAL libraries.
- Don't call the close callback on a floppy drive that is already empty. Fixes some FDI crashes.
- Rewrite emulator UI. This commit makes the following changes : - Change UI to use wxWidgets - Add configuration manager - Add per-configuration CMOS files - Add per-configuration hard drive image files Currently only building on Windows is supported.
- Fix Linux build errors
- Added autotools-based build system for Linux and other platforms
- Fixed Linux podule loader
- Fixed build warnings in AKA31
- Set window title text on non-Windows platforms
- Remove 'Limit speed' option
- Clean up config int/string usage
- Split config dialogue into multiple pages
- Change preset list in config dialogue to a 'Load Preset' button
- Implemented fullscreen menu option
- Added configurable fullscreen scaling. Supports full screen, 4:3, square pixels and integer scaling.
- Added scale filtering option
- Added option to choose SDL render driver
- Added option for resizeable window
- Don't allow mouse capture while configuration dialogue open.
- Don't update SDL texture if width or height <= 0.
- Modularise IDE code a bit.
- Rework podule API.
- Add ICS ideA podule emulation.
- Fix build errors on Linux.
- Fix AKA31 build errors on Linux.
- Port timer system over from PCem. This provides a more flexible peripheral timer system than a long list of timers in execarm(). Keyboard, sound, discs and podules have been ported over. IOC and video are currently still on the old 'system'.
- Check timers after every instruction rather than every scanline. Floppy drives work again.
- Port IOC timers to new timer system.
- Port VIDC to new timer system. Clean up duplicate timer systems in arm.c, and remove cycles variable entirely.
- Initial attempt at fixing awful formatting in execarm().
- Remove dead ArculFS trap.
- Clean up exception handling.
- Abstract data processing R15 writes. Cleaner, should also fix a few bugs with some 'S' instructions writing mode/interrupt bits in user mode.
- Rename shift/rotate functions to be more meaningful. Also clean up handling of register rotates for LDR/STR - this should not be able to kill the emulator anymore.
- Modularise ST506 code.
- Add ability to configure old-world IO system without ST-506 controller (A305/A310/A3000).
- Add private data pointer to st506_t structure.
- Add missing st506.h file.
- Add AKD52 Hard Disc Podule emulation.
- Implement podule timer API.
- Added emulation of HCCS Ultimate CD-ROM podule, and Mitsumi FX001D drive. Currently Windows only. To use, a native drive path must be in the config file. An example for a podule in slot 2 using drive H :
- Clear prefetch aborts after processing. Fixes RISCiX booting.
- Update CPU mode on data processing write to R15 with S bit set. Ensures prefetch following jump with mode change uses correct mode.
- More sane timings on AKA31 podule. AKA31 now works again.
- Fixed prefetch abort timing - prefetch aborts were occuring two instructions too early. Fixes the 'undefined instruction' error in ifconfig in RISCiX.
- Fixed backplane IRQ masking.
- Sort out disc poll times. FDI discs now work again.
- Stop disc operations on FDC reset and disc eject. Fixes oddities (including false underruns) on reset/FDC reset/disc eject/change.
- Implement proper underrun handling for SuperIO FDC.
- Implement index pulse-based timeout on 177x read/write commands. Fixes disc change in Burn 'Out and probably other stuff.
- Cut back on 1772 logging.
- Re-enable disc drive noise.
- Call c82c711_fdc_init() instead of c82c711_fdc_reset() on init.
- Sound rework.
- Don't start emulation if no configuration is selected.
- Correct timeslice value reported to podule run functions.
- Move podule directories around a bit. This moves each podule into it's own directory under podules\, storing the DLL, any ROM images and any other files. Arculator will search for a DLL with the same name as the directory. Podule source is a subdirectory within the podule directory.
- Add Wild Vision MIDI Max emulation. Currently MIDI functionality has only been implemented for Windows.
- Add Conputer Concepts Lark emulation. Currently MIDI and audio in functionality have only been implemented for Windows.
- Fix some compiler warnings.
- Add initial podule configuration GUI. Currently basic checkbox and drop-down controls are supported. Configuration has been added to the Lark, MIDI Max, and Ultimate CD-ROM podules.
- Added drive configuration to IDE podules. This involved significant changes to the config GUI system, to allow nested dialogs, user callbacks and other features.
- Added drive configuration to ST-506 podule.
- Add full hard drive parameter configuration to IDE and ST-506 drives. Also modified IDE Identify command to report back both physical and current drive parameters; IdeA formatter now detects size of drive correctly.
- Add new files from last commit to Makefiles.
- Add timestamp to log messages.
- Implement FDC 'disc change clear' line (only implemented on Archimedes 305/310/440). Fixes 'drive empty' errors on Arthur.
- Don't empty disc drives on reset.
- Add 'machine type' to machine configs.
- Fix loading of IDE disc images with 512 byte headers (as generated by older Arculator versions).
- Only test for address exceptions on the first transfer in an LDM/STM instruction.
- Use fdctype rather than romset to determine which FDC is in use.
- Disable some uses of romset for Eterna-specific behaviour for now.
- Rework ROM configuration. Arculator now supports configuring ROM images from Arthur 0.30 to RISC OS 3.19. The configuration GUI will only show ROM images that are available and supported by the configured machine. Configurations specifying ROM sets that are not available will not run, giving the user an error instead. The configured ROM set is now stored in the configuration file as a string rather than an opaque int.
- Fix real time clock.
- Cleaned up CMOS/I2C code a bit.
- Clean some dead code from arc.h.
- Only clear DSKCHG line if drive is not empty. Fixes some drive empty issues.
- Add monitor type to machine configuration. Support reading monitor ID from IOEB. Split IOEB out of mem.c into separate file while I'm at it.
- Disable log message on reading FPSR, which could cause vast amounts of log spam when FPA in use.
- Add missing resetmouse() prototype in keyboard.h.
- Force DSKCHG signal on emulator init.
- Updates to podule API documentation.
- Re-implemented MUL/MLA using Booth's algorithm. Should provide accurate emulation of invalid register combinations, as well as better timing. !SICK no longer claims that the emulated machine is Virtual A5000.
- Remove superfluous address exception checking in readmem/writemem macros. Fixes !SICK detection of LDM/STM address exception bug.
- Added video scale menu, for fixed 0.5x - 4x scaling of the emulator window.
- Rejig menu order a bit. Main emulator menu is now File/Disc/Video/Sound/Settings.
- Add sound gain menu.
- Major reworking of CPU & memory timing. Includes the following changes : - Improved emulation of ARM2 merged cycles - Improved (and hopefully correct!) MEMC1 timing - Proper emulation of FCLK/MCLK switching on ARM3 - Emulate CPU clocking during cache fills on ARM3 - Tweaked MUL/MLA timing - Reworked DMA timing. MEMC DMA sources will signal DMA requests when required and the run_dma() function will determine delays to memory bus availability - Moved all CPU & DMA timestamps to 32:32 fixed point format
- Add emulation of unique machine ID chip.
- Fix overflow in remaining samples calculation when switching sound clock. Also fix up a couple of other issues that could cause further sound clicking.
- Fixed off-by-one video errors.
- Deleted some dead code.
- Fix APD disc loading.
- Reduce APD logging.
- Fixed JFD disc loading.
- Re-implement A3010 joystick support. Joystick button and axis mappings are fully configurable.
- Add RTFM Joystick Interface emulation.
- Added GamesPad/GamesPad Pro emulation. As part of this change, added some basic printer port infrastructure.
- Use specific axis/button/POV names in joystick configuration dialogue.
- Fixed mapping of tilde (`~) key.
- Added emulation of The Serial Port / Vertical Twist joystick interface.
- Move all SDL initialisation into main().
- Pass more window messages to DefWindowProc().
- Attach thread inputs between main and window threads in an attempt to fix SDL focus issues.
- Rework AKA31 podule to emulate SCSI bus properly. The bus code emulates the individual SCSI phases, interfacing to device emulation.
- Add hard drive configuration interface to AKA31.
- Support SCSI HD reads longer than 256kB.
- Added SCSI CD-ROM emulation. Currently a Toshiba CD-ROM XM-3301 is emulated. This is supported by the CDFSSoftToshibaEESOX driver in later AKA31 ROMs.
- Fixes to podule configuration to support AKA31 SCSI configuration w/CD-ROM.
- Fix some build warnings in vidc.c.
- Use common CD-ROM and sound code in Ultimate CD-ROM podule.
- Remove unused 'Fast disc access' menu item.
- Add configurable sound filter.
- Add disc drive noise volume control.
- Start updating readme.txt.
- Add placeholder for configs directory.
- Rename timer_t to emu_timer_t to avoid conflicts with sys/types.h.
- Remove dead arc_set_hires() function in wx-sdl2.c.
- Update automake files
- Add missing pci.png icon (used for podules in config dialogue).
- Tweaks to menu.
- Remove duff wxALIGN_CENTRE_HORIZONTAL style from arculator.xrc.
- Move ROMs for 'internal' podules to directories under roms/podules.
- 'Internal' podules now detect presence of required ROM images.
- Remove hard limit on loaded podule DLLs.
- Podule list now in alphabetical order.
- Reset memory timers on CPU reset. Fixes intermittent hangs on reset.
- Reduce sound buffer length to 50ms.
- Fix uninitialised variable in wx-config.cc.
- Reduce logging in disc_adf.c.
- Remove some unused variables in arm.c.
- Default new configurations to RISC OS 3.11.
- Use strcasecmp() instead of stricmp().
- Don't call SDL_Quit() from video_renderer_close(). Prevents issues when closing an emulator session and starting a new one.
- Fix podule library loading on Linux.
- Ported MIDIMax podule to Linux. Uses ALSA for MIDI in/out. Has not been extensively tested!
- Ported Lark podule to Linux. Uses ALSA for MIDI in/out and wave in. Has not been extensively tested!
- Ported Ultimate CD-ROM podule to Linux.
- Added makefile missing from last commit.
- Fix AKA31 on Linux.
- Added podules to autotools build system. Podules are built by default. To skip building podules, run ./configure --disable-podules
- Clamp horizontal display start/end registers against horizontal cycle width. Fixes !SinDemo.
- Add config.guess/config.sub files.
- rom_establish_availability() now allocates a temporary rom array instead of loading into NULL.
- Add dummy Mac podule loader.
- Initialise wxWidgets before SDL. Fixes crash on startup on Mac OS X.
- Delay ROM presence check to after wxEntry(). Fixes crash when no ROMs present.
- Fix 1770 FDC ready signal. Fixes empty floppy drive detection in !PCem.
- Only implement FDC 'disc change clear' line when running Arthur. Fixes !PCem disc change detection.
- Add MS-DOS 1.44MB format to disc image code.
- Remove dead 'not found' APD write code. Fixes Nevyron.
- Fix duplicate log messages.
- Fix log timestamps.
- ARM2/3 only test bits 4 and 7 to decode MUL/MLA. Fixes Diggers.
- MUL/MLA don't modify R15.
- Fix data timings on 711 FDC.
- Add disc_stop functions for ADF/SSD/DSD images.
- Add fake index pulse on APD tracks with no data at the current density.
- Don't exit APD poll routine if read not in progress; this is required to keep a constant rate of index pulses. Fixes erronous 'disc empty' errors with 711 FDC.
- Fix result disc address on 711 FDC read/write commands.
- Return current disc address on 711 FDC overrun error.
- Return current disc address on 711 FDC CRC errors.
- Implemented missing 711 FDC write protect handling.
- Remove unused fdi_notfound variable.
- Trigger 'sector not found' for ADF reads/writes beyond the end of the image. Fixes Starch (which has a deliberately undersized image).
- Little cleanup of disc_adf.c.
- Tweak sound read pointer offset. Fixes some sound glitches.
- Fix timing crash when booting RISCiX.
- Fix timings for hi-res mono monitor.
- Close SCSI devices on AKA31 close/reset. Fixes 'Bad Directory' errors after reset.
- Fix persistent ghost image when switching from non-doubled to line doubled mode with scanlines enabled.
- S-cycles don't hit ARM3 cache unless the cache was enabled on the first N-cycle. Fixes Drifter.
- Added compatibility list.
- Set CPU speed before resetting timer system, and clear out obsolete arc_setspeed() function. Fixes broken timing when changing CPU speed without exiting back to config menu.
- Remove some unused variables.
- Added new icon.

- VIDC: never return negative cyclesperline\_{display, blanking}, and clean up logging and externs

## Unreleased

- Adding icon
