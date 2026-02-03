// Build script for isa_simulator_native
// Configures linker flags for macOS to allow undefined Ruby symbols

fn main() {
    // On macOS, Ruby extensions are loaded as bundles and Ruby symbols
    // are resolved at runtime from the Ruby interpreter.
    // We need to tell the linker to allow undefined symbols.
    if std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() == "macos" {
        println!("cargo:rustc-cdylib-link-arg=-undefined");
        println!("cargo:rustc-cdylib-link-arg=dynamic_lookup");
    }
}
