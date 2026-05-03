use std::path::{Path, PathBuf};

pub const LABEL: &str = "com.voco.daemon";

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LaunchAgentPaths {
    pub plist_path: PathBuf,
    pub daemon_path: PathBuf,
    pub working_dir: PathBuf,
    pub home: PathBuf,
}

pub fn render_plist(paths: &LaunchAgentPaths) -> String {
    render_plist_from_template(plist_template(), paths)
}

fn render_plist_from_template(template: &str, paths: &LaunchAgentPaths) -> String {
    template
        .replace(
            "{{VOCO_DAEMON_PATH}}",
            &xml_escape(&paths.daemon_path.display().to_string()),
        )
        .replace("{{HOME}}", &xml_escape(&paths.home.display().to_string()))
        .replace(
            "{{WORKING_DIR}}",
            &xml_escape(&paths.working_dir.display().to_string()),
        )
}

fn plist_template() -> &'static str {
    include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../packaging/com.voco.daemon.plist.tmpl"
    ))
}

fn xml_escape(input: &str) -> String {
    input
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

pub fn choose_working_dir(current_dir: &Path, daemon_path: &Path) -> PathBuf {
    let source_tree = current_dir.join("Cargo.toml").is_file()
        && current_dir.join("hud/Package.swift").is_file()
        && current_dir
            .join("packaging/com.voco.daemon.plist.tmpl")
            .is_file();
    if source_tree {
        current_dir.to_path_buf()
    } else {
        daemon_path
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| current_dir.to_path_buf())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn paths(home: &str, daemon: &str, working_dir: &str) -> LaunchAgentPaths {
        LaunchAgentPaths {
            plist_path: PathBuf::from(home).join("Library/LaunchAgents/com.voco.daemon.plist"),
            daemon_path: PathBuf::from(daemon),
            working_dir: PathBuf::from(working_dir),
            home: PathBuf::from(home),
        }
    }

    #[test]
    fn renders_plist_with_replaced_values() {
        let rendered = render_plist_from_template(
            "<string>{{VOCO_DAEMON_PATH}}</string><string>{{HOME}}</string><string>{{WORKING_DIR}}</string>",
            &paths("/Users/me", "/opt/voco/voco-daemon", "/opt/voco"),
        );

        assert_eq!(
            rendered,
            "<string>/opt/voco/voco-daemon</string><string>/Users/me</string><string>/opt/voco</string>"
        );
    }

    #[test]
    fn renders_plist_with_xml_escaped_paths() {
        let rendered = render_plist_from_template(
            "<string>{{VOCO_DAEMON_PATH}}</string><string>{{HOME}}</string><string>{{WORKING_DIR}}</string>",
            &paths(
                "/Users/a&b",
                "/tmp/voco<debug>/voco-daemon",
                "/tmp/quote\"single'work",
            ),
        );

        assert_eq!(
            rendered,
            "<string>/tmp/voco&lt;debug&gt;/voco-daemon</string><string>/Users/a&amp;b</string><string>/tmp/quote&quot;single&apos;work</string>"
        );
    }

    #[test]
    fn real_template_renders_working_directory() {
        let rendered = render_plist(&paths("/Users/me", "/opt/voco/voco-daemon", "/opt/voco"));

        assert!(rendered.contains("<key>WorkingDirectory</key>"));
        assert!(rendered.contains("<string>/opt/voco</string>"));
        assert!(!rendered.contains("{{WORKING_DIR}}"));
    }

    #[test]
    fn source_tree_current_dir_is_working_dir() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        std::fs::write(tmp.path().join("Cargo.toml"), "[workspace]\n")?;
        std::fs::create_dir_all(tmp.path().join("hud"))?;
        std::fs::write(tmp.path().join("hud/Package.swift"), "// swift\n")?;
        std::fs::create_dir_all(tmp.path().join("packaging"))?;
        std::fs::write(
            tmp.path().join("packaging/com.voco.daemon.plist.tmpl"),
            "<plist/>",
        )?;

        let daemon = tmp.path().join("target/debug/voco-daemon");
        assert_eq!(choose_working_dir(tmp.path(), &daemon), tmp.path());
        Ok(())
    }

    #[test]
    fn non_source_tree_uses_daemon_parent_as_working_dir() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let bin_dir = tmp.path().join("bin");
        std::fs::create_dir_all(&bin_dir)?;
        let daemon = bin_dir.join("voco-daemon");

        assert_eq!(choose_working_dir(tmp.path(), &daemon), bin_dir);
        Ok(())
    }
}
