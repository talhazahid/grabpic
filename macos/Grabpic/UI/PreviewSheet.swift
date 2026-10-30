import SwiftUI
import AppKit

struct PreviewSheet: View {
    @EnvironmentObject private var state: AppState
    let capture: LatestCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(capture.name)
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(capture.detail)
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 12)
                Button {
                    state.closePreview()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(Theme.card)
                        )
                        .overlay(
                            Circle().stroke(Theme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close preview")
            }
            .padding(.bottom, 16)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: 0x101117))
                if let image = capture.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(1)
                } else {
                    Text("The image could not be loaded.")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 420, maxHeight: 480)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )

            HStack(spacing: 10) {
                Text(capture.path)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(capture.path)
                Spacer(minLength: 16)
                SoftButton(title: "Copy again") {
                    state.copyLatest()
                }
                SoftButton(title: "Reveal") {
                    state.revealLatest()
                }
                SoftButton(title: "Done") {
                    state.closePreview()
                }
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 860)
        .background(Theme.canvas)
        .preferredColorScheme(.dark)
    }
}
