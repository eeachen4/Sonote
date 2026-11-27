import Foundation
import AppKit
import SonoteCore

/// Native macOS multi-page PDF exporter converting structured meeting minutes HTML into
/// a clean paginated A4 PDF document with full CJK (PingFang SC) typography & table support.
@MainActor
enum MeetingPDFExporter {
    static func exportPDF(for meeting: MeetingSession, includeTranscript: Bool = false, to destinationURL: URL) throws {
        let html = MeetingStore.exportHTML(for: meeting, includeTranscript: includeTranscript)
        let htmlData = Data(html.utf8)

        guard let attributed = try? NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else {
            throw NSError(
                domain: "Sonote.PDFExporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法生成 PDF 排版内容。"]
            )
        }

        // Standard A4 geometry (595 x 842 pt) with clean editorial margins
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let marginX: CGFloat = 48
        let marginY: CGFloat = 48
        let contentWidth = pageWidth - marginX * 2
        let contentHeight = pageHeight - marginY * 2

        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var textContainers: [NSTextContainer] = []
        var glyphIndex = 0
        let totalGlyphs = layoutManager.numberOfGlyphs

        // Paginate dynamically across as many A4 pages as needed (cap 80 pages as safeguard)
        while glyphIndex < totalGlyphs && textContainers.count < 80 {
            let container = NSTextContainer(size: NSSize(width: contentWidth, height: contentHeight))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            let range = layoutManager.glyphRange(for: container)
            if range.length == 0 { break }
            textContainers.append(container)
            glyphIndex = NSMaxRange(range)
        }

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(url: destinationURL as CFURL),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(
                domain: "Sonote.PDFExporter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法创建 PDF 输出文件。"]
            )
        }

        let nsContext = NSGraphicsContext(cgContext: pdfContext, flipped: true)
        let previousContext = NSGraphicsContext.current

        for (pageIndex, container) in textContainers.enumerated() {
            pdfContext.beginPDFPage(nil)
            pdfContext.saveGState()

            // White page background
            pdfContext.setFillColor(NSColor.white.cgColor)
            pdfContext.fill(mediaBox)

            // Flip coordinate space for AppKit NSLayoutManager drawing
            pdfContext.translateBy(x: 0, y: pageHeight)
            pdfContext.scaleBy(x: 1, y: -1)

            NSGraphicsContext.current = nsContext
            let range = layoutManager.glyphRange(for: container)
            let origin = NSPoint(x: marginX, y: marginY)
            layoutManager.drawBackground(forGlyphRange: range, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: range, at: origin)

            // Subtle page footer ("Sonote 声记 · 第 X / Y 页")
            let footer = "Sonote 声记 · 第 \(pageIndex + 1) / \(textContainers.count) 页" as NSString
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5),
                .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1.0)
            ]
            let footerSize = footer.size(withAttributes: footerAttrs)
            footer.draw(
                at: NSPoint(x: (pageWidth - footerSize.width) / 2, y: pageHeight - marginY + 14),
                withAttributes: footerAttrs
            )

            pdfContext.restoreGState()
            pdfContext.endPDFPage()
        }

        NSGraphicsContext.current = previousContext
        pdfContext.closePDF()
    }
}
