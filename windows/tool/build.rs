//! Embeds the application manifest (UTF-8 active code page, long paths) into song2vid.exe.
//!
//! The MSVC linker takes the manifest as an input file, so no resource compiler is needed.

use std::env;
use std::path::PathBuf;

fn main() -> () {
    println!("cargo:rerun-if-changed=song2vid.manifest");
    println!("cargo:rerun-if-changed=build.rs");
    let target_os: String = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_env: String = env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
    if target_os != "windows" || target_env != "msvc" {
        return;
    }
    let manifest_dir: PathBuf = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap_or_default());
    let manifest: PathBuf = manifest_dir.join("song2vid.manifest");
    println!("cargo:rustc-link-arg-bins=/MANIFEST:EMBED");
    println!(
        "cargo:rustc-link-arg-bins=/MANIFESTINPUT:{}",
        manifest.display()
    );
    println!("cargo:rustc-link-arg-bins=/MANIFESTUAC:NO");
}
