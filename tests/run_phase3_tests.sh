#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

clang -I src \
	tests/phase3_tests.c \
	src/emulation_control.c \
	src/input_snapshot.c \
	-o tests/phase3_tests

./tests/phase3_tests
