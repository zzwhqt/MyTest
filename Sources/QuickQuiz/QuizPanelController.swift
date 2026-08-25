import AppKit
import PDFKit

private final class QuizFlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class QuizPanelController: NSWindowController, NSWindowDelegate {
    private static let defaultExpandedSize = NSSize(width: 360, height: 390)
    private static let expandedMinimumSize = NSSize(width: 240, height: 180)
    private static let collapsedSize = NSSize(width: 20, height: 20)

    var onCloseToManager: (() -> Void)?

    private let store: QuestionStore
    private var configuration: QuizConfiguration
    private var sequence: [QuizQuestion] = []
    private var currentIndex = 0
    private var selectedChoice: String?
    private var sessionAnswers: [Int: String] = [:]
    private var settlementController: SettlementWindowController?
    private var activeWholePaperSessionKey: String?
    private var isHoverCollapsed = false
    private var expandedFrame: NSRect?
    private(set) var isVisibilityStateLocked = false
    private var wholePaperElapsedSeconds: TimeInterval = 0
    private var timerStartedAt: Date?
    private var timer: Timer?
    private var suppressPersistenceForTesting = false

    private let rootView = HoverContentView()
    private let contentStack = NSStackView()
    private let ballView = HoverContentView()
    private var ballPanel: NSPanel!
    private let progressLabel = NSTextField(labelWithString: "")
    private let timerLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private let stemLabel = NSTextField(wrappingLabelWithString: "")
    private let pageImageView = ClickableImageView()
    private let imagePreviewOverlay = NSView()
    private let previewScrollView = ZoomableScrollView()
    private let previewImageView = ClickableImageView()
    private let previewZoomOutButton = NSButton(title: "−", target: nil, action: nil)
    private let previewZoomInButton = NSButton(title: "+", target: nil, action: nil)
    private let previewCloseButton = NSButton(title: "×", target: nil, action: nil)
    private var previewKeyMonitor: Any?
    private var currentVisualSource: (url: URL, pageIndex: Int)?
    private let optionStack = NSStackView()
    private var optionButtons: [NSButton] = []
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private let explanationLabel = NSTextField(wrappingLabelWithString: "")
    private let nextButton = NSButton(title: "下一题", target: nil, action: nil)

    init(store: QuestionStore) {
        self.store = store
        self.configuration = QuizConfiguration.load(questionCount: store.bank?.questions.count ?? 100)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultExpandedSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = Self.expandedMinimumSize
        panel.center()
        super.init(window: panel)
        panel.delegate = self
        buildUI()
        buildBallWindow()
        apply(configuration: configuration, reset: true)
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let window else { return }
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 16
        rootView.layer?.masksToBounds = true
        rootView.onMouseEnter = { [weak self] in self?.restoreFromHover() }
        rootView.onMouseExit = { [weak self] in self?.hideForHover() }
        window.contentView = rootView

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 4
        contentStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        progressLabel.font = .systemFont(ofSize: 13, weight: .medium)
        closeButton.target = self
        closeButton.action = #selector(closeToManager)
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.toolTip = "关闭答题页并返回管理页"
        closeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let headerSpacer = NSView()
        let header = NSStackView(views: [progressLabel, headerSpacer, timerLabel, closeButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentStack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -32).isActive = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        let documentView = QuizFlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        let documentStack = NSStackView()
        documentStack.orientation = .vertical
        documentStack.alignment = .leading
        documentStack.spacing = 13
        documentStack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 12, right: 10)
        documentStack.translatesAutoresizingMaskIntoConstraints = false
        documentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        documentStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        documentView.addSubview(documentStack)
        NSLayoutConstraint.activate([
            documentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            documentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            documentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            documentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        contentStack.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -32).isActive = true
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        stemLabel.maximumNumberOfLines = 0
        configureWrappingLabel(stemLabel)
        documentStack.addArrangedSubview(stemLabel)
        stemLabel.widthAnchor.constraint(equalTo: documentStack.widthAnchor, constant: -14).isActive = true

        pageImageView.imageScaling = .scaleProportionallyUpOrDown
        pageImageView.wantsLayer = true
        pageImageView.layer?.backgroundColor = NSColor.white.cgColor
        pageImageView.layer?.cornerRadius = 8
        pageImageView.toolTip = "点击放大图片"
        pageImageView.onClick = { [weak self] in self?.openImagePreview() }
        pageImageView.isHidden = true
        documentStack.addArrangedSubview(pageImageView)
        pageImageView.widthAnchor.constraint(equalTo: documentStack.widthAnchor, constant: -14).isActive = true
        pageImageView.heightAnchor.constraint(equalToConstant: 300).isActive = true

        optionStack.orientation = .vertical
        optionStack.alignment = .leading
        optionStack.spacing = 10
        documentStack.addArrangedSubview(optionStack)
        optionStack.widthAnchor.constraint(equalTo: documentStack.widthAnchor, constant: -14).isActive = true
        for index in 0..<4 {
            let button = NSButton(radioButtonWithTitle: "", target: self, action: #selector(optionSelected(_:)))
            button.tag = index
            button.alignment = .left
            button.lineBreakMode = .byWordWrapping
            (button.cell as? NSButtonCell)?.wraps = true
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            optionButtons.append(button)
            optionStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: optionStack.widthAnchor).isActive = true
        }

        resultLabel.maximumNumberOfLines = 0
        configureWrappingLabel(resultLabel)
        documentStack.addArrangedSubview(resultLabel)
        resultLabel.widthAnchor.constraint(equalTo: documentStack.widthAnchor, constant: -14).isActive = true

        explanationLabel.maximumNumberOfLines = 0
        configureWrappingLabel(explanationLabel)
        documentStack.addArrangedSubview(explanationLabel)
        explanationLabel.widthAnchor.constraint(equalTo: documentStack.widthAnchor, constant: -14).isActive = true

        nextButton.target = self
        nextButton.action = #selector(nextQuestion)
        nextButton.isHidden = true
        let actionRow = NSStackView(views: [nextButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10
        contentStack.addArrangedSubview(actionRow)

        buildImagePreview()
    }

    private func buildImagePreview() {
        imagePreviewOverlay.translatesAutoresizingMaskIntoConstraints = false
        imagePreviewOverlay.wantsLayer = true
        imagePreviewOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        imagePreviewOverlay.isHidden = true
        rootView.addSubview(imagePreviewOverlay, positioned: .above, relativeTo: contentStack)
        NSLayoutConstraint.activate([
            imagePreviewOverlay.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            imagePreviewOverlay.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            imagePreviewOverlay.topAnchor.constraint(equalTo: rootView.topAnchor),
            imagePreviewOverlay.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        previewScrollView.translatesAutoresizingMaskIntoConstraints = false
        previewScrollView.drawsBackground = false
        previewScrollView.borderType = .noBorder
        previewScrollView.hasVerticalScroller = true
        previewScrollView.hasHorizontalScroller = true
        previewScrollView.autohidesScrollers = true
        previewScrollView.allowsMagnification = true
        previewScrollView.minMagnification = 1
        previewScrollView.maxMagnification = 6
        previewScrollView.wantsLayer = true
        previewScrollView.layer?.zPosition = 0
        imagePreviewOverlay.addSubview(previewScrollView)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.backgroundColor = NSColor.white.cgColor
        previewImageView.onClick = { [weak self] in self?.closeImagePreview() }
        previewImageView.onMagnify = { [weak self] event in
            self?.previewScrollView.magnify(with: event)
        }
        previewImageView.onScrollWheel = { [weak self] event in
            self?.previewScrollView.scrollWheel(with: event)
        }
        previewScrollView.documentView = previewImageView

        configurePreviewButton(previewZoomOutButton, action: #selector(zoomPreviewOut), toolTip: "缩小图片")
        configurePreviewButton(previewZoomInButton, action: #selector(zoomPreviewIn), toolTip: "放大图片")
        imagePreviewOverlay.addSubview(previewZoomOutButton, positioned: .above, relativeTo: previewScrollView)
        imagePreviewOverlay.addSubview(previewZoomInButton, positioned: .above, relativeTo: previewScrollView)

        previewCloseButton.target = self
        previewCloseButton.action = #selector(closeImagePreview)
        previewCloseButton.isBordered = false
        previewCloseButton.font = .systemFont(ofSize: 24, weight: .semibold)
        previewCloseButton.contentTintColor = .white
        previewCloseButton.toolTip = "关闭图片预览（Esc）"
        previewCloseButton.wantsLayer = true
        previewCloseButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        previewCloseButton.layer?.cornerRadius = 15
        previewCloseButton.layer?.zPosition = 100
        previewCloseButton.translatesAutoresizingMaskIntoConstraints = false
        imagePreviewOverlay.addSubview(previewCloseButton, positioned: .above, relativeTo: previewScrollView)

        let hint = NSTextField(labelWithString: "− / + 缩放 · 双指滑动查看 · 点击图片或按 Esc 关闭")
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 11, weight: .medium)
        hint.alignment = .center
        hint.wantsLayer = true
        hint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        hint.layer?.cornerRadius = 5
        hint.layer?.zPosition = 100
        hint.translatesAutoresizingMaskIntoConstraints = false
        imagePreviewOverlay.addSubview(hint, positioned: .above, relativeTo: previewScrollView)

        NSLayoutConstraint.activate([
            previewScrollView.leadingAnchor.constraint(equalTo: imagePreviewOverlay.leadingAnchor),
            previewScrollView.trailingAnchor.constraint(equalTo: imagePreviewOverlay.trailingAnchor),
            previewScrollView.topAnchor.constraint(equalTo: imagePreviewOverlay.topAnchor),
            previewScrollView.bottomAnchor.constraint(equalTo: imagePreviewOverlay.bottomAnchor),
            previewZoomOutButton.topAnchor.constraint(equalTo: imagePreviewOverlay.topAnchor, constant: 8),
            previewZoomOutButton.leadingAnchor.constraint(equalTo: imagePreviewOverlay.leadingAnchor, constant: 10),
            previewZoomOutButton.widthAnchor.constraint(equalToConstant: 34),
            previewZoomOutButton.heightAnchor.constraint(equalToConstant: 30),
            previewZoomInButton.topAnchor.constraint(equalTo: previewZoomOutButton.topAnchor),
            previewZoomInButton.leadingAnchor.constraint(equalTo: previewZoomOutButton.trailingAnchor, constant: 6),
            previewZoomInButton.widthAnchor.constraint(equalToConstant: 34),
            previewZoomInButton.heightAnchor.constraint(equalToConstant: 30),
            previewCloseButton.topAnchor.constraint(equalTo: imagePreviewOverlay.topAnchor, constant: 8),
            previewCloseButton.trailingAnchor.constraint(equalTo: imagePreviewOverlay.trailingAnchor, constant: -10),
            previewCloseButton.widthAnchor.constraint(equalToConstant: 30),
            previewCloseButton.heightAnchor.constraint(equalToConstant: 30),
            hint.centerXAnchor.constraint(equalTo: imagePreviewOverlay.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: imagePreviewOverlay.bottomAnchor, constant: -8)
        ])
    }

    private func configurePreviewButton(_ button: NSButton, action: Selector, toolTip: String) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.font = .systemFont(ofSize: 20, weight: .semibold)
        button.contentTintColor = .white
        button.toolTip = toolTip
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        button.layer?.cornerRadius = 8
        button.layer?.zPosition = 100
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureWrappingLabel(_ label: NSTextField) {
        label.lineBreakMode = .byWordWrapping
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window, !isHoverCollapsed else { return }
        expandedFrame = window.frame
        stemLabel.invalidateIntrinsicContentSize()
        resultLabel.invalidateIntrinsicContentSize()
        explanationLabel.invalidateIntrinsicContentSize()
        optionButtons.forEach { $0.invalidateIntrinsicContentSize() }
        rootView.needsLayout = true
        if !imagePreviewOverlay.isHidden, previewScrollView.magnification <= 1.01 {
            layoutPreviewImageToViewport()
        }
    }

    private func buildBallWindow() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.collapsedSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true

        ballView.wantsLayer = true
        ballView.layer?.cornerRadius = Self.collapsedSize.width / 2
        ballView.layer?.masksToBounds = true
        ballView.layer?.backgroundColor = configuration.fontColor.cgColor
        ballView.onMouseEnter = { [weak self] in self?.restoreFromHover() }
        panel.contentView = ballView
        ballPanel = panel
    }

    func apply(configuration: QuizConfiguration, reset: Bool, persist: Bool = true) {
        self.configuration = configuration
        if reset {
            isVisibilityStateLocked = false
            expandFromHover(force: true)
        }
        if persist { configuration.save() }
        ballView.layer?.backgroundColor = configuration.fontColor.cgColor
        updateExpandedAppearance()
        applyTextAppearance()
        window?.isMovable = !configuration.panelLocked
        window?.isMovableByWindowBackground = !configuration.panelLocked
        if !configuration.hoverHide { restoreFromHover() }
        rebuildSequence(reset: reset)
    }

    private func applyTextAppearance() {
        let color = configuration.fontColor
        let size = CGFloat(configuration.fontSize)
        progressLabel.textColor = color
        progressLabel.font = .systemFont(ofSize: max(11, size - 3), weight: .medium)
        timerLabel.textColor = color
        timerLabel.font = .monospacedDigitSystemFont(ofSize: max(11, size - 3), weight: .medium)
        stemLabel.textColor = color
        stemLabel.font = .systemFont(ofSize: size, weight: .medium)
        resultLabel.textColor = color
        resultLabel.font = .systemFont(ofSize: size, weight: .semibold)
        explanationLabel.textColor = color
        explanationLabel.font = .systemFont(ofSize: max(11, size - 2))
        nextButton.contentTintColor = color
        closeButton.contentTintColor = color
        closeButton.font = .systemFont(ofSize: max(16, size), weight: .medium)
        for button in optionButtons {
            button.contentTintColor = color
            button.font = .systemFont(ofSize: size)
        }
    }

    private func rebuildSequence(reset: Bool) {
        var questions = (store.bank?.questions ?? []).filter { configuration.selectedQuestionIDs.contains($0.id) }
        if configuration.wrongOnly {
            let wrongQuestions = questions.filter { store.progress.wrongQuestionIDs.contains($0.id) }
            if !wrongQuestions.isEmpty { questions = wrongQuestions }
        }
        if reset, configuration.judgeMode == .wholePaper {
            let key = store.wholePaperSessionKey(configuration: configuration, questionIDs: questions.map(\.id))
            activeWholePaperSessionKey = key
            if configuration.restartWholePaper {
                store.clearWholePaperSession(for: key)
            }
            if !configuration.restartWholePaper,
               let saved = store.wholePaperSession(for: key),
               saved.questionIDs.count == questions.count {
                let questionsByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
                let restoredSequence = saved.questionIDs.compactMap { questionsByID[$0] }
                if restoredSequence.count == questions.count {
                    sequence = restoredSequence
                    sessionAnswers = saved.answers
                    currentIndex = min(max(0, saved.currentIndex), max(0, sequence.count - 1))
                    wholePaperElapsedSeconds = max(0, saved.elapsedSeconds ?? 0)
                } else {
                    startNewWholePaperSession(questions: questions, key: key)
                }
            } else {
                startNewWholePaperSession(questions: questions, key: key)
            }
        } else {
            activeWholePaperSessionKey = nil
            stopTimer(reset: true)
            if configuration.randomOrder { questions.shuffle() }
            sequence = questions
            if reset {
                currentIndex = 0
                sessionAnswers = [:]
            } else if currentIndex >= sequence.count {
                currentIndex = 0
            }
        }
        if sequence.isEmpty {
            currentIndex = 0
            sessionAnswers = [:]
        } else if currentIndex >= sequence.count {
            currentIndex = 0
        }
        displayCurrentQuestion()
        updateTimerLabel()
    }

    private func startNewWholePaperSession(questions: [QuizQuestion], key: String) {
        sequence = questions
        if configuration.randomOrder { sequence.shuffle() }
        currentIndex = 0
        sessionAnswers = [:]
        stopTimer(reset: true)
        persistWholePaperSession()
    }

    private func persistWholePaperSession() {
        guard !suppressPersistenceForTesting,
              configuration.judgeMode == .wholePaper,
              let key = activeWholePaperSessionKey,
              !sequence.isEmpty else { return }
        store.saveWholePaperSession(
            WholePaperSession(
                questionIDs: sequence.map(\.id),
                answers: sessionAnswers,
                currentIndex: currentIndex,
                elapsedSeconds: effectiveElapsedSeconds
            ),
            for: key
        )
    }

    private func displayCurrentQuestion() {
        closeImagePreview()
        guard !sequence.isEmpty, currentIndex < sequence.count else { return }
        let question = sequence[currentIndex]
        selectedChoice = sessionAnswers[question.id]
        progressLabel.stringValue = "\(currentIndex + 1)/\(sequence.count)"
        stemLabel.stringValue = question.stem
        for (index, button) in optionButtons.enumerated() {
            let choice = String(UnicodeScalar(65 + index)!)
            button.title = index < question.options.count ? question.options[index] : choice
            button.state = selectedChoice == choice ? .on : .off
            button.isEnabled = true
        }
        resultLabel.stringValue = ""
        explanationLabel.stringValue = ""
        nextButton.isHidden = true

        if question.hasVisual, let documentURL = store.questionPDFURL,
           let document = PDFDocument(url: documentURL),
           let page = document.page(at: question.sourcePage) {
            pageImageView.image = page.thumbnail(of: NSSize(width: 380, height: 500), for: .mediaBox)
            currentVisualSource = (documentURL, question.sourcePage)
            pageImageView.isHidden = false
        } else {
            pageImageView.image = nil
            currentVisualSource = nil
            pageImageView.isHidden = true
        }
    }

    @objc private func openImagePreview() {
        guard let source = currentVisualSource,
              let document = PDFDocument(url: source.url),
              let page = document.page(at: source.pageIndex) else { return }
        previewImageView.image = page.thumbnail(of: NSSize(width: 1800, height: 2400), for: .mediaBox)
        imagePreviewOverlay.isHidden = false
        rootView.layoutSubtreeIfNeeded()
        previewScrollView.magnification = 1
        layoutPreviewImageToViewport()
        if previewKeyMonitor == nil {
            previewKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                self?.closeImagePreview()
                return nil
            }
        }
    }

    private func layoutPreviewImageToViewport() {
        let viewport = previewScrollView.contentView.bounds.size
        guard viewport.width > 0, viewport.height > 0 else { return }
        previewImageView.frame = NSRect(origin: .zero, size: viewport)
    }

    @objc private func zoomPreviewIn() {
        setPreviewMagnification(previewScrollView.magnification + 0.5)
    }

    @objc private func zoomPreviewOut() {
        setPreviewMagnification(previewScrollView.magnification - 0.5)
    }

    private func setPreviewMagnification(_ requestedValue: CGFloat) {
        let value = min(previewScrollView.maxMagnification,
                        max(previewScrollView.minMagnification, requestedValue))
        let visibleRect = previewScrollView.documentVisibleRect
        let center = NSPoint(x: visibleRect.midX, y: visibleRect.midY)
        previewScrollView.setMagnification(value, centeredAt: center)
    }

    @objc private func closeImagePreview() {
        imagePreviewOverlay.isHidden = true
        previewImageView.image = nil
        previewScrollView.magnification = 1
        if let previewKeyMonitor {
            NSEvent.removeMonitor(previewKeyMonitor)
            self.previewKeyMonitor = nil
        }
    }

    @objc private func optionSelected(_ sender: NSButton) {
        selectedChoice = String(UnicodeScalar(65 + sender.tag)!)
        for button in optionButtons { button.state = button === sender ? .on : .off }
        commitSelectedChoice()
    }

    private func commitSelectedChoice() {
        guard let choice = selectedChoice, !sequence.isEmpty else {
            NSSound.beep()
            return
        }
        let question = sequence[currentIndex]
        sessionAnswers[question.id] = choice
        if configuration.judgeMode == .immediate {
            store.recordAnswer(question: question, choice: choice)
            store.saveProgress()
            reveal(question: question, choice: choice)
        } else if currentIndex + 1 < sequence.count {
            store.recordFirstAttempt(question: question, choice: choice)
            currentIndex += 1
            persistWholePaperSession()
            displayCurrentQuestion()
        } else {
            store.recordFirstAttempt(question: question, choice: choice)
            finishWholePaper()
        }
    }

    private func reveal(question: QuizQuestion, choice: String) {
        let correct = choice == question.answer
        resultLabel.stringValue = correct ? "✓ 回答正确 · 答案 \(question.answer)" : "✗ 回答错误 · 你的答案 \(choice)，正确答案 \(question.answer)"
        explanationLabel.stringValue = "解析\n\(question.explanation)"
        for button in optionButtons { button.isEnabled = false }
        nextButton.title = currentIndex + 1 < sequence.count ? "下一题" : "完成"
        nextButton.isHidden = false
    }

    private func finishWholePaper() {
        pauseTimer(persist: false)
        for question in sequence {
            if let choice = sessionAnswers[question.id] {
                store.recordAnswer(question: question, choice: choice)
            }
        }
        let score = sequence.filter { sessionAnswers[$0.id] == $0.answer }.count
        let scoreKey = store.paperScoreKey(questionIDs: sequence.map(\.id))
        store.recordPaperScore(score: score, total: sequence.count, for: scoreKey)
        store.saveProgress()
        if let key = activeWholePaperSessionKey {
            store.clearWholePaperSession(for: key)
            activeWholePaperSessionKey = nil
        }
        window?.orderOut(nil)
        let controller = SettlementWindowController(questions: sequence, answers: sessionAnswers, configuration: configuration)
        settlementController = controller
        controller.showSettlement()
    }

    @objc private func nextQuestion() {
        if currentIndex + 1 < sequence.count {
            currentIndex += 1
            displayCurrentQuestion()
        } else {
            window?.orderOut(nil)
        }
    }

    @objc private func closeToManager() {
        closeImagePreview()
        expandFromHover(force: true)
        pauseTimer(persist: false)
        window?.orderOut(nil)
        persistWholePaperSession()
        store.saveProgress()
        onCloseToManager?()
    }

    private func hideForHover() {
        guard imagePreviewOverlay.isHidden, !isVisibilityStateLocked, configuration.hoverHide, !isHoverCollapsed,
              let window, window.isVisible else { return }
        expandedFrame = window.frame
        if configuration.pauseTimerWhenCollapsed {
            pauseTimer(persist: true)
        }
        isHoverCollapsed = true
        let collapsedFrame = NSRect(
            x: window.frame.maxX - Self.collapsedSize.width,
            y: window.frame.maxY - Self.collapsedSize.height,
            width: Self.collapsedSize.width,
            height: Self.collapsedSize.height
        )
        window.orderOut(nil)
        ballPanel.setFrame(collapsedFrame, display: true, animate: false)
        ballPanel.orderFrontRegardless()
    }

    private func restoreFromHover() {
        expandFromHover(force: false)
    }

    private func expandFromHover(force: Bool) {
        guard isHoverCollapsed, force || !isVisibilityStateLocked, let window else { return }
        isHoverCollapsed = false
        ballPanel.orderOut(nil)
        if let expandedFrame {
            window.setFrame(expandedFrame, display: true, animate: false)
        }
        updateExpandedAppearance()
        window.orderFrontRegardless()
        startTimerIfNeeded()
    }

    private func updateExpandedAppearance() {
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(configuration.backgroundOpacity).cgColor
        window?.hasShadow = configuration.backgroundOpacity > 0.001
    }

    func toggleVisibility() {
        guard let window else { return }
        if isHoverCollapsed, ballPanel.isVisible {
            pauseTimer(persist: true)
            ballPanel.orderOut(nil)
        } else if window.isVisible {
            pauseTimer(persist: true)
            window.orderOut(nil)
        } else {
            expandFromHover(force: true)
            window.alphaValue = 1
            window.orderFrontRegardless()
            startTimerIfNeeded()
        }
    }

    @discardableResult
    func toggleVisibilityStateLock() -> Bool {
        isVisibilityStateLocked.toggle()
        if !isVisibilityStateLocked, configuration.hoverHide, let window,
           window.isVisible || ballPanel.isVisible {
            let interactiveFrame = isHoverCollapsed ? ballPanel.frame : window.frame
            if interactiveFrame.contains(NSEvent.mouseLocation) {
                restoreFromHover()
            } else {
                hideForHover()
            }
        }
        return isVisibilityStateLocked
    }

    func showPanel() {
        expandFromHover(force: true)
        guard let window else { return }
        let oldFrame = window.frame
        let defaultFrame = NSRect(
            x: oldFrame.minX,
            y: oldFrame.maxY - Self.defaultExpandedSize.height,
            width: Self.defaultExpandedSize.width,
            height: Self.defaultExpandedSize.height
        )
        window.setFrame(defaultFrame, display: true)
        expandedFrame = defaultFrame
        window.alphaValue = 1
        window.orderFrontRegardless()
        startTimerIfNeeded()
    }

    private var effectiveElapsedSeconds: TimeInterval {
        wholePaperElapsedSeconds + (timerStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func startTimerIfNeeded() {
        guard configuration.judgeMode == .wholePaper,
              timerStartedAt == nil,
              !(isHoverCollapsed && configuration.pauseTimerWhenCollapsed) else {
            updateTimerLabel()
            return
        }
        timerStartedAt = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTimerLabel() }
        }
        updateTimerLabel()
    }

    private func pauseTimer(persist: Bool) {
        if let timerStartedAt {
            wholePaperElapsedSeconds += max(0, Date().timeIntervalSince(timerStartedAt))
        }
        timerStartedAt = nil
        timer?.invalidate()
        timer = nil
        updateTimerLabel()
        if persist { persistWholePaperSession() }
    }

    private func stopTimer(reset: Bool) {
        timerStartedAt = nil
        timer?.invalidate()
        timer = nil
        if reset { wholePaperElapsedSeconds = 0 }
    }

    private func updateTimerLabel() {
        guard configuration.judgeMode == .wholePaper else {
            timerLabel.stringValue = ""
            timerLabel.isHidden = true
            return
        }
        timerLabel.isHidden = false
        let elapsed = max(0, effectiveElapsedSeconds)
        let limit = TimeInterval(max(1, configuration.wholePaperTimeLimitMinutes) * 60)
        if elapsed > limit {
            timerLabel.stringValue = "已超时 \(formatDuration(elapsed - limit))"
            timerLabel.textColor = .systemRed
        } else {
            timerLabel.stringValue = "\(formatDuration(elapsed)) / \(formatDuration(limit))"
            timerLabel.textColor = configuration.fontColor
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func prepareForApplicationTermination() {
        guard !suppressPersistenceForTesting else { return }
        pauseTimer(persist: true)
        store.saveProgress()
    }

    func enableUITestingMode() {
        suppressPersistenceForTesting = true
    }

    func showSettlementForTesting() {
        sequence = Array((store.bank?.questions ?? []).prefix(10))
        sessionAnswers = [:]
        for (index, question) in sequence.enumerated() {
            sessionAnswers[question.id] = index.isMultiple(of: 3) ? "A" : question.answer
        }
        window?.orderOut(nil)
        let controller = SettlementWindowController(
            questions: sequence,
            answers: sessionAnswers,
            configuration: configuration
        )
        settlementController = controller
        controller.showSettlement()
    }

    func closeToManagerForTesting() {
        closeToManager()
    }

    func collapseForTesting() {
        hideForHover()
    }

    func showOvertimeForTesting() {
        pauseTimer(persist: false)
        wholePaperElapsedSeconds = TimeInterval(configuration.wholePaperTimeLimitMinutes * 60 + 65)
        updateTimerLabel()
    }

    func verifyFlexibleSizingForTesting() -> Bool {
        guard let window else { return false }
        window.setContentSize(NSSize(width: 260, height: 220))
        let expectedWidth = window.frame.width
        stemLabel.stringValue = String(repeating: "这是用于验证自动换行的超长题干，", count: 30)
        optionButtons.first?.title = "A. " + String(repeating: "超长选项内容应该在当前宽度内换行，", count: 20)
        rootView.layoutSubtreeIfNeeded()
        let widthStayedFixed = abs(window.frame.width - expectedWidth) < 0.5
        let contentFitsViewport = stemLabel.frame.width <= window.contentView!.bounds.width
        return widthStayedFixed && contentFitsViewport
    }

    func showImagePreviewForTesting() -> Bool {
        guard let question = store.bank?.questions.first(where: \.hasVisual) else { return false }
        sequence = [question]
        currentIndex = 0
        displayCurrentQuestion()
        guard let click = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: pageImageView.bounds.midX, y: pageImageView.bounds.midY),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ) else { return false }
        pageImageView.mouseDown(with: click)
        previewScrollView.magnification = 1
        zoomPreviewIn()
        let zoomInWorked = abs(previewScrollView.magnification - 1.5) < 0.01
        zoomPreviewOut()
        let zoomOutWorked = abs(previewScrollView.magnification - 1) < 0.01
        let zoomCenter = NSPoint(x: previewImageView.bounds.midX, y: previewImageView.bounds.midY)
        previewScrollView.applyMagnification(delta: 1, centeredAt: zoomCenter)
        let gestureZoomWorked = abs(previewScrollView.magnification - 2) < 0.01
        previewScrollView.magnification = 1
        return !imagePreviewOverlay.isHidden
            && previewImageView.image != nil
            && previewScrollView.allowsMagnification
            && previewScrollView.maxMagnification >= 6
            && zoomInWorked
            && zoomOutWorked
            && gestureZoomWorked
    }

    func showVisualQuestionForClickTesting() -> Bool {
        guard let question = store.bank?.questions.first(where: \.hasVisual) else { return false }
        sequence = [question]
        currentIndex = 0
        displayCurrentQuestion()
        return !pageImageView.isHidden && pageImageView.image != nil
    }
}
