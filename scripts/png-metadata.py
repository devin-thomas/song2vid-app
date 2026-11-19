#!/usr/bin/env python3
"""Prints the text a PNG carries besides its picture (text chunks, EXIF, and any other ancillary chunk).

Used by safety-scan.sh: the picture data of a PNG is compressed noise that sometimes looks like an email address or a
path by chance, so only the chunks that can hold a name or a path are read. Exits 1 if the file is not a PNG.
"""
import re
import struct
import sys
import zlib

PICTURE_CHUNKS = {b"IHDR", b"PLTE", b"IDAT", b"IEND"}


def printable_runs(data, minimum=4):
    return [run.decode("latin-1") for run in re.findall(rb"[\x20-\x7e]{%d,}" % minimum, data)]


def main(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return 1
    position = 8
    while position + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[position:position + 8])
        body = data[position + 8:position + 8 + length]
        position += 12 + length
        if kind in PICTURE_CHUNKS:
            continue
        if kind == b"tEXt":
            print(body.decode("latin-1", "replace").replace("\0", ": "))
        elif kind == b"zTXt":
            key, _, rest = body.partition(b"\0")
            try:
                print(key.decode("latin-1") + ": " + zlib.decompress(rest[1:]).decode("utf-8", "replace"))
            except zlib.error:
                print(key.decode("latin-1"))
        elif kind == b"iTXt":
            key, _, rest = body.partition(b"\0")
            flag = rest[0:1]
            rest = rest[2:]
            _, _, rest = rest.partition(b"\0")  # language tag
            _, _, text = rest.partition(b"\0")  # translated keyword
            if flag == b"\x01":
                try:
                    text = zlib.decompress(text)
                except zlib.error:
                    text = b""
            print(key.decode("latin-1") + ": " + text.decode("utf-8", "replace"))
        else:
            print(kind.decode("latin-1"))
            for run in printable_runs(body):
                print(run)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
