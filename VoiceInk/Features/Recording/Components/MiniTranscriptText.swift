import AppKit
import SwiftUI

/// Live transcript for the mini recorder: 13 pt text showing the latest one to three lines
/// (older text is cut at the front with "…"). The card hugs the text and grows or shrinks one
/// line at a time with `resize`, never per word.
///
/// The text is pinned to the top of its clip. As the card grows upward, the lines already shown
/// rise with its top edge and the new line slides out from above the control bar. Pinned to the
/// bottom instead, every line would first jump up a full line (the first one vanishing past the
/// top) and only then be revealed again as the card caught up.
struct MiniTranscriptText: View {
    let text: String
    let resize: Animation

    private let fontSize: CGFloat = 13
    private let lineHeight: CGFloat = 18
    private let maxLines = 3

    @State private var shownHeight: CGFloat = 0

    private var lineSpacing: CGFloat {
        let natural = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: fontSize))
        return max(0, lineHeight - natural)
    }

    private var styledText: some View {
        Text(text)
            .font(.system(size: fontSize))
            .lineSpacing(lineSpacing)
            .lineLimit(maxLines)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        styledText
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(height: shownHeight > 0 ? shownHeight : nil, alignment: .top)
            .clipped()
            .background {
                // Invisible copy that measures how tall the text wants to be; the visible text's
                // height follows it with the resize animation, so only line changes animate.
                styledText
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        guard abs(height - shownHeight) > 0.5 else { return }
                        if shownHeight == 0 {
                            shownHeight = height
                        } else {
                            withAnimation(resize) { shownHeight = height }
                        }
                    }
            }
    }
}
