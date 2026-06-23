import AppKit

final class HibernateProgressController {
    static let shared = HibernateProgressController()

    private var panel: NSPanel?
    private var titleLabel: NSTextField?
    private var detailLabel: NSTextField?
    private var cancelButton: NSButton?
    private var timer: Timer?
    private var onReady: (() -> Void)?
    private var activeGeneration = 0
    private var waitedSeconds = 0
    private let maxACWaitSeconds = 45

    private init() {}

    func begin(generation: Int, onReady: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.finish()
            self.activeGeneration = generation
            self.onReady = onReady
            self.waitedSeconds = 0
            self.showPanel(title: "Preparing hibernate…", detail: "Checking system status")
            self.evaluateAndContinue()
        }
    }

    func cancel() {
        DispatchQueue.main.async {
            self.finish()
        }
    }

    private func evaluateAndContinue() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        tick()
    }

    private func tick() {
        guard onReady != nil else { return }

        let status = SleepAssertionMonitor.evaluate()

        if !status.blocked {
            showPanel(title: "Hibernating…", detail: "Starting now")
            complete()
            return
        }

        waitedSeconds += 1
        let remaining = max(0, (status.suggestedWaitSeconds ?? maxACWaitSeconds) - waitedSeconds)
        let reason = status.reason ?? "Waiting for AC power cooldown"
        showPanel(
            title: "Preparing hibernate…",
            detail: "\(reason)\nStarting in \(remaining)s"
        )

        if waitedSeconds >= (status.suggestedWaitSeconds ?? maxACWaitSeconds) {
            showPanel(title: "Hibernating…", detail: "Starting now")
            complete()
        }
    }

    private func complete() {
        guard let ready = onReady else { return }
        finish()
        ready()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        onReady = nil
        panel?.orderOut(nil)
        panel = nil
        titleLabel = nil
        detailLabel = nil
        cancelButton = nil
    }

    @objc private func cancelPressed() {
        HibernateRunner.cancelPending()
        finish()
    }

    private func showPanel(title: String, detail: String) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                styleMask: [.titled, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "Hibernate Control"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.center()

            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .boldSystemFont(ofSize: 14)
            titleLabel.alignment = .center
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.alignment = .center
            detailLabel.lineBreakMode = .byWordWrapping
            detailLabel.maximumNumberOfLines = 3
            detailLabel.translatesAutoresizingMaskIntoConstraints = false

            let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
            cancelButton.bezelStyle = .rounded
            cancelButton.translatesAutoresizingMaskIntoConstraints = false

            let content = NSView()
            content.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(titleLabel)
            content.addSubview(detailLabel)
            content.addSubview(cancelButton)
            panel.contentView = content

            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
                detailLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                detailLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                cancelButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 12),
                cancelButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                cancelButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            ])

            self.panel = panel
            self.titleLabel = titleLabel
            self.detailLabel = detailLabel
            self.cancelButton = cancelButton
        }

        titleLabel?.stringValue = title
        detailLabel?.stringValue = detail
        panel?.orderFrontRegardless()
    }
}

enum SleepAssertionMonitor {
    struct Status {
        var blocked: Bool
        var reason: String?
        var suggestedWaitSeconds: Int?
    }

    static func evaluate() -> Status {
        let output = runPmsetAssertions()
        guard let listed = listedAssertions(from: output) else {
            return Status(blocked: false, reason: nil, suggestedWaitSeconds: nil)
        }

        if listed.contains("acwakelinger") {
            let timeout = parseTimeoutSeconds(from: listed, near: "acwakelinger")
            return Status(
                blocked: true,
                reason: "Waiting for AC power cooldown",
                suggestedWaitSeconds: min(timeout.map { $0 + 2 } ?? 30, 45)
            )
        }

        return Status(blocked: false, reason: nil, suggestedWaitSeconds: nil)
    }

    private static func listedAssertions(from output: String) -> String? {
        guard let range = output.range(of: "Listed by owning process:") else { return nil }
        return String(output[range.upperBound...])
    }

    private static func runPmsetAssertions() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func parseTimeoutSeconds(from output: String, near keyword: String) -> Int? {
        guard let keywordRange = output.range(of: keyword) else { return nil }
        let section = output[keywordRange.lowerBound...]
        let pattern = #"Timeout will fire in (\d+) sec"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsSection = String(section) as NSString
        let range = NSRange(location: 0, length: nsSection.length)
        guard let match = regex.firstMatch(in: nsSection as String, range: range),
              match.numberOfRanges > 1 else { return nil }
        let valueRange = match.range(at: 1)
        return NumberFormatter().number(from: nsSection.substring(with: valueRange))?.intValue
    }
}