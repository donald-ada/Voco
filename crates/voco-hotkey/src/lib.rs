use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::thread::JoinHandle;

use thiserror::Error;
use tokio::sync::mpsc;
use voco_config::HotkeyConfig;

const ALPHA_SHIFT_MASK: u64 = 0x0001_0000;
const SHIFT_MASK: u64 = 0x0002_0000;
const CTRL_MASK: u64 = 0x0004_0000;
const OPTION_MASK: u64 = 0x0008_0000;
const COMMAND_MASK: u64 = 0x0010_0000;
const FN_MASK: u64 = 0x0080_0000;
const MATCHED_MODIFIER_MASK: u64 = SHIFT_MASK | CTRL_MASK | OPTION_MASK | COMMAND_MASK | FN_MASK;
const ACTIVE_MODIFIER_MASK: u64 = MATCHED_MODIFIER_MASK | ALPHA_SHIFT_MASK;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HotkeyEvent {
    Toggle,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventKind {
    KeyDown,
    KeyUp,
    FlagsChanged,
}

#[derive(Debug, Clone)]
pub struct HotkeyMatcher {
    config: HotkeyConfig,
    pressed: bool,
}

impl HotkeyMatcher {
    pub fn new(config: HotkeyConfig) -> Self {
        Self {
            config,
            pressed: false,
        }
    }

    pub fn handle(&mut self, kind: EventKind, keycode: u16, flags: u64) -> Option<HotkeyEvent> {
        if keycode != self.config.keycode {
            return None;
        }

        match kind {
            EventKind::KeyDown => self.handle_down(flags),
            EventKind::KeyUp => {
                self.pressed = false;
                None
            }
            EventKind::FlagsChanged => {
                if flags_active(flags, self.config.modifiers) {
                    if self.config.modifiers == 0 {
                        self.emit_once()
                    } else {
                        self.handle_down(flags)
                    }
                } else {
                    self.pressed = false;
                    None
                }
            }
        }
    }

    fn handle_down(&mut self, flags: u64) -> Option<HotkeyEvent> {
        if !modifiers_match(flags, self.config.modifiers) {
            return None;
        }
        self.emit_once()
    }

    fn emit_once(&mut self) -> Option<HotkeyEvent> {
        if self.pressed {
            return None;
        }
        self.pressed = true;
        Some(HotkeyEvent::Toggle)
    }
}

fn modifiers_match(flags: u64, modifiers: u32) -> bool {
    let modifiers = modifiers as u64;
    (flags & MATCHED_MODIFIER_MASK) == modifiers
}

fn flags_active(flags: u64, modifiers: u32) -> bool {
    let modifiers = modifiers as u64;
    if modifiers == 0 {
        (flags & ACTIVE_MODIFIER_MASK) != 0
    } else {
        modifiers_match(flags, modifiers as u32)
    }
}

#[derive(Debug, Error)]
pub enum HotkeyError {
    #[error("event tap unavailable: {0}")]
    EventTap(String),
    #[error("hotkey unsupported on this platform")]
    Unsupported,
}

pub struct HotkeyManager {
    installed: Arc<AtomicBool>,
    stop: Arc<AtomicBool>,
    join: Option<JoinHandle<()>>,
}

impl HotkeyManager {
    pub fn install(cfg: &HotkeyConfig, tx: mpsc::Sender<HotkeyEvent>) -> Result<Self, HotkeyError> {
        platform::install(cfg.clone(), tx)
    }

    pub fn is_installed(&self) -> bool {
        self.installed.load(Ordering::SeqCst)
    }
}

impl Drop for HotkeyManager {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}

#[cfg(target_os = "macos")]
pub fn accessibility_trusted() -> bool {
    platform::accessibility_trusted()
}

#[cfg(not(target_os = "macos"))]
pub fn accessibility_trusted() -> bool {
    false
}

#[cfg(target_os = "macos")]
mod platform {
    use super::*;
    use std::ffi::c_void;
    use std::os::raw::{c_double, c_int};
    use std::ptr;
    use std::sync::mpsc as std_mpsc;
    use std::time::Duration;

    type CFAllocatorRef = *const c_void;
    type CFMachPortRef = *mut c_void;
    type CFRunLoopRef = *mut c_void;
    type CFRunLoopSourceRef = *mut c_void;
    type CFStringRef = *const c_void;
    type CGEventRef = *mut c_void;
    type CGEventTapProxy = *mut c_void;
    type CGEventType = u32;

    const K_CG_SESSION_EVENT_TAP: u32 = 1;
    const K_CG_HEAD_INSERT_EVENT_TAP: u32 = 0;
    const K_CG_EVENT_TAP_OPTION_LISTEN_ONLY: u32 = 1;
    const K_CG_EVENT_KEY_DOWN: CGEventType = 10;
    const K_CG_EVENT_KEY_UP: CGEventType = 11;
    const K_CG_EVENT_FLAGS_CHANGED: CGEventType = 12;
    const K_CG_KEYBOARD_EVENT_KEYCODE: u32 = 9;

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXIsProcessTrusted() -> bool;
        fn CGEventTapCreate(
            tap: u32,
            place: u32,
            options: u32,
            events_of_interest: u64,
            callback: extern "C" fn(
                CGEventTapProxy,
                CGEventType,
                CGEventRef,
                *mut c_void,
            ) -> CGEventRef,
            user_info: *mut c_void,
        ) -> CFMachPortRef;
        fn CGEventTapEnable(tap: CFMachPortRef, enable: bool);
        fn CGEventGetIntegerValueField(event: CGEventRef, field: u32) -> i64;
        fn CGEventGetFlags(event: CGEventRef) -> u64;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        static kCFRunLoopDefaultMode: CFStringRef;
        fn CFMachPortCreateRunLoopSource(
            allocator: CFAllocatorRef,
            port: CFMachPortRef,
            order: isize,
        ) -> CFRunLoopSourceRef;
        fn CFRunLoopGetCurrent() -> CFRunLoopRef;
        fn CFRunLoopAddSource(rl: CFRunLoopRef, source: CFRunLoopSourceRef, mode: CFStringRef);
        fn CFRunLoopRemoveSource(rl: CFRunLoopRef, source: CFRunLoopSourceRef, mode: CFStringRef);
        fn CFRunLoopRunInMode(
            mode: CFStringRef,
            seconds: c_double,
            return_after_source_handled: bool,
        ) -> c_int;
        fn CFRelease(cf: *const c_void);
    }

    struct TapContext {
        matcher: HotkeyMatcher,
        tx: mpsc::Sender<HotkeyEvent>,
    }

    pub fn accessibility_trusted() -> bool {
        unsafe { AXIsProcessTrusted() }
    }

    pub fn install(
        cfg: HotkeyConfig,
        tx: mpsc::Sender<HotkeyEvent>,
    ) -> Result<HotkeyManager, HotkeyError> {
        let installed = Arc::new(AtomicBool::new(false));
        let stop = Arc::new(AtomicBool::new(false));
        let (ready_tx, ready_rx) = std_mpsc::channel();
        let thread_installed = installed.clone();
        let thread_stop = stop.clone();

        let join = std::thread::spawn(move || unsafe {
            run_event_tap(cfg, tx, thread_installed, thread_stop, ready_tx);
        });

        match ready_rx.recv_timeout(Duration::from_secs(2)) {
            Ok(Ok(())) => Ok(HotkeyManager {
                installed,
                stop,
                join: Some(join),
            }),
            Ok(Err(err)) => {
                let _ = join.join();
                Err(err)
            }
            Err(_) => Err(HotkeyError::EventTap(
                "timed out waiting for event tap".into(),
            )),
        }
    }

    unsafe fn run_event_tap(
        cfg: HotkeyConfig,
        tx: mpsc::Sender<HotkeyEvent>,
        installed: Arc<AtomicBool>,
        stop: Arc<AtomicBool>,
        ready_tx: std_mpsc::Sender<Result<(), HotkeyError>>,
    ) {
        let mut context = Box::new(TapContext {
            matcher: HotkeyMatcher::new(cfg),
            tx,
        });
        let context_ptr = context.as_mut() as *mut TapContext as *mut c_void;
        let mask = (1u64 << K_CG_EVENT_KEY_DOWN)
            | (1u64 << K_CG_EVENT_KEY_UP)
            | (1u64 << K_CG_EVENT_FLAGS_CHANGED);
        let tap = CGEventTapCreate(
            K_CG_SESSION_EVENT_TAP,
            K_CG_HEAD_INSERT_EVENT_TAP,
            K_CG_EVENT_TAP_OPTION_LISTEN_ONLY,
            mask,
            callback,
            context_ptr,
        );
        if tap.is_null() {
            let _ = ready_tx.send(Err(HotkeyError::EventTap(
                "CGEventTapCreate returned null; grant Accessibility/Input Monitoring".into(),
            )));
            return;
        }
        let source = CFMachPortCreateRunLoopSource(ptr::null(), tap, 0);
        if source.is_null() {
            CFRelease(tap as *const c_void);
            let _ = ready_tx.send(Err(HotkeyError::EventTap(
                "CFMachPortCreateRunLoopSource returned null".into(),
            )));
            return;
        }
        let run_loop = CFRunLoopGetCurrent();
        CFRunLoopAddSource(run_loop, source, kCFRunLoopDefaultMode);
        CGEventTapEnable(tap, true);
        installed.store(true, Ordering::SeqCst);
        let _ = ready_tx.send(Ok(()));

        while !stop.load(Ordering::SeqCst) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
        }

        installed.store(false, Ordering::SeqCst);
        CGEventTapEnable(tap, false);
        CFRunLoopRemoveSource(run_loop, source, kCFRunLoopDefaultMode);
        CFRelease(source as *const c_void);
        CFRelease(tap as *const c_void);
        drop(context);
    }

    extern "C" fn callback(
        _proxy: CGEventTapProxy,
        event_type: CGEventType,
        event: CGEventRef,
        user_info: *mut c_void,
    ) -> CGEventRef {
        let Some(kind) = event_kind(event_type) else {
            return event;
        };
        if user_info.is_null() || event.is_null() {
            return event;
        }
        unsafe {
            let context = &mut *(user_info as *mut TapContext);
            let keycode = CGEventGetIntegerValueField(event, K_CG_KEYBOARD_EVENT_KEYCODE) as u16;
            let flags = CGEventGetFlags(event);
            if let Some(event) = context.matcher.handle(kind, keycode, flags) {
                let _ = context.tx.try_send(event);
            }
        }
        event
    }

    fn event_kind(event_type: CGEventType) -> Option<EventKind> {
        match event_type {
            K_CG_EVENT_KEY_DOWN => Some(EventKind::KeyDown),
            K_CG_EVENT_KEY_UP => Some(EventKind::KeyUp),
            K_CG_EVENT_FLAGS_CHANGED => Some(EventKind::FlagsChanged),
            _ => None,
        }
    }
}

#[cfg(not(target_os = "macos"))]
mod platform {
    use super::*;

    pub fn install(
        _cfg: HotkeyConfig,
        _tx: mpsc::Sender<HotkeyEvent>,
    ) -> Result<HotkeyManager, HotkeyError> {
        Err(HotkeyError::Unsupported)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use voco_config::HotkeyConfig;

    fn cfg(keycode: u16, modifiers: u32) -> HotkeyConfig {
        HotkeyConfig {
            keycode,
            modifiers,
            display_name: "test".into(),
        }
    }

    #[test]
    fn keydown_matches_exact_key_and_debounces_until_keyup() {
        let mut matcher = HotkeyMatcher::new(cfg(80, 0));

        assert_eq!(
            matcher.handle(EventKind::KeyDown, 80, 0),
            Some(HotkeyEvent::Toggle)
        );
        assert_eq!(matcher.handle(EventKind::KeyDown, 80, 0), None);
        assert_eq!(matcher.handle(EventKind::KeyUp, 80, 0), None);
        assert_eq!(
            matcher.handle(EventKind::KeyDown, 80, 0),
            Some(HotkeyEvent::Toggle)
        );
    }

    #[test]
    fn keydown_requires_configured_modifiers() {
        let mut matcher = HotkeyMatcher::new(cfg(12, COMMAND_MASK as u32));

        assert_eq!(matcher.handle(EventKind::KeyDown, 12, 0), None);
        assert_eq!(
            matcher.handle(EventKind::KeyDown, 12, COMMAND_MASK),
            Some(HotkeyEvent::Toggle)
        );
    }

    #[test]
    fn keydown_ignores_extra_modifiers() {
        let mut matcher = HotkeyMatcher::new(cfg(12, COMMAND_MASK as u32));

        assert_eq!(
            matcher.handle(EventKind::KeyDown, 12, COMMAND_MASK | OPTION_MASK),
            None
        );
    }

    #[test]
    fn flags_changed_ignores_extra_modifiers() {
        let mut matcher = HotkeyMatcher::new(cfg(63, FN_MASK as u32));

        assert_eq!(
            matcher.handle(EventKind::FlagsChanged, 63, FN_MASK | COMMAND_MASK),
            None
        );
    }

    #[test]
    fn flags_changed_supports_modifier_only_hotkeys() {
        let mut matcher = HotkeyMatcher::new(cfg(54, 0));

        assert_eq!(
            matcher.handle(EventKind::FlagsChanged, 54, COMMAND_MASK),
            Some(HotkeyEvent::Toggle)
        );
        assert_eq!(
            matcher.handle(EventKind::FlagsChanged, 54, COMMAND_MASK),
            None
        );
        assert_eq!(matcher.handle(EventKind::FlagsChanged, 54, 0), None);
        assert_eq!(
            matcher.handle(EventKind::FlagsChanged, 54, COMMAND_MASK),
            Some(HotkeyEvent::Toggle)
        );
    }

    #[test]
    fn wrong_key_is_ignored() {
        let mut matcher = HotkeyMatcher::new(cfg(80, 0));

        assert_eq!(matcher.handle(EventKind::KeyDown, 79, 0), None);
        assert_eq!(
            matcher.handle(EventKind::FlagsChanged, 79, COMMAND_MASK),
            None
        );
    }
}
