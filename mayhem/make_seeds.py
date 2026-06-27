#!/usr/bin/env python3
"""Generate a small UEFI/FFS seed corpus for UEFITool's FfsParser.

Each seed is a valid EFI Firmware Volume so the parser reaches FfsParser::parse ->
performFirstPass -> parseImage -> parseRawArea -> parseVolumeHeader (common/ffsparser.cpp).
The FV is recognised by the `_FVH` signature (0x4856465F at offset 0x28) and the
FileSystemGuid at offset 16 (see common/ffs.h, common/ffs.cpp).

Layout of EFI_FIRMWARE_VOLUME_HEADER (common/ffs.h):
  0x00 ZeroVector[16]
  0x10 FileSystemGuid (EFI_GUID, 16 bytes)
  0x20 FvLength (u64)
  0x28 Signature  (u32, '_FVH' = 0x4856465F)
  0x2C Attributes (u32)
  0x30 HeaderLength (u16)
  0x32 Checksum (u16)
  0x34 ExtHeaderOffset (u16)
  0x36 Reserved (u8)
  0x37 Revision (u8)
  0x38 FvBlockMap[] : {NumBlocks u32, Length u32} ... terminated by {0,0}
"""
import struct, sys, os

# Standard file-system GUIDs, raw bytes exactly as in common/ffs.cpp.
FFS2_GUID = bytes.fromhex("78E58C8C3D8A1C4F99358961" "85C32DD3")  # 8C8CE578-8A3D-4F1C-9935-896185C32DD3
FFS3_GUID = bytes.fromhex("7AC07354CB3DCA4DBD6F1E96" "89E7349A")  # 5473C07A-3DCB-4DCA-BD6F-1E9689E7349A

FV_SIGNATURE = 0x4856465F  # '_FVH'
HEADER_LEN = 0x48          # header + one block-map entry + terminator (aligned)

# FFS file types / states (common/ffs.h)
EFI_FV_FILETYPE_RAW = 0x01
EFI_FV_FILETYPE_FREEFORM = 0x02
EFI_FILE_DATA_VALID = 0x04
EFI_FILE_HEADER_VALID = 0x02
EFI_FILE_HEADER_CONSTRUCTION = 0x01
# Section types
EFI_SECTION_RAW = 0x19


def fv_header(fs_guid, fv_len, revision=2, attributes=0x000A0000 | 0x800):
    # attributes: a sane alignment + ERASE_POLARITY set (empty byte 0xFF)
    h = bytearray()
    h += b"\x00" * 16                       # ZeroVector
    h += fs_guid                            # FileSystemGuid
    h += struct.pack("<Q", fv_len)          # FvLength
    h += struct.pack("<I", FV_SIGNATURE)    # Signature
    h += struct.pack("<I", attributes)      # Attributes
    h += struct.pack("<H", HEADER_LEN)      # HeaderLength
    h += struct.pack("<H", 0)               # Checksum (parser warns but continues)
    h += struct.pack("<H", 0)               # ExtHeaderOffset (none)
    h += struct.pack("<B", 0)               # Reserved
    h += struct.pack("<B", revision)        # Revision
    # Block map: one entry covering the whole volume, then terminator {0,0}.
    block_size = 0x1000
    num_blocks = (fv_len + block_size - 1) // block_size
    h += struct.pack("<II", num_blocks, block_size)
    h += struct.pack("<II", 0, 0)
    assert len(h) == HEADER_LEN, len(h)
    return bytes(h)


def ffs_file(name_guid, ftype, body):
    # EFI_FFS_FILE_HEADER (24 bytes): Name(16) IntegrityCheck(2) Type(1) Attributes(1) Size[3] State(1)
    size = 24 + len(body)
    hdr = bytearray()
    hdr += name_guid
    hdr += struct.pack("<H", 0xAAAA)        # IntegrityCheck (not verified strictly)
    hdr += struct.pack("<B", ftype)
    hdr += struct.pack("<B", 0x00)          # Attributes
    hdr += struct.pack("<BBB", size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF)
    hdr += struct.pack("<B", EFI_FILE_DATA_VALID | EFI_FILE_HEADER_VALID)  # State
    return bytes(hdr) + body


def raw_section(data):
    # EFI_COMMON_SECTION_HEADER: Size[3] Type(1)
    size = 4 + len(data)
    hdr = struct.pack("<BBB", size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF)
    hdr += struct.pack("<B", EFI_SECTION_RAW)
    return hdr + data


def pad_to(buf, total, fill=b"\xff"):
    if len(buf) < total:
        buf = buf + fill * (total - len(buf))
    return buf


def build_fv(fs_guid, body, total, revision=2):
    hdr = fv_header(fs_guid, total, revision=revision)
    raw = bytearray(hdr) + body
    return pad_to(bytes(raw), total)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__)) + "/testsuite"
    os.makedirs(outdir, exist_ok=True)
    A_GUID = bytes.fromhex("01020304" "0506" "0708" "090A0B0C0D0E0F10")  # arbitrary file name GUID

    seeds = {}

    # 1) Minimal valid FFSv2 firmware volume (header only, padded). Reaches parseVolumeHeader,
    #    recognised as FFSv2.
    seeds["fv_ffs2_empty.fd"] = build_fv(FFS2_GUID, b"", 0x1000)

    # 2) FFSv2 FV containing one RAW FFS file with a RAW section — exercises parseFileHeader /
    #    parseSections beyond the volume header.
    sec = raw_section(b"HELLO-UEFI-RAW-SECTION")
    f = ffs_file(A_GUID, EFI_FV_FILETYPE_FREEFORM, sec)
    seeds["fv_ffs2_file_section.fd"] = build_fv(FFS2_GUID, f, 0x2000)

    # 3) FFSv2 FV with a RAW-type file (no sections) — different file-type path.
    f2 = ffs_file(A_GUID, EFI_FV_FILETYPE_RAW, b"RAWFILEPAYLOAD")
    seeds["fv_ffs2_raw_file.fd"] = build_fv(FFS2_GUID, f2, 0x2000)

    # 4) FFSv3 firmware volume (different FileSystemGuid → ffsVersion 3 path).
    seeds["fv_ffs3_empty.fd"] = build_fv(FFS3_GUID, b"", 0x1000)

    for name, data in seeds.items():
        with open(os.path.join(outdir, name), "wb") as fh:
            fh.write(data)
        print(f"wrote {name}: {len(data)} bytes")


if __name__ == "__main__":
    main()
