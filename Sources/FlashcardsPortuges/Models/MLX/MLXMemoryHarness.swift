import Foundation
import MLX

/// Total free + reclaimable system memory (bytes) via Mach VM stats.
/// Uses `free_count + inactive_count` — inactive pages can be
/// reclaimed by the kernel before swapping.
func freeSystemMemoryBytes() -> Int {
    let host = mach_host_self()
    var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    var vmInfo = vm_statistics64_data_t()
    let kr = withUnsafeMutablePointer(to: &vmInfo) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
            host_statistics64(host, HOST_VM_INFO64, intPtr, &size)
        }
    }
    guard kr == KERN_SUCCESS else { return 0 }
    let pageSize = Int(sysconf(_SC_PAGESIZE))
    return (Int(vmInfo.free_count) + Int(vmInfo.inactive_count)) * pageSize
}

struct MLXMemorySnapshot: Equatable, Sendable {
    let activeMemory: Int
    let cacheMemory: Int
    let peakMemory: Int

    init(activeMemory: Int, cacheMemory: Int, peakMemory: Int) {
        self.activeMemory = activeMemory
        self.cacheMemory = cacheMemory
        self.peakMemory = peakMemory
    }

    init(from gpuSnapshot: MLX.Memory.Snapshot) {
        self.activeMemory = gpuSnapshot.activeMemory
        self.cacheMemory = gpuSnapshot.cacheMemory
        self.peakMemory = gpuSnapshot.peakMemory
    }
}

struct MemoryBudget: Equatable, Sendable {
    let memoryLimitBytes: Int
    let wiredLimitBytes: Int
    let cacheLimitBytes: Int

    static func conservativeDefaults(physicalRAMBytes: Int) -> MemoryBudget {
        MemoryBudget(
            memoryLimitBytes: Int(Double(physicalRAMBytes) * 0.60),
            wiredLimitBytes: Int(Double(physicalRAMBytes) * 0.40),
            cacheLimitBytes: 256 * 1024 * 1024
        )
    }
}

enum MLXLoadDecision: Equatable, Sendable {
    case allowed
    case rejected(reason: MLXLoadRejection)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

enum MLXLoadRejection: Equatable, Sendable {
    case wouldExceedMemoryLimit(requestedBytes: Int, budgetBytes: Int, currentBytes: Int)
    case notConfigured
    case memoryPressureCritical
    case approachingBudgetCeiling(currentBytes: Int, ceilingBytes: Int)
    case freeMemoryLow(requestedBytes: Int, availableBytes: Int)

    var userMessage: String {
        switch self {
        case .wouldExceedMemoryLimit(let requested, let budget, let current):
            return "Loading would push MLX memory past the configured limit (request \(format(requested)) + already \(format(current)) > limit \(format(budget))). Free another model first or raise the limit."
        case .notConfigured:
            return "MLX memory harness has not been configured."
        case .memoryPressureCritical:
            return "macOS reported low memory recently. New MLX loads are paused until the system recovers."
        case .approachingBudgetCeiling(let current, let ceiling):
            return "MLX is near its memory ceiling (\(format(current)) / \(format(ceiling))). New loads paused; complete or unload current work first."
        case .freeMemoryLow(let requested, let available):
            return "System does not have enough free memory to load the model (needs \(format(requested)), only \(format(available)) available). Close other applications and try again."
        }
    }

    private func format(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

/// Single safety harness for every MLX operation. Mitigates the
/// known kernel-panic class where wired memory bypasses macOS pressure
/// notifications. Conservative defaults: 60% memoryLimit, 40% wiredLimit,
/// 256 MB cacheLimit.
actor MLXMemoryHarness {
    private var budget: MemoryBudget?
    private var physicalRAMBytes: Int = 0
    private(set) var criticalPressureActive: Bool = false
    private let safetyThreshold: Double = 0.90
    private let freeMemoryThreshold: Double = 0.85

    func configure(physicalRAMBytes: Int) {
        self.physicalRAMBytes = physicalRAMBytes
        let resolved = MemoryBudget.conservativeDefaults(physicalRAMBytes: physicalRAMBytes)
        self.budget = resolved
        MLX.Memory.memoryLimit = resolved.memoryLimitBytes
        MLX.Memory.cacheLimit = resolved.cacheLimitBytes
        MLX.Memory.peakMemory = 0
    }

    func currentBudget() -> MemoryBudget? { budget }

    func currentSnapshot() -> MLXMemorySnapshot {
        MLXMemorySnapshot(from: MLX.Memory.snapshot())
    }

    func canAccept(estimatedAdditionalBytes requested: Int) -> MLXLoadDecision {
        guard let budget = budget else { return .rejected(reason: .notConfigured) }
        if criticalPressureActive {
            return .rejected(reason: .memoryPressureCritical)
        }

        let available = freeSystemMemoryBytes()
        let headroom = Int(Double(available) * freeMemoryThreshold)
        if requested > headroom {
            return .rejected(reason: .freeMemoryLow(
                requestedBytes: requested,
                availableBytes: available
            ))
        }

        let snap = MLX.Memory.snapshot()
        let projected = snap.activeMemory + requested
        if projected > budget.memoryLimitBytes {
            return .rejected(reason: .wouldExceedMemoryLimit(
                requestedBytes: requested,
                budgetBytes: budget.memoryLimitBytes,
                currentBytes: snap.activeMemory
            ))
        }
        let ceiling = Int(Double(budget.memoryLimitBytes) * safetyThreshold)
        if projected > ceiling {
            return .rejected(reason: .approachingBudgetCeiling(
                currentBytes: snap.activeMemory,
                ceilingBytes: ceiling
            ))
        }
        return .allowed
    }

    func didUnload() {
        MLX.Memory.clearCache()
    }

    func handlePressureWarning() {
        MLX.Memory.clearCache()
    }

    func handlePressureCritical() {
        MLX.Memory.clearCache()
        criticalPressureActive = true
    }

    func clearCriticalPressure() {
        criticalPressureActive = false
    }
}
