#!/usr/bin/env ruby

require "fileutils"
require "rubygems"

gem "xcodeproj", ">= 1.21.0"
require "xcodeproj"

PROJECT_NAME = "Arculator"
PROJECT_PATH = File.join("macos", "#{PROJECT_NAME}.xcodeproj")

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
  src/snapshot.c
  src/snapshot_load.c
  src/sound.c
  src/st506.c
  src/st506_akd52.c
  src/timer.c
  src/vidc.c
  src/macos/video_metal.m
  src/wd1770.c
  src/macos/console_macos.mm
  src/macos/hd_macos.mm
  src/macos/joystick_config_macos.mm
  src/macos/podule_config_macos.mm
  src/macos/joystick_gc.m
  src/macos/sound_coreaudio.m
  src/macos/EmulatorBridge.mm
  src/macos/ConfigBridge.mm
  src/macos/MachinePresetBridge.mm
  src/macos/SwiftInteropSmoke.swift
  src/macos/MachinePresets.swift
  src/macos/MachineConfigModel.swift
  src/macos/ConfigListModel.swift
  src/macos/EmulatorState.swift
  src/macos/EmulatorMetalView.swift
  src/macos/MainSplitViewController.swift
  src/macos/SidebarHostingController.swift
  src/macos/ContentHostingController.swift
  src/macos/ToolbarManager.swift
  src/macos/NewWindowBridge.mm
  src/macos/ConfigEditorBridge.mm
  src/macos/HardwareEnumeration.swift
  src/macos/MutabilityGating.swift
  src/macos/ConfigEditorView.swift
  src/macos/GeneralSettingsView.swift
  src/macos/StorageSettingsView.swift
  src/macos/PeripheralsSettingsView.swift
  src/macos/DisplaySettingsView.swift
  src/macos/SidebarView.swift
  src/macos/ConfigListView.swift
  src/macos/RunningControlsView.swift
  src/macos/DiscSlotView.swift
  src/macos/ScriptingCommandSupport.mm
  src/macos/LifecycleScriptingCommands.mm
  src/macos/ConfigScriptingCommands.mm
  src/macos/InputScriptingCommands.mm
  src/macos/NSApplication+Scripting.mm
  src/macos/InputInjectionBridge.mm
  src/macos/InternalDriveScriptingCommands.mm
  src/macos/AutomationScriptingCommands.mm
].freeze

RESOURCE_FILES = %w[
  macos/Assets.xcassets
  macos/Arculator.sdef
  macos/templates
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
  SwiftUI
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
  copy_dir "cmos" "cmos"
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
project.root_object.project_dir_path = ".."

target = project.new_target(:application, PROJECT_NAME, :osx, "13.0")
target.product_reference.name = "#{PROJECT_NAME}.app"
target.product_reference.path = "#{PROJECT_NAME}.app"

project.build_configurations.each do |config|
  settings = config.build_settings
  settings["CLANG_ENABLE_MODULES"] = "NO"
  settings["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
  settings["SDKROOT"] = "macosx"
  settings["SWIFT_VERSION"] = "5.0"

  if config.name == "Debug"
    settings["DEBUG_INFORMATION_FORMAT"] = "dwarf"
    settings["ENABLE_TESTABILITY"] = "YES"
    settings["GCC_DYNAMIC_NO_PIC"] = "NO"
    settings["GCC_OPTIMIZATION_LEVEL"] = "0"
    settings["GCC_PREPROCESSOR_DEFINITIONS"] = [
      "DEBUG=1",
      "$(inherited)"
    ]
    settings["MTL_ENABLE_DEBUG_INFO"] = "INCLUDE_SOURCE"
    settings["ONLY_ACTIVE_ARCH"] = "YES"
    settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
    settings["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
  else
    settings["DEBUG_INFORMATION_FORMAT"] = "dwarf-with-dsym"
    settings["ENABLE_NS_ASSERTIONS"] = "NO"
    settings["MTL_ENABLE_DEBUG_INFO"] = "NO"
    settings["SWIFT_COMPILATION_MODE"] = "wholemodule"
    settings["SWIFT_OPTIMIZATION_LEVEL"] = "-O"
  end
end

main_group = project.main_group
src_group = main_group.find_subpath("src", true)
src_macos_group = src_group.find_subpath("macos", true)
macos_group = main_group.find_subpath("macos", true)
frameworks_group = project.frameworks_group || main_group.find_subpath("Frameworks", true)

macos_group.new_file("macos/Info.plist")
src_macos_group.new_file("src/macos/Shaders.metal")
src_macos_group.new_file("src/macos/ArcMetalView.h")
src_macos_group.new_file("src/macos/NewWindowBridge.h")
src_macos_group.new_file("src/macos/ConfigEditorBridge.h")
src_macos_group.new_file("src/macos/ScriptingCommandSupport.h")
src_macos_group.new_file("src/macos/InputInjectionBridge.h")
src_group.new_file("src/snapshot.h")
src_group.new_file("src/snapshot_chunks.h")
src_group.new_file("src/snapshot_internal.h")
src_group.new_file("src/snapshot_subsystems.h")

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
  settings["CLANG_ENABLE_MODULES"] = "YES"
  settings["ENABLE_HARDENED_RUNTIME"] = "NO"
  settings["DEFINES_MODULE"] = "YES"
  settings["ENABLE_PREVIEWS"] = "YES"
  settings["SWIFT_OBJC_BRIDGING_HEADER"] = "src/macos/Arculator-Bridging-Header.h"
  settings["SWIFT_VERSION"] = "5.0"
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
    "-Winvalid-offsetof",
    "-fno-modules"
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

# --- ArculatorUITests target ---

ui_test_target = nil
UI_TEST_FILES = Dir.glob("tests/ArculatorUITests/*.swift").sort.freeze

unless UI_TEST_FILES.empty?
  ui_test_target = project.new_target(:unit_test_bundle, "ArculatorUITests", :osx, "13.0")
  ui_test_target.add_dependency(target)

  # Override product type from unit test to UI test bundle
  ui_test_target.product_type = "com.apple.product-type.bundle.ui-testing"
  ui_test_target.product_reference.explicit_file_type = "wrapper.cfbundle"

  ui_test_target.build_configurations.each do |config|
    settings = config.build_settings
    settings["TEST_TARGET_NAME"] = PROJECT_NAME
    settings["SWIFT_VERSION"] = "5.0"
    settings["CODE_SIGN_STYLE"] = "Automatic"
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.arculator.mac.uitests"
    settings["GENERATE_INFOPLIST_FILE"] = "YES"
    settings["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
    # UI test bundles should NOT set TEST_HOST or BUNDLE_LOADER
    settings.delete("TEST_HOST")
    settings.delete("BUNDLE_LOADER")
  end

  ui_tests_group = main_group.find_subpath("tests/ArculatorUITests", true)
  UI_TEST_FILES.each do |path|
    ref = ui_tests_group.new_file(path)
    ui_test_target.source_build_phase.add_file_reference(ref, true)
  end
end

# --- ArculatorCoreTests target ---

core_test_target = nil

# C sources compiled into the headless test bundle (subset of emulator + stubs)
CORE_TEST_C_SOURCES = %w[
  src/config.c
  src/cmos.c
  src/platform_paths.c
  src/timer.c
  tests/ArculatorCoreTests/core_test_stubs.c
].freeze

# ObjC XCTest files
CORE_TEST_OBJ_FILES = Dir.glob("tests/ArculatorCoreTests/*.{m,mm}").sort.freeze

CORE_TEST_ALL_SOURCES = (CORE_TEST_C_SOURCES + CORE_TEST_OBJ_FILES).freeze

CORE_TEST_FIXTURES_SCRIPT = <<~SCRIPT.freeze
  set -euo pipefail
  fixtures_src="$SRCROOT/tests/fixtures"
  templates_src="$SRCROOT/macos/templates"
  resources_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
  fixtures_dst="$resources_dir/fixtures"
  templates_dst="$resources_dir/templates"
  mkdir -p "$resources_dir"
  rm -rf "$fixtures_dst"
  rm -rf "$templates_dst"
  cp -R "$fixtures_src" "$fixtures_dst"
  cp -R "$templates_src" "$templates_dst"
SCRIPT

unless CORE_TEST_OBJ_FILES.empty?
  core_test_target = project.new_target(:unit_test_bundle, "ArculatorCoreTests", :osx, "13.0")
  # No dependency on the main app target — this is a host-less unit test bundle.

  core_test_target.build_configurations.each do |config|
    settings = config.build_settings
    settings["CODE_SIGN_STYLE"] = "Automatic"
    settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.arculator.mac.coretests"
    settings["GENERATE_INFOPLIST_FILE"] = "YES"
    settings["MACOSX_DEPLOYMENT_TARGET"] = "13.0"
    settings["ARCHS"] = "arm64"
    settings["HEADER_SEARCH_PATHS"] = [
      "$(inherited)",
      "$(SRCROOT)/src"
    ]
    settings["OTHER_CFLAGS"] = [
      "$(inherited)",
      "-D_FILE_OFFSET_BITS=64"
    ]
    # No TEST_HOST or BUNDLE_LOADER — host-less
    settings.delete("TEST_HOST")
    settings.delete("BUNDLE_LOADER")
  end

  # Link CoreFoundation (needed by platform_paths.c)
  cf_ref = frameworks_group.new_file("System/Library/Frameworks/CoreFoundation.framework")
  cf_ref.source_tree = "SDKROOT"
  core_test_target.frameworks_build_phase.add_file_reference(cf_ref, true)

  core_tests_group = main_group.find_subpath("tests/ArculatorCoreTests", true)
  core_tests_src_group = main_group.find_subpath("src", false) || src_group

  CORE_TEST_ALL_SOURCES.each do |path|
    if path.start_with?("tests/")
      ref = core_tests_group.new_file(path)
    else
      ref = core_tests_src_group.new_file(path)
    end
    core_test_target.source_build_phase.add_file_reference(ref, true)
  end

  # Copy test fixtures into the bundle resources
  fixtures_phase = core_test_target.new_shell_script_build_phase("Copy Test Fixtures")
  fixtures_phase.shell_path = "/bin/sh"
  fixtures_phase.shell_script = CORE_TEST_FIXTURES_SCRIPT
end

project.save

# --- Shared scheme ---

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)

if ui_test_target
  scheme.add_build_target(ui_test_target, false)
  scheme.add_test_target(ui_test_target)
end

if core_test_target
  scheme.add_build_target(core_test_target, false)
  scheme.add_test_target(core_test_target)
end

scheme.save_as(project.path, PROJECT_NAME, true)

# Disambiguate the nested project from any stale root-level Arculator.xcodeproj.
scheme_path = File.join(PROJECT_PATH, "xcshareddata", "xcschemes", "#{PROJECT_NAME}.xcscheme")
scheme_xml = File.read(scheme_path)
scheme_xml.gsub!("container:#{File.basename(PROJECT_PATH)}", "container:#{PROJECT_PATH}")
File.write(scheme_path, scheme_xml)
