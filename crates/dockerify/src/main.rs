use clap::{Args, Parser, Subcommand};
use dockerify::{
    default_compat_dir, default_proton_prefix, default_steam_compat_client_install_path,
    default_steam_compat_data_path, default_wine_prefix, list_installed_proton_versions,
    parse_release_tag, parse_release_tags, proton_asset_url, proton_latest_release_api_url,
    proton_releases_api_url, resolve_proton_dir, setup_steam_client_symlinks,
};
use std::env;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

/// Install and run Wine/Proton for steamcmd-bases images.
#[derive(Parser)]
#[command(name = "dockerify", version, about)]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Run an executable through Wine or Proton
    Run(RunArgs),
    /// Install Wine or Proton
    Install {
        #[command(subcommand)]
        target: InstallCmd,
    },
    /// Manage installed Proton-GE versions
    Proton {
        #[command(subcommand)]
        action: ProtonCmd,
    },
    /// Diagnose the Wine/Proton environment (installations, env vars, display, libraries)
    Diagnose,
    /// (Re)create ~/.steam/sdk32|64 -> steamcmd's install dir, and
    /// steamservice.so -> steamclient.so inside each. `dockerify run` already
    /// does this automatically right before launching - this is for manual
    /// use (e.g. from an init script, right after `steamcmd +app_update`).
    LinkSteamClient,
}

#[derive(Subcommand)]
enum ProtonCmd {
    /// List installed Proton-GE versions, newest first
    List,
    /// List Proton-GE versions available on GitHub, newest first
    Available,
    /// Point the "current" symlink at an already-installed version
    Use {
        /// Proton-GE release tag (e.g. GE-Proton9-20)
        version: String,
    },
}

#[derive(Args)]
struct RunArgs {
    /// Run through Proton (auto-detected if neither flag is given)
    #[arg(long, conflicts_with = "wine")]
    proton: bool,
    /// Run through Wine (auto-detected if neither flag is given)
    #[arg(long, conflicts_with = "proton")]
    wine: bool,
    /// Executable to run
    exe: PathBuf,
    /// Arguments passed through to the executable
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    args: Vec<String>,
}

#[derive(Subcommand)]
enum InstallCmd {
    /// Install Wine (Debian/Ubuntu, via apt)
    Wine,
    /// Install Proton-GE
    Proton {
        /// Proton-GE release tag (e.g. GE-Proton9-20), or "latest"
        #[arg(long, default_value = "latest")]
        version: String,
    },
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let home = env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/home/steam"));

    let result = match cli.command {
        Cmd::Run(args) => run_cmd(&home, args),
        Cmd::Install { target } => match target {
            InstallCmd::Wine => install_wine(),
            InstallCmd::Proton { version } => install_proton(&home, &version).map(|_| 0),
        },
        Cmd::Proton { action } => match action {
            ProtonCmd::List => proton_list(&home).map(|_| 0),
            ProtonCmd::Available => proton_available().map(|_| 0),
            ProtonCmd::Use { version } => proton_use(&home, &version).map(|_| 0),
        },
        Cmd::Diagnose => diagnose(&home).map(|_| 0),
        Cmd::LinkSteamClient => {
            link_steam_client(&home);
            Ok(0)
        }
    };

    match result {
        Ok(code) => ExitCode::from(code as u8),
        Err(err) => {
            eprintln!("❌ {err}");
            ExitCode::FAILURE
        }
    }
}

// ─── run ────────────────────────────────────────────────────────────────

fn link_steam_client(home: &Path) {
    for link in setup_steam_client_symlinks(home) {
        println!("✓ linked {link}");
    }
}

fn run_cmd(home: &Path, args: RunArgs) -> Result<i32, String> {
    if !args.exe.exists() {
        return Err(format!("executable not found: {}", args.exe.display()));
    }

    // Retry point: setup_steam_client_symlinks() may have already run during
    // setup/init, but steamcmd might not have downloaded steamclient.so yet
    // at that point. By the time we're actually spawning the server,
    // steamcmd has definitely run - so this is what actually has to succeed.
    link_steam_client(home);

    let use_proton = if args.proton {
        true
    } else if args.wine {
        false
    } else if resolve_proton_dir(&default_compat_dir(home)).is_some() {
        true
    } else if wine_is_installed() {
        false
    } else {
        return Err("neither Wine nor Proton is installed".into());
    };

    if use_proton {
        run_proton(home, &args.exe, &args.args)
    } else {
        run_wine(home, &args.exe, &args.args)
    }
}

fn run_wine(home: &Path, exe: &Path, extra_args: &[String]) -> Result<i32, String> {
    if !wine_is_installed() {
        return Err("Wine is not installed".into());
    }

    let prefix = env::var_os("WINEPREFIX")
        .map(PathBuf::from)
        .unwrap_or_else(|| default_wine_prefix(home));
    env::set_var("WINEARCH", env::var("WINEARCH").unwrap_or_else(|_| "win64".into()));
    env::set_var(
        "WINEDEBUG",
        env::var("WINEDEBUG").unwrap_or_else(|_| "fixme-all".into()),
    );
    env::set_var("WINEPREFIX", &prefix);

    if !prefix.join("drive_c").is_dir() {
        std::fs::create_dir_all(&prefix).map_err(|e| e.to_string())?;
        println!("🏗️ Creating new Wine prefix at {}", prefix.display());
        let status = Command::new("wine").args(["wineboot", "--init"]).status();
        if !matches!(status, Ok(s) if s.success()) {
            eprintln!("⚠️ Wine prefix initialization failed, continuing anyway");
        }
    }

    println!("▶️ Running {} via Wine", exe.display());
    let status = Command::new("wine")
        .arg(exe)
        .args(extra_args)
        .status()
        .map_err(|e| format!("failed to launch wine: {e}"))?;
    Ok(status.code().unwrap_or(1))
}

fn run_proton(home: &Path, exe: &Path, extra_args: &[String]) -> Result<i32, String> {
    let compat_dir = default_compat_dir(home);
    let proton_dir = resolve_proton_dir(&compat_dir)
        .ok_or_else(|| format!("no Proton installation found in {}", compat_dir.display()))?;
    let proton_bin = proton_dir.join("proton");

    let client_path = env::var_os("STEAM_COMPAT_CLIENT_INSTALL_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|| default_steam_compat_client_install_path(home));
    let data_path = env::var_os("STEAM_COMPAT_DATA_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|| default_steam_compat_data_path(home));
    let prefix = env::var_os("WINEPREFIX")
        .map(PathBuf::from)
        .unwrap_or_else(|| default_proton_prefix(home));

    env::set_var("STEAM_COMPAT_CLIENT_INSTALL_PATH", &client_path);
    env::set_var("STEAM_COMPAT_DATA_PATH", &data_path);
    env::set_var("WINEPREFIX", &prefix);

    let mut xvfb_child = None;
    if env::var_os("DISPLAY").is_none() {
        env::set_var("DISPLAY", ":99");
        env::set_var("SDL_VIDEODRIVER", "x11");
        if command_exists("Xvfb") {
            xvfb_child = Command::new("Xvfb")
                .args([":99", "-screen", "0", "1024x768x16"])
                .spawn()
                .ok();
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
    }

    println!(
        "▶️ Running {} via Proton ({})",
        exe.display(),
        proton_bin.display()
    );
    let status = Command::new(&proton_bin)
        .arg("run")
        .arg(exe)
        .args(extra_args)
        .status();

    if let Some(mut child) = xvfb_child {
        let _ = child.kill();
    }

    let status = status.map_err(|e| format!("failed to launch proton: {e}"))?;
    Ok(status.code().unwrap_or(1))
}

// ─── install ────────────────────────────────────────────────────────────

fn install_wine() -> Result<i32, String> {
    if wine_is_installed() {
        println!("✓ Wine already installed: {}", wine_version().unwrap_or_default());
        return Ok(0);
    }

    println!("→ Installing Wine (stable)...");
    let script = r#"
set -e
sudo dpkg --add-architecture i386
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
sudo chmod 644 /etc/apt/keyrings/winehq-archive.key
sudo wget -NP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/ubuntu/dists/$(lsb_release -cs)/winehq-$(lsb_release -cs).sources"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --install-recommends winehq-stable winetricks cabextract
"#;
    run_script(script)?;
    println!("✓ Wine installed: {}", wine_version().unwrap_or_default());
    Ok(0)
}

fn install_proton(home: &Path, version: &str) -> Result<(), String> {
    let compat_dir = default_compat_dir(home);
    std::fs::create_dir_all(&compat_dir).map_err(|e| e.to_string())?;

    let resolved = if version == "latest" {
        resolve_latest_proton_tag()?
    } else {
        version.to_string()
    };

    // Extract straight into a directory named after the clean tag, using
    // --strip-components=1 to drop whatever top-level directory name is
    // actually inside the archive. That name isn't guaranteed to stay
    // "<tag>-x86_64" forever, and this way we don't have to guess it.
    let target_dir = compat_dir.join(&resolved);
    if target_dir.is_dir() {
        println!("✓ {resolved} already installed");
    } else {
        let url = proton_asset_url(&resolved);
        println!("→ Installing GloriousEggroll Proton version: {resolved}");
        println!("→ Downloading {url}...");

        let tmp = std::env::temp_dir().join(format!("proton-ge-{}", std::process::id()));
        std::fs::create_dir_all(&tmp).map_err(|e| e.to_string())?;
        let archive = tmp.join("proton.tar.gz");

        let status = Command::new("curl")
            .args(["-sL", &url, "-o"])
            .arg(&archive)
            .status()
            .map_err(|e| format!("failed to run curl: {e}"))?;
        if !status.success() {
            return Err(format!("failed to download {url}"));
        }

        std::fs::create_dir_all(&target_dir).map_err(|e| e.to_string())?;
        let status = Command::new("tar")
            .arg("xzf")
            .arg(&archive)
            .arg("-C")
            .arg(&target_dir)
            .arg("--strip-components=1")
            .status()
            .map_err(|e| format!("failed to run tar: {e}"))?;
        let _ = std::fs::remove_dir_all(&tmp);
        if !status.success() {
            let _ = std::fs::remove_dir_all(&target_dir);
            return Err(format!("failed to extract {url}"));
        }

        println!("✓ Installed {resolved} to {}", target_dir.display());
    }

    let current = compat_dir.join("current");
    if current.exists() || current.symlink_metadata().is_ok() {
        std::fs::remove_file(&current).map_err(|e| e.to_string())?;
    }
    std::os::unix::fs::symlink(&target_dir, &current).map_err(|e| e.to_string())?;

    println!("Now using Proton-GE version: {resolved}");
    println!("PROTON_PATH={}/proton", current.display());
    Ok(())
}

fn proton_list(home: &Path) -> Result<(), String> {
    let compat_dir = default_compat_dir(home);
    let versions = list_installed_proton_versions(&compat_dir);
    if versions.is_empty() {
        println!("No Proton-GE versions installed in {}", compat_dir.display());
    } else {
        println!("Installed Proton-GE versions:");
        for v in versions {
            println!("  {v}");
        }
    }
    Ok(())
}

fn proton_available() -> Result<(), String> {
    println!("Fetching available Proton-GE versions...");
    let output = Command::new("curl")
        .args(["-s", &proton_releases_api_url()])
        .output()
        .map_err(|e| format!("failed to query GitHub API: {e}"))?;
    if !output.status.success() {
        return Err("failed to query GitHub API for Proton-GE releases".into());
    }
    let body = String::from_utf8_lossy(&output.stdout);
    let mut tags = parse_release_tags(&body)?;
    tags.sort();
    for tag in tags {
        println!("  {tag}");
    }
    Ok(())
}

fn proton_use(home: &Path, version: &str) -> Result<(), String> {
    let compat_dir = default_compat_dir(home);
    let target_dir = compat_dir.join(version);
    if !target_dir.is_dir() {
        let installed = list_installed_proton_versions(&compat_dir);
        let mut msg = format!("{version} is not installed.");
        if installed.is_empty() {
            msg.push_str(" No versions are installed - try `dockerify install proton --version ...` first.");
        } else {
            msg.push_str(&format!(" Installed versions: {}", installed.join(", ")));
        }
        return Err(msg);
    }

    let current = compat_dir.join("current");
    if current.exists() || current.symlink_metadata().is_ok() {
        std::fs::remove_file(&current).map_err(|e| e.to_string())?;
    }
    std::os::unix::fs::symlink(&target_dir, &current).map_err(|e| e.to_string())?;

    println!("Now using Proton-GE version: {version}");
    println!("PROTON_PATH={}/proton", current.display());
    Ok(())
}

fn resolve_latest_proton_tag() -> Result<String, String> {
    let output = Command::new("curl")
        .args(["-s", &proton_latest_release_api_url()])
        .output()
        .map_err(|e| format!("failed to query GitHub API: {e}"))?;
    if !output.status.success() {
        return Err("failed to query GitHub API for the latest Proton-GE release".into());
    }
    let body = String::from_utf8_lossy(&output.stdout);
    parse_release_tag(&body)
}

// ─── diagnose ───────────────────────────────────────────────────────────

fn diagnose(home: &Path) -> Result<(), String> {
    println!("===== Proton Environment Diagnostics =====\n");

    let compat_dir = default_compat_dir(home);
    println!("=== Proton Installations ===");
    let versions = list_installed_proton_versions(&compat_dir);
    if versions.is_empty() {
        println!("❌ No Proton installations found in {}", compat_dir.display());
    } else {
        println!("✅ Found Proton installations:");
        for v in &versions {
            println!("   - {v}");
        }
    }

    println!("\n=== Proton Path ===");
    match env::var_os("PROTON_PATH") {
        Some(path) => {
            let path = PathBuf::from(path);
            println!("PROTON_PATH = {}", path.display());
            if path.is_file() {
                println!("✅ Proton binary exists");
            } else {
                println!("❌ Proton binary not found at {}", path.display());
            }
        }
        None => println!("❌ PROTON_PATH environment variable not set"),
    }

    println!("\n=== Steam Environment ===");
    for var in ["STEAM_COMPAT_CLIENT_INSTALL_PATH", "STEAM_COMPAT_DATA_PATH", "WINEPREFIX"] {
        match env::var_os(var) {
            Some(val) => {
                let path = PathBuf::from(&val);
                println!("{var} = {}", path.display());
                if path.is_dir() {
                    println!("✅ Directory exists");
                } else {
                    println!("❌ Directory does not exist");
                }
            }
            None => println!("❌ {var} not set"),
        }
    }

    println!("\n=== Wine Prefix ===");
    match env::var_os("WINEPREFIX") {
        Some(prefix) => {
            let prefix = PathBuf::from(prefix);
            if prefix.is_dir() {
                println!("✅ Wine prefix exists at {}", prefix.display());
                if prefix.join("system.reg").is_file() {
                    println!("✅ Wine registry found");
                } else {
                    println!("❌ Wine registry not found, prefix may be incomplete");
                }
            } else {
                println!("❌ Wine prefix directory does not exist");
            }
        }
        None => println!("❌ WINEPREFIX not set"),
    }

    println!("\n=== Display Configuration ===");
    match env::var("DISPLAY") {
        Ok(display) => {
            println!("DISPLAY = {display}");
            let running = Command::new("pgrep")
                .args(["-f", &format!("Xvfb {display}")])
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false);
            if running {
                println!("✅ Xvfb running on {display}");
            } else {
                println!("❌ No Xvfb instance running on {display}");
            }
        }
        Err(_) => println!("❌ DISPLAY environment variable not set"),
    }

    println!("\n=== Required Libraries ===");
    for lib in [
        "/usr/lib/i386-linux-gnu/libncurses.so.5",
        "/usr/lib/x86_64-linux-gnu/libncurses.so.5",
        "/usr/lib/i386-linux-gnu/libcurl.so.4",
        "/usr/lib/x86_64-linux-gnu/libvulkan.so.1",
        "/home/steam/.steam/sdk64/steamclient.so",
    ] {
        let path = Path::new(lib);
        if path.exists() || path.symlink_metadata().is_ok() {
            println!("✅ Found: {lib}");
        } else {
            println!("❌ Missing: {lib} (may not be required for all games)");
        }
    }

    println!("\n=== Steam Runtime ===");
    if home.join(".steam/steam/steamapps/common/SteamLinuxRuntime").is_dir() {
        println!("✅ Steam Linux Runtime is installed");
    } else {
        println!("⚠️ Steam Linux Runtime is not installed (not critical for all games)");
    }

    println!("\n=== Environment Summary ===");
    println!("USER: {}", env::var("USER").unwrap_or_default());
    println!("HOME: {}", home.display());

    println!("\nFor problems, check the wiki at: https://github.com/GloriousEggroll/proton-ge-custom/wiki");
    Ok(())
}

// ─── shared helpers ─────────────────────────────────────────────────────

fn command_exists(name: &str) -> bool {
    Command::new("which")
        .arg(name)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn wine_is_installed() -> bool {
    command_exists("wine")
}

fn wine_version() -> Option<String> {
    let output = Command::new("wine").arg("--version").output().ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn run_script(script: &str) -> Result<(), String> {
    let status = Command::new("bash")
        .arg("-c")
        .arg(script)
        .status()
        .map_err(|e| e.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("install script failed: {status}"))
    }
}
