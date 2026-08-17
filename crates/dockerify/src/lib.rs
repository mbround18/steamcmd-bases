use std::path::{Path, PathBuf};

pub const PROTON_REPO: &str = "GloriousEggroll/proton-ge-custom";

/// GitHub release asset URL for a given GE-Proton tag.
/// GitHub packages the tarball as "<tag>-x86_64.tar.gz", not "<tag>.tar.gz".
pub fn proton_asset_url(version: &str) -> String {
    let dir_name = proton_install_dir_name(version);
    format!("https://github.com/{PROTON_REPO}/releases/download/{version}/{dir_name}.tar.gz")
}

pub fn proton_latest_release_api_url() -> String {
    format!("https://api.github.com/repos/{PROTON_REPO}/releases/latest")
}

pub fn proton_releases_api_url() -> String {
    format!("https://api.github.com/repos/{PROTON_REPO}/releases")
}

/// Pull `tag_name` out of every entry in a GitHub "list releases" API response.
pub fn parse_release_tags(body: &str) -> Result<Vec<String>, String> {
    let json: serde_json::Value =
        serde_json::from_str(body).map_err(|e| format!("invalid GitHub API response: {e}"))?;
    let items = json
        .as_array()
        .ok_or_else(|| "GitHub API response was not a list of releases".to_string())?;
    Ok(items
        .iter()
        .filter_map(|item| item.get("tag_name").and_then(|v| v.as_str()))
        .map(String::from)
        .collect())
}

/// Name of the top-level directory a GE-Proton release tarball extracts to.
/// GitHub's asset (and the archive's own top-level dir) is "<tag>-x86_64",
/// not the bare tag - trust that pattern rather than assuming it matches the
/// requested version string.
pub fn proton_install_dir_name(version: &str) -> String {
    format!("{version}-x86_64")
}

/// Pull `tag_name` out of a GitHub "get release" API response body.
pub fn parse_release_tag(body: &str) -> Result<String, String> {
    let json: serde_json::Value =
        serde_json::from_str(body).map_err(|e| format!("invalid GitHub API response: {e}"))?;
    json.get("tag_name")
        .and_then(|v| v.as_str())
        .map(String::from)
        .ok_or_else(|| "GitHub API response had no tag_name".to_string())
}

/// (Re)create ~/.steam/sdk32|64 -> wherever steamcmd actually put its
/// libraries, and steamservice.so -> steamclient.so inside each. Proton's
/// Steamworks bridge (lsteamclient) reads steamclient.so through this path,
/// and SteamGameServer_Init() hangs/fails without it.
///
/// This MUST run as the user that will actually run the server, and MUST be
/// retried right before spawning it rather than only once at image-build
/// time: a symlink created as root during `docker build` lands under
/// /root/.steam, which the runtime `steam` user can't use at all, and
/// steamcmd may not have downloaded anything into steamcmd/linux32|64 yet
/// the first time this runs anyway. Safe to call repeatedly - each half is
/// only linked once real content shows up, and it silently no-ops for
/// whichever arch isn't present yet.
///
/// Returns a description of each symlink actually (re)created, for logging.
pub fn setup_steam_client_symlinks(home: &Path) -> Vec<String> {
    let mut created = Vec::new();
    let steamcmd_dir = home.join(".local/share/Steam/steamcmd");
    let steam_dir = home.join(".steam");

    for (sdk, arch_dir) in [("sdk32", "linux32"), ("sdk64", "linux64")] {
        let source_dir = steamcmd_dir.join(arch_dir);
        let sdk_link = steam_dir.join(sdk);

        if source_dir.is_dir() && !sdk_link.is_dir() {
            let _ = std::fs::create_dir_all(&steam_dir);
            let _ = std::fs::remove_file(&sdk_link);
            if std::os::unix::fs::symlink(&source_dir, &sdk_link).is_ok() {
                created.push(format!("{} -> {}", sdk_link.display(), source_dir.display()));
            }
        }

        let steamclient = sdk_link.join("steamclient.so");
        let steamservice = sdk_link.join("steamservice.so");
        if steamclient.is_file() && !steamservice.is_file() {
            let _ = std::fs::remove_file(&steamservice);
            if std::os::unix::fs::symlink(&steamclient, &steamservice).is_ok() {
                created.push(format!("{} -> {}", steamservice.display(), steamclient.display()));
            }
        }
    }

    created
}

pub fn default_compat_dir(home: &Path) -> PathBuf {
    home.join(".steam/root/compatibilitytools.d")
}

pub fn default_wine_prefix(home: &Path) -> PathBuf {
    home.join(".wine")
}

pub fn default_proton_prefix(home: &Path) -> PathBuf {
    home.join(".proton/pfx")
}

pub fn default_steam_compat_client_install_path(home: &Path) -> PathBuf {
    home.join(".steam/steam")
}

pub fn default_steam_compat_data_path(home: &Path) -> PathBuf {
    home.join(".proton")
}

/// Resolve which installed GE-Proton directory to use: prefer the "current"
/// symlink (what `install proton` and `proton-manager use` point at), and
/// fall back to the newest installed GE-Proton* directory by name.
pub fn resolve_proton_dir(compat_dir: &Path) -> Option<PathBuf> {
    let current = compat_dir.join("current");
    if current.is_symlink() && current.is_dir() {
        return Some(current);
    }

    let mut candidates: Vec<PathBuf> = std::fs::read_dir(compat_dir)
        .ok()?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| {
            path.is_dir()
                && path
                    .file_name()
                    .and_then(|name| name.to_str())
                    .map(|name| name.starts_with("GE-Proton"))
                    .unwrap_or(false)
        })
        .collect();
    candidates.sort_by(|a, b| {
        let a = a.file_name().and_then(|n| n.to_str()).unwrap_or("");
        let b = b.file_name().and_then(|n| n.to_str()).unwrap_or("");
        natural_cmp(a, b)
    });
    candidates.pop()
}

/// Compare version-ish strings the way `sort -V` does: numeric runs compare
/// numerically (so "9-20" sorts after "9-5"), everything else compares as text.
fn natural_cmp(a: &str, b: &str) -> std::cmp::Ordering {
    version_chunks(a).cmp(&version_chunks(b))
}

#[derive(PartialEq, Eq, PartialOrd, Ord)]
enum VChunk {
    Num(u128),
    Str(String),
}

fn version_chunks(s: &str) -> Vec<VChunk> {
    let mut chunks = Vec::new();
    let mut chars = s.chars().peekable();
    while let Some(&c) = chars.peek() {
        if c.is_ascii_digit() {
            let mut num = String::new();
            while let Some(&c) = chars.peek() {
                if c.is_ascii_digit() {
                    num.push(c);
                    chars.next();
                } else {
                    break;
                }
            }
            chunks.push(VChunk::Num(num.parse().unwrap_or(0)));
        } else {
            let mut text = String::new();
            while let Some(&c) = chars.peek() {
                if c.is_ascii_digit() {
                    break;
                }
                text.push(c);
                chars.next();
            }
            chunks.push(VChunk::Str(text));
        }
    }
    chunks
}

/// List installed GE-Proton directories (excluding the "current" symlink),
/// newest first.
pub fn list_installed_proton_versions(compat_dir: &Path) -> Vec<String> {
    let mut versions: Vec<String> = std::fs::read_dir(compat_dir)
        .into_iter()
        .flatten()
        .filter_map(|entry| entry.ok())
        .filter_map(|entry| {
            let name = entry.file_name().to_str()?.to_string();
            if name != "current" && name.starts_with("GE-Proton") && entry.path().is_dir() {
                Some(name)
            } else {
                None
            }
        })
        .collect();
    versions.sort_by(|a, b| natural_cmp(b, a));
    versions
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn proton_install_dir_name_appends_arch_suffix() {
        assert_eq!(proton_install_dir_name("GE-Proton9-20"), "GE-Proton9-20-x86_64");
    }

    #[test]
    fn proton_asset_url_appends_arch_suffix() {
        assert_eq!(
            proton_asset_url("GE-Proton9-20"),
            "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-20/GE-Proton9-20-x86_64.tar.gz"
        );
    }

    #[test]
    fn parse_release_tag_reads_tag_name() {
        let body = r#"{"tag_name": "GE-Proton9-20", "other": "field"}"#;
        assert_eq!(parse_release_tag(body).unwrap(), "GE-Proton9-20");
    }

    #[test]
    fn parse_release_tag_rejects_missing_field() {
        assert!(parse_release_tag(r#"{"other": "field"}"#).is_err());
    }

    #[test]
    fn parse_release_tag_rejects_invalid_json() {
        assert!(parse_release_tag("not json").is_err());
    }

    #[test]
    fn resolve_proton_dir_prefers_current_symlink() {
        let dir = tempfile::tempdir().unwrap();
        let compat = dir.path();
        std::fs::create_dir_all(compat.join("GE-Proton9-20")).unwrap();
        std::fs::create_dir_all(compat.join("GE-Proton9-5")).unwrap();
        std::os::unix::fs::symlink(compat.join("GE-Proton9-5"), compat.join("current")).unwrap();

        assert_eq!(
            resolve_proton_dir(compat).unwrap(),
            compat.join("current")
        );
    }

    #[test]
    fn resolve_proton_dir_falls_back_to_newest_by_name() {
        let dir = tempfile::tempdir().unwrap();
        let compat = dir.path();
        std::fs::create_dir_all(compat.join("GE-Proton9-5")).unwrap();
        std::fs::create_dir_all(compat.join("GE-Proton9-20")).unwrap();

        assert_eq!(
            resolve_proton_dir(compat).unwrap(),
            compat.join("GE-Proton9-20")
        );
    }

    #[test]
    fn resolve_proton_dir_orders_versions_numerically_not_lexically() {
        let dir = tempfile::tempdir().unwrap();
        let compat = dir.path();
        // Lexically "9-5" > "10-1", but version-wise GE-Proton10-1 is newer.
        std::fs::create_dir_all(compat.join("GE-Proton9-5")).unwrap();
        std::fs::create_dir_all(compat.join("GE-Proton10-1")).unwrap();

        assert_eq!(
            resolve_proton_dir(compat).unwrap(),
            compat.join("GE-Proton10-1")
        );
    }

    #[test]
    fn resolve_proton_dir_none_when_empty() {
        let dir = tempfile::tempdir().unwrap();
        assert!(resolve_proton_dir(dir.path()).is_none());
    }

    #[test]
    fn parse_release_tags_reads_all_tags() {
        let body = r#"[{"tag_name": "GE-Proton9-20"}, {"tag_name": "GE-Proton9-5"}]"#;
        assert_eq!(
            parse_release_tags(body).unwrap(),
            vec!["GE-Proton9-20".to_string(), "GE-Proton9-5".to_string()]
        );
    }

    #[test]
    fn parse_release_tags_rejects_non_array() {
        assert!(parse_release_tags(r#"{"tag_name": "x"}"#).is_err());
    }

    #[test]
    fn steam_client_symlinks_noop_when_steamcmd_hasnt_run() {
        let home = tempfile::tempdir().unwrap();
        assert!(setup_steam_client_symlinks(home.path()).is_empty());
    }

    #[test]
    fn steam_client_symlinks_links_sdk_dir_once_present() {
        let home = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(home.path().join(".local/share/Steam/steamcmd/linux64")).unwrap();

        let created = setup_steam_client_symlinks(home.path());
        assert_eq!(created.len(), 1);
        assert!(home.path().join(".steam/sdk64").is_dir());
        // linux32 wasn't populated - no failure, just nothing to link yet.
        assert!(!home.path().join(".steam/sdk32").exists());
    }

    #[test]
    fn steam_client_symlinks_links_steamservice_once_steamclient_exists() {
        let home = tempfile::tempdir().unwrap();
        let linux64 = home.path().join(".local/share/Steam/steamcmd/linux64");
        std::fs::create_dir_all(&linux64).unwrap();
        std::fs::write(linux64.join("steamclient.so"), b"fake").unwrap();

        setup_steam_client_symlinks(home.path());
        let steamservice = home.path().join(".steam/sdk64/steamservice.so");
        assert!(steamservice.is_file());
    }

    #[test]
    fn steam_client_symlinks_idempotent_second_call_creates_nothing() {
        let home = tempfile::tempdir().unwrap();
        let linux64 = home.path().join(".local/share/Steam/steamcmd/linux64");
        std::fs::create_dir_all(&linux64).unwrap();
        std::fs::write(linux64.join("steamclient.so"), b"fake").unwrap();

        setup_steam_client_symlinks(home.path());
        assert!(setup_steam_client_symlinks(home.path()).is_empty());
    }

    #[test]
    fn steam_client_symlinks_retries_after_steamcmd_populates_later() {
        let home = tempfile::tempdir().unwrap();

        // First call: steamcmd hasn't downloaded anything yet.
        assert!(setup_steam_client_symlinks(home.path()).is_empty());

        // steamcmd runs (e.g. via `+app_update`) and populates linux64.
        let linux64 = home.path().join(".local/share/Steam/steamcmd/linux64");
        std::fs::create_dir_all(&linux64).unwrap();
        std::fs::write(linux64.join("steamclient.so"), b"fake").unwrap();

        // Retry right before spawning the server: this time it links.
        let created = setup_steam_client_symlinks(home.path());
        assert_eq!(created.len(), 2); // sdk64 dir + steamservice.so
        assert!(home.path().join(".steam/sdk64/steamclient.so").is_file());
    }

    #[test]
    fn list_installed_proton_versions_excludes_current_symlink() {
        let dir = tempfile::tempdir().unwrap();
        let compat = dir.path();
        std::fs::create_dir_all(compat.join("GE-Proton9-5")).unwrap();
        std::fs::create_dir_all(compat.join("GE-Proton10-1")).unwrap();
        std::os::unix::fs::symlink(compat.join("GE-Proton10-1"), compat.join("current")).unwrap();

        assert_eq!(
            list_installed_proton_versions(compat),
            vec!["GE-Proton10-1".to_string(), "GE-Proton9-5".to_string()]
        );
    }
}
