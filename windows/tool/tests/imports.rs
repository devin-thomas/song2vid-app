//! The built `song2vid.exe` imports only Windows' own DLLs, has a static C runtime, is 64-bit, and
//! carries its manifest (SPEC section 26.1, S2V-025). The test reads the file's import tables.

use std::fs;
use std::path::{Path, PathBuf};

/// What a DLL name may not be: any of these means the C runtime was not linked in statically.
const RUNTIME_DLLS: [&str; 5] = ["vcruntime", "msvcp", "ucrtbase", "api-ms-win-crt-", "msvcr"];

fn read_u16(bytes: &[u8], at: usize) -> usize {
    usize::from(u16::from_le_bytes([bytes[at], bytes[at + 1]]))
}

fn read_u32(bytes: &[u8], at: usize) -> usize {
    u32::from_le_bytes([bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]]) as usize
}

/// The file offset for a relative virtual address, through the section table.
fn offset_of(bytes: &[u8], sections: usize, table: usize, rva: usize) -> usize {
    for index in 0..sections {
        let at: usize = table + index * 40;
        let virtual_size: usize = read_u32(bytes, at + 8);
        let virtual_address: usize = read_u32(bytes, at + 12);
        let raw_size: usize = read_u32(bytes, at + 16);
        let raw_pointer: usize = read_u32(bytes, at + 20);
        if rva >= virtual_address && rva < virtual_address + virtual_size.max(raw_size) {
            return raw_pointer + (rva - virtual_address);
        }
    }
    panic!("RVA {rva:#x} is in no section");
}

fn c_string(bytes: &[u8], at: usize) -> String {
    let end: usize = bytes[at..]
        .iter()
        .position(|byte: &u8| -> bool { *byte == 0 })
        .expect("a terminated name");
    String::from_utf8_lossy(&bytes[at..at + end]).to_lowercase()
}

/// The DLL names in the import table and the delay-load import table, and the machine type.
fn imported_dlls(bytes: &[u8]) -> (Vec<String>, usize) {
    assert_eq!(&bytes[..2], b"MZ", "not a Windows program");
    let pe: usize = read_u32(bytes, 0x3C);
    assert_eq!(&bytes[pe..pe + 4], b"PE\0\0");
    let machine: usize = read_u16(bytes, pe + 4);
    let sections: usize = read_u16(bytes, pe + 6);
    let optional_size: usize = read_u16(bytes, pe + 20);
    let optional: usize = pe + 24;
    assert_eq!(
        read_u16(bytes, optional),
        0x20B,
        "not a 64-bit (PE32+) program"
    );
    let table: usize = optional + optional_size;
    let directories: usize = optional + 112;

    let mut names: Vec<String> = Vec::new();
    // Import directory (entry 1): 20-byte descriptors, the DLL name's RVA at byte 12.
    let import_rva: usize = read_u32(bytes, directories + 8);
    if import_rva != 0 {
        let mut at: usize = offset_of(bytes, sections, table, import_rva);
        while read_u32(bytes, at + 12) != 0 {
            names.push(c_string(
                bytes,
                offset_of(bytes, sections, table, read_u32(bytes, at + 12)),
            ));
            at += 20;
        }
    }
    // Delay-load import directory (entry 13): 32-byte descriptors, the name's RVA at byte 4.
    let delay_rva: usize = read_u32(bytes, directories + 13 * 8);
    if delay_rva != 0 {
        let mut at: usize = offset_of(bytes, sections, table, delay_rva);
        while read_u32(bytes, at + 4) != 0 {
            names.push(c_string(
                bytes,
                offset_of(bytes, sections, table, read_u32(bytes, at + 4)),
            ));
            at += 32;
        }
    }
    (names, machine)
}

/// The program under test: the one Cargo built for these tests, or the one named by
/// `SONG2VID_IMPORT_CHECK` (the release build, which is the one that ships).
fn built_program() -> Option<PathBuf> {
    let program: PathBuf = std::env::var_os("SONG2VID_IMPORT_CHECK").map_or_else(
        || -> PathBuf { PathBuf::from(env!("CARGO_BIN_EXE_song2vid")) },
        PathBuf::from,
    );
    // The test builds for the machine it runs on; only a Windows build has imports to check.
    if cfg!(windows) && program.is_file() {
        Some(program)
    } else {
        None
    }
}

#[test]
fn the_program_imports_only_windows_own_dlls_and_has_a_static_runtime() -> () {
    let Some(program) = built_program() else {
        eprintln!("skipped: this test reads the Windows program's import table");
        return;
    };
    let bytes: Vec<u8> = fs::read(&program).expect("the program");
    let (names, machine): (Vec<String>, usize) = imported_dlls(&bytes);
    assert_eq!(machine, 0x8664, "the program is not x86-64");
    println!("imports: {}", names.join(", "));
    assert!(!names.is_empty());

    let system: PathBuf =
        Path::new(&std::env::var("SystemRoot").expect("SystemRoot")).join("System32");
    for name in &names {
        for runtime in RUNTIME_DLLS {
            assert!(
                !name.starts_with(runtime),
                "{name} means the C runtime is not static"
            );
        }
        // Names like api-ms-win-core-* are Windows' own virtual DLLs; any other must be in System32.
        let virtual_dll: bool = name.starts_with("api-ms-win-") || name.starts_with("ext-ms-");
        assert!(
            virtual_dll || system.join(name).is_file(),
            "{name} is not a Windows DLL"
        );
    }
}

#[test]
fn the_manifest_asks_for_utf8_and_long_paths() -> () {
    let Some(program) = built_program() else {
        eprintln!("skipped: this test reads the Windows program's manifest");
        return;
    };
    let bytes: Vec<u8> = fs::read(&program).expect("the program");
    let contains = |needle: &str| -> bool {
        bytes
            .windows(needle.len())
            .any(|window: &[u8]| -> bool { window == needle.as_bytes() })
    };
    assert!(
        contains("<activeCodePage"),
        "no activeCodePage in the manifest"
    );
    assert!(contains(">UTF-8</activeCodePage>"));
    assert!(contains("<longPathAware"));
    assert!(contains(">true</longPathAware>"));
}
