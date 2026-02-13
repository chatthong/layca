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
        .glassEffect(accessoryGlass, in: Capsule(style: .continuous))
    }

    private var isInlinePlacement: Bool {
        accessoryPlacement == .inline
    }

    private var accessoryGlass: Glass {
        if isRecording {
            return .regular.tint(.red.opacity(0.12))
        }
        return .regular
    }

    private var expandedAccessory: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(recordingTimeText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text(activeSessionDateText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 12)

            Spacer(minLength: 8)

            expandedRecordControl
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var inlineAccessory: some View {
        HStack(spacing: 6) {
            Text(recordingTimeText)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.leading, 12)

            Spacer(minLength: 8)

            inlineRecordIcon
                .padding(.trailing, 10)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            onRecordTap()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRecording ? "Stop" : "Record")
    }

    private var inlineRecordIcon: some View {
        Image(systemName: isRecording ? "stop.circle" : "record.circle")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isRecording ? Color.red : Color.accentColor)
            .frame(width: 30, height: 30)
    }

    private var expandedRecordControl: some View {
        HStack(spacing: 6) {
            Image(systemName: isRecording ? "stop.circle" : "record.circle")
                .font(.subheadline.weight(.bold))
            Text(isRecording ? "Stop" : "Record")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isRecording ? Color.red : Color.accentColor)
        .frame(minWidth: 96, minHeight: 34)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(recordControlGlass, in: Capsule(style: .continuous))
        .glassEffectTransition(.identity)
        .contentShape(Rectangle())
        .onTapGesture {
            onRecordTap()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRecording ? "Stop" : "Record")
    }

    private var recordControlGlass: Glass {
        return .regular
    }
}
#endif
