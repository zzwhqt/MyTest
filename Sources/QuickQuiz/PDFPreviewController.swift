import AppKit
import PDFKit

final class PDFPreviewController: NSWindowController {
    private let pdfView = PDFView()

    init(pdfURL: URL, pageIndex: Int) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 900),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "原题 PDF - 第 \(pageIndex + 1) 页"
        window.center()
        super.init(window: window)

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        window.contentView = pdfView

        if let document = PDFDocument(url: pdfURL) {
            pdfView.document = document
            if let page = document.page(at: pageIndex) {
                pdfView.go(to: page)
            }
        }
    }

    required init?(coder: NSCoder) { nil }
}
