import SwiftUI

/// A mini line chart for displaying price trends in the market dashboard.
struct SparklineChart: View {
    let data: [Double]
    let isPositive: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        if data.count < 2 {
            Rectangle()
                .fill(TerminalTheme.dimText.opacity(0.2))
                .frame(width: width, height: height)
        } else {
            ZStack(alignment: .bottom) {
                // Filled area under the line
                filledArea
                    .fill(lineColor.opacity(0.15))

                // The line itself
                linePath
                    .stroke(lineColor, lineWidth: 1.5)

                // Baseline (first data point) dashed line
                baselinePath
                    .stroke(TerminalTheme.dimText.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            }
            .frame(width: width, height: height)
        }
    }

    private var lineColor: Color {
        isPositive ? TerminalTheme.accentGreen : TerminalTheme.accentRed
    }

    private var dataRange: (min: Double, max: Double) {
        let minVal = data.min() ?? 0
        let maxVal = data.max() ?? 1
        // Add small padding so the line doesn't touch edges
        let range = maxVal - minVal
        let padding = range > 0 ? range * 0.1 : 1.0
        return (minVal - padding, maxVal + padding)
    }

    private func normalizedY(_ value: Double) -> CGFloat {
        let (minVal, maxVal) = dataRange
        let range = maxVal - minVal
        guard range > 0 else { return height / 2 }
        return height - CGFloat((value - minVal) / range) * height
    }

    private var linePath: Path {
        Path { path in
            let step = width / CGFloat(data.count - 1)

            path.move(to: CGPoint(x: 0, y: normalizedY(data[0])))
            for i in 1..<data.count {
                path.addLine(to: CGPoint(x: step * CGFloat(i), y: normalizedY(data[i])))
            }
        }
    }

    private var filledArea: Path {
        Path { path in
            let step = width / CGFloat(data.count - 1)

            path.move(to: CGPoint(x: 0, y: height))
            path.addLine(to: CGPoint(x: 0, y: normalizedY(data[0])))
            for i in 1..<data.count {
                path.addLine(to: CGPoint(x: step * CGFloat(i), y: normalizedY(data[i])))
            }
            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
        }
    }

    private var baselinePath: Path {
        Path { path in
            let y = normalizedY(data[0])
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
    }
}
