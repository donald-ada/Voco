// crates/voco-config/tests/roundtrip.rs
use voco_config::schema::Config;
use voco_config::ConfigIo;

#[test]
fn default_roundtrips_through_disk() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("config.toml");

    let original = Config::default();
    ConfigIo::save_to(&path, &original).expect("save");

    let loaded = ConfigIo::load_from(&path).expect("load");
    assert_eq!(loaded, original);
}

#[test]
fn load_missing_returns_default() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("does_not_exist.toml");
    let loaded = ConfigIo::load_from(&path).expect("load");
    assert_eq!(loaded, Config::default());
}

#[test]
fn save_is_atomic() {
    // Save twice; intermediate files must not leak.
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("config.toml");
    ConfigIo::save_to(&path, &Config::default()).unwrap();
    ConfigIo::save_to(&path, &Config::default()).unwrap();

    let entries: Vec<_> = std::fs::read_dir(dir.path())
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().to_string())
        .collect();
    assert_eq!(entries, vec!["config.toml".to_string()]);
}
