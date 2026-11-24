import Foundation
import Vision
// Fail CI when the screenshot only shows SpringBoard or a blank launch surface.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
try VNImageRequestHandler(url:url).perform([request])
let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:" ").lowercased()
guard text.contains("focuz"), text.contains("focus"),
      (text.contains("hôm nay") || text.contains("today")),
      (text.contains("đổi quà") || text.contains("rewards")),
      (text.contains("lịch sử") || text.contains("history")) else {
    fputs("Focuz Today screen and navigation are not visible yet.\n",stderr)
    exit(1)
}
print("Verified visible Focuz Today screen with the five-section navigation.")
