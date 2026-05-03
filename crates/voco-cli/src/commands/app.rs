use crate::AppAction;
use anyhow::{bail, Result};

pub fn run(action: AppAction) -> Result<()> {
    match action {
        AppAction::Install { .. } => {
            bail!("voco app install is parsed but install implementation is not wired yet")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

    fn write_bundle_plist(path: &Path, identifier: &str, executable: &str) -> anyhow::Result<()> {
        let contents = format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>{identifier}</string>
  <key>CFBundleExecutable</key>
  <string>{executable}</string>
</dict>
</plist>
"#
        );
        std::fs::write(path, contents)?;
        Ok(())
    }

    #[cfg(unix)]
    fn make_executable(path: &Path) -> anyhow::Result<()> {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = std::fs::metadata(path)?.permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(path, permissions)?;
        Ok(())
    }

    fn create_test_bundle(
        tmp: &tempfile::TempDir,
        name: &str,
    ) -> anyhow::Result<PathBuf> {
        let bundle = tmp.path().join(name);
        let macos = bundle.join("Contents/MacOS");
        std::fs::create_dir_all(&macos)?;
        write_bundle_plist(
            &bundle.join("Contents/Info.plist"),
            "com.voco.app",
            "voco-daemon",
        )?;
        for executable in ["voco", "voco-daemon", "voco-hud"] {
            let path = macos.join(executable);
            std::fs::write(&path, b"#!/bin/sh\n")?;
            make_executable(&path)?;
        }
        Ok(bundle)
    }

    #[test]
    fn install_destination_defaults_to_home_applications() {
        let home = Path::new("/tmp/voco-home");

        assert_eq!(
            install_destination(home),
            PathBuf::from("/tmp/voco-home/Applications/Voco.app")
        );
    }

    #[test]
    fn missing_home_fails_loudly() {
        let err = home_dir_from(None).unwrap_err();

        assert!(err
            .to_string()
            .contains("HOME is not set; cannot resolve app install path"));
    }

    #[test]
    fn applications_path_as_file_fails_without_deleting_file() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let source = create_test_bundle(&tmp, "source/Voco.app")?;
        let home = tmp.path().join("home");
        std::fs::create_dir_all(&home)?;
        let applications = home.join("Applications");
        std::fs::write(&applications, b"not a directory")?;

        let err = install_app_bundle(&source, &home).unwrap_err();

        assert!(err
            .to_string()
            .contains("Applications path is not a directory"));
        assert_eq!(std::fs::read(&applications)?, b"not a directory");
        Ok(())
    }

    #[test]
    fn destination_file_fails_without_deleting_file() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let source = create_test_bundle(&tmp, "source/Voco.app")?;
        let home = tmp.path().join("home");
        let applications = home.join("Applications");
        std::fs::create_dir_all(&applications)?;
        let destination = applications.join("Voco.app");
        std::fs::write(&destination, b"not a directory")?;

        let err = install_app_bundle(&source, &home).unwrap_err();

        assert!(err
            .to_string()
            .contains("installed app path exists but is not a directory"));
        assert_eq!(std::fs::read(&destination)?, b"not a directory");
        Ok(())
    }

    #[test]
    fn install_app_bundle_copies_bundle_and_preserves_executables() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let source = create_test_bundle(&tmp, "source/Voco.app")?;
        let home = tmp.path().join("home");

        let installed = install_app_bundle(&source, &home)?;

        assert_eq!(
            installed.bundle_path,
            home.join("Applications/Voco.app").canonicalize()?
        );
        assert!(installed.daemon_path.is_file());
        assert!(is_executable(&installed.daemon_path));
        assert!(is_executable(&installed.working_dir.join("voco")));
        assert!(is_executable(&installed.working_dir.join("voco-hud")));
        Ok(())
    }

    #[test]
    fn replacing_existing_bundle_keeps_new_bundle() -> anyhow::Result<()> {
        let tmp = tempfile::tempdir()?;
        let first = create_test_bundle(&tmp, "first/Voco.app")?;
        let second = create_test_bundle(&tmp, "second/Voco.app")?;
        let home = tmp.path().join("home");

        install_app_bundle(&first, &home)?;
        std::fs::write(
            home.join("Applications/Voco.app/Contents/MacOS/marker"),
            b"old",
        )?;
        let installed = install_app_bundle(&second, &home)?;

        assert!(installed.daemon_path.is_file());
        assert!(!home
            .join("Applications/Voco.app/Contents/MacOS/marker")
            .exists());
        Ok(())
    }

    #[cfg(unix)]
    fn is_executable(path: &Path) -> bool {
        use std::os::unix::fs::PermissionsExt;
        std::fs::metadata(path)
            .map(|metadata| metadata.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    }
}
