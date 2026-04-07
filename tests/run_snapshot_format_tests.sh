#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

clang -std=c99 -Wall -Wextra -Werror -I src \
	tests/snapshot_format_tests.c \
	src/snapshot.c \
	-o tests/snapshot_format_tests

./tests/snapshot_format_tests
