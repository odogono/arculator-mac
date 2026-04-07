#!/bin/sh
set -eu

SRCROOT="${1:?missing src root}"
RESOURCES_ROOT="${2:?missing resources root}"

CC="$(xcrun --sdk macosx --find clang)"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
PODULES_OUT="$RESOURCES_ROOT/podules"

COMMON_FLAGS="
  -fPIC
  -dynamiclib
  -D_FILE_OFFSET_BITS=64
  -isysroot
  $SDKROOT
  -include stdio.h
  -include stdlib.h
  -include string.h
  -include unistd.h
  -I$SRCROOT/src
  -I$SRCROOT/podules/common/adc
  -I$SRCROOT/podules/common/cdrom
  -I$SRCROOT/podules/common/eeprom
  -I$SRCROOT/podules/common/joystick
  -I$SRCROOT/podules/common/midi
  -I$SRCROOT/podules/common/misc
  -I$SRCROOT/podules/common/net
  -I$SRCROOT/podules/common/net/slirp
  -I$SRCROOT/podules/common/scsi
  -I$SRCROOT/podules/common/sound
  -I$SRCROOT/podules/common/uart
"

COMMON_LDFLAGS="
  -framework AudioToolbox
  -framework Foundation
  -framework GameController
  -framework IOKit
  -lm
  -lz
"

copy_podule_assets() {
	name="$1"
	outdir="$PODULES_OUT/$name"

	rm -rf "$outdir"
	mkdir -p "$outdir"

	find "$SRCROOT/podules/$name" -maxdepth 1 -type f ! -name '*.dylib' ! -name '.DS_Store' -exec cp {} "$outdir/" ';'
}

build_podule() {
	name="$1"
	shift

	copy_podule_assets "$name"
	outdir="$PODULES_OUT/$name"

	# shellcheck disable=SC2086
	"$CC" $COMMON_FLAGS "$@" -o "$outdir/$name.dylib" $COMMON_LDFLAGS
}

rm -rf "$PODULES_OUT"
mkdir -p "$PODULES_OUT"

NET_SLIRP_SOURCES="
	$SRCROOT/podules/common/net/net.c
	$SRCROOT/podules/common/net/net_slirp.c
	$SRCROOT/podules/common/net/slirp/bootp.c
	$SRCROOT/podules/common/net/slirp/cksum.c
	$SRCROOT/podules/common/net/slirp/debug.c
	$SRCROOT/podules/common/net/slirp/if.c
	$SRCROOT/podules/common/net/slirp/ip_icmp.c
	$SRCROOT/podules/common/net/slirp/ip_input.c
	$SRCROOT/podules/common/net/slirp/ip_output.c
	$SRCROOT/podules/common/net/slirp/mbuf.c
	$SRCROOT/podules/common/net/slirp/misc.c
	$SRCROOT/podules/common/net/slirp/queue.c
	$SRCROOT/podules/common/net/slirp/sbuf.c
	$SRCROOT/podules/common/net/slirp/slirp.c
	$SRCROOT/podules/common/net/slirp/socket.c
	$SRCROOT/podules/common/net/slirp/tcp_input.c
	$SRCROOT/podules/common/net/slirp/tcp_output.c
	$SRCROOT/podules/common/net/slirp/tcp_subr.c
	$SRCROOT/podules/common/net/slirp/tcp_timer.c
	$SRCROOT/podules/common/net/slirp/tftp.c
	$SRCROOT/podules/common/net/slirp/udp.c
"

# shellcheck disable=SC2086
build_podule aeh50 \
	"$SRCROOT/podules/aeh50/src/aeh50.c" \
	"$SRCROOT/podules/common/net/ne2000.c" \
	$NET_SLIRP_SOURCES

# shellcheck disable=SC2086
build_podule aeh54 \
	"$SRCROOT/podules/aeh54/src/aeh54.c" \
	"$SRCROOT/podules/aeh54/src/seeq8005.c" \
	$NET_SLIRP_SOURCES

build_podule aka05 \
	"$SRCROOT/podules/aka05/src/aka05.c"

build_podule aka10 \
	"$SRCROOT/podules/common/uart/6850.c" \
	"$SRCROOT/podules/aka10/src/aka10.c" \
	"$SRCROOT/podules/common/joystick/joystick_gamecontroller.m" \
	"$SRCROOT/podules/common/adc/d7002c.c" \
	"$SRCROOT/podules/common/misc/6522.c" \
	"$SRCROOT/podules/common/midi/midi_null.c"

build_podule aka12 \
	"$SRCROOT/podules/common/misc/6522.c" \
	"$SRCROOT/podules/common/uart/scc2691.c" \
	"$SRCROOT/podules/aka12/src/aka12.c" \
	"$SRCROOT/podules/common/midi/midi_null.c"

build_podule aka16 \
	"$SRCROOT/podules/common/uart/scc2691.c" \
	"$SRCROOT/podules/aka16/src/aka16.c" \
	"$SRCROOT/podules/common/midi/midi_null.c"

build_podule aka31 \
	"$SRCROOT/podules/aka31/src/aka31.c" \
	"$SRCROOT/podules/aka31/src/d71071l.c" \
	"$SRCROOT/podules/common/scsi/hdd_file.c" \
	"$SRCROOT/podules/common/scsi/scsi.c" \
	"$SRCROOT/podules/common/scsi/scsi_cd.c" \
	"$SRCROOT/podules/common/scsi/scsi_config.c" \
	"$SRCROOT/podules/common/scsi/scsi_hd.c" \
	"$SRCROOT/podules/aka31/src/wd33c93a.c" \
	"$SRCROOT/podules/common/sound/sound_out_coreaudio.m" \
	"$SRCROOT/podules/common/cdrom/cdrom-osx-ioctl.c"

# shellcheck disable=SC2086
build_podule designit_e200 \
	"$SRCROOT/podules/designit_e200/src/designit_e200.c" \
	"$SRCROOT/podules/common/net/ne2000.c" \
	$NET_SLIRP_SOURCES

build_podule lark \
	"$SRCROOT/podules/common/uart/16550.c" \
	"$SRCROOT/podules/lark/src/ad1848.c" \
	"$SRCROOT/podules/lark/src/am7202a.c" \
	"$SRCROOT/podules/lark/src/lark.c" \
	"$SRCROOT/podules/common/midi/midi_null.c" \
	"$SRCROOT/podules/common/sound/sound_in_null.c" \
	"$SRCROOT/podules/common/sound/sound_out_coreaudio.m"

build_podule midimax \
	"$SRCROOT/podules/common/uart/16550.c" \
	"$SRCROOT/podules/midimax/src/midimax.c" \
	"$SRCROOT/podules/common/midi/midi_null.c"

build_podule morley_uap \
	"$SRCROOT/podules/morley_uap/src/morley_uap.c" \
	"$SRCROOT/podules/common/joystick/joystick_gamecontroller.m" \
	"$SRCROOT/podules/common/adc/d7002c.c" \
	"$SRCROOT/podules/common/misc/6522.c"

build_podule oak_scsi \
	"$SRCROOT/podules/oak_scsi/src/oak_scsi.c" \
	"$SRCROOT/podules/oak_scsi/src/ncr5380.c" \
	"$SRCROOT/podules/common/scsi/hdd_file.c" \
	"$SRCROOT/podules/common/scsi/scsi.c" \
	"$SRCROOT/podules/common/scsi/scsi_cd.c" \
	"$SRCROOT/podules/common/scsi/scsi_config.c" \
	"$SRCROOT/podules/common/scsi/scsi_hd.c" \
	"$SRCROOT/podules/common/sound/sound_out_coreaudio.m" \
	"$SRCROOT/podules/common/eeprom/93c06.c" \
	"$SRCROOT/podules/common/cdrom/cdrom-osx-ioctl.c"

build_podule pccard \
	"$SRCROOT/podules/pccard/src/pccard_podule.c" \
	"$SRCROOT/podules/pccard/src/pcem/808x.c" \
	"$SRCROOT/podules/pccard/src/pcem/386.c" \
	"$SRCROOT/podules/pccard/src/pcem/386_common.c" \
	"$SRCROOT/podules/pccard/src/pcem/386_dynarec.c" \
	"$SRCROOT/podules/pccard/src/pcem/cpu.c" \
	"$SRCROOT/podules/pccard/src/pcem/cpu_tables.c" \
	"$SRCROOT/podules/pccard/src/pcem/diva.c" \
	"$SRCROOT/podules/pccard/src/pcem/dma.c" \
	"$SRCROOT/podules/pccard/src/pcem/io.c" \
	"$SRCROOT/podules/pccard/src/pcem/lpt.c" \
	"$SRCROOT/podules/pccard/src/pcem/mem.c" \
	"$SRCROOT/podules/pccard/src/pcem/pc.c" \
	"$SRCROOT/podules/pccard/src/pcem/pic.c" \
	"$SRCROOT/podules/pccard/src/pcem/pit.c" \
	"$SRCROOT/podules/pccard/src/pcem/scamp.c" \
	"$SRCROOT/podules/pccard/src/pcem/serial.c" \
	"$SRCROOT/podules/pccard/src/pcem/timer.c" \
	"$SRCROOT/podules/pccard/src/pcem/x86seg.c" \
	"$SRCROOT/podules/pccard/src/pcem/x87.c" \
	"$SRCROOT/podules/pccard/src/pcem/x87_timings.c" \
	"$SRCROOT/podules/pccard/src/libco/libco.c"

build_podule ultimatecdrom \
	"$SRCROOT/podules/ultimatecdrom/src/mitsumi.c" \
	"$SRCROOT/podules/ultimatecdrom/src/ultimatecdrom.c" \
	"$SRCROOT/podules/common/sound/sound_out_coreaudio.m" \
	"$SRCROOT/podules/common/cdrom/cdrom-osx-ioctl.c"
