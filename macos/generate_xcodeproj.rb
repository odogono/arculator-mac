#!/usr/bin/env ruby

require "fileutils"
require "rubygems"

gem "xcodeproj", ">= 1.21.0"
require "xcodeproj"

PROJECT_NAME = "Arculator"
PROJECT_PATH = "#{PROJECT_NAME}.xcodeproj"

SOURCE_FILES = %w[
  src/82c711.c
  src/82c711_fdc.c
  src/arm.c
  src/bmu.c
  src/cmos.c
  src/colourcard.c
  src/config.c
  src/cp15.c
  src/ddnoise.c
  src/debugger.c
  src/debugger_swis.c
  src/disc.c
  src/disc_adf.c
  src/disc_apd.c
  src/disc_fdi.c
  src/disc_hfe.c
  src/disc_jfd.c
  src/disc_mfm_common.c
  src/disc_scp.c
  src/ds2401.c
  src/emulation_control.c
  src/eterna.c
  src/fdi2raw.c
  src/fpa.c
  src/g16.c
  src/g332.c
  src/hostfs.c
  src/hostfs-unix.c
  src/ide.c
  src/ide_a3in.c
  src/ide_config.c
  src/ide_idea.c
  src/ide_riscdev.c
  src/ide_zidefs.c
  src/ide_zidefs_a3k.c
  src/macos/input_macos.m
  src/input_snapshot.c
  src/ioc.c
  src/ioeb.c
  src/joystick.c
  src/keyboard.c
  src/lc.c
  src/macos/app_macos.mm
  src/main.c
  src/mem.c
  src/memc.c
  src/podules-macosx.c
  src/platform_paths.c
  src/podules.c
  src/printer.c
  src/riscdev_hdfc.c
  src/romload.c
  src/sound.c
  src/st506.c
  src/st506_akd52.c
  src/timer.c
  src/vidc.c
  src/macos/video_metal.m
  src/wd1770.c
  src/macos/config_macos.mm
  src/macos/console_macos.mm
  src/macos/hd_macos.mm
  src/macos/joystick_config_macos.mm
  src/macos/podule_config_macos.mm
  src/macos/joystick_gc.m
  src/macos/sound_coreaudio.m
].freeze

RESOURCE_FILES = %w[
  macos/Assets.xcassets
].freeze

SYSTEM_FRAMEWORKS = %w[
  AudioToolbox
  Carbon
  Cocoa
  CoreAudio
  GameController
  IOKit
  Metal
  MetalKit
  OpenGL
  QuartzCore
].freeze

LEGACY_RUNTIME_SCRIPT = <<~SCRIPT.freeze
  set -euo pipefail
  app_root="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
  resources_root="$app_root/Resources"

  mkdir -p "$resources_root"

  copy_dir() {
    local source_path="$SRCROOT/$1"
    local dest_path="$resources_root/$2"
    rm -rf "$dest_path"
    mkdir -p "$(dirname "$dest_path")"
    cp -R "$source_path" "$dest_path"
  }

  copy_file() {
    local source_path="$SRCROOT/$1"
    local dest_path="$resources_root/$2"
    mkdir -p "$(dirname "$dest_path")"
    cp "$source_path" "$dest_path"
  }

  copy_dir "ddnoise" "ddnoise"
  copy_dir "roms" "roms"
  copy_dir "src/icons" "icons"
  copy_file "src/arculator.xrc" "arculator.xrc"
  /bin/sh "$SRCROOT/macos/build_podules.sh" "$SRCROOT" "$resources_root"
SCRIPT

METAL_BOOTSTRAP_SCRIPT = <<~SCRIPT.freeze
  set -euo pipefail
  shader_src="$SRCROOT/src/macos/Shaders.metal"
  air_output="$TARGET_TEMP_DIR/ArculatorBootstrap.air"
  metallib_output="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/ArculatorBootstrap.metallib"

  mkdir -p "$(dirname "$metallib_output")"

  if xcrun metal -help >/dev/null 2>&1 && xcrun metallib -help >/dev/null 2>&1; then
    xcrun metal -c "$shader_src" -o "$air_output"
    xcrun metallib "$air_output" -o "$metallib_output"
  else
    echo "warning: Metal toolchain component is not installed; writing placeholder metallib"
    : > "$metallib_output"
  fi
SCRIPT

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes["LastUpgradeCheck"] = "2600"
project.root_object.attributes["BuildIndependentTargetsInParallel"] = "1"

target = project.new_target(:application, PROJECT_NAME, :osx, "13.0")
target.product_reference.name = "#{PROJECT_NAME}.app"
target.product_reference.path = "#{PROJECT_NAME}.app"

project.build_configurations.each do |config|
  config.build_settings["CLANG_ENABLE_MODULES"] = "NO"
  config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
  config.build_settings["SDKROOT"] = "macosx"
end

main_group = project.main_group
src_group = main_group.find_subpath("src", true)
src_macos_group = src_group.find_subpath("macos", true)
macos_group = main_group.find_subpath("macos", true)
frameworks_group = project.frameworks_group || main_group.find_subpath("Frameworks", true)

macos_group.new_file("macos/Info.plist")
src_macos_group.new_file("src/macos/Shaders.metal")

SOURCE_FILES.each do |path|
  group = path.start_with?("src/macos/") ? src_macos_group : (path.start_with?("src/") ? src_group : macos_group)
  ref = group.new_file(path)
  target.source_build_phase.add_file_reference(ref, true)
end

RESOURCE_FILES.each do |path|
  ref = macos_group.new_file(path)
  target.resources_build_phase.add_file_reference(ref, true)
end

SYSTEM_FRAMEWORKS.each do |framework_name|
  ref = frameworks_group.new_file("System/Library/Frameworks/#{framework_name}.framework")
  ref.source_tree = "SDKROOT"
  target.frameworks_build_phase.add_file_reference(ref, true)
end

script_phase = target.new_shell_script_build_phase("Stage Legacy Runtime")
script_phase.shell_path = "/bin/sh"
script_phase.shell_script = LEGACY_RUNTIME_SCRIPT

metal_phase = target.new_shell_script_build_phase("Compile Metal Bootstrap Shader")
metal_phase.shell_path = "/bin/sh"
metal_phase.input_paths = ["$(SRCROOT)/src/macos/Shaders.metal"]
metal_phase.output_paths = ["$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/ArculatorBootstrap.metallib"]
metal_phase.shell_script = METAL_BOOTSTRAP_SCRIPT

target.build_configurations.each do |config|
  settings = config.build_settings
  settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  settings["ARCHS"] = "arm64"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["CLANG_ENABLE_MODULES"] = "NO"
  settings["ENABLE_HARDENED_RUNTIME"] = "NO"
  settings["ENABLE_PREVIEWS"] = "NO"
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["HEADER_SEARCH_PATHS"] = [
    "$(inherited)",
    "$(SRCROOT)/src"
  ]
  settings["INFOPLIST_FILE"] = "macos/Info.plist"
  settings["LIBRARY_SEARCH_PATHS"] = [
    "$(inherited)",
    "/opt/homebrew/lib"
  ]
  settings["MTL_ENABLE_DEBUG_INFO"] = "INCLUDE_SOURCE"
  settings["OTHER_CFLAGS"] = [
    "$(inherited)",
    "-D_FILE_OFFSET_BITS=64",
    "-Winvalid-offsetof"
  ]
  settings["OTHER_CPLUSPLUSFLAGS"] = settings["OTHER_CFLAGS"]
  settings["OTHER_LDFLAGS"] = ["$(inherited)", "-lz"]
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.arculator.mac"
  settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
  settings["SWIFT_EMIT_LOC_STRINGS"] = "NO"

  if config.name == "Debug"
    settings["DEBUG_INFORMATION_FORMAT"] = "dwarf"
    settings["ONLY_ACTIVE_ARCH"] = "YES"
  else
    settings["DEBUG_INFORMATION_FORMAT"] = "dwarf-with-dsym"
    settings["ONLY_ACTIVE_ARCH"] = "NO"
    settings["SWIFT_COMPILATION_MODE"] = "wholemodule"
  end
end

project.save
