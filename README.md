# Overview

This repo is a macOS-focused fork of [arculator](https://github.com/sarah-walker-pcem/arculator), the Acorn Archimedes emulator, with changes to make it build and run reliably on modern macOS, including Apple Silicon.

As of April 2026, the native macOS build uses AppKit, Metal, and Core Audio instead of wxWidgets/SDL2.

&nbsp;

## What Is Different In This Repo

Compared with upstream Arculator, this repo is oriented around macOS development and packaging:

- Native macOS UI built with AppKit (Objective-C and Swift).
- Metal-based video rendering replacing SDL2.
- Core Audio-based sound replacing SDL2.
- Native keyboard/mouse handling and Game Controller support.
- An Xcode project for native macOS `.app` bundle builds.
- Ongoing native macOS porting work documented in [`docs/PORTING_PLAN.md`](docs/PORTING_PLAN.md).

The emulator core and ROM/disc compatibility remain aligned with Arculator; the main difference here is the macOS-specific build and platform work.

&nbsp;

## Build Overview

There are two supported ways to build on macOS.

### Option 1: Autotools build (legacy)

This is the cross-platform build path, retained for Linux and other platforms.

1. Install Xcode Command Line Tools and Homebrew.
2. Run `./mac-setup`.
3. Build with `make`.
4. Launch the binary with `./arculator`.

**Note:** The Autotools build still uses wxWidgets + SDL2 on macOS and is not the primary focus of this repo.

### Option 2: Xcode build (recommended for macOS)

This builds the native macOS app with AppKit, Metal, and Core Audio.

#### Prerequisites

1. **Xcode** - Install from the Mac App Store or download from [developer.apple.com](https://developer.apple.com/xcode/).
2. **Homebrew** - Install from [brew.sh](https://brew.sh):
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
3. **Ruby** - Pre-installed on macOS, but ensure you have the `xcodeproj` gem:
   ```bash
   gem install xcodeproj
   ```

#### Build Steps

1. **Generate the Xcode project** (if needed):
   
   The project is already included at `macos/Arculator.xcodeproj/`. If you need to regenerate it:
   ```bash
   ruby macos/generate_xcodeproj.rb
   ```

2. **Open in Xcode**:
   
   Open `macos/Arculator.xcodeproj` in Xcode:
   ```bash
   open macos/Arculator.xcodeproj
   ```
   
   Or build from the command line:
   ```bash
   xcodebuild -project macos/Arculator.xcodeproj -scheme Arculator -configuration Debug build
   ```

3. **Run the app**:
   
   The built app will be at:
   - Debug: `build/Debug/Arculator.app`
   - Release: `build/Release/Arculator.app`

   You can run it with:
   ```bash
   open build/Debug/Arculator.app
   ```

#### Build Configuration

The Xcode project targets macOS 13.0+ and builds for arm64 (Apple Silicon). It includes:

- **Swift 5.0** for UI components
- **Objective-C** for AppKit shell and native backends
- **Metal** for GPU-accelerated video rendering
- **Core Audio** for sound output
- **Game Controller** for joystick support

#### Building Without Code Signing

For local development without Apple Developer membership:
```bash
xcodebuild -project macos/Arculator.xcodeproj -scheme Arculator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The built app will be in `build/Debug/Arculator.app`.

## ROMs And Running

You will still need to provide a suitable RISC OS ROM set under one of the directories inside `./roms`. For example, a RISC OS 3.11 ROM set works.

The native macOS build searches for ROMs in this order:
1. User-configured ROM path
2. `~/Library/Application Support/Arculator/roms/`
3. Bundled `Resources/roms/` inside the app bundle

After building, run the built `Arculator.app` from Xcode or the build output directory.
