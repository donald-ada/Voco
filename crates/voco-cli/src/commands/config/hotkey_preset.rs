//! macOS keycode/modifier presets for the wizard's "Hotkey" question.
//!
//! Phase 4's CGEventTap consumer will read this same table — promote to
//! `voco-config::hotkey_presets` once that lands. For now, hardcoded here.

use voco_config::HotkeyConfig;

/// CGEventFlags secondary-Fn bit. `kCGEventFlagMaskSecondaryFn = 0x00800000`.
const FN_MASK: u32 = 0x00800000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HotkeyPreset {
    RightCommand,
    Fn,
    F19,
    CapsLock,
    Custom,
}

impl HotkeyPreset {
    pub const ALL: &'static [HotkeyPreset] = &[
        HotkeyPreset::RightCommand,
        HotkeyPreset::Fn,
        HotkeyPreset::F19,
        HotkeyPreset::CapsLock,
        HotkeyPreset::Custom,
    ];

    pub fn label(self) -> &'static str {
        match self {
            HotkeyPreset::RightCommand => "Right Command",
            HotkeyPreset::Fn => "Fn",
            HotkeyPreset::F19 => "F19",
            HotkeyPreset::CapsLock => "Caps Lock",
            HotkeyPreset::Custom => "Custom...",
        }
    }

    /// Returns `None` for `Custom` — caller must capture a real keypress.
    pub fn to_config(self) -> Option<HotkeyConfig> {
        let (keycode, modifiers, name) = match self {
            HotkeyPreset::RightCommand => (54, 0, "Right Command"),
            HotkeyPreset::Fn => (63, FN_MASK, "Fn"),
            HotkeyPreset::F19 => (80, 0, "F19"),
            HotkeyPreset::CapsLock => (57, 0, "Caps Lock"),
            HotkeyPreset::Custom => return None,
        };
        Some(HotkeyConfig {
            keycode,
            modifiers,
            display_name: name.to_string(),
        })
    }

    /// Best-effort: which preset (if any) matches a config?
    pub fn from_config(cfg: &HotkeyConfig) -> Option<HotkeyPreset> {
        Self::ALL
            .iter()
            .copied()
            .filter(|p| *p != HotkeyPreset::Custom)
            .find(|p| {
                let target = p.to_config().unwrap();
                target.keycode == cfg.keycode && target.modifiers == cfg.modifiers
            })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn presets_have_unique_keycodes() {
        let mut seen = std::collections::HashSet::new();
        for p in HotkeyPreset::ALL.iter().copied() {
            if let Some(cfg) = p.to_config() {
                assert!(
                    seen.insert((cfg.keycode, cfg.modifiers)),
                    "duplicate keycode/mod for {:?}",
                    p
                );
            }
        }
    }

    #[test]
    fn from_config_roundtrips() {
        for p in [
            HotkeyPreset::RightCommand,
            HotkeyPreset::Fn,
            HotkeyPreset::F19,
            HotkeyPreset::CapsLock,
        ] {
            let cfg = p.to_config().unwrap();
            assert_eq!(HotkeyPreset::from_config(&cfg), Some(p));
        }
    }

    #[test]
    fn from_config_returns_none_for_unknown() {
        let cfg = HotkeyConfig {
            keycode: 0xFFFF,
            modifiers: 0xDEAD,
            display_name: "weird".into(),
        };
        assert_eq!(HotkeyPreset::from_config(&cfg), None);
    }
}
