import Foundation
import BinFile

/// BPS patch format implementation
public class BPS: Patch {
    // MARK: - Types
    
    /// BPS patch action types
    public enum ActionType: Int {
        case sourceRead = 0
        case targetRead = 1
        case sourceCopy = 2
        case targetCopy = 3
    }
    
    /// BPS patch action
    public struct BPSAction {
        var type: ActionType
        var length: Int
        var bytes: [UInt8]
        var relativeOffset: Int
    }
    
    /// BPS patch errors
    public enum BPSError: Error {
        case invalidMagic
        case invalidMetadata
        case sourceChecksumMismatch
        case targetChecksumMismatch
        case patchChecksumMismatch
        case patchFailed(String)
        
        public var localizedDescription: String {
            switch self {
            case .invalidMagic:
                return "Invalid BPS magic number"
            case .invalidMetadata:
                return "Invalid BPS metadata"
            case .sourceChecksumMismatch:
                return "Source ROM checksum mismatch"
            case .targetChecksumMismatch:
                return "Target ROM checksum mismatch"
            case .patchChecksumMismatch:
                return "Patch file checksum mismatch"
            case .patchFailed(let message):
                return "Patch failed: \(message)"
            }
        }
    }
    
    // MARK: - Constants
    
    /// BPS magic string
    public static let magic = "BPS1"
    
    // MARK: - Properties
    
    /// Source ROM size
    public private(set) var sourceSize: Int = 0
    
    /// Target ROM size
    public private(set) var targetSize: Int = 0
    
    /// Patch metadata
    public private(set) var metaData: String = ""
    
    /// Patch actions
    public private(set) var actions: [BPSAction] = []
    
    /// Source ROM checksum
    public private(set) var sourceChecksum: UInt32 = 0
    
    /// Target ROM checksum
    public private(set) var targetChecksum: UInt32 = 0
    
    /// Patch file checksum
    public private(set) var patchChecksum: UInt32 = 0
    
    // MARK: - Initialization
    
    /// Creates a new BPS patch
    public init() {
        actions.reserveCapacity(50000)
    }
    
    // MARK: - Patch Protocol Implementation
    
    /// Calculates the file checksum
    public func calculateFileChecksum() -> UInt32 {
        let patchFile = try! export()
        return patchFile.hashCRC32(start: 0, length: patchFile.fileSize - 4)
    }
    
    /// Validates the source ROM
    public func validateSource(_ romFile: BinFile, headerSize: Int = 0) -> Bool {
        return sourceChecksum == romFile.hashCRC32(start: headerSize)
    }
    
    /// Gets validation information
    public func getValidationInfo() -> String {
        return String(format: "Source CRC32: %08x\nTarget CRC32: %08x\nPatch CRC32: %08x",
                     sourceChecksum, targetChecksum, patchChecksum)
    }

    /// Applies the patch to a ROM file
    public func apply(to romFile: BinFile, validate: Bool = true) throws -> BinFile {
        let monitor = PerformanceMonitor(functionName: "BPS.apply")
        
        if validate && !validateSource(romFile) {
            throw BPSError.sourceChecksumMismatch
        }
        
        monitor.measure("Source validation")
        
        // Create local copies of the arrays for efficient access
        let sourceData = try romFile.readBytesToArray(offset: 0, length: romFile.fileSize)
        var targetData = [UInt8](repeating: 0, count: targetSize)
        
        monitor.measure("Buffer allocation")
        
        var sourceRelativeOffset = 0
        var targetRelativeOffset = 0
        var currentOffset = 0
        
        targetData.withUnsafeMutableBufferPointer { targetBuffer in
            sourceData.withUnsafeBufferPointer { sourceBuffer in
                for action in actions {
                    switch action.type {
                    case .sourceRead:
                        if action.length >= 4 {
                            // Use memcpy for contiguous blocks
                            memcpy(targetBuffer.baseAddress! + currentOffset,
                                    sourceBuffer.baseAddress! + currentOffset,
                                    action.length)
                        } else {
                            // Small blocks: use direct copy
                            for i in 0..<action.length {
                                targetBuffer[currentOffset + i] = sourceBuffer[currentOffset + i]
                            }
                        }
                        currentOffset += action.length
                        
                    case .targetRead:
                        if action.bytes.count >= 4 {
                            // Use memcpy for contiguous blocks
                            memcpy(targetBuffer.baseAddress! + currentOffset,
                                    action.bytes,
                                    action.bytes.count)
                        } else {
                            // Small blocks: use direct copy
                            for i in 0..<action.bytes.count {
                                targetBuffer[currentOffset + i] = action.bytes[i]
                            }
                        }
                        currentOffset += action.bytes.count
                        
                    case .sourceCopy:
                        sourceRelativeOffset += action.relativeOffset
                        if action.length >= 4 {
                            // Use memcpy for contiguous blocks
                            memcpy(targetBuffer.baseAddress! + currentOffset,
                                    sourceBuffer.baseAddress! + sourceRelativeOffset,
                                    action.length)
                        } else {
                            // Small blocks: use direct copy
                            for i in 0..<action.length {
                                targetBuffer[currentOffset + i] = sourceBuffer[sourceRelativeOffset + i]
                            }
                        }
                        sourceRelativeOffset += action.length
                        currentOffset += action.length
                        
                    case .targetCopy:
                        targetRelativeOffset += action.relativeOffset
                        
                        if action.length > 4 {
                            // Check if regions overlap
                            let sourceStart = targetRelativeOffset
                            let sourceEnd = targetRelativeOffset + action.length
                            let destStart = currentOffset
                            let destEnd = currentOffset + action.length
                            
                            if sourceStart < destEnd && destStart < sourceEnd {
                                // Regions overlap - find the overlap pattern
                                let overlapStart = max(sourceStart, destStart)
                                let patternLength = overlapStart - sourceStart
                                
                                if patternLength > 0 {
                                    if patternLength == 1 {
                                        // For single-byte patterns, use memset
                                        let patternByte = targetBuffer[targetRelativeOffset]
                                        memset(targetBuffer.baseAddress! + currentOffset,
                                              Int32(patternByte),
                                              action.length)
                                    } else {
                                        // Copy the pattern first
                                        memcpy(targetBuffer.baseAddress! + currentOffset,
                                              targetBuffer.baseAddress! + targetRelativeOffset,
                                              patternLength)
                                        
                                        // Then fill the rest with the repeating pattern
                                        for i in stride(from: patternLength, to: action.length, by: patternLength) {
                                            let copyLength = min(patternLength, action.length - i)
                                            memcpy(targetBuffer.baseAddress! + currentOffset + i,
                                                  targetBuffer.baseAddress! + targetRelativeOffset,
                                                  copyLength)
                                        }
                                    }
                                } else {
                                    // No pattern to repeat, just use memcpy
                                    memcpy(targetBuffer.baseAddress! + currentOffset,
                                          targetBuffer.baseAddress! + targetRelativeOffset,
                                          action.length)
                                }
                            } else {
                                // No overlap, use memcpy
                                memcpy(targetBuffer.baseAddress! + currentOffset,
                                      targetBuffer.baseAddress! + targetRelativeOffset,
                                      action.length)
                            }
                        } else {
                            // Direct byte-by-byte copy for small copies
                            for i in 0..<action.length {
                                targetBuffer[currentOffset + i] = targetBuffer[targetRelativeOffset + i]
                            }
                        }
                        
                        targetRelativeOffset += action.length
                        currentOffset += action.length
                    }
                }
            }
        }
        
        monitor.measure("Action application")
        
        // Create the final file with the patched data
        let tempFile = try BinFile(source: targetData)
        
        monitor.measure("Final file creation")
        
        if validate && targetChecksum != tempFile.hashCRC32() {
            throw BPSError.targetChecksumMismatch
        }
        
        monitor.measure("Output validation")
        monitor.printMeasurementResults()
        
        return tempFile
    }
    
    /// Exports the patch to a BinFile
    public func export() throws -> BinFile {
        var patchFileSize = BPS.magic.count
        patchFileSize += BPS.getVLVLength(sourceSize)
        patchFileSize += BPS.getVLVLength(targetSize)
        patchFileSize += BPS.getVLVLength(metaData.count)
        patchFileSize += metaData.count
        
        for action in actions {
            patchFileSize += BPS.getVLVLength(((action.length - 1) << 2) + action.type.rawValue)
            
            if action.type == .targetRead {
                patchFileSize += action.bytes.count
            } else if action.type == .sourceCopy || action.type == .targetCopy {
                patchFileSize += BPS.getVLVLength((abs(action.relativeOffset) << 1) + (action.relativeOffset < 0 ? 1 : 0))
            }
        }
        
        patchFileSize += 12 // Checksums
        
        let patchFile = try BinFile(source: patchFileSize)
        patchFile.littleEndian = true
        
        try patchFile.writeString(BPS.magic)
        try BPS.writeVLV(patchFile, sourceSize)
        try BPS.writeVLV(patchFile, targetSize)
        try BPS.writeVLV(patchFile, metaData.count)
        try patchFile.writeString(metaData)
        
        // Pre-calculate total size needed
        var totalBytes = 0
        for action in actions {
            totalBytes += BPS.getVLVLength(((action.length - 1) << 2) + action.type.rawValue)
            if action.type == .targetRead {
                totalBytes += action.bytes.count
            } else if action.type == .sourceCopy || action.type == .targetCopy {
                totalBytes += BPS.getVLVLength((abs(action.relativeOffset) << 1) + (action.relativeOffset < 0 ? 1 : 0))
            }
        }
        
        // Allocate buffer for all action bytes
        var actionBytes = [UInt8](repeating: 0, count: totalBytes)
        var currentOffset = 0
        
        // Write all actions to buffer
        for action in actions {
            // Write action VLV
            let actionVLV = ((action.length - 1) << 2) + action.type.rawValue
            var value = actionVLV
            while true {
                let x = value & 0x7f
                value >>= 7
                if value == 0 {
                    actionBytes[currentOffset] = UInt8(0x80 | x)
                    currentOffset += 1
                    break
                }
                actionBytes[currentOffset] = UInt8(x)
                currentOffset += 1
                value -= 1
            }
            
            if action.type == .targetRead {
                // Use memcpy for target read bytes
                if action.bytes.count >= 4 {
                    memcpy(&actionBytes[currentOffset], action.bytes, action.bytes.count)
                } else {
                    // For small blocks, use direct copy
                    for i in 0..<action.bytes.count {
                        actionBytes[currentOffset + i] = action.bytes[i]
                    }
                }
                currentOffset += action.bytes.count
            } else if action.type == .sourceCopy || action.type == .targetCopy {
                // Write offset VLV
                let offsetVLV = (abs(action.relativeOffset) << 1) + (action.relativeOffset < 0 ? 1 : 0)
                value = offsetVLV
                while true {
                    let x = value & 0x7f
                    value >>= 7
                    if value == 0 {
                        actionBytes[currentOffset] = UInt8(0x80 | x)
                        currentOffset += 1
                        break
                    }
                    actionBytes[currentOffset] = UInt8(x)
                    currentOffset += 1
                    value -= 1
                }
            }
        }
        
        // Batch write all action bytes
        try patchFile.writeBytes(actionBytes)
        
        try patchFile.writeU32(sourceChecksum)
        try patchFile.writeU32(targetChecksum)
        try patchFile.writeU32(patchChecksum)
        
        return patchFile
    }
    
    /// Creates a BPS patch from a file
    public static func fromFile(_ file: BinFile) throws -> BPS {
        let monitor = PerformanceMonitor(functionName: "BPS.fromFile")
        file.littleEndian = true
        let patch = BPS()
        
        file.seek(to: 4) // Skip BPS1
        
        patch.sourceSize = try readVLV(file)
        patch.targetSize = try readVLV(file)
        
        let metaDataLength = try readVLV(file)
        if metaDataLength > 0 {
            patch.metaData = try file.readString(metaDataLength)
        }
        
        monitor.measure("Header parsing")
        
        let endActionsOffset = file.fileSize - 12
        
        while file.offset < endActionsOffset {
            let data = try readVLV(file)
            let rawType = data & 3
            guard let type = ActionType(rawValue: rawType) else {
                throw BPSError.patchFailed("Invalid action type: \(rawType)")
            }
            let length = (data >> 2) + 1
            
            var action = BPSAction(type: type, length: length, bytes: [], relativeOffset: 0)
            
            if type == .targetRead {
                action.bytes = try file.readBytes(length)
            } else if type == .sourceCopy || type == .targetCopy {
                let relativeOffset = try readVLV(file)
                let sign = (relativeOffset & 1) != 0 ? -1 : 1
                let magnitude = relativeOffset >> 1
                action.relativeOffset = sign * magnitude
            }

            patch.actions.append(action)
        }
        
        monitor.measure("Action parsing")
        
        patch.sourceChecksum = try file.readU32()
        patch.targetChecksum = try file.readU32()
        patch.patchChecksum = try file.readU32()
        
        let calculatedChecksum = file.hashCRC32(start: 0, length: file.fileSize - 4)
        if patch.patchChecksum != calculatedChecksum {
            throw BPSError.patchChecksumMismatch
        }
        
        monitor.measure("Checksum validation")
        monitor.printMeasurementResults()
        
        return patch
    }
    
    /// Creates a BPS patch from two ROM files
    public static func buildFromRoms(original: BinFile, modified: BinFile, deltaMode: Bool = false) throws -> BPS {
        let monitor = PerformanceMonitor(functionName: "BPS.buildFromRoms")
        let patch = BPS()
        patch.sourceSize = original.fileSize
        patch.targetSize = modified.fileSize
        
        monitor.measure("Initialization")
        
        if deltaMode {
            patch.actions = try createBPSFromFilesDelta(original: original, modified: modified)
        } else {
            patch.actions = try createBPSFromFilesLinear(original: original, modified: modified)
        }
        
        monitor.measure("Action creation")
        
        patch.sourceChecksum = original.hashCRC32()
        patch.targetChecksum = modified.hashCRC32()
        patch.patchChecksum = patch.calculateFileChecksum()
        
        monitor.measure("Checksum calculation")
        monitor.printMeasurementResults()
        
        return patch
    }
    
    // MARK: - Helper Methods
    
    /// Reads a variable-length value
    private static func readVLV(_ file: BinFile) throws -> Int {
        var data = 0
        var shift = 1
        
        while true {
            let x = try file.readU8()
            data += (Int(x) & 0x7f) * shift
            if x & 0x80 != 0 {
                break
            }
            shift <<= 7
            data += shift
        }
        
        return data
    }
    
    /// Writes a variable-length value
    private static func writeVLV(_ file: BinFile, _ data: Int) throws {
        var value = data
        while true {
            let x = value & 0x7f
            value >>= 7
            if value == 0 {
                try file.writeU8(UInt8(0x80 | x))
                break
            }
            try file.writeU8(UInt8(x))
            value -= 1
        }
    }
    
    /// Gets the length of a variable-length value
    private static func getVLVLength(_ data: Int) -> Int {
        var value = data
        var length = 1
        while true {
            value >>= 7
            if value == 0 {
                break
            }
            length += 1
            value -= 1
        }
        return length
    }
    
    /// Creates a BPS patch using linear algorithm
    private static func createBPSFromFilesLinear(original: BinFile, modified: BinFile) throws -> [BPSAction] {
        var patchActions: [BPSAction] = []
        let sourceData = try original.readBytes(original.fileSize)
        let targetData = try modified.readBytes(modified.fileSize)
        let sourceSize = original.fileSize
        let targetSize = modified.fileSize
        
        var targetReadLength = 0
        var targetReadBytes: [UInt8] = []
        
        var offset = 0
        while offset < targetSize {
            var matchLength = 0
            // Try to find a match in the source data
            if offset < sourceSize {
                let maxLength = min(sourceSize - offset, targetSize - offset)
                for length in 1...maxLength {
                    if sourceData[offset..<(offset + length)] == targetData[offset..<(offset + length)] {
                        matchLength = length
                    } else {
                        break
                    }
                }
            }
            
            if matchLength > 0 {
                // Found a match in source data
                if targetReadLength > 0 {
                    // Flush target read
                    patchActions.append(BPSAction(type: .targetRead, length: targetReadLength, bytes: targetReadBytes, relativeOffset: 0))
                    targetReadLength = 0
                    targetReadBytes = []
                }
                patchActions.append(BPSAction(type: .sourceRead, length: matchLength, bytes: [], relativeOffset: 0))
                offset += matchLength
            } else {
                // No match found, add to target read
                targetReadLength += 1
                targetReadBytes.append(targetData[offset])
                offset += 1
            }
        }
        
        // Flush any remaining target read
        if targetReadLength > 0 {
            patchActions.append(BPSAction(type: .targetRead, length: targetReadLength, bytes: targetReadBytes, relativeOffset: 0))
        }
        
        return patchActions
    }
    
    /// Creates a BPS patch using delta algorithm
    private static func createBPSFromFilesDelta(original: BinFile, modified: BinFile) throws -> [BPSAction] {
        // TODO: Implement delta algorithm
        // For now, fall back to linear algorithm
        return try createBPSFromFilesLinear(original: original, modified: modified)
    }
}
