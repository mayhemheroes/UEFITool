#!/usr/bin/env bash
# UEFITool/mayhem/build.sh — build the UEFI/FFS firmware-image parser fuzz surface.
#
# UEFITool is a C++ UEFI firmware-image parser. Everything it needs is vendored in-tree
# (zlib, brotli, LZMA, Tiano, bstrlib, kaitai) — no external libraries, NO Qt (the
# command-line tools and the fuzz harness build with USE_QT=OFF, the upstream default).
#
# Two Mayhem targets, both exercising the FFS / UEFI-volume parser (common/ffsparser.cpp):
#   (1) ffsparser_fuzzer  — upstream libFuzzer harness (fuzzing/ffsparser_fuzzer.cpp), which
#                           constructs an FfsParser and calls parse() on the raw input bytes.
#                           Built sanitized + libFuzzer, plus a -standalone run-once reproducer.
#   (2) uefiextract       — the UEFIExtract command-line tool (UEFIExtract/, USE_QT off). This
#                           is the OLD deployed file-input target `uefiextract_all`
#                           (cmd: UEFIExtract @@ all). Kept for parity + Mayhem history.
#
# Both reach FfsParser::parse() → performFirstPass → parseImage → parseRawArea, which scans
# for the FV `_FVH` signature (common/ffs.h: EFI_FV_SIGNATURE 0x4856465F at offset 0x28).
#
# The project sources are compiled WITH $SANITIZER_FLAGS (ASan+UBSan, halting by default) so
# the fuzzed parser code is instrumented — not just the harness.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit
# empty value (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (natural crash).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS: DWARF < 4 required (§6.2 item 10); clang-19 plain -g emits DWARF-5, so pin to -gdwarf-3.
# Overridable via --build-arg (e.g. empty for a no-debug build), threaded AFTER $SANITIZER_FLAGS.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS

cd "$SRC"

# The parser feature defines the fuzzer/extract targets compile with (mirrors the upstream
# CMakeLists for fuzzing/ and UEFIExtract/). USE_QT stays OFF — no Qt anywhere.
DEFS="-DU_ENABLE_NVRAM_PARSING_SUPPORT -DU_ENABLE_ME_PARSING_SUPPORT -DU_ENABLE_FIT_PARSING_SUPPORT -DU_ENABLE_GUID_DATABASE_SUPPORT"

# Common C/C++ sources shared by both targets (the parser library + all vendored deps), as listed
# in fuzzing/CMakeLists.txt and UEFIExtract/CMakeLists.txt. Compiled with $SANITIZER_FLAGS so the
# fuzzed code is instrumented.
PARSER_SRCS_CPP=(
  common/types.cpp common/descriptor.cpp common/guiddatabase.cpp common/ffs.cpp
  common/nvram.cpp common/nvramparser.cpp common/meparser.cpp common/ffsparser.cpp
  common/amd_microcode.cpp common/fitparser.cpp common/peimage.cpp common/treeitem.cpp
  common/treemodel.cpp common/utility.cpp common/ustring.cpp
  common/bstrlib/bstrwrap.cpp
  common/generated/ami_nvar.cpp common/generated/apple_sysf.cpp common/generated/dell_dvar.cpp
  common/generated/edk2_vss.cpp common/generated/edk2_vss2.cpp common/generated/edk2_ftw.cpp
  common/generated/insyde_fdc.cpp common/generated/insyde_fdm.cpp
  common/generated/ms_slic_marker.cpp common/generated/ms_slic_pubkey.cpp
  common/generated/phoenix_flm.cpp common/generated/phoenix_evsa.cpp
  common/generated/intel_acbp_v1.cpp common/generated/intel_acbp_v2.cpp
  common/generated/intel_keym_v1.cpp common/generated/intel_keym_v2.cpp
  common/generated/intel_acm.cpp common/kaitai/kaitaistream.cpp
)
PARSER_SRCS_C=(
  common/brotli/common/constants.c common/brotli/common/context.c
  common/brotli/common/dictionary.c common/brotli/common/platform.c
  common/brotli/common/shared_dictionary.c common/brotli/common/transform.c
  common/brotli/dec/bit_reader.c common/brotli/dec/decode.c common/brotli/dec/huffman.c
  common/brotli/dec/prefix.c common/brotli/dec/state.c common/brotli/dec/static_init.c
  common/LZMA/LzmaDecompress.c common/LZMA/SDK/C/Bra.c common/LZMA/SDK/C/Bra86.c
  common/LZMA/SDK/C/CpuArch.c common/LZMA/SDK/C/LzmaDec.c
  common/Tiano/EfiTianoDecompress.c
  common/bstrlib/bstrlib.c
  common/digest/sha1.c common/digest/sha256.c common/digest/sha512.c common/digest/sm3.c
  common/zlib/adler32.c common/zlib/compress.c common/zlib/crc32.c common/zlib/deflate.c
  common/zlib/gzclose.c common/zlib/gzlib.c common/zlib/gzread.c common/zlib/gzwrite.c
  common/zlib/inflate.c common/zlib/infback.c common/zlib/inftrees.c common/zlib/inffast.c
  common/zlib/trees.c common/zlib/uncompr.c common/zlib/zutil.c
)
CXXSTD="-std=c++11"

OBJDIR=/tmp/uefitool-obj
rm -rf "$OBJDIR"; mkdir -p "$OBJDIR"

compile_objs() {
  # compile_objs <out-suffix>  — compile the shared parser library to $OBJDIR/<src>.<suffix>.o,
  # echoing the object paths. Used twice (fuzzer vs uefiextract may need separate object sets only
  # if flags differ; here they share the same flags, so we compile once and reuse).
  :
}

echo "build.sh: compiling shared parser library ($SANITIZER_FLAGS $DEBUG_FLAGS)"
OBJS=()
i=0
for s in "${PARSER_SRCS_CPP[@]}"; do
  o="$OBJDIR/cpp_$i.o"; i=$((i+1))
  $CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $DEFS -Icommon -c "$s" -o "$o" &
  OBJS+=("$o")
  # Throttle parallel compiles to MAYHEM_JOBS.
  while [ "$(jobs -rp | wc -l)" -ge "$MAYHEM_JOBS" ]; do wait -n; done
done
for s in "${PARSER_SRCS_C[@]}"; do
  o="$OBJDIR/c_$i.o"; i=$((i+1))
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $DEFS -Icommon -c "$s" -o "$o" &
  OBJS+=("$o")
  while [ "$(jobs -rp | wc -l)" -ge "$MAYHEM_JOBS" ]; do wait -n; done
done
wait

# ---------------------------------------------------------------------------
# (1) libFuzzer harness: fuzzing/ffsparser_fuzzer.cpp -> /mayhem/ffsparser_fuzzer
#     plus a non-fuzzer run-once reproducer -> /mayhem/ffsparser_fuzzer-standalone
# ---------------------------------------------------------------------------
echo "build.sh: linking ffsparser_fuzzer (libFuzzer)"
$CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE $DEFS -Icommon \
    fuzzing/ffsparser_fuzzer.cpp "${OBJS[@]}" \
    -o /mayhem/ffsparser_fuzzer

# Standalone: compile the LLVM run-once driver as a C object first (the harness exports
# LLVMFuzzerTestOneInput with C linkage; clang++ would mangle the driver's reference to it).
echo "build.sh: linking ffsparser_fuzzer-standalone (run-once reproducer)"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJDIR/standalone_main.o"
$CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $DEFS -Icommon \
    fuzzing/ffsparser_fuzzer.cpp "${OBJS[@]}" "$OBJDIR/standalone_main.o" \
    -o /mayhem/ffsparser_fuzzer-standalone

# ---------------------------------------------------------------------------
# (2) UEFIExtract CLI (the OLD deployed file-input target `uefiextract_all`,
#     cmd: UEFIExtract @@ all). USE_QT off. -> /mayhem/UEFIExtract/UEFIExtract
#     Path kept identical to the old integration's Mayhemfile cmd for parity.
# ---------------------------------------------------------------------------
echo "build.sh: linking UEFIExtract CLI (file-input target)"
mkdir -p /mayhem/UEFIExtract
# UEFIExtract adds a few sources the fuzzer doesn't: its main + dumpers + ffsreport + filesystem.
$CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $DEFS -Icommon \
    UEFIExtract/uefiextract_main.cpp UEFIExtract/ffsdumper.cpp UEFIExtract/uefidump.cpp \
    common/ffsreport.cpp common/filesystem.cpp \
    "${OBJS[@]}" \
    -o /mayhem/UEFIExtract/UEFIExtract

# ---------------------------------------------------------------------------
# (3) TEST-ORACLE build of UEFIExtract — the project's NORMAL flags (no sanitizer), an
#     independent clean build so mayhem/test.sh stays an honest functional oracle and never
#     compiles. UEFITool ships no in-tree unit-test suite for this revision, so test.sh is a
#     golden-output harness: it runs THIS binary on a crafted FV and diffs the parsed report
#     against a checked-in expected report (asserts real parser behaviour — a no-op/exit(0)
#     "patch" cannot reproduce the FFSv2/Freeform/Raw-section tree, so it fails the oracle).
#     Built only when sanitizers are active (the off-switch reuses the single build).
echo "build.sh: building UEFIExtract test oracle (normal flags)"
TESTDIR=/mayhem/build-tests
mkdir -p "$TESTDIR/obj"
NORMAL_FLAGS="-O2 -g"
TOBJS=()
j=0
for s in "${PARSER_SRCS_CPP[@]}"; do
  o="$TESTDIR/obj/cpp_$j.o"; j=$((j+1))
  $CXX $CXXSTD $NORMAL_FLAGS $DEFS -Icommon -c "$s" -o "$o" &
  TOBJS+=("$o")
  while [ "$(jobs -rp | wc -l)" -ge "$MAYHEM_JOBS" ]; do wait -n; done
done
for s in "${PARSER_SRCS_C[@]}"; do
  o="$TESTDIR/obj/c_$j.o"; j=$((j+1))
  $CC $NORMAL_FLAGS $DEFS -Icommon -c "$s" -o "$o" &
  TOBJS+=("$o")
  while [ "$(jobs -rp | wc -l)" -ge "$MAYHEM_JOBS" ]; do wait -n; done
done
wait
$CXX $CXXSTD $NORMAL_FLAGS $DEFS -Icommon \
    UEFIExtract/uefiextract_main.cpp UEFIExtract/ffsdumper.cpp UEFIExtract/uefidump.cpp \
    common/ffsreport.cpp common/filesystem.cpp \
    "${TOBJS[@]}" \
    -o "$TESTDIR/UEFIExtract"

echo "build.sh: built targets:"
ls -l /mayhem/ffsparser_fuzzer /mayhem/ffsparser_fuzzer-standalone /mayhem/UEFIExtract/UEFIExtract "$TESTDIR/UEFIExtract"
