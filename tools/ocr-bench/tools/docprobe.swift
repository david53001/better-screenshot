import Vision
import CoreGraphics
import ImageIO
import Foundation

let r = VNRecognizeTextRequest()
print("minimumTextHeight default:", r.minimumTextHeight, "customWords:", r.customWords, "automaticallyDetectsLanguage:", r.automaticallyDetectsLanguage)

func load(_ p: String) -> CGImage { let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!; return CGImageSourceCreateImageAtIndex(s, 0, nil)! }

if #available(macOS 26.0, *) {
    let sem = DispatchSemaphore(value: 0)
    Task {
        for id in CommandLine.arguments.dropFirst() {
            let img = load("out/images/\(id).png")
            do {
                let req = RecognizeDocumentsRequest()
                let obs = try await req.perform(on: img)
                print("=== \(id): \(obs.count) document observations")
                for o in obs {
                    let d = o.document
                    print("  tables: \(d.tables.count)  lists: \(d.lists.count)  paragraphs: \(d.paragraphs.count)")
                    for t in d.tables {
                        for row in t.rows {
                            print("   row: " + row.map { $0.content.text.transcript.replacingOccurrences(of: "\n", with: " ⏎ ") }.joined(separator: " ⇥ "))
                        }
                    }
                    for l in d.lists {
                        for item in l.items { print("   item: \(item.markerString) | \(item.content.text.transcript)") }
                    }
                    for p in d.paragraphs { print("   para: \(p.transcript.replacingOccurrences(of: "\n", with: " ⏎ "))") }
                    print("  text: \(d.text.transcript.debugDescription)")
                }
            } catch { print("=== \(id): error \(error)") }
        }
        sem.signal()
    }
    sem.wait()
} else { print("RecognizeDocumentsRequest unavailable") }
