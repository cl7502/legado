// IOS/Legado/App/UI/BatteryMonitor.swift
import UIKit
import Combine

/// 电量监控单例，仅在 view onAppear/onDisappear 时开关监听，避免持续唤醒。
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var level: Float = 1.0
    @Published private(set) var isCharging: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var enableRefCount: Int = 0

    private init() {
        refresh()
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    /// 视图出现时调用，启用系统电量监听（引用计数）
    func enable() {
        enableRefCount += 1
        if enableRefCount == 1 {
            UIDevice.current.isBatteryMonitoringEnabled = true
            refresh()
        }
    }

    /// 视图消失时调用，关闭系统监听节省资源（引用计数）
    func disable() {
        enableRefCount = max(0, enableRefCount - 1)
        if enableRefCount == 0 {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    private func refresh() {
        let raw = UIDevice.current.batteryLevel
        if raw >= 0 { level = raw }
        let state = UIDevice.current.batteryState
        isCharging = state == .charging || state == .full
    }
}
