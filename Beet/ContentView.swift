//
//  ContentView.swift
//  Beet
//
//  Created by Ted Schultz on 5/14/26.
//

import SwiftUI

private enum PlayRoute: Hashable {
    case modeSelect
    case singleMaze
    case splitScreen
}

struct ContentView: View {
    @State private var route: PlayRoute = .modeSelect
    @State private var selectedBpm: Double = 120

    var body: some View {
        Group {
            switch route {
            case .modeSelect:
                PlayModeSelectView(
                    bpm: $selectedBpm,
                    onSingle: { route = .singleMaze },
                    onSplit: { route = .splitScreen }
                )
            case .singleMaze:
                BeetGameView(initialBpm: selectedBpm, onMainMenu: { route = .modeSelect })
            case .splitScreen:
                DualBeetGameView(initialBpm: selectedBpm, onMainMenu: { route = .modeSelect })
            }
        }
        .animation(.easeInOut(duration: 0.22), value: route)
    }
}

// MARK: - Rhythm helpers (match `LedgesGameScene` scroll speed & width caps)

private enum MenuRhythmLayout {
    static let scrollSpeed: CGFloat = 120
    static let maxColumnWidth: CGFloat = 132

    static func scrollPointsPerBeat(bpm: Double) -> CGFloat {
        let b = max(40, min(240, bpm))
        return scrollSpeed * 60 / CGFloat(b)
    }

    static func columnWidthGridUnit(bpm: Double) -> CGFloat {
        var g = scrollPointsPerBeat(bpm: bpm)
        while g > maxColumnWidth {
            g /= 2
        }
        return max(1, g)
    }

    static func helperLine(bpm: Double) -> String {
        let beat = scrollPointsPerBeat(bpm: bpm)
        let grid = columnWidthGridUnit(bpm: bpm)
        let bStr = beat >= 100 ? String(format: "%.0f", beat) : String(format: "%.1f", beat)
        let gStr = grid >= 100 ? String(format: "%.0f", grid) : String(format: "%.1f", grid)
        return "Scroll per beat ≈ \(bStr) pt · column widths = multiples of \(gStr) pt"
    }
}

private struct MenuBPMCard: View {
    @Binding var bpm: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BPM")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 10) {
                Button {
                    bpm = max(40, bpm - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                Text("\(Int(bpm))")
                    .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
                    .frame(minWidth: 48)
                Button {
                    bpm = min(240, bpm + 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            Slider(value: $bpm, in: 40...240, step: 1)
            Text(MenuRhythmLayout.helperLine(bpm: bpm))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Mode picker

private struct PlayModeSelectView: View {
    @Binding var bpm: Double
    let onSingle: () -> Void
    let onSplit: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.11)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("Beet")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Ledges")
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.bottom, 4)

                MenuBPMCard(bpm: $bpm)
                    .padding(.horizontal, 24)

                Text("How do you want to play?")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))

                VStack(spacing: 14) {
                    Button {
                        onSingle()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("One maze")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                            Text("Full screen, single lane.")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.22, green: 0.55, blue: 0.34))

                    Button {
                        onSplit()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Split screen")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                            Text("Two mazes side by side. One wall ends the run; steps add together.")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .padding(.top, 48)
        }
    }
}

#Preview {
    ContentView()
}
