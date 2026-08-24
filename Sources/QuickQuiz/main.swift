import AppKit
import Foundation

if CommandLine.arguments.contains("--logic-test") {
    let sample = QuizQuestion(id: 1, stem: "测试", options: ["A", "B", "C", "D"], answer: "B", explanation: "解析", sourcePage: 0, hasVisual: false)
    var progress = QuizProgress()
    progress.record(question: sample, choice: "A")
    let wrongRecorded = progress.wrongQuestionIDs.contains(1) && progress.wrongCount[1] == 1
    progress.record(question: sample, choice: "B")
    let wrongPersisted = progress.wrongQuestionIDs.contains(1) && progress.correctCount[1] == 1
    progress.removeWrong(questionID: 1)
    let explicitlyRemoved = !progress.wrongQuestionIDs.contains(1) && progress.wrongCount[1] == nil
    let roundTrip = (try? JSONDecoder.quiz.decode(QuizProgress.self, from: JSONEncoder.pretty.encode(progress))) != nil
    let session = WholePaperSession(questionIDs: [3, 1, 2], answers: [3: "A", 1: "B"], currentIndex: 2, elapsedSeconds: 372.5)
    let sessionRoundTrip = (try? JSONDecoder.quiz.decode(WholePaperSession.self, from: JSONEncoder.pretty.encode(session))) == session
    let score = PaperScoreRecord(lastScore: 82, bestScore: 91, totalQuestions: 100, attempts: 3)
    let scoreRoundTrip = (try? JSONDecoder.quiz.decode(PaperScoreRecord.self, from: JSONEncoder.pretty.encode(score))) == score
    let accuracy = ModuleAccuracy(module: QuestionModule.standard[0], correct: 12, answered: 15, total: 15)
    let accuracyCalculated = accuracy.percentage == 80
    guard wrongRecorded, wrongPersisted, explicitlyRemoved, roundTrip, sessionRoundTrip, scoreRoundTrip, accuracyCalculated else {
        fputs("FAIL progress logic\n", stderr)
        exit(1)
    }
    fputs("PASS permanent-wrong explicit-removal whole-paper-resume timer-score-module json-roundtrip\n", stdout)
    fflush(stdout)
    exit(0)
}

if let exportIndex = CommandLine.arguments.firstIndex(of: "--export-bank"),
   CommandLine.arguments.count > exportIndex + 3 {
    _ = NSApplication.shared
    let questionURL = URL(fileURLWithPath: CommandLine.arguments[exportIndex + 1])
    let answerURL = URL(fileURLWithPath: CommandLine.arguments[exportIndex + 2])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[exportIndex + 3])
    do {
        let bank = try PDFQuestionImporter.importBank(questionURL: questionURL, answerURL: answerURL)
        try JSONEncoder.pretty.encode(bank).write(to: outputURL, options: .atomic)
        fputs("PASS exported=\(bank.questions.count) path=\(outputURL.path)\n", stdout)
        fflush(stdout)
        exit(0)
    } catch {
        fputs("FAIL \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--self-test") {
    _ = NSApplication.shared
    let args = CommandLine.arguments
    let questionURL: URL
    let answerURL: URL
    if let index = args.firstIndex(of: "--self-test"), args.count > index + 2 {
        questionURL = URL(fileURLWithPath: args[index + 1])
        answerURL = URL(fileURLWithPath: args[index + 2])
    } else if let resources = Bundle.main.resourceURL {
        questionURL = resources.appendingPathComponent("2020广东县级真题.pdf")
        answerURL = resources.appendingPathComponent("2020广东县级答案解析.pdf")
    } else {
        fputs("FAIL no resource directory\n", stderr)
        exit(2)
    }
    do {
        fputs(try PDFQuestionImporter.selfTest(questionURL: questionURL, answerURL: answerURL) + "\n", stdout)
        fflush(stdout)
        exit(0)
    } catch {
        fputs("FAIL \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
