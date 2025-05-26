import SwiftUI

// Configuration for a single sine wave within the group
private struct WaveConfig: Identifiable {
    let id = UUID()
    var frequencyMultiplier: CGFloat
    var amplitudeMultiplier: CGFloat // Relative to the main audioLevel-driven amplitude
    var opacity: Double
    var phaseShift: CGFloat = 0.0 // To make waves offset from each other
}

struct AudioLevelIndicatorView: View {
    var audioLevel: Float // Normalized 0.0 to 1.0
    var baseWaveColor: Color = .accentColor
    var waveMaxHeight: CGFloat = 50.0
    var baseLineWidth: CGFloat = 1.5
    var density: Int = 100 // Number of points to draw the wave

    // Define multiple wave configurations
    // You can tweak these for different visual effects
    private let waveConfigs: [WaveConfig] = [
        WaveConfig(frequencyMultiplier: 1.0, amplitudeMultiplier: 1.0, opacity: 1.0),
        WaveConfig(frequencyMultiplier: 0.7, amplitudeMultiplier: 0.6, opacity: 0.6, phaseShift: .pi / 3),
        WaveConfig(frequencyMultiplier: 1.3, amplitudeMultiplier: 0.4, opacity: 0.4, phaseShift: .pi / -3)
    ]

    var body: some View {
        ZStack { // Use ZStack to overlay multiple paths
            ForEach(waveConfigs) { config in
                GeometryReader { geometry in
                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        let midHeight = height / 2
                        
                        let baseAmplitudeValue: CGFloat = 1.0 // Minimum visible wave before scaling
                        let dynamicAmplitudeValue = (waveMaxHeight / 2 - baseAmplitudeValue) * CGFloat(audioLevel)
                        let currentMasterAmplitude = baseAmplitudeValue + dynamicAmplitudeValue

                        // Apply individual wave config multipliers
                        let waveAmplitude = currentMasterAmplitude * config.amplitudeMultiplier
                        let waveFrequency = 2.0 * config.frequencyMultiplier // Base frequency of 2 cycles

                        path.move(to: CGPoint(x: 0, y: midHeight))

                        for i in 0...density {
                            let x = CGFloat(i) / CGFloat(density) * width
                            let angle = (CGFloat(i) / CGFloat(density)) * waveFrequency * 2 * .pi + config.phaseShift
                            let yOffset = waveAmplitude * sin(angle)
                            path.addLine(to: CGPoint(x: x, y: midHeight - yOffset))
                        }
                    }
                    .stroke(baseWaveColor.opacity(config.opacity), lineWidth: baseLineWidth)
                    .animation(.easeInOut(duration: 0.04), value: audioLevel) // Faster, smoother animation
                }
            }
        }
        .frame(height: waveMaxHeight)
        .opacity(audioLevel > 0.01 ? 1.0 : 0.3)
        .animation(.easeInOut(duration: 0.2), value: audioLevel > 0.01)
    }
}

#Preview {
    VStack(spacing: 30) {
        Text("Audio Level: 0.0")
        AudioLevelIndicatorView(audioLevel: 0.0)
            .frame(width: 200) // Give it some width for preview
        Text("Audio Level: 0.2")
        AudioLevelIndicatorView(audioLevel: 0.2, baseWaveColor: .blue)
            .frame(width: 200)
        Text("Audio Level: 0.5")
        AudioLevelIndicatorView(audioLevel: 0.5, baseWaveColor: .green)
            .frame(width: 200)
        Text("Audio Level: 0.8")
        AudioLevelIndicatorView(audioLevel: 0.8, baseWaveColor: .orange, baseLineWidth: 2)
            .frame(width: 200)
        Text("Audio Level: 1.0")
        AudioLevelIndicatorView(audioLevel: 1.0, baseWaveColor: .purple)
            .frame(width: 200)
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
