import Foundation
import BinFile

/// UPS patch format implementation
public class UPS: Patch {
    // MARK: - Types
    
    /// UPS patch record
    public struct UPSRecord {
        var offset: Int
        var XORdata: [UInt8]
    }
    
    /// UPS patch errors
    public enum UPSError: Error {
        case invalidMagic
        case sourceChecksumMismatch
        case targetChecksumMismatch
        case patchChecksumMismatch
        case patchFailed(String)
        
        public var localizedDescription: String {
            switch self {
            case .invalidMagic:
                return "Invalid UPS magic number"
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
    
    /// UPS magic string
    public static let magic = "UPS1"
    
    // MARK: - Properties
    
    /// Patch records
    public private(set) var records: [UPSRecord] = []
    
    /// Input file size
    public private(set) var sizeInput: Int = 0
    
    /// Output file size
    public private(set) var sizeOutput: Int = 0
    
    /// Input file checksum
    public private(set) var checksumInput: UInt32 = 0
    
    /// Output file checksum
    public private(set) var checksumOutput: UInt32 = 0
    
    // MARK: - Initialization
    
    /// Creates a new UPS patch
    public init() {
        records.reserveCapacity(50000)
    }
    
    // MARK: - Patch Protocol Implementation
    
    /// Adds a record to the patch
    public func addRecord(relativeOffset: Int, XORdata: [UInt8]) {
        records.append(UPSRecord(offset: relativeOffset, XORdata: XORdata))
    }
    
    /// Validates the source ROM
    public func validateSource(_ romFile: BinFile, headerSize: Int = 0) -> Bool {
        return checksumInput == romFile.hashCRC32(start: headerSize)
    }
    
    /// Gets validation information
    public func getValidationInfo() -> String {
        return String(format: "Source CRC32: %08x\nTarget CRC32: %08x",
                     checksumInput, checksumOutput)
    }
    
    /// Applies the patch to a ROM file
    public func apply(to romFile: BinFile, validate: Bool = true) throws -> BinFile {
        let monitor = PerformanceMonitor(functionName: "UPS.apply")
        
        if validate && !validateSource(romFile) {
            throw UPSError.sourceChecksumMismatch
        }
        
        monitor.measure("Source validation")
        
        // Handle the glitch that cuts the end of the file if it's larger than the changed file
        // More info: https://github.com/marcrobledo/RomPatcher.js/pull/40#issuecomment-1069087423
        var outputSize = sizeOutput
        var inputSize = sizeInput
        
        if !validate && inputSize < romFile.fileSize {
            inputSize = romFile.fileSize
            if outputSize < inputSize {
                outputSize = inputSize
            }
        }
        
        // Read source data into buffer for efficient access
        let sourceData = try romFile.readBytesToArray(offset: 0, length: inputSize)
        var targetData = [UInt8](repeating: 0, count: outputSize)
        
        monitor.measure("Buffer allocation")
        
        // Copy original file data
        if inputSize >= 4 {
            _ = targetData.withUnsafeMutableBufferPointer { targetBuffer in
                sourceData.withUnsafeBufferPointer { sourceBuffer in
                    memcpy(targetBuffer.baseAddress!, sourceBuffer.baseAddress!, inputSize)
                }
            }
        } else {
            // For very small blocks, use direct copy
            for i in 0..<inputSize {
                targetData[i] = sourceData[i]
            }
        }
        
        monitor.measure("Initial data copy")
        
        // Apply records using optimized memory access
        targetData.withUnsafeMutableBufferPointer { targetBuffer in
            sourceData.withUnsafeBufferPointer { sourceBuffer in
                let targetPtr = targetBuffer.baseAddress!
                let sourcePtr = sourceBuffer.baseAddress!
                var currentOffset = 0
                
                // Pre-allocate a temporary buffer for XOR operations
                let maxXORLength = records.reduce(0) { max($0, $1.XORdata.count) }
                var xorBuffer = [UInt8](repeating: 0, count: maxXORLength)
                
                for record in records {
                    currentOffset += record.offset
                    let xorData = record.XORdata
                    let xorLength = xorData.count
                    
                    if currentOffset >= sourceData.count {
                        // Past source data - direct copy
                        if xorLength >= 4 {
                            memcpy(targetPtr.advanced(by: currentOffset), xorData, xorLength)
                        } else {
                            // For very small blocks, use direct assignment
                            for i in 0..<xorLength {
                                targetPtr[currentOffset + i] = xorData[i]
                            }
                        }
                    } else {
                        // Within source data - need XOR
                        if xorLength >= 4 {
                            // For larger blocks:
                            // 1. Copy source to temp buffer
                            memcpy(&xorBuffer, sourcePtr.advanced(by: currentOffset), xorLength)
                            
                            // 2. XOR in place using pointer arithmetic for better performance
                            let chunks = xorLength / 8
                            let remainder = xorLength % 8
                            
                            // Process 8-byte chunks
                            xorBuffer.withUnsafeMutableBytes { xorBufferPtr in
                                xorData.withUnsafeBytes { xorDataPtr in
                                    for i in 0..<chunks {
                                        let offset = i * 8
                                        let sourceValue = xorBufferPtr.load(fromByteOffset: offset, as: UInt64.self)
                                        let xorValue = xorDataPtr.load(fromByteOffset: offset, as: UInt64.self)
                                        xorBufferPtr.storeBytes(of: sourceValue ^ xorValue, toByteOffset: offset, as: UInt64.self)
                                    }
                                }
                            }
                            
                            // Handle remaining bytes separately
                            if remainder > 0 {
                                let startOffset = chunks * 8
                                for i in 0..<remainder {
                                    xorBuffer[startOffset + i] ^= xorData[startOffset + i]
                                }
                            }
                            
                            // 3. Copy result to target
                            memcpy(targetPtr.advanced(by: currentOffset), xorBuffer, xorLength)
                        } else {
                            // For very small blocks, use direct XOR
                            for i in 0..<xorLength {
                                targetPtr[currentOffset + i] = sourcePtr[currentOffset + i] ^ xorData[i]
                            }
                        }
                    }
                    
                    currentOffset += xorLength + 1
                }
            }
        }
        
        monitor.measure("Record application")
        
        // Create final file from patched data
        let tempFile = try BinFile(source: targetData)
        
        monitor.measure("Final file creation")
        
        if validate && tempFile.hashCRC32() != checksumOutput {
            throw UPSError.targetChecksumMismatch
        }
        
        monitor.measure("Output validation")
        monitor.printMeasurementResults()
        
        return tempFile
    }
    
    /// Exports the patch to a BinFile
    public func export() throws -> BinFile {
        var patchFileSize = UPS.magic.count
        patchFileSize += UPS.getVLVLength(sizeInput)
        patchFileSize += UPS.getVLVLength(sizeOutput)
        
        for record in records {
            patchFileSize += UPS.getVLVLength(record.offset)
            patchFileSize += record.XORdata.count + 1
        }
        
        patchFileSize += 12 // Checksums
        
        let patchFile = try BinFile(source: patchFileSize)
        patchFile.littleEndian = true
        
        try patchFile.writeString(UPS.magic)
        try UPS.writeVLV(patchFile, sizeInput)
        try UPS.writeVLV(patchFile, sizeOutput)
        
        for record in records {
            try UPS.writeVLV(patchFile, record.offset)
            try patchFile.writeBytes(record.XORdata)
            try patchFile.writeU8(0x00)
        }
        
        try patchFile.writeU32(checksumInput)
        try patchFile.writeU32(checksumOutput)
        try patchFile.writeU32(patchFile.hashCRC32(start: 0, length: patchFile.fileSize - 4))
        
        return patchFile
    }
    
    /// Creates a UPS patch from a file
    public static func fromFile(_ file: BinFile) throws -> UPS {
        let monitor = PerformanceMonitor(functionName: "UPS.fromFile")
        let patch = UPS()
        
        monitor.measure("Initialization")
        
        // Check file size
        guard file.fileSize >= UPS.magic.count + 12 else {
            throw UPSError.patchFailed("File too small to be a valid UPS patch")
        }
        
        // Read entire file into memory
        file.seek(to: 0)
        let fileData = try file.readBytesToArray(offset: 0, length: file.fileSize)
        var offset = 0
        
        monitor.measure("File read")
        
        // Check magic number
        let magic = String(bytes: fileData[0..<UPS.magic.count], encoding: .ascii)!
        guard magic == UPS.magic else {
            throw UPSError.invalidMagic
        }
        
        offset += UPS.magic.count
        monitor.measure("Magic number validation")
        
        // Read and validate sizes
        patch.sizeInput = try readVLVFromBuffer(fileData, &offset)
        patch.sizeOutput = try readVLVFromBuffer(fileData, &offset)
        
        guard patch.sizeInput > 0 else {
            throw UPSError.patchFailed("Invalid input size: \(patch.sizeInput)")
        }
        
        guard patch.sizeOutput > 0 else {
            throw UPSError.patchFailed("Invalid output size: \(patch.sizeOutput)")
        }
        
        monitor.measure("Size validation")
        
        // Read records
        let endOffset = fileData.count - 12
        var totalOffset = 0
        
        while offset < endOffset {
            let relativeOffset = try readVLVFromBuffer(fileData, &offset)
            totalOffset += relativeOffset
            
            guard totalOffset >= 0 else {
                throw UPSError.patchFailed("Invalid offset: \(totalOffset)")
            }
            
            var XORdifferences: [UInt8] = []
            var byte: UInt8
            
            repeat {
                byte = fileData[offset]
                offset += 1
                if byte != 0 {
                    XORdifferences.append(byte)
                }
            } while byte != 0
            
            guard !XORdifferences.isEmpty else {
                throw UPSError.patchFailed("Empty XOR data at offset \(totalOffset)")
            }
            
            patch.addRecord(relativeOffset: relativeOffset, XORdata: XORdifferences)
        }
        
        monitor.measure("Record reading")
        
        // Read checksums
        patch.checksumInput = UInt32(fileData[offset]) | (UInt32(fileData[offset + 1]) << 8) |
                             (UInt32(fileData[offset + 2]) << 16) | (UInt32(fileData[offset + 3]) << 24)
        offset += 4
        
        patch.checksumOutput = UInt32(fileData[offset]) | (UInt32(fileData[offset + 1]) << 8) |
                              (UInt32(fileData[offset + 2]) << 16) | (UInt32(fileData[offset + 3]) << 24)
        offset += 4
        
        let calculatedChecksum = file.hashCRC32(start: 0, length: file.fileSize - 4)
        let storedChecksum = UInt32(fileData[offset]) | (UInt32(fileData[offset + 1]) << 8) |
                            (UInt32(fileData[offset + 2]) << 16) | (UInt32(fileData[offset + 3]) << 24)
        
        if storedChecksum != calculatedChecksum {
            throw UPSError.patchChecksumMismatch
        }
        
        monitor.measure("Checksum validation")
        monitor.printMeasurementResults()
        
        return patch
    }
    
    private static func readVLVFromBuffer(_ buffer: [UInt8], _ offset: inout Int) throws -> Int {
        var data = 0
        var shift = 1
        
        while true {
            let x = buffer[offset]
            offset += 1
            
            data += (Int(x) & 0x7f) * shift
            if x & 0x80 != 0 {
                break
            }
            shift <<= 7
            data += shift
        }
        
        return data
    }
    
    /// Creates a UPS patch from two ROM files
    public static func buildFromRoms(original: BinFile, modified: BinFile) throws -> UPS {
        let patch = UPS()
        
        // Validate input files
        guard original.fileSize > 0 else {
            throw UPSError.patchFailed("Original file is empty")
        }
        
        guard modified.fileSize > 0 else {
            throw UPSError.patchFailed("Modified file is empty")
        }
        
        patch.sizeInput = original.fileSize
        patch.sizeOutput = modified.fileSize
        
        var previousSeek = 1
        var currentOffset = 0
        
        while !modified.isEOF() {
            let b1 = try original.isEOF() ? 0x00 : original.readU8()
            let b2 = try modified.readU8()
            currentOffset += 1
            
            if b1 != b2 {
                let currentSeek = modified.offset
                var XORdata: [UInt8] = []
                
                var currentB1 = b1
                var currentB2 = b2
                while currentB1 != currentB2 {
                    XORdata.append(currentB1 ^ currentB2)
                    
                    if modified.isEOF() {
                        break
                    }
                    currentB1 = try original.isEOF() ? 0x00 : original.readU8()
                    currentB2 = try modified.readU8()
                    currentOffset += 1
                }
                
                guard !XORdata.isEmpty else {
                    throw UPSError.patchFailed("Empty XOR data at offset \(currentOffset)")
                }
                
                let relativeOffset = currentSeek - previousSeek
                
                guard relativeOffset >= 0 else {
                    throw UPSError.patchFailed("Invalid relative offset: \(relativeOffset) at position \(currentOffset)")
                }
                
                patch.addRecord(relativeOffset: relativeOffset, XORdata: XORdata)
                previousSeek = currentSeek + XORdata.count + 1
            }
        }
        
        // Calculate checksums
        patch.checksumInput = original.hashCRC32()
        patch.checksumOutput = modified.hashCRC32()
        
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
        var length = 0
        while true {
            _ = value & 0x7f
            value >>= 7
            length += 1
            if value == 0 {
                break
            }
            value -= 1
        }
        return length
    }
}
