import AppKit
import WebKit
import QuillandCore

/// Turns the print HTML of a book into a paginated PDF file with the system's web engine: the pages, their breaks and the headers and footers are the engine's.
final class PDFRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let window: NSWindow
    private var target: URL
    private var pageSize: NSSize
    private var margin: CGFloat
    private var completion: ((Result<Int, Error>) -> Void)?
    private var keepAlive: PDFRenderer?

    struct Failure: Error, CustomStringConvertible { var description: String }

    init(target: URL, pageSize: NSSize, margin: CGFloat) {
        self.target = target
        self.pageSize = pageSize
        self.margin = margin
        webView = WKWebView(frame: NSRect(origin: .zero, size: pageSize))
        window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: pageSize), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    /// Prints `html` to `target`; the result is the number of pages. The renderer keeps itself alive until it is done.
    static func render(html: String, to target: URL, layout: ExportOptions.Layout, completion: @escaping (Result<Int, Error>) -> Void) {
        let size = NSSize(width: Double(layout.pageWidthTwips) / 20, height: Double(layout.pageHeightTwips) / 20)
        let renderer = PDFRenderer(target: target, pageSize: size, margin: CGFloat(layout.marginTwips) / 20)
        renderer.keepAlive = renderer
        renderer.completion = completion
        renderer.webView.loadHTMLString(html, baseURL: nil)
    }

    /// The same, waiting for the end (for the automatic checks): spins the run loop.
    static func renderAndWait(html: String, to target: URL, layout: ExportOptions.Layout, timeout: TimeInterval = 30) -> Result<Int, Error> {
        var result: Result<Int, Error>?
        render(html: html, to: target, layout: layout) { result = $0 }
        let end = Date().addingTimeInterval(timeout)
        while result == nil, Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return result ?? .failure(Failure(description: "timed out"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // A moment for the images and the fonts, then the print job.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in print() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }

    private func print() {
        try? FileManager.default.removeItem(at: target)
        let info = NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = target
        info.paperSize = pageSize
        // The margins are the page rule of the HTML; the print job adds none.
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        info.scalingFactor = 1
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = NSRect(origin: .zero, size: pageSize)
        op.runModal(for: window, delegate: self, didRun: #selector(printDone(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printDone(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard success, let doc = CGPDFDocument(target as CFURL) else { finish(.failure(Failure(description: "The PDF could not be written."))); return }
        finish(.success(doc.numberOfPages))
    }

    private func finish(_ result: Result<Int, Error>) {
        let done = completion
        completion = nil
        keepAlive = nil
        done?(result)
    }
}
