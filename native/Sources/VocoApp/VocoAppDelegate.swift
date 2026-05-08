import AppKit
import VocoAppCore

@MainActor
final class VocoAppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: AppCoordinator?
    var showSettingsWindow: (AppCoordinator) -> Void = { coordinator in
        SettingsWindowPresenter.shared.show(coordinator: coordinator)
    }
    var currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    var currentBundleIdentifier: String? = Bundle.main.bundleIdentifier
    var runningApplications: () -> [VocoRunningApplicationSnapshot] = {
        NSWorkspace.shared.runningApplications.map {
            VocoRunningApplicationSnapshot(
                processIdentifier: $0.processIdentifier,
                bundleIdentifier: $0.bundleIdentifier
            )
        }
    }
    var activateRunningApplication: (pid_t) -> Void = { processIdentifier in
        NSRunningApplication(processIdentifier: processIdentifier)?.activate(
            options: [.activateAllWindows]
        )
    }
    var postShowSettingsWindowNotification: () -> Void = {
        DistributedNotificationCenter.default().post(
            name: .vocoShowSettingsWindow,
            object: Bundle.main.bundleIdentifier
        )
    }
    var terminateCurrentApplication: () -> Void = {
        NSApplication.shared.terminate(nil)
    }
    var scheduleDelayedSingleInstanceCheck: (@escaping @MainActor () -> Void) -> Void = { check in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            Task { @MainActor in
                check()
            }
        }
    }

    private var showSettingsObserver: NSObjectProtocol?
    private var hasPresentedInitialSettingsWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installShowSettingsObserverIfNeeded()

        if enforceSingleInstanceIfNeeded() {
            return
        }

        showInitialSettingsWindowIfNeeded()
        scheduleDelayedSingleInstanceCheck { [weak self] in
            _ = self?.enforceSingleInstanceIfNeeded()
        }
    }

    @discardableResult
    func enforceSingleInstanceIfNeeded() -> Bool {
        guard let existingInstance = VocoSingleInstancePolicy.existingInstance(
            currentProcessIdentifier: currentProcessIdentifier,
            currentBundleIdentifier: currentBundleIdentifier,
            runningApplications: runningApplications()
        ) else {
            return false
        }

        postShowSettingsWindowNotification()
        activateRunningApplication(existingInstance.processIdentifier)
        terminateCurrentApplication()
        return true
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard let coordinator else {
            return false
        }

        coordinator.prepareForSettingsPresentation()
        showSettingsWindow(coordinator)
        return false
    }

    func coordinatorDidBecomeAvailable() {
        DispatchQueue.main.async { [weak self] in
            self?.showInitialSettingsWindowIfNeeded()
        }
    }

    private func showInitialSettingsWindowIfNeeded() {
        guard !hasPresentedInitialSettingsWindow,
              let coordinator,
              !coordinator.silentLaunchEnabled else {
            return
        }

        hasPresentedInitialSettingsWindow = true
        coordinator.prepareForSettingsPresentation()
        showSettingsWindow(coordinator)
    }

    private func installShowSettingsObserverIfNeeded() {
        guard showSettingsObserver == nil else {
            return
        }

        showSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: .vocoShowSettingsWindow,
            object: currentBundleIdentifier,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let coordinator = self.coordinator else {
                    return
                }

                coordinator.prepareForSettingsPresentation()
                self.showSettingsWindow(coordinator)
            }
        }
    }
}
