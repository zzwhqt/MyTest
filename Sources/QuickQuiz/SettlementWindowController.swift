import AppKit

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class SettlementWindowController: NSWindowController {
    private let questions: [QuizQuestion]
    private let answers: [Int: String]
    private let fontColor: NSColor
    private let fontSize: CGFloat
    private let reviewScroll = NSScrollView()
    private var sectionViews: [NSView] = []

    init(questions: [QuizQuestion], answers: [Int: String], configuration: QuizConfiguration) {
        self.questions = questions
        self.answers = answers
        self.fontColor = configuration.fontColor
        self.fontSize = CGFloat(configuration.fontSize)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "答题结算"
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        guard let window else { return }
        let correct = questions.filter { answers[$0.id] == $0.answer }.count
        let percentage = Int(Double(correct) / Double(max(1, questions.count)) * 100)

        let root = NSStackView()
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(root)
        window.contentView = content
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let left = NSStackView()
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 12
        let score = NSTextField(labelWithString: "得分：\(correct) / \(questions.count) · 正确率 \(percentage)%")
        score.font = .systemFont(ofSize: 22, weight: .bold)
        score.textColor = fontColor
        left.addArrangedSubview(score)

        reviewScroll.hasVerticalScroller = true
        reviewScroll.drawsBackground = false
        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        reviewScroll.documentView = documentView
        let reviewStack = NSStackView()
        reviewStack.orientation = .vertical
        reviewStack.alignment = .leading
        reviewStack.spacing = 18
        reviewStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(reviewStack)
        NSLayoutConstraint.activate([
            reviewStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            reviewStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            reviewStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            reviewStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: reviewScroll.contentView.widthAnchor)
        ])

        for question in questions {
            let section = makeSection(question: question, choice: answers[question.id])
            sectionViews.append(section)
            reviewStack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: reviewStack.widthAnchor, constant: -14).isActive = true
        }
        left.addArrangedSubview(reviewScroll)
        reviewScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 570).isActive = true
        reviewScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        reviewScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        reviewScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        reviewScroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        root.addArrangedSubview(left)

        let right = NSStackView()
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 10
        right.widthAnchor.constraint(equalToConstant: 230).isActive = true
        let listTitle = NSTextField(labelWithString: "题目列表")
        listTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        right.addArrangedSubview(listTitle)

        let numberScroll = NSScrollView()
        numberScroll.hasVerticalScroller = true
        numberScroll.drawsBackground = false
        let numberDocument = FlippedDocumentView()
        numberDocument.translatesAutoresizingMaskIntoConstraints = false
        numberScroll.documentView = numberDocument
        let numberStack = NSStackView()
        numberStack.orientation = .vertical
        numberStack.alignment = .leading
        numberStack.spacing = 6
        numberStack.translatesAutoresizingMaskIntoConstraints = false
        numberDocument.addSubview(numberStack)
        NSLayoutConstraint.activate([
            numberStack.leadingAnchor.constraint(equalTo: numberDocument.leadingAnchor),
            numberStack.trailingAnchor.constraint(equalTo: numberDocument.trailingAnchor),
            numberStack.topAnchor.constraint(equalTo: numberDocument.topAnchor),
            numberStack.bottomAnchor.constraint(equalTo: numberDocument.bottomAnchor),
            numberDocument.widthAnchor.constraint(equalTo: numberScroll.contentView.widthAnchor)
        ])
        for rowStart in stride(from: 0, to: questions.count, by: 5) {
            var buttons: [NSView] = []
            for index in rowStart..<min(rowStart + 5, questions.count) {
                let question = questions[index]
                let button = NSButton(title: "\(question.id)", target: self, action: #selector(jumpToQuestion(_:)))
                button.tag = index
                button.bezelStyle = .inline
                button.widthAnchor.constraint(equalToConstant: 38).isActive = true
                let numberColor: NSColor = answers[question.id] == question.answer ? .labelColor : .systemRed
                button.attributedTitle = NSAttributedString(
                    string: "\(question.id)",
                    attributes: [
                        .foregroundColor: numberColor,
                        .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
                    ]
                )
                buttons.append(button)
            }
            let row = NSStackView(views: buttons)
            row.orientation = .horizontal
            row.spacing = 4
            numberStack.addArrangedSubview(row)
        }
        right.addArrangedSubview(numberScroll)
        numberScroll.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        numberScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        root.addArrangedSubview(right)
    }

    private func makeSection(question: QuizQuestion, choice: String?) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 12, right: 10)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        stack.layer?.cornerRadius = 10

        let correct = choice == question.answer
        let symbol = correct ? "✓" : "✗"
        let headingText = "第 \(question.id) 题  \(symbol)"
        let heading = NSTextField(labelWithString: headingText)
        heading.font = .systemFont(ofSize: fontSize, weight: .bold)
        let headingValue = NSMutableAttributedString(
            string: headingText,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: fontColor
            ]
        )
        headingValue.addAttribute(
            .foregroundColor,
            value: correct ? NSColor.systemGreen : NSColor.systemRed,
            range: (headingText as NSString).range(of: symbol)
        )
        heading.attributedStringValue = headingValue
        stack.addArrangedSubview(heading)

        let stem = NSTextField(wrappingLabelWithString: question.stem)
        stem.font = .systemFont(ofSize: fontSize)
        stem.textColor = fontColor
        stack.addArrangedSubview(stem)
        stem.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true

        for option in question.options {
            let label = NSTextField(wrappingLabelWithString: option)
            label.font = .systemFont(ofSize: max(12, fontSize - 1))
            label.textColor = fontColor
            stack.addArrangedSubview(label)
        }

        let answer = NSTextField(wrappingLabelWithString: "你的答案：\(choice ?? "未答")    原题答案：\(question.answer)\n解析：\(question.explanation)")
        answer.font = .systemFont(ofSize: max(12, fontSize - 2))
        answer.textColor = correct ? .systemGreen : .systemRed
        stack.addArrangedSubview(answer)
        answer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
        return stack
    }

    @objc private func jumpToQuestion(_ sender: NSButton) {
        guard sender.tag < sectionViews.count else { return }
        sectionViews[sender.tag].scrollToVisible(sectionViews[sender.tag].bounds)
    }

    func showSettlement() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self, let first = self.sectionViews.first else { return }
            first.scrollToVisible(first.bounds)
            self.reviewScroll.reflectScrolledClipView(self.reviewScroll.contentView)
        }
    }
}
