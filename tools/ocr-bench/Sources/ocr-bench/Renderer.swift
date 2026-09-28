import AppKit
import WebKit

/// Renders an HTML snippet offscreen with WKWebView and returns the pixels of
/// the `#cap` element (the simulated user selection) at 2x density.
///
/// The window is never ordered in (it lives far off-screen at desktop level),
/// so nothing ever appears in front of the user's windows.
final class Renderer: NSObject, WKNavigationDelegate {
    var debug = false
    private let window: NSWindow
    private let webView: WKWebView
    private var finished = false
    private var failed: Error?

    override init() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 800, height: 600),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.contentView = webView
        webView.navigationDelegate = self
    }

    deinit { }

    func close() { window.close() }

    var backingScale: CGFloat { window.backingScaleFactor }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed = error; finished = true
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed = error; finished = true
    }
    /// Block every network request: only the inline HTML string and data: URIs may load.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme ?? ""
        decisionHandler(scheme == "about" || scheme == "data" || scheme.isEmpty ? .allow : .cancel)
    }

    /// Returns the #cap element rendered at the window's backing scale (2x here).
    func render(document: String, widthPt: CGFloat, timeout: TimeInterval = 20) throws -> CGImage {
        finished = false; failed = nil
        window.setContentSize(NSSize(width: widthPt, height: 3000))
        webView.frame = NSRect(x: 0, y: 0, width: widthPt, height: 3000)
        webView.loadHTMLString(document, baseURL: nil)
        try pump(timeout) { self.finished }
        if debug { print("loaded") }
        if let failed { throw failed }

        var rect: CGRect?
        var jsError: Error?
        webView.callAsyncJavaScript("""
            await document.fonts.ready;
            await new Promise(r => setTimeout(r, 50));
            const r = document.getElementById('cap').getBoundingClientRect();
            return [r.x, r.y, r.width, r.height];
            """, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let v):
                if let a = v as? [Double], a.count == 4 { rect = CGRect(x: a[0], y: a[1], width: a[2], height: a[3]) }
                else { jsError = RenderError.badRect }
            case .failure(let e): jsError = e
            }
        }
        try pump(timeout) { rect != nil || jsError != nil }
        if debug { print("rect", rect as Any, jsError as Any) }
        if let jsError { throw jsError }
        guard var r = rect else { throw RenderError.badRect }
        r = r.integral
        if r.maxY > 2990 { throw RenderError.tooTall }

        let snap = WKSnapshotConfiguration()
        snap.rect = r
        snap.afterScreenUpdates = false
        var image: NSImage?
        var snapError: Error?
        webView.takeSnapshot(with: snap) { img, err in image = img; snapError = err ?? (img == nil ? RenderError.noSnapshot : nil) }
        try pump(timeout) { image != nil || snapError != nil }
        if let snapError { throw snapError }
        guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw RenderError.noSnapshot }
        return cg
    }

    private func pump(_ timeout: TimeInterval, until done: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() {
            if Date() > deadline { throw RenderError.timeout }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}

enum RenderError: Error { case timeout, badRect, noSnapshot, tooTall }

/// Area-averaged downscale (used to simulate a 1x external monitor from a 2x render).
func downscale(_ image: CGImage, by factor: Int) -> CGImage? {
    let w = image.width / factor, h = image.height / factor
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

func loadPNG(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
