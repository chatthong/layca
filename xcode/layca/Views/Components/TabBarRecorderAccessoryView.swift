#if os(iOS)
import SwiftUI

@available(iOS 26.0, *)
struct TabBarRecorderAccessoryView: View {
    let isRecording: Bool
    let recordingTimeText: String
    let activeSessionDateText: String
    let preflightMessage: String?
    let onRecordTap: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement

    var body: some View {
        Group {
            if isInlinePlacement {
                inlineAccessory
            } else {
                expandedAccessory
            }
        }
    }

    private var isInlinePlacement: Bool {
        accessoryPlacement == .inline
    }

    private var expandedAccessory: some View {
        HStack(spacing: 10) {
            Image(systemName: isRecording ? "waveform.circle.fill" : "record.circle.fill")
                .foregroundStyle(isRecording ? Color.red : Color.accentColor)
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 1) {
                Text(recordingTimeText)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text(activeSessionDateText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            recordActionButton(showsLabel: true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var inlineAccessory: some View {
        HStack(spacing: 6) {
            Image(systemName: isRecording ? "waveform.circle.fill" : "record.circle")
                .foregroundStyle(isRecording ? Color.red : Color.accentColor)
                .font(.system(size: 13, weight: .semibold))

            Text(recordingTimeText)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: 4)

            recordActionButton(showsLabel: false)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
    }

    private func recordActionButton(showsLabel: Bool) -> some View {
        Button(action: onRecordTap) {
            HStack(spacing: showsLabel ? 6 : 0) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                    .font(.subheadline.weight(.bold))

                if showsLabel {
                    Text(isRecording ? "Stop" : "Record")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isRecording ? Color.red : Color.accentColor)
            .frame(width: showsLabel ? 112 : 40, height: 38)
            .background(
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.secondary.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .fixedSize()
    }
}
#endif
