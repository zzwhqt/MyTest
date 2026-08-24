import AppKit
import Foundation

struct QuizQuestion: Codable, Identifiable, Equatable {
    let id: Int
    var stem: String
    var options: [String]
    var answer: String
    var explanation: String
    var sourcePage: Int
    var hasVisual: Bool
}

struct QuestionBank: Codable, Equatable {
    var title: String
    var importedAt: Date
    var questions: [QuizQuestion]
}

enum JudgeMode: Int, Codable {
    case immediate = 0
    case wholePaper = 1
}

struct QuizProgress: Codable {
    var wrongQuestionIDs: Set<Int> = []
    var lastAnswers: [Int: String] = [:]
    var correctCount: [Int: Int] = [:]
    var wrongCount: [Int: Int] = [:]

    mutating func record(question: QuizQuestion, choice: String) {
        lastAnswers[question.id] = choice
        if choice == question.answer {
            correctCount[question.id, default: 0] += 1
        } else {
            wrongCount[question.id, default: 0] += 1
            wrongQuestionIDs.insert(question.id)
        }
    }

    mutating func removeWrong(questionID: Int) {
        wrongQuestionIDs.remove(questionID)
        wrongCount.removeValue(forKey: questionID)
    }
}

struct WholePaperSession: Codable, Equatable {
    var questionIDs: [Int]
    var answers: [Int: String]
    var currentIndex: Int
    var elapsedSeconds: TimeInterval? = nil
}

struct PaperScoreRecord: Codable, Equatable {
    var lastScore: Int
    var bestScore: Int
    var totalQuestions: Int
    var attempts: Int
}

struct QuestionModule: Equatable {
    let name: String
    let range: ClosedRange<Int>

    static let standard: [QuestionModule] = [
        QuestionModule(name: "言语理解与表达", range: 1...15),
        QuestionModule(name: "常识判断", range: 16...30),
        QuestionModule(name: "数量关系", range: 31...45),
        QuestionModule(name: "判断推理", range: 46...85),
        QuestionModule(name: "资料分析", range: 86...100)
    ]
}

struct ModuleAccuracy: Equatable {
    let module: QuestionModule
    let correct: Int
    let answered: Int
    let total: Int

    var percentage: Int? {
        guard answered > 0 else { return nil }
        return Int((Double(correct) / Double(answered) * 100).rounded())
    }
}

extension NSColor {
    var quizHex: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#1F2937" }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }

    convenience init?(quizHex: String) {
        let value = quizHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }
}
