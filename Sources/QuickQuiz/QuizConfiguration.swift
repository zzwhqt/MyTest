import AppKit
import Foundation

struct QuizConfiguration {
    var selectedQuestionIDs: Set<Int>
    var randomOrder: Bool
    var wrongOnly: Bool
    var judgeMode: JudgeMode
    var panelLocked: Bool
    var hoverHide: Bool
    var backgroundOpacity: Double
    var fontColor: NSColor
    var fontSize: Double
    var restartWholePaper: Bool
    var wholePaperTimeLimitMinutes: Int
    var pauseTimerWhenCollapsed: Bool

    static func load(questionCount: Int) -> QuizConfiguration {
        let defaults = UserDefaults.standard
        let storedIDs = defaults.array(forKey: "selectedQuestionIDs") as? [Int]
        return QuizConfiguration(
            selectedQuestionIDs: Set(storedIDs ?? Array(1...questionCount)),
            randomOrder: defaults.bool(forKey: "randomOrder"),
            wrongOnly: defaults.bool(forKey: "wrongOnly"),
            judgeMode: JudgeMode(rawValue: defaults.integer(forKey: "judgeMode")) ?? .immediate,
            panelLocked: defaults.bool(forKey: "panelLocked"),
            hoverHide: defaults.bool(forKey: "hoverHide"),
            backgroundOpacity: defaults.object(forKey: "backgroundOpacity") as? Double ?? 0.90,
            fontColor: NSColor(quizHex: defaults.string(forKey: "fontColor") ?? "#1F2937") ?? .labelColor,
            fontSize: defaults.object(forKey: "fontSize") as? Double ?? 17,
            restartWholePaper: false,
            wholePaperTimeLimitMinutes: defaults.object(forKey: "wholePaperTimeLimitMinutes") as? Int ?? 90,
            pauseTimerWhenCollapsed: defaults.bool(forKey: "pauseTimerWhenCollapsed")
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(selectedQuestionIDs.sorted(), forKey: "selectedQuestionIDs")
        defaults.set(randomOrder, forKey: "randomOrder")
        defaults.set(wrongOnly, forKey: "wrongOnly")
        defaults.set(judgeMode.rawValue, forKey: "judgeMode")
        defaults.set(panelLocked, forKey: "panelLocked")
        defaults.set(hoverHide, forKey: "hoverHide")
        defaults.set(backgroundOpacity, forKey: "backgroundOpacity")
        defaults.set(fontColor.quizHex, forKey: "fontColor")
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(wholePaperTimeLimitMinutes, forKey: "wholePaperTimeLimitMinutes")
        defaults.set(pauseTimerWhenCollapsed, forKey: "pauseTimerWhenCollapsed")
    }
}
