import Foundation

@MainActor
final class QuestionStore {
    static let shared = QuestionStore()

    private(set) var bank: QuestionBank?
    private(set) var questionPDFURL: URL?
    private(set) var answerPDFURL: URL?
    private(set) var activeBankID = "bundled"
    var progress = QuizProgress()
    private var wholePaperSessions: [String: WholePaperSession] = [:]
    private var paperScores: [String: PaperScoreRecord] = [:]
    private var firstAttemptResults: [String: Bool] = [:]

    private let fm = FileManager.default
    private lazy var appSupportURL: URL = {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("QuickQuiz", isDirectory: true)
    }()
    private var bankCacheURL: URL { appSupportURL.appendingPathComponent("question-bank.json") }
    private var customBankCacheURL: URL { appSupportURL.appendingPathComponent("custom-question-bank.json") }
    private var progressURL: URL { appSupportURL.appendingPathComponent("progress.json") }
    private var wholePaperSessionsURL: URL { appSupportURL.appendingPathComponent("whole-paper-sessions.json") }
    private var paperScoresURL: URL { appSupportURL.appendingPathComponent("paper-scores.json") }
    private var moduleStatisticsURL: URL { appSupportURL.appendingPathComponent("module-first-attempts.json") }
    private var customQuestionPDFURL: URL { appSupportURL.appendingPathComponent("custom-question.pdf") }
    private var customAnswerPDFURL: URL { appSupportURL.appendingPathComponent("custom-answer.pdf") }
    private var customCombinedPDFURL: URL { appSupportURL.appendingPathComponent("custom-combined.pdf") }

    func load() throws {
        try fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        loadProgress()
        loadWholePaperSessions()
        loadPaperScores()
        loadModuleStatistics()

        if UserDefaults.standard.bool(forKey: "hasCustomBank"),
           !fm.fileExists(atPath: customBankCacheURL.path),
           fm.fileExists(atPath: bankCacheURL.path) {
            try? fm.copyItem(at: bankCacheURL, to: customBankCacheURL)
        }

        let preferred = UserDefaults.standard.string(forKey: "activeBankID")
            ?? (UserDefaults.standard.bool(forKey: "hasCustomBank") ? "custom" : "bundled")
        if preferred == "custom", availableBanks().contains(where: { $0.id == "custom" }) {
            try activateBank(id: "custom")
        } else {
            try activateBank(id: "bundled")
        }
    }

    func availableBanks() -> [(id: String, title: String)] {
        var result: [(String, String)] = []
        if let bundled = readBundledBank() { result.append(("bundled", bundled.title)) }
        if let custom = readCustomBank(), customPDFURLs() != nil { result.append(("custom", custom.title)) }
        return result
    }

    func activateBank(id: String) throws {
        switch id {
        case "custom":
            guard let custom = readCustomBank(), let urls = customPDFURLs() else {
                throw QuizImportError.missingPDF
            }
            bank = custom
            questionPDFURL = urls.question
            answerPDFURL = urls.answer
            activeBankID = "custom"
        default:
            guard let bundled = readBundledBank() else { throw QuizImportError.invalidQuestionCount(0) }
            bank = bundled
            questionPDFURL = Bundle.main.resourceURL?.appendingPathComponent("2020广东县级真题.pdf")
            answerPDFURL = Bundle.main.resourceURL?.appendingPathComponent("2020广东县级答案解析.pdf")
            activeBankID = "bundled"
        }
        if let bank, let data = try? JSONEncoder.pretty.encode(bank) {
            try? data.write(to: bankCacheURL, options: .atomic)
        }
        UserDefaults.standard.set(activeBankID, forKey: "activeBankID")
    }

    private func readBundledBank() -> QuestionBank? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("BundledQuestionBank.json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder.quiz.decode(QuestionBank.self, from: data),
              value.questions.count == 100 else { return nil }
        return value
    }

    private func readCustomBank() -> QuestionBank? {
        guard let data = try? Data(contentsOf: customBankCacheURL),
              let value = try? JSONDecoder.quiz.decode(QuestionBank.self, from: data),
              value.questions.count == 100 else { return nil }
        return value
    }

    private func customPDFURLs() -> (question: URL, answer: URL)? {
        if fm.fileExists(atPath: customCombinedPDFURL.path) {
            return (customCombinedPDFURL, customCombinedPDFURL)
        }
        if fm.fileExists(atPath: customQuestionPDFURL.path), fm.fileExists(atPath: customAnswerPDFURL.path) {
            return (customQuestionPDFURL, customAnswerPDFURL)
        }
        return nil
    }

    func importPDFs(questionURL: URL, answerURL: URL) throws {
        let imported = try PDFQuestionImporter.importBank(questionURL: questionURL, answerURL: answerURL)
        guard imported.questions.count == 100 else {
            throw QuizImportError.invalidQuestionCount(imported.questions.count)
        }
        if fm.fileExists(atPath: customQuestionPDFURL.path) { try fm.removeItem(at: customQuestionPDFURL) }
        if fm.fileExists(atPath: customAnswerPDFURL.path) { try fm.removeItem(at: customAnswerPDFURL) }
        try fm.copyItem(at: questionURL, to: customQuestionPDFURL)
        try fm.copyItem(at: answerURL, to: customAnswerPDFURL)
        bank = imported
        questionPDFURL = customQuestionPDFURL
        answerPDFURL = customAnswerPDFURL
        let data = try JSONEncoder.pretty.encode(imported)
        try data.write(to: bankCacheURL, options: .atomic)
        try data.write(to: customBankCacheURL, options: .atomic)
        UserDefaults.standard.set(true, forKey: "hasCustomBank")
        activeBankID = "custom"
        UserDefaults.standard.set(activeBankID, forKey: "activeBankID")
    }

    func importPDF(url: URL) throws {
        let imported = try PDFQuestionImporter.importBank(combinedURL: url)
        guard imported.questions.count == 100 else {
            throw QuizImportError.invalidQuestionCount(imported.questions.count)
        }
        if fm.fileExists(atPath: customCombinedPDFURL.path) { try fm.removeItem(at: customCombinedPDFURL) }
        try fm.copyItem(at: url, to: customCombinedPDFURL)
        bank = imported
        questionPDFURL = customCombinedPDFURL
        answerPDFURL = customCombinedPDFURL
        let data = try JSONEncoder.pretty.encode(imported)
        try data.write(to: bankCacheURL, options: .atomic)
        try data.write(to: customBankCacheURL, options: .atomic)
        UserDefaults.standard.set(true, forKey: "hasCustomBank")
        activeBankID = "custom"
        UserDefaults.standard.set(activeBankID, forKey: "activeBankID")
    }

    func restoreBundledBank() throws {
        try activateBank(id: "bundled")
    }

    func saveProgress() {
        try? fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.pretty.encode(progress) else { return }
        try? data.write(to: progressURL, options: .atomic)
    }

    private func loadProgress() {
        guard let data = try? Data(contentsOf: progressURL),
              let saved = try? JSONDecoder.quiz.decode(QuizProgress.self, from: data) else { return }
        progress = saved
    }

    func wholePaperSessionKey(configuration: QuizConfiguration, questionIDs: [Int]) -> String {
        let questionPart = questionIDs.sorted().map(String.init).joined(separator: ",")
        return "\(bankIdentity())|questions=\(questionPart)|random=\(configuration.randomOrder)|wrong=\(configuration.wrongOnly)"
    }

    func wholePaperSession(for key: String) -> WholePaperSession? {
        wholePaperSessions[key]
    }

    func saveWholePaperSession(_ session: WholePaperSession, for key: String) {
        wholePaperSessions[key] = session
        persistWholePaperSessions()
    }

    func clearWholePaperSession(for key: String) {
        wholePaperSessions.removeValue(forKey: key)
        persistWholePaperSessions()
    }

    private func loadWholePaperSessions() {
        guard let data = try? Data(contentsOf: wholePaperSessionsURL),
              let saved = try? JSONDecoder.quiz.decode([String: WholePaperSession].self, from: data) else { return }
        wholePaperSessions = saved
    }

    private func persistWholePaperSessions() {
        try? fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.pretty.encode(wholePaperSessions) else { return }
        try? data.write(to: wholePaperSessionsURL, options: .atomic)
    }

    func recordAnswer(question: QuizQuestion, choice: String) {
        progress.record(question: question, choice: choice)
        recordFirstAttempt(question: question, choice: choice)
    }

    func recordFirstAttempt(question: QuizQuestion, choice: String) {
        let key = firstAttemptKey(questionID: question.id)
        guard firstAttemptResults[key] == nil else { return }
        firstAttemptResults[key] = choice == question.answer
        persistModuleStatistics()
    }

    func moduleAccuracies() -> [ModuleAccuracy] {
        QuestionModule.standard.map { module in
            let availableIDs = (bank?.questions ?? [])
                .map(\.id)
                .filter { module.range.contains($0) }
            let results = availableIDs.compactMap { firstAttemptResults[firstAttemptKey(questionID: $0)] }
            return ModuleAccuracy(
                module: module,
                correct: results.filter { $0 }.count,
                answered: results.count,
                total: availableIDs.count
            )
        }
    }

    func paperScoreKey(questionIDs: [Int]) -> String {
        let questionPart = questionIDs.sorted().map(String.init).joined(separator: ",")
        return "\(bankIdentity())|score-questions=\(questionPart)"
    }

    func paperScore(for key: String) -> PaperScoreRecord? {
        paperScores[key]
    }

    func recordPaperScore(score: Int, total: Int, for key: String) {
        let previous = paperScores[key]
        paperScores[key] = PaperScoreRecord(
            lastScore: score,
            bestScore: max(score, previous?.bestScore ?? score),
            totalQuestions: total,
            attempts: (previous?.attempts ?? 0) + 1
        )
        persistPaperScores()
    }

    private func bankIdentity() -> String {
        guard let bank else { return "unknown-bank" }
        return "\(bank.title)|\(bank.importedAt.timeIntervalSince1970)|\(bank.questions.count)"
    }

    private func firstAttemptKey(questionID: Int) -> String {
        "\(bankIdentity())|question=\(questionID)"
    }

    private func loadPaperScores() {
        guard let data = try? Data(contentsOf: paperScoresURL),
              let saved = try? JSONDecoder.quiz.decode([String: PaperScoreRecord].self, from: data) else { return }
        paperScores = saved
    }

    private func persistPaperScores() {
        guard let data = try? JSONEncoder.pretty.encode(paperScores) else { return }
        try? data.write(to: paperScoresURL, options: .atomic)
    }

    private func loadModuleStatistics() {
        guard let data = try? Data(contentsOf: moduleStatisticsURL),
              let saved = try? JSONDecoder.quiz.decode([String: Bool].self, from: data) else { return }
        firstAttemptResults = saved
    }

    private func persistModuleStatistics() {
        guard let data = try? JSONEncoder.pretty.encode(firstAttemptResults) else { return }
        try? data.write(to: moduleStatisticsURL, options: .atomic)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var quiz: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum QuizImportError: LocalizedError {
    case missingPDF
    case unreadablePDF(String)
    case invalidQuestionCount(Int)
    case missingAnswers([Int])

    var errorDescription: String? {
        switch self {
        case .missingPDF:
            return "应用资源中缺少真题或答案解析 PDF。"
        case .unreadablePDF(let name):
            return "无法读取 PDF：\(name)"
        case .invalidQuestionCount(let count):
            return "只识别到 \(count) 道题，预期为 100 道。"
        case .missingAnswers(let ids):
            return "以下题目没有识别到答案：\(ids.map(String.init).joined(separator: ", "))"
        }
    }
}
