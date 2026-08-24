import AppKit
import UniformTypeIdentifiers

@MainActor
final class ManagerWindowController: NSWindowController {
    private let store: QuestionStore
    private let onStart: (QuizConfiguration) -> Void
    private var combinedPDFURL: URL?
    private var questionButtons: [Int: NSButton] = [:]

    private let bankPopup = NSPopUpButton()
    private let pdfPathLabel = NSTextField(labelWithString: "请选择包含题目、答案和解析的 PDF")
    private let pdfDropZone = PDFDropZoneView()
    private let selectedCountLabel = NSTextField(labelWithString: "")
    private let scoreSummaryLabel = NSTextField(labelWithString: "")
    private var moduleAccuracyLabels: [NSTextField] = []
    private let rangeStart = NSTextField(string: "1")
    private let rangeEnd = NSTextField(string: "100")
    private let modeControl = NSSegmentedControl(labels: ["逐题判定", "整卷判定"], trackingMode: .selectOne, target: nil, action: nil)
    private let randomToggle = NSButton(checkboxWithTitle: "随机顺序", target: nil, action: nil)
    private let restartWholePaperToggle = NSButton(checkboxWithTitle: "从头开始做（清除本卷断点）", target: nil, action: nil)
    private let wrongToggle = NSButton(checkboxWithTitle: "只做错题", target: nil, action: nil)
    private let lockToggle = NSButton(checkboxWithTitle: "锁定答题页位置", target: nil, action: nil)
    private let hoverToggle = NSButton(checkboxWithTitle: "鼠标移出后缩成小圆球，移入恢复", target: nil, action: nil)
    private let timeLimitField = NSTextField(string: "90")
    private let pauseTimerWhenCollapsedToggle = NSButton(checkboxWithTitle: "缩成小圆球时暂停计时", target: nil, action: nil)
    private let opacitySlider = NSSlider(value: 0.90, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private let opacityValue = NSTextField(labelWithString: "90%")
    private let colorWell = NSColorWell()
    private let fontSizeSlider = NSSlider(value: 17, minValue: 12, maxValue: 30, target: nil, action: nil)
    private let fontSizeValue = NSTextField(labelWithString: "17 pt")
    private let wrongQuestionPopup = NSPopUpButton()
    private let wrongCountLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    init(store: QuestionStore, onStart: @escaping (QuizConfiguration) -> Void) {
        self.store = store
        self.onStart = onStart
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 690, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "轻刷题 - 管理"
        window.minSize = NSSize(width: 620, height: 620)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        loadConfiguration()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let window else { return }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = documentView
        window.contentView = scroll

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        let title = NSTextField(labelWithString: "题库与答题设置")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(title)

        bankPopup.addItem(withTitle: store.bank?.title ?? "未加载题库")
        bankPopup.isEnabled = false
        stack.addArrangedSubview(labeledRow("当前题库", [bankPopup]))
        scoreSummaryLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(labeledRow("整卷成绩", [scoreSummaryLabel]))

        let choosePDF = NSButton(title: "选择合订 PDF…", target: self, action: #selector(selectCombinedPDF))
        let importButton = NSButton(title: "导入并识别", target: self, action: #selector(importCombinedPDF))
        importButton.bezelStyle = .rounded
        stack.addArrangedSubview(row([choosePDF, pdfPathLabel, importButton]))
        pdfPathLabel.lineBreakMode = .byTruncatingMiddle
        pdfDropZone.onPDFsDropped = { [weak self] urls in
            self?.handleDroppedPDFs(urls)
        }
        stack.addArrangedSubview(pdfDropZone)
        pdfDropZone.heightAnchor.constraint(equalToConstant: 68).isActive = true
        pdfDropZone.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true

        stack.addArrangedSubview(separator())

        let selectionTitle = NSTextField(labelWithString: "选择本次要做的题")
        selectionTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        let selectAll = NSButton(title: "全选", target: self, action: #selector(selectAllQuestions))
        let clearAll = NSButton(title: "清空", target: self, action: #selector(clearAllQuestions))
        rangeStart.alignment = .center
        rangeEnd.alignment = .center
        rangeStart.widthAnchor.constraint(equalToConstant: 44).isActive = true
        rangeEnd.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let applyRange = NSButton(title: "应用范围", target: self, action: #selector(applyQuestionRange))
        stack.addArrangedSubview(row([selectionTitle, selectedCountLabel, selectAll, clearAll, NSTextField(labelWithString: "范围"), rangeStart, NSTextField(labelWithString: "至"), rangeEnd, applyRange]))

        let count = store.bank?.questions.count ?? 100
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 5
        for rowIndex in 0..<Int(ceil(Double(count) / 10.0)) {
            var rowViews: [NSView] = []
            for column in 0..<10 {
                let number = rowIndex * 10 + column + 1
                if number <= count {
                    let button = NSButton(checkboxWithTitle: "\(number)", target: self, action: #selector(questionSelectionChanged))
                    button.tag = number
                    button.widthAnchor.constraint(equalToConstant: 54).isActive = true
                    questionButtons[number] = button
                    rowViews.append(button)
                } else {
                    let spacer = NSView()
                    spacer.widthAnchor.constraint(equalToConstant: 54).isActive = true
                    rowViews.append(spacer)
                }
            }
            let row = NSStackView(views: rowViews)
            row.orientation = .horizontal
            row.spacing = 6
            grid.addArrangedSubview(row)
        }
        stack.addArrangedSubview(grid)

        stack.addArrangedSubview(separator())

        let moduleTitle = NSTextField(labelWithString: "模块首次作答正确率")
        moduleTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        stack.addArrangedSubview(moduleTitle)
        for module in QuestionModule.standard {
            let label = NSTextField(labelWithString: "")
            label.widthAnchor.constraint(equalToConstant: 520).isActive = true
            moduleAccuracyLabels.append(label)
            stack.addArrangedSubview(labeledRow("\(module.range.lowerBound)-\(module.range.upperBound)", [label]))
        }

        stack.addArrangedSubview(separator())

        let settingsTitle = NSTextField(labelWithString: "答题页设置")
        settingsTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        stack.addArrangedSubview(settingsTitle)
        modeControl.widthAnchor.constraint(equalToConstant: 300).isActive = true
        modeControl.target = self
        modeControl.action = #selector(judgeModeChanged)
        stack.addArrangedSubview(labeledRow("判题方式", [modeControl]))
        wrongToggle.target = self
        wrongToggle.action = #selector(scoreSelectionChanged)
        stack.addArrangedSubview(row([randomToggle, wrongToggle, lockToggle]))
        stack.addArrangedSubview(restartWholePaperToggle)
        timeLimitField.alignment = .center
        timeLimitField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        stack.addArrangedSubview(labeledRow("整卷计时", [timeLimitField, NSTextField(labelWithString: "分钟"), pauseTimerWhenCollapsedToggle]))
        stack.addArrangedSubview(hoverToggle)

        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        opacitySlider.widthAnchor.constraint(equalToConstant: 280).isActive = true
        colorWell.widthAnchor.constraint(equalToConstant: 50).isActive = true
        stack.addArrangedSubview(labeledRow("背景透明度", [opacitySlider, opacityValue, NSTextField(labelWithString: "（只影响背景）")]))
        stack.addArrangedSubview(labeledRow("题目与选项颜色", [colorWell]))
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(fontSizeChanged)
        fontSizeSlider.widthAnchor.constraint(equalToConstant: 280).isActive = true
        stack.addArrangedSubview(labeledRow("答题字体大小", [fontSizeSlider, fontSizeValue]))

        let deleteWrongButton = NSButton(title: "删除选中错题记录", target: self, action: #selector(deleteSelectedWrongQuestion))
        stack.addArrangedSubview(labeledRow("错题管理", [wrongQuestionPopup, wrongCountLabel, deleteWrongButton]))
        refreshWrongQuestions()

        statusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusLabel)
        statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true

        let startButton = NSButton(title: "开始 / 更新答题页", target: self, action: #selector(startQuiz))
        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.keyEquivalent = "\r"
        stack.addArrangedSubview(startButton)
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func labeledRow(_ label: String, _ views: [NSView]) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.widthAnchor.constraint(equalToConstant: 100).isActive = true
        return row([title] + views)
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func loadConfiguration() {
        let config = QuizConfiguration.load(questionCount: store.bank?.questions.count ?? 100)
        for (number, button) in questionButtons {
            button.state = config.selectedQuestionIDs.contains(number) ? .on : .off
        }
        modeControl.selectedSegment = config.judgeMode.rawValue
        updateRestartWholePaperAvailability()
        randomToggle.state = config.randomOrder ? .on : .off
        wrongToggle.state = config.wrongOnly ? .on : .off
        lockToggle.state = config.panelLocked ? .on : .off
        hoverToggle.state = config.hoverHide ? .on : .off
        opacitySlider.doubleValue = config.backgroundOpacity
        opacityValue.stringValue = "\(Int(config.backgroundOpacity * 100))%"
        colorWell.color = config.fontColor
        fontSizeSlider.doubleValue = config.fontSize
        fontSizeValue.stringValue = "\(Int(config.fontSize)) pt"
        timeLimitField.integerValue = config.wholePaperTimeLimitMinutes
        pauseTimerWhenCollapsedToggle.state = config.pauseTimerWhenCollapsed ? .on : .off
        updateSelectedCount()
        refreshModuleStatistics()
    }

    private func currentConfiguration() -> QuizConfiguration {
        QuizConfiguration(
            selectedQuestionIDs: Set(questionButtons.compactMap { $0.value.state == .on ? $0.key : nil }),
            randomOrder: randomToggle.state == .on,
            wrongOnly: wrongToggle.state == .on,
            judgeMode: JudgeMode(rawValue: modeControl.selectedSegment) ?? .immediate,
            panelLocked: lockToggle.state == .on,
            hoverHide: hoverToggle.state == .on,
            backgroundOpacity: opacitySlider.doubleValue,
            fontColor: colorWell.color,
            fontSize: fontSizeSlider.doubleValue,
            restartWholePaper: restartWholePaperToggle.state == .on,
            wholePaperTimeLimitMinutes: max(1, timeLimitField.integerValue),
            pauseTimerWhenCollapsed: pauseTimerWhenCollapsedToggle.state == .on
        )
    }

    @objc private func judgeModeChanged() {
        updateRestartWholePaperAvailability()
    }

    @objc private func scoreSelectionChanged() {
        refreshScoreSummary()
    }

    private func updateRestartWholePaperAvailability() {
        let isWholePaper = modeControl.selectedSegment == JudgeMode.wholePaper.rawValue
        restartWholePaperToggle.isEnabled = isWholePaper
        timeLimitField.isEnabled = isWholePaper
        pauseTimerWhenCollapsedToggle.isEnabled = isWholePaper
        if !isWholePaper { restartWholePaperToggle.state = .off }
    }

    @objc private func questionSelectionChanged() { updateSelectedCount() }

    private func updateSelectedCount() {
        let count = questionButtons.values.filter { $0.state == .on }.count
        selectedCountLabel.stringValue = "已选 \(count) 题"
        selectedCountLabel.textColor = count == 0 ? .systemRed : .secondaryLabelColor
        refreshScoreSummary()
    }

    private func effectiveSelectedQuestionIDs() -> [Int] {
        let selected = questionButtons.compactMap { $0.value.state == .on ? $0.key : nil }.sorted()
        guard wrongToggle.state == .on else { return selected }
        let wrong = selected.filter { store.progress.wrongQuestionIDs.contains($0) }
        return wrong.isEmpty ? selected : wrong
    }

    private func refreshScoreSummary() {
        let ids = effectiveSelectedQuestionIDs()
        guard !ids.isEmpty else {
            scoreSummaryLabel.stringValue = "请先选题"
            return
        }
        let key = store.paperScoreKey(questionIDs: ids)
        if let record = store.paperScore(for: key) {
            scoreSummaryLabel.stringValue = "上次 \(record.lastScore)/\(record.totalQuestions)  ·  最高 \(record.bestScore)/\(record.totalQuestions)  ·  已完成 \(record.attempts) 次"
        } else {
            scoreSummaryLabel.stringValue = "上次 --/\(ids.count)  ·  最高 --/\(ids.count)"
        }
    }

    private func refreshModuleStatistics() {
        let accuracies = store.moduleAccuracies()
        for (index, accuracy) in accuracies.enumerated() where index < moduleAccuracyLabels.count {
            if let percentage = accuracy.percentage {
                moduleAccuracyLabels[index].stringValue = "\(accuracy.module.name)  \(percentage)%  (首次答对 \(accuracy.correct)/\(accuracy.answered)，共 \(accuracy.total) 题)"
            } else {
                moduleAccuracyLabels[index].stringValue = "\(accuracy.module.name)  --  (尚无首次作答记录，共 \(accuracy.total) 题)"
            }
        }
    }

    @objc private func selectAllQuestions() {
        questionButtons.values.forEach { $0.state = .on }
        updateSelectedCount()
    }

    @objc private func clearAllQuestions() {
        questionButtons.values.forEach { $0.state = .off }
        updateSelectedCount()
    }

    @objc private func applyQuestionRange() {
        let lower = max(1, Int(rangeStart.stringValue) ?? 1)
        let upper = min(questionButtons.count, Int(rangeEnd.stringValue) ?? questionButtons.count)
        questionButtons.forEach { $0.value.state = ($0.key >= min(lower, upper) && $0.key <= max(lower, upper)) ? .on : .off }
        updateSelectedCount()
    }

    @objc private func opacityChanged() {
        opacityValue.stringValue = "\(Int(opacitySlider.doubleValue * 100))%"
    }

    @objc private func fontSizeChanged() {
        fontSizeValue.stringValue = "\(Int(fontSizeSlider.doubleValue)) pt"
    }

    private func refreshWrongQuestions() {
        let ids = store.progress.wrongQuestionIDs.sorted()
        wrongQuestionPopup.removeAllItems()
        if ids.isEmpty {
            wrongQuestionPopup.addItem(withTitle: "暂无错题")
            wrongQuestionPopup.isEnabled = false
        } else {
            wrongQuestionPopup.addItems(withTitles: ids.map { "第 \($0) 题" })
            wrongQuestionPopup.isEnabled = true
        }
        wrongCountLabel.stringValue = "共 \(ids.count) 题"
    }

    @objc private func deleteSelectedWrongQuestion() {
        let ids = store.progress.wrongQuestionIDs.sorted()
        guard wrongQuestionPopup.isEnabled, wrongQuestionPopup.indexOfSelectedItem < ids.count else { return }
        store.progress.removeWrong(questionID: ids[wrongQuestionPopup.indexOfSelectedItem])
        store.saveProgress()
        refreshWrongQuestions()
    }

    @objc private func selectCombinedPDF() {
        choosePDF(title: "选择包含题目、答案和解析的 PDF") { [weak self] url in
            self?.combinedPDFURL = url
            self?.pdfPathLabel.stringValue = url.lastPathComponent
        }
    }

    private func choosePDF(title: String, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        completion(url)
    }

    @objc private func importCombinedPDF() {
        guard let combinedPDFURL else {
            showAlert(title: "请选择 PDF", message: "请选择一个同时包含题目、答案和解析的 PDF。")
            return
        }
        statusLabel.stringValue = "正在识别 PDF，请稍候…"
        window?.displayIfNeeded()
        do {
            try store.importPDF(url: combinedPDFURL)
            bankPopup.removeAllItems()
            bankPopup.addItem(withTitle: store.bank?.title ?? "已导入题库")
            statusLabel.stringValue = "导入成功：\(store.bank?.questions.count ?? 0) 道题。"
            refreshScoreSummary()
            refreshModuleStatistics()
        } catch {
            statusLabel.stringValue = "导入失败：\(error.localizedDescription)"
            showAlert(title: "导入失败", message: error.localizedDescription)
        }
    }

    private func handleDroppedPDFs(_ urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else { return }

        combinedPDFURL = pdfs[0]
        pdfPathLabel.stringValue = pdfs[0].lastPathComponent
        statusLabel.stringValue = "已接收 PDF，正在自动识别并导入…"
        importCombinedPDF()
    }

    @objc private func startQuiz() {
        let config = currentConfiguration()
        guard !config.selectedQuestionIDs.isEmpty else {
            showAlert(title: "尚未选择题目", message: "请至少勾选一道题。")
            return
        }
        config.save()
        onStart(config)
        restartWholePaperToggle.state = .off
        window?.orderOut(nil)
    }

    func showManager() {
        refreshWrongQuestions()
        refreshScoreSummary()
        refreshModuleStatistics()
        guard let window else { return }
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let targetSize = NSSize(
            width: min(690, max(620, visibleFrame.width - 40)),
            height: min(760, max(620, visibleFrame.height - 40))
        )
        let targetFrame = NSRect(
            x: visibleFrame.midX - targetSize.width / 2,
            y: visibleFrame.midY - targetSize.height / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        window.setFrame(targetFrame, display: true)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
