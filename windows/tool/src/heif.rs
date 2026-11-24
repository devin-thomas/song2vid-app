//! The orientation of a HEIC picture, read from its boxes (SPEC section 26.3).
//!
//! HEIC stores a turn as an `irot` property (quarter turns anticlockwise) and a mirror as an `imir`
//! property, attached to the primary item. FFprobe 8.1 reports them as a display matrix for a plain
//! picture but not for a tile grid, so the command reads the two properties itself. A property only
//! counts for the item it is attached to, through the `ipma` table.

use std::fs::File;
use std::io::Read;
use std::path::Path;

use crate::orientation::Orientation;

/// The file's first bytes, which hold the `meta` box.
const HEADER_READ_LIMIT: u64 = 4 * 1024 * 1024;

/// Where the four corners of the stored picture end up once it is shown: row by row, 0 is the
/// stored top left, 1 top right, 2 bottom left, 3 bottom right.
type Corners = [[u8; 2]; 2];

const UPRIGHT: Corners = [[0, 1], [2, 3]];

/// One property of the primary item that changes how the picture is shown.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Transform {
    /// Quarter turns anticlockwise, 0 to 3.
    Turn(u8),
    /// Mirror left to right (about a vertical axis).
    MirrorAcross,
    /// Mirror top to bottom (about a horizontal axis).
    MirrorDown,
}

/// The orientation of the primary item of a HEIC file, or None when the file has no readable
/// `meta` box with a primary item.
pub fn read_from_file(path: &Path) -> Option<Orientation> {
    let mut bytes: Vec<u8> = Vec::new();
    File::open(path)
        .ok()?
        .take(HEADER_READ_LIMIT)
        .read_to_end(&mut bytes)
        .ok()?;
    orientation_of_primary(&bytes)
}

pub fn orientation_of_primary(bytes: &[u8]) -> Option<Orientation> {
    let meta: &[u8] = find_box(bytes, b"meta")?;
    // `meta` is a full box: four bytes of version and flags come before its children.
    let children: &[u8] = meta.get(4..)?;
    let primary: u32 = primary_item(find_box(children, b"pitm")?)?;
    let properties: &[u8] = find_box(children, b"iprp")?;
    let property_boxes: Vec<(&[u8], &[u8])> = list_boxes(find_box(properties, b"ipco")?);
    let associated: Vec<usize> = associations(find_box(properties, b"ipma")?, primary)?;

    let mut corners: Corners = UPRIGHT;
    for index in associated {
        // Property indexes count from one.
        let Some((kind, payload)) = index
            .checked_sub(1)
            .and_then(|at: usize| -> Option<&(&[u8], &[u8])> { property_boxes.get(at) })
        else {
            continue;
        };
        let value: u8 = payload.first().copied().unwrap_or(0);
        let transform: Option<Transform> = match *kind {
            b"irot" => Some(Transform::Turn(value & 3)),
            // The axis bit as ImageIO writes it and FFmpeg reads it: 0 swaps top and bottom, 1 swaps
            // left and right (checked against the Mac reader on all eight orientations).
            b"imir" => Some(if value & 1 == 0 {
                Transform::MirrorDown
            } else {
                Transform::MirrorAcross
            }),
            _ => None,
        };
        if let Some(transform) = transform {
            corners = apply(corners, transform);
        }
    }
    Some(orientation_of(corners))
}

fn apply(corners: Corners, transform: Transform) -> Corners {
    let [[a, b], [c, d]] = corners;
    match transform {
        Transform::Turn(quarters) => {
            let mut turned: Corners = corners;
            for _ in 0..quarters {
                let [[a, b], [c, d]] = turned;
                turned = [[b, d], [a, c]];
            }
            turned
        }
        Transform::MirrorAcross => [[b, a], [d, c]],
        Transform::MirrorDown => [[c, d], [a, b]],
    }
}

/// The EXIF orientation that arranges the stored corners this way.
fn orientation_of(corners: Corners) -> Orientation {
    match corners {
        [[1, 0], [3, 2]] => Orientation::MirrorHorizontal,
        [[3, 2], [1, 0]] => Orientation::Rotate180,
        [[2, 3], [0, 1]] => Orientation::MirrorVertical,
        [[0, 2], [1, 3]] => Orientation::Transpose,
        [[2, 0], [3, 1]] => Orientation::Rotate90Clockwise,
        [[3, 1], [2, 0]] => Orientation::Transverse,
        [[1, 3], [0, 2]] => Orientation::Rotate90CounterClockwise,
        _ => Orientation::Upright,
    }
}

/// The payload of the first box of this kind among `bytes`, which holds sibling boxes.
fn find_box<'a>(bytes: &'a [u8], kind: &[u8; 4]) -> Option<&'a [u8]> {
    list_boxes(bytes)
        .into_iter()
        .find(|(found, _payload): &(&[u8], &[u8])| -> bool { *found == kind })
        .map(|(_found, payload): (&[u8], &[u8])| -> &[u8] { payload })
}

/// Every box among `bytes`, as its kind and payload. A box that does not fit ends the list.
fn list_boxes(bytes: &[u8]) -> Vec<(&[u8], &[u8])> {
    let mut boxes: Vec<(&[u8], &[u8])> = Vec::new();
    let mut at: usize = 0;
    while at + 8 <= bytes.len() {
        let size32: usize = u32_at(bytes, at).unwrap_or(0) as usize;
        let kind: &[u8] = &bytes[at + 4..at + 8];
        let (header, size): (usize, usize) = match size32 {
            // The box runs to the end.
            0 => (8, bytes.len() - at),
            // A 64-bit size follows the kind.
            1 => {
                let Some(large) = bytes.get(at + 8..at + 16) else {
                    break;
                };
                let mut wide: [u8; 8] = [0; 8];
                wide.copy_from_slice(large);
                (
                    16,
                    usize::try_from(u64::from_be_bytes(wide)).unwrap_or(usize::MAX),
                )
            }
            other => (8, other),
        };
        if size < header
            || at
                .checked_add(size)
                .is_none_or(|end: usize| -> bool { end > bytes.len() })
        {
            break;
        }
        boxes.push((kind, &bytes[at + header..at + size]));
        at += size;
    }
    boxes
}

fn u32_at(bytes: &[u8], at: usize) -> Option<u32> {
    let window: &[u8] = bytes.get(at..at + 4)?;
    Some(u32::from_be_bytes([
        window[0], window[1], window[2], window[3],
    ]))
}

fn u16_at(bytes: &[u8], at: usize) -> Option<u16> {
    let window: &[u8] = bytes.get(at..at + 2)?;
    Some(u16::from_be_bytes([window[0], window[1]]))
}

/// The primary item's id from a `pitm` box (version and flags, then a 16 or 32 bit id).
fn primary_item(payload: &[u8]) -> Option<u32> {
    let version: u8 = *payload.first()?;
    if version == 0 {
        u16_at(payload, 4).map(u32::from)
    } else {
        u32_at(payload, 4)
    }
}

/// The property indexes attached to an item, in the order the `ipma` table lists them.
fn associations(payload: &[u8], item: u32) -> Option<Vec<usize>> {
    let version: u8 = *payload.first()?;
    let wide_indexes: bool = payload.get(3).copied()? & 1 == 1;
    let entries: u32 = u32_at(payload, 4)?;
    let mut at: usize = 8;
    for _ in 0..entries {
        let id: u32 = if version < 1 {
            let found: u32 = u32::from(u16_at(payload, at)?);
            at += 2;
            found
        } else {
            let found: u32 = u32_at(payload, at)?;
            at += 4;
            found
        };
        let count: usize = usize::from(*payload.get(at)?);
        at += 1;
        let mut listed: Vec<usize> = Vec::new();
        for _ in 0..count {
            if wide_indexes {
                listed.push(usize::from(u16_at(payload, at)? & 0x7FFF));
                at += 2;
            } else {
                listed.push(usize::from(*payload.get(at)? & 0x7F));
                at += 1;
            }
        }
        if id == item {
            return Some(listed);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_box(kind: &[u8; 4], payload: &[u8]) -> Vec<u8> {
        let mut bytes: Vec<u8> = ((payload.len() + 8) as u32).to_be_bytes().to_vec();
        bytes.extend_from_slice(kind);
        bytes.extend_from_slice(payload);
        bytes
    }

    /// A file whose primary item (id 7) has the listed `irot` and `imir` properties, after a
    /// property of another kind and with a second item (id 9) that has its own turn.
    fn file_with(properties: &[(&[u8; 4], u8)]) -> Vec<u8> {
        let mut ipco: Vec<u8> = make_box(b"hvcC", &[0, 0]);
        for (kind, value) in properties {
            ipco.extend(make_box(kind, &[*value]));
        }
        let other: u8 = (properties.len() + 2) as u8;
        ipco.extend(make_box(b"irot", &[1]));
        let mut ipma: Vec<u8> = vec![0, 0, 0, 0, 0, 0, 0, 2];
        ipma.extend_from_slice(&7u16.to_be_bytes());
        ipma.push((properties.len() + 1) as u8);
        ipma.push(1);
        for index in 0..properties.len() {
            ipma.push(0x80 | (index as u8 + 2));
        }
        ipma.extend_from_slice(&9u16.to_be_bytes());
        ipma.push(1);
        ipma.push(other);
        let mut iprp: Vec<u8> = make_box(b"ipco", &ipco);
        iprp.extend(make_box(b"ipma", &ipma));
        let mut meta: Vec<u8> = vec![0, 0, 0, 0];
        meta.extend(make_box(b"pitm", &[0, 0, 0, 0, 0, 7]));
        meta.extend(make_box(b"iprp", &iprp));
        let mut file: Vec<u8> = make_box(b"ftyp", b"heic\0\0\0\0mif1heic");
        file.extend(make_box(b"meta", &meta));
        file
    }

    #[test]
    fn a_picture_without_turns_is_upright() {
        assert_eq!(
            orientation_of_primary(&file_with(&[])),
            Some(Orientation::Upright)
        );
    }

    #[test]
    fn quarter_turns_are_anticlockwise_and_only_the_primary_items_count() {
        assert_eq!(
            orientation_of_primary(&file_with(&[(b"irot", 1)])),
            Some(Orientation::Rotate90CounterClockwise)
        );
        assert_eq!(
            orientation_of_primary(&file_with(&[(b"irot", 2)])),
            Some(Orientation::Rotate180)
        );
        assert_eq!(
            orientation_of_primary(&file_with(&[(b"irot", 3)])),
            Some(Orientation::Rotate90Clockwise)
        );
    }

    #[test]
    fn mirrors_and_turns_compose_in_the_order_listed() {
        assert_eq!(
            orientation_of_primary(&file_with(&[(b"imir", 1)])),
            Some(Orientation::MirrorHorizontal)
        );
        assert_eq!(
            orientation_of_primary(&file_with(&[(b"imir", 0)])),
            Some(Orientation::MirrorVertical)
        );
        assert_eq!(
            orientation_of_primary(&file_with(&[(b"irot", 1), (b"imir", 0)])),
            Some(Orientation::Transpose)
        );
        assert_eq!(
            orientation_of_primary(&file_with(&[(b"irot", 1), (b"imir", 1)])),
            Some(Orientation::Transverse)
        );
    }

    #[test]
    fn a_file_that_is_not_heic_has_no_answer() {
        assert_eq!(orientation_of_primary(b"not a picture at all"), None);
        assert_eq!(orientation_of_primary(&make_box(b"ftyp", b"heic")), None);
    }
}
