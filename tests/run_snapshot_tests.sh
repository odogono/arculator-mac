#!/bin/sh
#
# Umbrella runner for every standalone C snapshot test binary.
#
# Compiles and runs:
#   - tests/snapshot_format_tests  (file format + scope guards)
#   - tests/floppy_is_idle_tests   (floppy_is_idle() truth table)
#
# XCTest-based snapshot tests (SnapshotScopeTests.m,
# SnapshotMenuUITests.swift) run under `xcodebuild test` and are not
# exercised by this script.

set -eu

cd "$(dirname "$0")/.."

./tests/run_snapshot_format_tests.sh

clang -std=c99 -I src \
	tests/floppy_is_idle_tests.c \
	tests/floppy_is_idle_stubs.c \
	src/disc.c \
	src/timer.c \
	src/snapshot.c \
	-o tests/floppy_is_idle_tests

./tests/floppy_is_idle_tests
