#if DEBUG
import Foundation

/// Performance monitoring class for debugging and profiling
public class PerformanceMonitor {
    private var startTime: TimeInterval
    private var lastTime: TimeInterval
    private var measurements: [(String, TimeInterval)] = []
    private var functionName: String
    
    public init(functionName: String) {
        self.startTime = ProcessInfo.processInfo.systemUptime
        self.lastTime = startTime
        self.functionName = functionName
    }
    
    public func measure(_ description: String) {
        let currentTime = ProcessInfo.processInfo.systemUptime
        let elapsed = currentTime - lastTime
        measurements.append((description, elapsed))
        lastTime = currentTime
    }
    
    public func printMeasurementResults() {
        let totalTime = ProcessInfo.processInfo.systemUptime - startTime
        print("\nPerformance Measurements for \(functionName):")
        print("----------------------------------------")
        for (description, time) in measurements {
            let formattedTime = String(format: "%.4f", time * 1000)
            print("\(description.padding(toLength: 30, withPad: " ", startingAt: 0)): \(formattedTime) ms")
        }
        print("----------------------------------------")
        print(String(format: "Total time: %.4f ms", totalTime * 1000))
    }
}

#else
/// Stub performance monitor for release builds
public class PerformanceMonitor {
    public init(functionName: String) {}
    public func measure(_ description: String) {}
    public func printMeasurementResults() {}
}
#endif
