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
