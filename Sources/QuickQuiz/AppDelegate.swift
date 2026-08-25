import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: QuizPanelController?
    private var managerController: ManagerWindowController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var stateLockMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        do {
            try QuestionStore.shared.load()
            let quizController = QuizPanelController(store: .shared)
            if CommandLine.arguments.contains(where: { $0.hasPrefix("--ui-test") }) {
                quizController.enableUITestingMode()
            }
            panelController = quizController
            let manager = ManagerWindowController(store: .shared) { [weak quizController] configuration in
                quizController?.apply(configuration: configuration, reset: true)
                quizController?.showPanel()
            }
            managerController = manager
            quizController.onCloseToManager = { [weak manager] in
                manager?.showManager()
            }
            quizController.window?.orderOut(nil)
            manager.showManager()
            if CommandLine.arguments.contains("--ui-test") {
                var testConfiguration = QuizConfiguration.load(questionCount: QuestionStore.shared.bank?.questions.count ?? 100)
                testConfiguration.selectedQuestionIDs = Set(1...10)
                testConfiguration.backgroundOpacity = 0
                testConfiguration.hoverHide = false
                testConfiguration.fontSize = 20
                quizController.apply(configuration: testConfiguration, reset: true, persist: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.window?.orderOut(nil)
                    quizController.showPanel()
                }
            }
            if CommandLine.arguments.contains("--ui-test-settlement") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.window?.orderOut(nil)
                    quizController.showSettlementForTesting()
                }
            }
            if CommandLine.arguments.contains("--ui-test-close") {
                var testConfiguration = QuizConfiguration.load(questionCount: QuestionStore.shared.bank?.questions.count ?? 100)
                testConfiguration.selectedQuestionIDs = Set(1...10)
                testConfiguration.hoverHide = false
                quizController.apply(configuration: testConfiguration, reset: true, persist: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.window?.orderOut(nil)
                    quizController.showPanel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        quizController.closeToManagerForTesting()
                        let passed = manager.window?.isVisible == true && quizController.window?.isVisible == false
                        fputs(passed ? "PASS close-return-to-manager\n" : "FAIL close-return-to-manager\n", passed ? stdout : stderr)
                        fflush(passed ? stdout : stderr)
                        NSApp.terminate(nil)
                    }
                }
            }
            if CommandLine.arguments.contains("--ui-test-collapse") {
                var testConfiguration = QuizConfiguration.load(questionCount: QuestionStore.shared.bank?.questions.count ?? 100)
                testConfiguration.selectedQuestionIDs = Set(1...10)
                testConfiguration.backgroundOpacity = 0
                testConfiguration.hoverHide = true
                quizController.apply(configuration: testConfiguration, reset: true, persist: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.window?.orderOut(nil)
                    quizController.showPanel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        quizController.collapseForTesting()
                    }
                }
            }
            if CommandLine.arguments.contains("--ui-test-ball-bounds") {
                var testConfiguration = QuizConfiguration.load(questionCount: QuestionStore.shared.bank?.questions.count ?? 100)
                testConfiguration.selectedQuestionIDs = Set(1...10)
                testConfiguration.hoverHide = true
                quizController.apply(configuration: testConfiguration, reset: true, persist: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.window?.orderOut(nil)
                    quizController.showPanel()
                    let passed = quizController.verifyCollapsedBallScreenBoundsForTesting()
                    fputs(passed ? "PASS collapsed-ball-inside-screen\n" : "FAIL collapsed-ball-inside-screen\n", passed ? stdout : stderr)
                    fflush(passed ? stdout : stderr)
                    NSApp.terminate(nil)
                }
            }
            if CommandLine.arguments.contains("--ui-test-ball-expansion") {
                var testConfiguration = QuizConfiguration.load(questionCount: QuestionStore.shared.bank?.questions.count ?? 100)
                testConfiguration.selectedQuestionIDs = Set(1...10)
                testConfiguration.hoverHide = true
                quizController.apply(configuration: testConfiguration, reset: true, persist: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.window?.orderOut(nil)
                    quizController.showPanel()
                    let passed = quizController.verifyBallDisappearsAfterExpansionForTesting()
                    fputs(passed ? "PASS ball-hidden-after-expansion\n" : "FAIL ball-hidden-after-expansion\n", passed ? stdout : stderr)
                    fflush(passed ? stdout : stderr)
                    NSApp.terminate(nil)
                }
            }
            if CommandLine.arguments.contains("--ui-test-overtime") {
                var testConfiguration = QuizConfiguration.load(questionCount: QuestionStore.shared.bank?.questions.count ?? 100)
                testConfiguration.selectedQuestionIDs = Set(1...10)
                testConfiguration.judgeMode = .wholePaper
                testConfiguration.wholePaperTimeLimitMinutes = 1
                testConfiguration.hoverHide = false
                quizController.apply(configuration: testConfiguration, reset: true, persist: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.window?.orderOut(nil)
                    quizController.showPanel()
                    quizController.showOvertimeForTesting()
                }
            }
            if CommandLine.arguments.contains("--ui-test-resize-check") {
                var testConfiguration = QuizConfiguration.load(questionCount: QuestionStore.shared.bank?.questions.count ?? 100)
                testConfiguration.selectedQuestionIDs = Set(1...10)
                testConfiguration.hoverHide = false
                quizController.apply(configuration: testConfiguration, reset: true, persist: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.window?.orderOut(nil)
                    quizController.showPanel()
                    let passed = quizController.verifyFlexibleSizingForTesting()
                    fputs(passed ? "PASS flexible-resize-wraps-without-width-growth\n" : "FAIL flexible-resize-wraps-without-width-growth\n", passed ? stdout : stderr)
                    fflush(passed ? stdout : stderr)
                    NSApp.terminate(nil)
                }
            }
            if CommandLine.arguments.contains("--ui-test-image-preview") {
                var testConfiguration = QuizConfiguration.load(questionCount: QuestionStore.shared.bank?.questions.count ?? 100)
                testConfiguration.hoverHide = false
                quizController.apply(configuration: testConfiguration, reset: true, persist: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.window?.orderOut(nil)
                    quizController.showPanel()
                    let passed = quizController.showImagePreviewForTesting()
                    fputs(passed ? "PASS image-preview-magnification\n" : "FAIL image-preview-magnification\n", passed ? stdout : stderr)
                    fflush(passed ? stdout : stderr)
                }
            }
            if CommandLine.arguments.contains("--ui-test-image-click") {
                var testConfiguration = QuizConfiguration.load(questionCount: QuestionStore.shared.bank?.questions.count ?? 100)
                testConfiguration.hoverHide = false
                quizController.apply(configuration: testConfiguration, reset: true, persist: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    manager.window?.orderOut(nil)
                    quizController.showPanel()
                    let passed = quizController.showVisualQuestionForClickTesting()
                    fputs(passed ? "PASS visual-question-ready-for-click\n" : "FAIL visual-question-ready-for-click\n", passed ? stdout : stderr)
                    fflush(passed ? stdout : stderr)
                }
            }
            installStatusItem()
            let hotKey = HotKeyManager()
            hotKey.onVisibilityPressed = { [weak self] in self?.panelController?.toggleVisibility() }
            hotKey.onStateLockPressed = { [weak self] in self?.toggleVisibilityStateLock() }
            hotKeyManager = hotKey
        } catch {
            NSApp.setActivationPolicy(.regular)
            let alert = NSAlert()
            alert.messageText = "题库加载失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "题"
        item.button?.toolTip = "轻刷题"
        let menu = NSMenu()
        let managerItem = NSMenuItem(title: "显示管理页", action: #selector(showManager), keyEquivalent: "")
        managerItem.target = self
        menu.addItem(managerItem)
        let showItem = NSMenuItem(title: "显示 / 隐藏答题页（⌘⌥Q）", action: #selector(togglePanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        let lockItem = NSMenuItem(title: "锁定当前显隐状态（⌘⌥L）", action: #selector(toggleVisibilityStateLock), keyEquivalent: "")
        lockItem.target = self
        menu.addItem(lockItem)
        stateLockMenuItem = lockItem
        let resetItem = NSMenuItem(title: "恢复内置题库", action: #selector(restoreBundledBank), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出轻刷题", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() { panelController?.toggleVisibility() }
    @objc private func toggleVisibilityStateLock() {
        guard let panelController else { return }
        let locked = panelController.toggleVisibilityStateLock()
        stateLockMenuItem?.title = locked
            ? "解除当前显隐状态锁定（⌘⌥L）"
            : "锁定当前显隐状态（⌘⌥L）"
    }
    @objc private func showManager() { managerController?.showManager() }

    @objc private func restoreBundledBank() {
        do {
            try QuestionStore.shared.restoreBundledBank()
            let alert = NSAlert()
            alert.messageText = "题库已恢复"
            alert.informativeText = "已恢复内置的 \(QuestionStore.shared.bank?.questions.count ?? 0) 道题，重新启动后生效。"
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "恢复题库失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        panelController?.prepareForApplicationTermination()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.prepareForApplicationTermination()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--ui-test") }) {
            return true
        }
        managerController?.showManager()
        return true
    }
}
