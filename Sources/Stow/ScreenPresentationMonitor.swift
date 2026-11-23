import AppKit
import ApplicationServices
import Foundation

/// Polls for screen capture / share UI and updates `AppModel.isPresenting`.
@MainActor
final class ScreenPresentationMonitor {
    private let model: AppModel
    private var timer: Timer?
    private let interval: TimeInterval = 0.75

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if model.isPresenting {
            model.setPresenting(false)
        }
    }

    private func tick() {
        let windows = Self.currentWindows()
        let active = PresentationCaptureDetector.isActive(windows: windows)
        model.setPresenting(active)
    }

    private static func currentWindows() -> [PresentationCaptureDetector.WindowInfo] {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [PresentationCaptureDetector.WindowInfo] = []
        result.reserveCapacity(info.count)
        for entry in info {
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            let name = entry[kCGWindowName as String] as? String ?? ""
            let pid = entry[kCGWindowOwnerPID as String] as? pid_t
            let bundleID = pid.flatMap { bundleID(forPID: $0) }
            result.append(
                PresentationCaptureDetector.WindowInfo(
                    ownerName: owner,
                    windowName: name,
                    bundleID: bundleID
                )
            )
        }
        return result
    }

    private static func bundleID(forPID pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
