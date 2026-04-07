# Overview

This repo is a macOS-focused fork of [arculator](https://github.com/sarah-walker-pcem/arculator), the Acorn Archimedes emulator, with changes to make it build and run reliably on modern macOS, including Apple Silicon.  

As of March 2026, confirmed it builds and runs on macOS Tahoe.

&nbsp;

## What Is Different In This Repo

Compared with upstream Arculator, this repo is oriented around macOS development and packaging:

- macOS build fixes for current toolchains, including Apple Silicon support.
- A maintained macOS setup flow via `./mac-setup` for the legacy Autotools build.
- An Xcode project generator in `macos/generate_xcodeproj.rb` for native macOS app builds.
- Ongoing native macOS porting work under `src/macos/` and in [`docs/PORTING_PLAN.md`](docs/PORTING_PLAN.md).

The emulator core and ROM/disc compatibility remain aligned with Arculator; the main difference here is the macOS-specific build and platform work.

## Build Overview

There are two supported ways to build on macOS.

### Option 1: Autotools build

This is the existing cross-platform build path adapted for macOS.

1. Install Xcode Command Line Tools and Homebrew.
2. Run `./mac-setup`.
3. Build with `make`.
4. Launch the binary with `./arculator`.

`mac-setup` installs the required dependencies, including `autoconf`, `automake`, `libtool`, `wxwidgets`, `sdl2`, and `xquartz`, then runs `configure` for you.

### Option 2: Xcode app build

This is the better path if you want a native `.app` bundle for local macOS development.

1. Install Xcode, Homebrew, Ruby, and the `xcodeproj` gem.
2. Install the Homebrew dependencies used by the project, especially `wxwidgets` and `sdl2`.
3. Generate the project with `ruby macos/generate_xcodeproj.rb`.
4. Open `Arculator.xcodeproj` in Xcode and build the `Arculator` target.

The generated app bundle stages the runtime assets it needs from this repo, including `roms`, `podules`, `ddnoise`, and UI resources.

## ROMs And Running

You will still need to provide a suitable RISC OS ROM set under one of the directories inside `./roms`. For example, a RISC OS 3.11 ROM set works.

After building:

- use `./arculator` for the Autotools build, or
- run the built `Arculator.app` from Xcode.
