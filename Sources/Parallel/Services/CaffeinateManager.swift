import Foundation
import IOKit.pwr_mgt
import Observation

/// Prevents the display from dimming and the system from idle-sleeping while
/// the user wants it kept awake (e.g. a long background `claude` run).
/// Equivalent to `caffeinate -di` but via native IOPMAssertion so it's
/// scoped to this app's lifetime — quitting Parallel automatically releases.
@Observable
final class CaffeinateManager {
    private(set) var isOn = false

    private var displaySleepAssertion: IOPMAssertionID = 0
    private var systemSleepAssertion: IOPMAssertionID = 0

    func toggle() { isOn ? disable() : enable() }

    func enable() {
        guard !isOn else { return }
        let reason = "Parallel: prevent sleep while a session is active" as CFString
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displaySleepAssertion
        )
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemSleepAssertion
        )
        isOn = true
        AppLogger.app.info("caffeinate ON")
    }

    func disable() {
        guard isOn else { return }
        if displaySleepAssertion != 0 {
            IOPMAssertionRelease(displaySleepAssertion)
            displaySleepAssertion = 0
        }
        if systemSleepAssertion != 0 {
            IOPMAssertionRelease(systemSleepAssertion)
            systemSleepAssertion = 0
        }
        isOn = false
        AppLogger.app.info("caffeinate OFF")
    }

    deinit {
        if displaySleepAssertion != 0 {
            IOPMAssertionRelease(displaySleepAssertion)
        }
        if systemSleepAssertion != 0 {
            IOPMAssertionRelease(systemSleepAssertion)
        }
    }
}
