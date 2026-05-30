// IOS/Legado/App/UI/BatteryIconView.swift
import SwiftUI

/// 自绘电池图标：Canvas 轮廓 + 比例填充 + 叠加百分比/充电符号。
/// 用于阅读器底部状态栏左侧。
struct BatteryIconView: View {
    let level: Float       // 0.0 – 1.0
    let isCharging: Bool
    let textColor: Color   // 与当前阅读主题文字颜色对应

    var body: some View {
        ZStack {
            // Canvas 绘制轮廓 + 填充
            Canvas { ctx, size in
                let nubW: CGFloat = 3
                let bodyW = size.width - nubW
                let bodyH = size.height
                let r: CGFloat = 2
                let inset: CGFloat = 1

                // 电池本体轮廓
                ctx.stroke(
                    Path(roundedRect: CGRect(x: 0, y: 0, width: bodyW, height: bodyH),
                         cornerRadius: r),
                    with: .color(textColor.opacity(0.5)),
                    lineWidth: 1
                )

                // 右侧电极凸起
                let nubH = bodyH * 0.5
                let nubY = (bodyH - nubH) / 2
                ctx.fill(
                    Path(roundedRect: CGRect(x: bodyW, y: nubY, width: nubW, height: nubH),
                         cornerRadius: 1),
                    with: .color(textColor.opacity(0.5))
                )

                // 电量填充（从左向右）
                let maxFillW = bodyW - 2 * inset
                let fillW = maxFillW * CGFloat(max(0, min(1, level)))
                if fillW > 0.5 {
                    let fillR = max(0, r - inset)
                    ctx.fill(
                        Path(roundedRect: CGRect(x: inset, y: inset,
                                                 width: fillW, height: bodyH - 2 * inset),
                             cornerRadius: fillR),
                        with: .color(isCharging ? Color.green
                                                : (level <= 0.2 ? Color.red
                                                                : textColor.opacity(0.7)))
                    )
                }
            }
            .frame(width: 28, height: 14)

            // 叠加文字（百分比或充电符号），向左偏移 1.5pt 使其居中于电池本体
            Group {
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(Int(level * 100))%")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                }
            }
            .offset(x: -1.5)  // 修正右侧电极凸起导致的视觉偏移
        }
        .frame(width: 28, height: 14)
    }
}

#Preview {
    VStack(spacing: 8) {
        BatteryIconView(level: 0.84, isCharging: false, textColor: .black)
        BatteryIconView(level: 0.15, isCharging: false, textColor: .black)
        BatteryIconView(level: 0.60, isCharging: true,  textColor: .black)
    }
    .padding()
}
