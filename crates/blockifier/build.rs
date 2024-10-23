use std::{
    fs::{self, OpenOptions},
    io,
};

use curl::easy::Easy;
use std::io::Write;
use std::path::Path;

use toml::{self, Table};

#[cfg(unix)]
/// Creates a symbolic link `from` that points at `to`.
fn sym_link(from: &str, to: &str) -> io::Result<()> {
    std::os::unix::fs::symlink(to, from)
}

fn pull_cairo_native_lib(
    version: &str,
    output_path: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let source_url = format!("https://github.com/lambdaclass/cairo_native/releases/download/v{version}/libcairo_native_runtime.a");
    let mut data = Vec::new();
    let mut handle = Easy::new();
    handle.url(&source_url).unwrap();
    {
        let mut transfer = handle.transfer();
        transfer
            .write_function(|new_data| {
                data.extend_from_slice(new_data);
                Ok(new_data.len())
            })
        .unwrap();
        transfer.perform().unwrap();
    }

    let mut out_file = OpenOptions::new()
        .write(true)
        .append(false)
        .create(true)
        .open(output_path)?;
    out_file.write_all(&data)?;
    Ok(())
}

/// Symlinks libcairo_native_runtime.a to the given version.
/// If the given version doesn't exists, downloads it before linking.
fn ensure_cairo_native_lib(version: &str) -> Result<(), Box<dyn std::error::Error>> {
    let libcairo_native_dir = ".";
    let path_with_version = format!("{libcairo_native_dir}/libcairo_native_runtime-v{version}.a");
    let libnative_path = format!("{libcairo_native_dir}/libcairo_native_runtime.a");

    if Path::new(&path_with_version).exists() == false {
        println!("cargo:warning=Matching version of libcairo_native_runtime not found. Downloading correct version.");
        pull_cairo_native_lib(version, &path_with_version)?;
    }

    // Check if the runtime library exists (either as a symbolic link or a file).
    if let Ok(_) = std::fs::symlink_metadata(&libnative_path) {
        println!("cargo:warning='{libnative_path}' already exists. Removing it.");
        std::fs::remove_file(&libnative_path)?;
    }

    println!("cargo:warning=Creating symbolic link: '{libnative_path}' -> '{path_with_version}'");
    sym_link(&libnative_path, &path_with_version)?;

    Ok(())
}

fn main() {
    let cairo_native = "cairo-native";

    let cargo_path = fs::canonicalize(Path::new("../../Cargo.toml")).expect("Failed to get sequencer Cargo.toml");
    let config = fs::read_to_string(cargo_path).unwrap();
    let config_table: Table = toml::from_str(&config).unwrap();
    let cairo_native_version= config_table
        .get("workspace")
        .expect("Failed to get workspace from sequencer Cargo.toml")
        .get("dependencies")
        .expect("Failed to get workspace.dependencies from sequencer Cargo.toml")
        .get(cairo_native)
        .expect("dependency cairo_native not found")
        .as_str()
        .expect("value for key 'cairo_native' was not a version string");

    println!("cargo:warning=cairo_native version from Cargo.toml: {cairo_native_version:?}");
    ensure_cairo_native_lib(cairo_native_version)
        .expect("failed to ensure cairo_native runtime library exists and is correctly set");
}