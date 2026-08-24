import Foundation
import PDFKit

enum PDFQuestionImporter {
    private struct RawBlock {
        let number: Int
        let body: String
        let pageIndex: Int
    }

    static func importBank(questionURL: URL, answerURL: URL) throws -> QuestionBank {
        guard let questionDocument = PDFDocument(url: questionURL) else {
            throw QuizImportError.unreadablePDF(questionURL.lastPathComponent)
        }
        guard let answerDocument = PDFDocument(url: answerURL) else {
            throw QuizImportError.unreadablePDF(answerURL.lastPathComponent)
        }

        let questionBlocks = sequentialBlocks(from: questionDocument)
        let answerBlocks = sequentialBlocks(from: answerDocument)
        guard questionBlocks.count == 100 else {
            throw QuizImportError.invalidQuestionCount(questionBlocks.count)
        }

        var answers: [Int: (answer: String, explanation: String, question: (stem: String, options: [String]))] = [:]
        for block in answerBlocks {
            let parsed = parseAnswer(from: block.body)
            if !parsed.answer.isEmpty {
                let questionText = block.body.components(separatedBy: "【答案】").first ?? block.body
                answers[block.number] = (parsed.answer, parsed.explanation, parseQuestion(from: questionText))
            }
        }
        let missing = (1...100).filter { answers[$0] == nil }
        guard missing.isEmpty else { throw QuizImportError.missingAnswers(missing) }

        let visualPages: Set<Int> = [6, 8, 9, 10, 11, 12, 17, 18, 19, 20, 21, 22, 24, 25, 26]
        let questions = questionBlocks.map { block -> QuizQuestion in
            let answer = answers[block.number]!
            return QuizQuestion(
                id: block.number,
                stem: answer.question.stem,
                options: answer.question.options,
                answer: answer.answer,
                explanation: answer.explanation,
                sourcePage: block.pageIndex,
                hasVisual: visualPages.contains(block.pageIndex + 1)
            )
        }

        return QuestionBank(
            title: "2020 广东省公务员行测（县级）",
            importedAt: Date(),
            questions: questions
        )
    }

    static func selfTest(questionURL: URL, answerURL: URL) throws -> String {
        let bank = try importBank(questionURL: questionURL, answerURL: answerURL)
        let invalidOptions = bank.questions.filter { $0.options.count != 4 }.map(\.id)
        let invalidAnswers = bank.questions.filter { !["A", "B", "C", "D"].contains($0.answer) }.map(\.id)
        let emptyStems = bank.questions.filter { $0.stem.count < 3 }.map(\.id)
        guard invalidOptions.isEmpty, invalidAnswers.isEmpty, emptyStems.isEmpty else {
            return "FAIL options=\(invalidOptions) answers=\(invalidAnswers) stems=\(emptyStems)"
        }
        let fallbackAnswers = bank.questions.filter { [53, 55].contains($0.id) }.map { "\($0.id)=\($0.answer)" }
        return "PASS questions=\(bank.questions.count) answers=100 fallback=[\(fallbackAnswers.joined(separator: ","))] visual=\(bank.questions.filter(\.hasVisual).count)"
    }

    private static func sequentialBlocks(from document: PDFDocument) -> [RawBlock] {
        var combined = ""
        var pageOffsets: [(offset: Int, page: Int)] = []
        for pageIndex in 0..<document.pageCount {
            pageOffsets.append(((combined as NSString).length, pageIndex))
            let pageText = cleanPage(document.page(at: pageIndex)?.string ?? "")
            combined += pageText + "\n"
        }

        let nsText = combined as NSString
        let regex = try! NSRegularExpression(pattern: #"(?m)(?:^|\n)[\s　]*(\d{1,3})\s*[\.．、][\s]*"#)
        let matches = regex.matches(in: combined, range: NSRange(location: 0, length: nsText.length))
        var accepted: [(number: Int, start: Int, contentStart: Int)] = []
        var expected = 1
        for match in matches where expected <= 100 {
            let number = Int(nsText.substring(with: match.range(at: 1))) ?? -1
            guard number == expected else { continue }
            accepted.append((number, match.range.location, NSMaxRange(match.range)))
            expected += 1
        }

        return accepted.enumerated().map { index, marker in
            let end = index + 1 < accepted.count ? accepted[index + 1].start : nsText.length
            let body = nsText.substring(with: NSRange(location: marker.contentStart, length: max(0, end - marker.contentStart)))
            let page = pageOffsets.last(where: { $0.offset <= marker.start })?.page ?? 0
            return RawBlock(number: marker.number, body: tidy(body), pageIndex: page)
        }
    }

    private static func cleanPage(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\r", with: "\n")
        value = value.replacingOccurrences(of: #"第\s*\d+\s*页\s*共\s*\d+\s*页"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        return value
    }

    private static func parseQuestion(from body: String) -> (stem: String, options: [String]) {
        let nsBody = body as NSString
        var markers: [(letter: String, range: NSRange)] = []
        var cursor = 0
        for letter in ["A", "B", "C", "D"] {
            let regex = try! NSRegularExpression(pattern: "(?m)(?:^|\\n)[\\s　]*\(letter)[.．][\\s]*")
            let searchRange = NSRange(location: cursor, length: max(0, nsBody.length - cursor))
            guard let match = regex.firstMatch(in: body, range: searchRange) else { break }
            markers.append((letter, match.range))
            cursor = NSMaxRange(match.range)
        }

        guard markers.count == 4 else {
            return (tidy(body), ["A", "B", "C", "D"])
        }

        let stem = tidy(nsBody.substring(with: NSRange(location: 0, length: markers[0].range.location)))
        var options: [String] = []
        for index in markers.indices {
            let start = NSMaxRange(markers[index].range)
            let end = index + 1 < markers.count ? markers[index + 1].range.location : nsBody.length
            var option = tidy(nsBody.substring(with: NSRange(location: start, length: max(0, end - start))))
            if index == 3 {
                option = option.replacingOccurrences(of: #"\n第[一二三四五六七八九十]+部分[\s\S]*$"#, with: "", options: .regularExpression)
            }
            options.append("\(markers[index].letter). \(option.isEmpty ? markers[index].letter : option)")
        }
        return (stem, options)
    }

    private static func parseAnswer(from body: String) -> (answer: String, explanation: String) {
        let explicit = firstCapture(pattern: #"【答案】\s*([A-D])"#, in: body)
        let fallback = firstCapture(pattern: #"正确选项是\s*([A-D])"#, in: body)
        let answer = explicit ?? fallback ?? ""

        var explanation = body
        if let range = explanation.range(of: #"解析[：:]"#, options: .regularExpression) {
            explanation = String(explanation[range.upperBound...])
        }
        explanation = tidy(explanation)
        return (answer, explanation.isEmpty ? "本题解析见原 PDF。" : explanation)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: pattern)
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)), match.numberOfRanges > 1 else { return nil }
        return nsText.substring(with: match.range(at: 1))
    }

    private static func tidy(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\u{3000}", with: " ")
        value = value.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
