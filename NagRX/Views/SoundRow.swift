import SwiftUI

struct SoundRow: View {
    let sound: NagRXSound
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isPlaying = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(sound.displayName)
                    .foregroundStyle(isSelected ? .red : .primary)

                Spacer()

                Button {
                    if isPlaying {
                        SoundPlayer.shared.stop()
                        isPlaying = false
                    } else {
                        SoundPlayer.shared.play(sound)
                        isPlaying = true
                        // Auto-reset after a few seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            isPlaying = false
                        }
                    }
                } label: {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}
