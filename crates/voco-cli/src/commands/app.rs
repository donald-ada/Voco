use crate::commands::launch_agent::{self, AppBundle, LaunchAgent};
use crate::AppAction;
use anyhow::{anyhow, bail, Context, Result};
use std::ffi::OsString;
use std::path::{Path, PathBuf};

pub fn run(action: AppAction) -> Result<()> {
    match action {
        AppAction::Install { app_bundle } => install(app_bundle),
    }
}

fn install(app_bundle: PathBuf) -> Result<()> {
    let home = home_dir()?;
    let installed = install_app_bundle(&app_bundle, &home)?;
    println!(
        "✓ installed app bundle: {}",
        installed.bundle_path.display()
    );
    let agent = LaunchAgent::from_parts(
        home,
        installed.daemon_path.clone(),
        installed.working_dir.clone(),
    );
    launch_agent::install_and_print(&agent).map_err(|err| {
        anyhow!(
            "installed app bundle at {} but LaunchAgent install failed: {}",
            installed.bundle_path.display(),
            err
        )
    })
}

fn home_dir() -> Result<PathBuf> {
    home_dir_from(std::env::var_os("HOME"))
}

fn home_dir_from(home: Option<OsString>) -> Result<PathBuf> {
    home.map(PathBuf::from)
        .ok_or_else(|| anyhow!("HOME is not set; cannot resolve app install path"))
}

fn install_destination(home: &Path) -> PathBuf {
    home.join("Applications/Voco.app")
}

fn install_app_bundle(source_bundle: &Path, home: &Path) -> Result<AppBundle> {
    let source = AppBundle::discover(source_bundle)?;
    let destination = install_destination(home);
    let applications = destination.parent().ok_or_else(|| {
        anyhow!(
            "cannot resolve Applications directory for {}",
            destination.display()
        )
    })?;

    if applications.exists() && !applications.is_dir() {
        bail!(
            "Applications path is not a directory: {}",
            applications.display()
        );
    }
    std::fs::create_dir_all(applications)
        .with_context(|| format!("create Applications directory {}", applications.display()))?;

    if destination.exists() && !destination.is_dir() {
        bail!(
            "installed app path exists but is not a directory: {}",
            destination.display()
        );
    }

    let pid = std::process::id();
    let tmp = applications.join(format!(".Voco.app.tmp-{pid}"));
    let backup = applications.join(format!(".Voco.app.backup-{pid}"));
    remove_dir_if_exists(&tmp)?;
    remove_dir_if_exists(&backup)?;

    copy_dir_recursive(&source.bundle_path, &tmp).with_context(|| {
        format!(
            "copy app bundle from {} to {} failed",
            source.bundle_path.display(),
            tmp.display()
        )
    })?;
    AppBundle::discover(&tmp)?;

    let mut backup_created = false;
    if destination.exists() {
        std::fs::rename(&destination, &backup).with_context(|| {
            format!(
                "replace installed app bundle at {} failed",
                destination.display()
            )
        })?;
        backup_created = true;
    }

    if let Err(err) = std::fs::rename(&tmp, &destination) {
        if backup_created {
            let _ = std::fs::rename(&backup, &destination);
        }
        return Err(anyhow!(
            "replace installed app bundle at {} failed: {}",
            destination.display(),
            err
        ));
    }

    let installed = AppBundle::discover(&destination)?;
    if backup_created {
        remove_dir_if_exists(&backup)?;
    }
    Ok(installed)
}

fn remove_dir_if_exists(path: &Path) -> Result<()> {
    match std::fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err).with_context(|| format!("remove {}", path.display())),
    }
}

fn copy_dir_recursive(source: &Path, destination: &Path) -> Result<()> {
    let metadata = std::fs::symlink_metadata(source)
        .with_context(|| format!("inspect {}", source.display()))?;
    if metadata.file_type().is_symlink() {
        bail!(
            "symlink in app bundle is not supported: {}",
            source.display()
        );
    }
    if metadata.is_dir() {
        std::fs::create_dir(destination)
            .with_context(|| format!("create directory {}", destination.display()))?;
        std::fs::set_permissions(destination, metadata.permissions())
            .with_context(|| format!("copy permissions to directory {}", destination.display()))?;
        for entry in std::fs::read_dir(source)
            .with_context(|| format!("read directory {}", source.display()))?
        {
            let entry = entry?;
            copy_dir_recursive(&entry.path(), &destination.join(entry.file_name()))?;
        }
        return Ok(());
    }
    if metadata.is_file() {
        std::fs::copy(source, destination).with_context(|| {
            format!(
                "copy file {} to {}",
                source.display(),
                destination.display()
            )
        })?;
        std::fs::set_permissions(destination, metadata.permissions())
            .with_context(|| format!("copy permissions to file {}", destination.display()))?;
        return Ok(());
    }
    bail!("unsupported file in app bundle: {}", source.display())
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

    fn create_test_bundle(tmp: &tempfile::TempDir, name: &str) -> anyhow::Result<PathBuf> {
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
