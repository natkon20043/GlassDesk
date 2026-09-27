import Foundation
import IOKit.ps
import Observation

/// Samples CPU, memory, disk and battery every few seconds. Uses only public,
/// permission-free APIs (Mach host statistics, volume resource values, IOPowerSources).
@MainActor
@Observable
final class SystemStats {
    static let shared = SystemStats()

    private(set) var cpu: Double = 0
    private(set) var memory: Double = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    private(set) var disk: Double = 0
    /// nil on Macs without a battery.
    private(set) var battery: Double?
    private(set) var charging = false

    @ObservationIgnored private var previousTicks: (busy: UInt64, total: UInt64)?
    @ObservationIgnored private var timer: Timer?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        // Only publish whole-percent changes: each change redraws a glass widget, and every
        // redraw costs WindowServer a fresh blur of whatever is behind it.
        publish(\.cpu, sampleCPU())
        publish(\.memory, sampleMemory())
        publish(\.disk, sampleDisk())
        let (level, onAC) = sampleBattery()
        let roundedLevel = level.map { ($0 * 100).rounded() / 100 }
        if roundedLevel != battery { battery = roundedLevel }
        if onAC != charging { charging = onAC }
    }

    private func publish(_ keyPath: ReferenceWritableKeyPath<SystemStats, Double>, _ value: Double) {
        let rounded = (value * 100).rounded() / 100
        if self[keyPath: keyPath] != rounded { self[keyPath: keyPath] = rounded }
    }

    private func sampleCPU() -> Double {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return cpu }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        for core in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * core
            func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            let used = ticks(CPU_STATE_USER) + ticks(CPU_STATE_SYSTEM) + ticks(CPU_STATE_NICE)
            busy += used
            total += used + ticks(CPU_STATE_IDLE)
        }
        defer { previousTicks = (busy, total) }
        guard let previous = previousTicks, total > previous.total else { return cpu }
        return Double(busy &- previous.busy) / Double(total - previous.total)
    }

    /// Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
    private func sampleMemory() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return memory }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let appPages = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return Double(usedPages * UInt64(pageSize)) / Double(ProcessInfo.processInfo.physicalMemory)
    }

    private func sampleDisk() -> Double {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage else { return disk }
        return 1 - Double(available) / Double(total)
    }

    private func sampleBattery() -> (Double?, Bool) {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (Double(current) / Double(max), onAC)
        }
        return (nil, false)
    }
}
