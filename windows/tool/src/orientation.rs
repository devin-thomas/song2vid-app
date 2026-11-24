//! Image orientation (SPEC section 26.3): the EXIF orientation tag, read from the file, and the
//! FFmpeg filters that turn the picture upright.
//!
//! The bundled FFmpeg can rotate by itself, but not for every input (it leaves HEIC tile grids
//! alone), so the command reads the tag and applies it with explicit filters. JPEG, PNG, TIFF and
//! WebP carry the tag as EXIF. HEIC carries it as a rotation and a mirror, which FFprobe reports as
//! a display matrix.

use std::fs::File;
use std::io::{Cursor, Read, Seek, SeekFrom};
use std::path::Path;

/// How far the file reads looking for the tag. JPEG, PNG and WebP keep their EXIF near the start.
const HEADER_READ_LIMIT: usize = 4 * 1024 * 1024;

/// One of the eight EXIF orientations. `Upright` is orientation 1.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Orientation {
    Upright,
    MirrorHorizontal,
    Rotate180,
    MirrorVertical,
    Transpose,
    Rotate90Clockwise,
    Transverse,
    Rotate90CounterClockwise,
}

impl Orientation {
    /// The orientation for an EXIF value. Anything but 1 to 8 is upright, as the Mac reader treats it.
    pub fn from_exif(value: u16) -> Orientation {
        match value {
            2 => Orientation::MirrorHorizontal,
            3 => Orientation::Rotate180,
            4 => Orientation::MirrorVertical,
            5 => Orientation::Transpose,
            6 => Orientation::Rotate90Clockwise,
            7 => Orientation::Transverse,
            8 => Orientation::Rotate90CounterClockwise,
            _ => Orientation::Upright,
        }
    }

    /// True when the picture is turned a quarter, so its width and height trade places.
    pub fn swaps_sides(self) -> bool {
        match self {
            Orientation::Transpose
            | Orientation::Rotate90Clockwise
            | Orientation::Transverse
            | Orientation::Rotate90CounterClockwise => true,
            Orientation::Upright
            | Orientation::MirrorHorizontal
            | Orientation::Rotate180
            | Orientation::MirrorVertical => false,
        }
    }

    /// The FFmpeg filters that make the picture upright, or None when it already is.
    pub fn filter(self) -> Option<&'static str> {
        match self {
            Orientation::Upright => None,
            Orientation::MirrorHorizontal => Some("hflip"),
            Orientation::Rotate180 => Some("hflip,vflip"),
            Orientation::MirrorVertical => Some("vflip"),
            Orientation::Transpose => Some("transpose=0"),
            Orientation::Rotate90Clockwise => Some("transpose=1"),
            Orientation::Transverse => Some("transpose=3"),
            Orientation::Rotate90CounterClockwise => Some("transpose=2"),
        }
    }

    /// The orientation a display matrix stands for. FFprobe writes the matrix as three lines of
    /// 16.16 numbers; only the top-left 2x2 block matters, and its entries are 0 or one in size.
    pub fn from_display_matrix(text: &str) -> Orientation {
        let mut rows: Vec<Vec<i64>> = Vec::new();
        for line in text.lines() {
            let Some((_, numbers)) = line.split_once(':') else {
                continue;
            };
            let parsed: Vec<i64> = numbers
                .split_whitespace()
                .filter_map(|token: &str| -> Option<i64> { token.parse::<i64>().ok() })
                .collect();
            rows.push(parsed);
        }
        if rows.len() < 2 || rows[0].len() < 2 || rows[1].len() < 2 {
            return Orientation::Upright;
        }
        let signs: [i64; 4] = [rows[0][0], rows[0][1], rows[1][0], rows[1][1]]
            .map(|value: i64| -> i64 { value.signum() });
        match signs {
            [-1, 0, 0, 1] => Orientation::MirrorHorizontal,
            [-1, 0, 0, -1] => Orientation::Rotate180,
            [1, 0, 0, -1] => Orientation::MirrorVertical,
            [0, 1, 1, 0] => Orientation::Transpose,
            [0, 1, -1, 0] => Orientation::Rotate90Clockwise,
            [0, -1, -1, 0] => Orientation::Transverse,
            [0, -1, 1, 0] => Orientation::Rotate90CounterClockwise,
            _ => Orientation::Upright,
        }
    }
}

/// Reads the orientation tag of a JPEG, PNG, TIFF or WebP file. Any other file, a file without the
/// tag, and a file that can't be read are upright.
pub fn read_from_file(path: &Path) -> Orientation {
    let Ok(mut file) = File::open(path) else {
        return Orientation::Upright;
    };
    let mut magic: [u8; 12] = [0; 12];
    let Ok(count) = file.read(&mut magic) else {
        return Orientation::Upright;
    };
    if count < 8 {
        return Orientation::Upright;
    }
    if file.seek(SeekFrom::Start(0)).is_err() {
        return Orientation::Upright;
    }
    let tag: Option<u16> = if magic.starts_with(&[0xFF, 0xD8]) {
        read_prefix(&mut file)
            .and_then(|bytes: Vec<u8>| -> Option<u16> { jpeg_exif_orientation(&bytes) })
    } else if magic.starts_with(&[0x89, b'P', b'N', b'G']) {
        read_prefix(&mut file)
            .and_then(|bytes: Vec<u8>| -> Option<u16> { png_exif_orientation(&bytes) })
    } else if magic.starts_with(b"RIFF") && &magic[8..12] == b"WEBP" {
        read_prefix(&mut file)
            .and_then(|bytes: Vec<u8>| -> Option<u16> { webp_exif_orientation(&bytes) })
    } else if magic.starts_with(b"II*\0") || magic.starts_with(b"MM\0*") {
        tiff_orientation(&mut file)
    } else {
        None
    };
    tag.map_or(Orientation::Upright, Orientation::from_exif)
}

fn read_prefix(file: &mut File) -> Option<Vec<u8>> {
    let mut bytes: Vec<u8> = Vec::new();
    file.take(HEADER_READ_LIMIT as u64)
        .read_to_end(&mut bytes)
        .ok()?;
    Some(bytes)
}

/// The orientation in the first Exif segment of a JPEG.
pub fn jpeg_exif_orientation(bytes: &[u8]) -> Option<u16> {
    let mut at: usize = 2;
    while at + 4 <= bytes.len() {
        if bytes[at] != 0xFF {
            return None;
        }
        let marker: u8 = bytes[at + 1];
        // Padding bytes and markers without a length.
        if marker == 0xFF {
            at += 1;
            continue;
        }
        if marker == 0x01 || (0xD0..=0xD8).contains(&marker) {
            at += 2;
            continue;
        }
        // Start of scan or end of image: the headers are over.
        if marker == 0xDA || marker == 0xD9 {
            return None;
        }
        let length: usize = usize::from(bytes[at + 2]) << 8 | usize::from(bytes[at + 3]);
        if length < 2 || at + 2 + length > bytes.len() {
            return None;
        }
        let segment: &[u8] = &bytes[at + 4..at + 2 + length];
        if marker == 0xE1 && segment.starts_with(b"Exif\0\0") {
            return tiff_orientation(&mut Cursor::new(&segment[6..]));
        }
        at += 2 + length;
    }
    None
}

/// The orientation in the `eXIf` chunk of a PNG.
pub fn png_exif_orientation(bytes: &[u8]) -> Option<u16> {
    let mut at: usize = 8;
    while at + 8 <= bytes.len() {
        let length: usize = usize::try_from(u32::from_be_bytes([
            bytes[at],
            bytes[at + 1],
            bytes[at + 2],
            bytes[at + 3],
        ]))
        .ok()?;
        let kind: &[u8] = &bytes[at + 4..at + 8];
        if kind == b"IDAT" || kind == b"IEND" {
            return None;
        }
        let end: usize = at.checked_add(8)?.checked_add(length)?;
        if end > bytes.len() {
            return None;
        }
        if kind == b"eXIf" {
            return tiff_orientation(&mut Cursor::new(&bytes[at + 8..end]));
        }
        at = end.checked_add(4)?;
    }
    None
}

/// The orientation in the `EXIF` chunk of a WebP.
pub fn webp_exif_orientation(bytes: &[u8]) -> Option<u16> {
    let mut at: usize = 12;
    while at + 8 <= bytes.len() {
        let length: usize = usize::try_from(u32::from_le_bytes([
            bytes[at + 4],
            bytes[at + 5],
            bytes[at + 6],
            bytes[at + 7],
        ]))
        .ok()?;
        let end: usize = at.checked_add(8)?.checked_add(length)?;
        if end > bytes.len() {
            return None;
        }
        if &bytes[at..at + 4] == b"EXIF" {
            let payload: &[u8] = &bytes[at + 8..end];
            let tiff: &[u8] = payload.strip_prefix(b"Exif\0\0").unwrap_or(payload);
            return tiff_orientation(&mut Cursor::new(tiff));
        }
        // Chunks are padded to an even size.
        at = end.checked_add(length % 2)?;
    }
    None
}

/// The Orientation entry (tag 0x0112) of the first directory of a TIFF structure.
pub fn tiff_orientation<R: Read + Seek>(reader: &mut R) -> Option<u16> {
    reader.seek(SeekFrom::Start(0)).ok()?;
    let mut header: [u8; 8] = [0; 8];
    reader.read_exact(&mut header).ok()?;
    let little: bool = match &header[0..2] {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let read_u16 = |bytes: [u8; 2]| -> u16 {
        if little {
            u16::from_le_bytes(bytes)
        } else {
            u16::from_be_bytes(bytes)
        }
    };
    let read_u32 = |bytes: [u8; 4]| -> u32 {
        if little {
            u32::from_le_bytes(bytes)
        } else {
            u32::from_be_bytes(bytes)
        }
    };
    if read_u16([header[2], header[3]]) != 42 {
        return None;
    }
    let directory: u64 = u64::from(read_u32([header[4], header[5], header[6], header[7]]));
    reader.seek(SeekFrom::Start(directory)).ok()?;
    let mut count_bytes: [u8; 2] = [0; 2];
    reader.read_exact(&mut count_bytes).ok()?;
    let count: u16 = read_u16(count_bytes);
    for _ in 0..count {
        let mut entry: [u8; 12] = [0; 12];
        reader.read_exact(&mut entry).ok()?;
        if read_u16([entry[0], entry[1]]) == 0x0112 {
            // A SHORT with one value sits in the first two bytes of the value field.
            return Some(read_u16([entry[8], entry[9]]));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tiff_with_orientation(little: bool, value: u16) -> Vec<u8> {
        let short = |number: u16| -> [u8; 2] {
            if little {
                number.to_le_bytes()
            } else {
                number.to_be_bytes()
            }
        };
        let long = |number: u32| -> [u8; 4] {
            if little {
                number.to_le_bytes()
            } else {
                number.to_be_bytes()
            }
        };
        let mut bytes: Vec<u8> = Vec::new();
        bytes.extend_from_slice(if little { b"II" } else { b"MM" });
        bytes.extend_from_slice(&short(42));
        bytes.extend_from_slice(&long(8));
        bytes.extend_from_slice(&short(2));
        // A different entry first, then the orientation.
        bytes.extend_from_slice(&short(0x0100));
        bytes.extend_from_slice(&short(3));
        bytes.extend_from_slice(&long(1));
        bytes.extend_from_slice(&short(300));
        bytes.extend_from_slice(&[0, 0]);
        bytes.extend_from_slice(&short(0x0112));
        bytes.extend_from_slice(&short(3));
        bytes.extend_from_slice(&long(1));
        bytes.extend_from_slice(&short(value));
        bytes.extend_from_slice(&[0, 0]);
        bytes
    }

    #[test]
    fn a_tiff_directory_gives_its_orientation_in_either_byte_order() {
        for little in [true, false] {
            let bytes: Vec<u8> = tiff_with_orientation(little, 6);
            assert_eq!(tiff_orientation(&mut Cursor::new(bytes)), Some(6));
        }
        assert_eq!(
            tiff_orientation(&mut Cursor::new(b"not a tiff at all".to_vec())),
            None
        );
    }

    #[test]
    fn jpeg_png_and_webp_carry_the_tiff_block() {
        let tiff: Vec<u8> = tiff_with_orientation(false, 8);

        let mut jpeg: Vec<u8> = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00];
        let mut exif: Vec<u8> = b"Exif\0\0".to_vec();
        exif.extend_from_slice(&tiff);
        jpeg.extend_from_slice(&[0xFF, 0xE1]);
        jpeg.extend_from_slice(&((exif.len() + 2) as u16).to_be_bytes());
        jpeg.extend_from_slice(&exif);
        jpeg.extend_from_slice(&[0xFF, 0xDA, 0x00, 0x02]);
        assert_eq!(jpeg_exif_orientation(&jpeg), Some(8));

        let mut png: Vec<u8> = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
        png.extend_from_slice(&13u32.to_be_bytes());
        png.extend_from_slice(b"IHDR");
        png.extend_from_slice(&[0; 13]);
        png.extend_from_slice(&[0; 4]);
        png.extend_from_slice(&(tiff.len() as u32).to_be_bytes());
        png.extend_from_slice(b"eXIf");
        png.extend_from_slice(&tiff);
        png.extend_from_slice(&[0; 4]);
        png.extend_from_slice(&0u32.to_be_bytes());
        png.extend_from_slice(b"IDAT");
        assert_eq!(png_exif_orientation(&png), Some(8));

        let mut webp: Vec<u8> = b"RIFF\0\0\0\0WEBP".to_vec();
        webp.extend_from_slice(b"EXIF");
        webp.extend_from_slice(&(tiff.len() as u32).to_le_bytes());
        webp.extend_from_slice(&tiff);
        assert_eq!(webp_exif_orientation(&webp), Some(8));
    }

    #[test]
    fn a_picture_without_the_tag_or_with_a_bad_value_is_upright() {
        assert_eq!(jpeg_exif_orientation(&[0xFF, 0xD8, 0xFF, 0xDA, 0, 2]), None);
        assert_eq!(Orientation::from_exif(0), Orientation::Upright);
        assert_eq!(Orientation::from_exif(9), Orientation::Upright);
    }

    #[test]
    fn quarter_turns_swap_the_sides() {
        let swapping: Vec<u16> = (1..=8)
            .filter(|value: &u16| -> bool { Orientation::from_exif(*value).swaps_sides() })
            .collect();
        assert_eq!(swapping, vec![5, 6, 7, 8]);
    }

    #[test]
    fn display_matrices_map_back_to_the_orientation() {
        let matrix = |a: i64, b: i64, c: i64, d: i64| -> String {
            format!("\n00000000: {a:>12} {b:>12} 0\n00000001: {c:>12} {d:>12} 0\n00000002: 0 0 1073741824\n")
        };
        assert_eq!(
            Orientation::from_display_matrix(&matrix(0, 65536, -65536, 0)),
            Orientation::Rotate90Clockwise
        );
        assert_eq!(
            Orientation::from_display_matrix(&matrix(0, -65536, 65536, 0)),
            Orientation::Rotate90CounterClockwise
        );
        assert_eq!(
            Orientation::from_display_matrix(&matrix(-65536, 0, 0, 65536)),
            Orientation::MirrorHorizontal
        );
        assert_eq!(
            Orientation::from_display_matrix(&matrix(65536, 0, 0, 65536)),
            Orientation::Upright
        );
        assert_eq!(
            Orientation::from_display_matrix("garbage"),
            Orientation::Upright
        );
    }
}
