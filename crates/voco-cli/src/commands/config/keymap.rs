//! Crossterm `KeyEvent` → macOS `(keycode, modifiers, display_name)` for the
//! wizard's "Custom..." hotkey path.
//!
//! Coverage is best-effort: common alphanumeric, function, and arrow keys.
//! Anything else returns `None` and the wizard re-prompts.

use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};

// CGEventFlags bitmasks. The Fn flag (0x00800000) lives on the preset side
// — terminals can't reliably surface raw Fn presses, so it's not mapped here.
const CMD_MASK: u32 = 0x00100000;
const SHIFT_MASK: u32 = 0x00020000;
const CTRL_MASK: u32 = 0x00040000;
const OPTION_MASK: u32 = 0x00080000;

pub struct CapturedHotkey {
    pub keycode: u16,
    pub modifiers: u32,
    pub display_name: String,
}

/// `None` if the event is just a pure-modifier press, or maps to no
/// known macOS keycode.
pub fn capture(ev: &KeyEvent) -> Option<CapturedHotkey> {
    if ev.kind != KeyEventKind::Press {
        return None;
    }
    let kc = match ev.code {
        KeyCode::Char(c) => char_to_keycode(c)?,
        KeyCode::F(n) => fn_key_to_keycode(n)?,
        KeyCode::Up => 126,
        KeyCode::Down => 125,
        KeyCode::Left => 123,
        KeyCode::Right => 124,
        KeyCode::Esc => 53,
        KeyCode::Tab => 48,
        KeyCode::Enter => 36,
        KeyCode::Backspace => 51,
        KeyCode::Delete => 117,
        KeyCode::Home => 115,
        KeyCode::End => 119,
        KeyCode::PageUp => 116,
        KeyCode::PageDown => 121,
        _ => return None,
    };

    let mut modifiers = 0u32;
    if ev.modifiers.contains(KeyModifiers::SHIFT) {
        modifiers |= SHIFT_MASK;
    }
    if ev.modifiers.contains(KeyModifiers::CONTROL) {
        modifiers |= CTRL_MASK;
    }
    if ev.modifiers.contains(KeyModifiers::ALT) {
        modifiers |= OPTION_MASK;
    }
    if ev.modifiers.contains(KeyModifiers::SUPER) {
        modifiers |= CMD_MASK;
    }

    Some(CapturedHotkey {
        keycode: kc,
        modifiers,
        display_name: render_name(ev),
    })
}

fn char_to_keycode(c: char) -> Option<u16> {
    Some(match c.to_ascii_lowercase() {
        'a' => 0,
        'b' => 11,
        'c' => 8,
        'd' => 2,
        'e' => 14,
        'f' => 3,
        'g' => 5,
        'h' => 4,
        'i' => 34,
        'j' => 38,
        'k' => 40,
        'l' => 37,
        'm' => 46,
        'n' => 45,
        'o' => 31,
        'p' => 35,
        'q' => 12,
        'r' => 15,
        's' => 1,
        't' => 17,
        'u' => 32,
        'v' => 9,
        'w' => 13,
        'x' => 7,
        'y' => 16,
        'z' => 6,
        '0' => 29,
        '1' => 18,
        '2' => 19,
        '3' => 20,
        '4' => 21,
        '5' => 23,
        '6' => 22,
        '7' => 26,
        '8' => 28,
        '9' => 25,
        ' ' => 49,
        _ => return None,
    })
}

fn fn_key_to_keycode(n: u8) -> Option<u16> {
    Some(match n {
        1 => 122,
        2 => 120,
        3 => 99,
        4 => 118,
        5 => 96,
        6 => 97,
        7 => 98,
        8 => 100,
        9 => 101,
        10 => 109,
        11 => 103,
        12 => 111,
        13 => 105,
        14 => 107,
        15 => 113,
        16 => 106,
        17 => 64,
        18 => 79,
        19 => 80,
        _ => return None,
    })
}

fn render_name(ev: &KeyEvent) -> String {
    let mut parts = Vec::new();
    if ev.modifiers.contains(KeyModifiers::CONTROL) {
        parts.push("Ctrl");
    }
    if ev.modifiers.contains(KeyModifiers::ALT) {
        parts.push("Option");
    }
    if ev.modifiers.contains(KeyModifiers::SHIFT) {
        parts.push("Shift");
    }
    if ev.modifiers.contains(KeyModifiers::SUPER) {
        parts.push("Cmd");
    }
    let key = match ev.code {
        KeyCode::Char(c) => format!("{}", c.to_ascii_uppercase()),
        KeyCode::F(n) => format!("F{n}"),
        KeyCode::Up => "↑".into(),
        KeyCode::Down => "↓".into(),
        KeyCode::Left => "←".into(),
        KeyCode::Right => "→".into(),
        KeyCode::Esc => "Esc".into(),
        KeyCode::Tab => "Tab".into(),
        KeyCode::Enter => "Enter".into(),
        KeyCode::Backspace => "Backspace".into(),
        KeyCode::Delete => "Del".into(),
        other => format!("{other:?}"),
    };
    let mut s = parts.join("+");
    if !s.is_empty() {
        s.push('+');
    }
    s.push_str(&key);
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ev(code: KeyCode, mods: KeyModifiers) -> KeyEvent {
        KeyEvent::new(code, mods)
    }

    #[test]
    fn captures_alpha() {
        let h = capture(&ev(KeyCode::Char('q'), KeyModifiers::NONE)).unwrap();
        assert_eq!(h.keycode, 12);
        assert_eq!(h.modifiers, 0);
        assert_eq!(h.display_name, "Q");
    }

    #[test]
    fn captures_modifiers() {
        let h = capture(&ev(
            KeyCode::Char('a'),
            KeyModifiers::CONTROL | KeyModifiers::ALT,
        ))
        .unwrap();
        assert_eq!(h.keycode, 0);
        assert_eq!(h.modifiers, CTRL_MASK | OPTION_MASK);
        assert_eq!(h.display_name, "Ctrl+Option+A");
    }

    #[test]
    fn captures_function_keys() {
        let h = capture(&ev(KeyCode::F(13), KeyModifiers::NONE)).unwrap();
        assert_eq!(h.keycode, 105);
        assert_eq!(h.display_name, "F13");
    }

    #[test]
    fn captures_arrows() {
        assert_eq!(
            capture(&ev(KeyCode::Up, KeyModifiers::NONE))
                .unwrap()
                .keycode,
            126
        );
    }

    #[test]
    fn rejects_unknown_char() {
        assert!(capture(&ev(KeyCode::Char('§'), KeyModifiers::NONE)).is_none());
    }

    #[test]
    fn rejects_non_press() {
        let mut e = ev(KeyCode::Char('a'), KeyModifiers::NONE);
        e.kind = KeyEventKind::Release;
        assert!(capture(&e).is_none());
    }
}
