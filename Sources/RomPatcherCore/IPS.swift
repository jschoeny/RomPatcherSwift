import Foundation
import BinFile

/// IPS patch format implementation
public class IPS: Patch {
    // MARK: - Types
    
    /// IPS record types
    public enum RecordType: Int {
        case simple = 0x01
        case rle = 0x0000
    }
    
    /// IPS record
    public struct IPSRecord {
        var offset: UInt32
        var type: RecordType
        var length: UInt16
        var data: [UInt8]
        var byte: UInt8 // Only used for RLE records
    }
    
    /// IPS errors
    public enum IPSError: Error {
        case invalidMagic
        case invalidRecord
        case patchFailed(String)
        
        public var localizedDescription: String {
            switch self {
            case .invalidMagic:
                return "Invalid IPS magic number"
            case .invalidRecord:
                return "Invalid IPS record"
            case .patchFailed(let message):
                return "Patch failed: \(message)"
            }
        }
    }
    
    // MARK: - Constants
    
    /// IPS magic string
    public static let magic = "PATCH"
    
    /// Maximum ROM size (16MB)
    public static let maxRomSize: UInt32 = 0x1000000
    
    // MARK: - Properties
    
    /// Patch records
    public private(set) var records: [IPSRecord] = []
    
    /// Truncate size (optional)
    public private(set) var truncate: UInt32?
    
    // MARK: - Initialization
    
    /// Creates a new IPS patch
    public init() {
        records.reserveCapacity(1000)
    }
    
    // MARK: - Patch Protocol Implementation
    
    /// Calculates the file checksum
    public func calculateFileChecksum() -> UInt32 {
        let patchFile = try! export()
        return patchFile.hashCRC32(start: 0, length: patchFile.fileSize)
    }
    
    /// Validates the source ROM
    public func validateSource(_ romFile: BinFile, headerSize: Int = 0) -> Bool {
        // IPS format doesn't have source validation
        return true
    }
    
    /// Gets validation information
    public func getValidationInfo() -> String {
        var info = "Simple records: \(records.filter { $0.type == .simple }.count)"
        info += "\nRLE records: \(records.filter { $0.type == .rle }.count)"
        info += "\nTotal records: \(records.count)"
        if let truncate = truncate {
            info += "\nTruncate at: 0x\(String(format: "%x", truncate))"
        }
        return info
    }
    
    /// Applies the patch to a ROM file
    public func apply(to romFile: BinFile, validate: Bool = true) throws -> BinFile {
        let monitor = PerformanceMonitor(functionName: "IPS.apply")
        
        var tempFile: BinFile
        
        if let truncate = truncate {
            if truncate > UInt32(romFile.fileSize) {
                // Expand file
                tempFile = try BinFile(source: Int(truncate))
                try romFile.copyTo(target: tempFile, sourceOffset: 0, length: romFile.fileSize)
            } else {
                // Truncate file
                tempFile = try romFile.slice(length: Int(truncate))
            }
        } else {
            // Calculate target ROM size
            var newFileSize = romFile.fileSize
            for record in records {
                if record.type == .rle {
                    if Int(record.offset) + Int(record.length) > newFileSize {
                        newFileSize = Int(record.offset) + Int(record.length)
                    }
                } else {
                    if Int(record.offset) + record.data.count > newFileSize {
                        newFileSize = Int(record.offset) + record.data.count
                    }
                }
            }
            
            if newFileSize == romFile.fileSize {
                tempFile = try romFile.slice(length: romFile.fileSize)
            } else {
                tempFile = try BinFile(source: newFileSize)
                try romFile.copyTo(target: tempFile, sourceOffset: 0, length: romFile.fileSize)
            }
        }
        
        monitor.measure("File size calculation and initialization")
        
        // Apply records
        romFile.seek(to: 0)
        
        for record in records {
            tempFile.seek(to: Int(record.offset))
            
            if record.type == .rle {
                for _ in 0..<Int(record.length) {
                    try tempFile.writeU8(record.byte)
                }
            } else {
                try tempFile.writeBytes(record.data)
            }
        }
        
        monitor.measure("Record application")
        monitor.printMeasurementResults()
        
        return tempFile
    }
    
    /// Exports the patch to a BinFile
    public func export() throws -> BinFile {
        var patchFileSize = IPS.magic.count
        
        for record in records {
            if record.type == .rle {
                patchFileSize += 3 + 2 + 2 + 1 // offset + 0x0000 + length + RLE byte
            } else {
                patchFileSize += 3 + 2 + record.data.count // offset + length + data
            }
        }
        
        patchFileSize += 3 // EOF string
        if truncate != nil {
            patchFileSize += 3 // truncate
        }
        
        let patchFile = try BinFile(source: patchFileSize)
        
        try patchFile.writeString(IPS.magic)
        
        for record in records {
            try patchFile.writeU24(record.offset)
            
            if record.type == .rle {
                try patchFile.writeU16(0x0000)
                try patchFile.writeU16(record.length)
                try patchFile.writeU8(record.byte)
            } else {
                try patchFile.writeU16(UInt16(record.data.count))
                try patchFile.writeBytes(record.data)
            }
        }
        
        try patchFile.writeString("EOF")
        if let truncate = truncate {
            try patchFile.writeU24(truncate)
        }
        
        return patchFile
    }
    
    /// Creates an IPS patch from a file
    public static func fromFile(_ file: BinFile) throws -> IPS {
        let monitor = PerformanceMonitor(functionName: "IPS.fromFile")
        let patch = IPS()
        
        file.seek(to: 5) // Skip PATCH
        
        while !file.isEOF() {
            let offset = try file.readU24()
            
            if offset == 0x454f46 { // EOF
                if file.isEOF() {
                    break
                } else if file.offset + 3 == file.fileSize {
                    patch.truncate = try file.readU24()
                    break
                }
            }
            
            let length = try file.readU16()
            
            if length == IPS.RecordType.rle.rawValue {
                let rleLength = try file.readU16()
                let byte = try file.readU8()
                patch.addRLERecord(offset: offset, length: rleLength, byte: byte)
            } else {
                let data = try file.readBytes(Int(length))
                patch.addSimpleRecord(offset: offset, data: data)
            }
        }
        
        monitor.measure("Record parsing")
        monitor.printMeasurementResults()
        
        return patch
    }
    
    /// Creates an IPS patch from two ROM files
    public static func buildFromRoms(original: BinFile, modified: BinFile) throws -> IPS {
        let patch = IPS()
        
        if modified.fileSize < original.fileSize {
            patch.truncate = UInt32(modified.fileSize)
        }
        
        var previousRecord: (type: Int, startOffset: UInt32, length: Int) = (0xdeadbeef, 0, 0)
        
        original.seek(to: 0)
        modified.seek(to: 0)
        
        while !modified.isEOF() {
            let b1 = original.isEOF() ? 0x00 : try original.readU8()
            let b2 = try modified.readU8()
            
            if b1 != b2 {
                var rleMode = true
                var differentData: [UInt8] = []
                let startOffset = UInt32(modified.offset - 1)
                
                while b1 != b2 && differentData.count < 0xffff {
                    differentData.append(b2)
                    if b2 != differentData[0] {
                        rleMode = false
                    }
                    
                    if modified.isEOF() || differentData.count == 0xffff {
                        break
                    }
                    
                    _ = original.isEOF() ? 0x00 : try original.readU8()
                    _ = try modified.readU8()
                }
                
                // Check if this record is near the previous one
                let distance = Int(startOffset) - (Int(previousRecord.startOffset) + previousRecord.length)
                if previousRecord.type == IPS.RecordType.simple.rawValue &&
                   distance < 6 &&
                   (previousRecord.length + distance + differentData.count) < 0xffff {
                    if rleMode && differentData.count > 6 {
                        // Separate a potential RLE record
                        original.seek(to: Int(startOffset))
                        modified.seek(to: Int(startOffset))
                        previousRecord = (0xdeadbeef, 0, 0)
                    } else {
                        // Merge both records
                        var mergedData = try modified.readBytes(distance)
                        mergedData.append(contentsOf: differentData)
                        patch.addSimpleRecord(offset: previousRecord.startOffset, data: mergedData)
                        previousRecord.length = mergedData.count
                    }
                } else {
                    if startOffset >= IPS.maxRomSize {
                        throw IPSError.patchFailed("Files are too big for IPS format")
                    }
                    
                    if rleMode && differentData.count > 2 {
                        patch.addRLERecord(offset: startOffset, length: UInt16(differentData.count), byte: differentData[0])
                    } else {
                        patch.addSimpleRecord(offset: startOffset, data: differentData)
                    }
                    previousRecord = (IPS.RecordType.simple.rawValue, startOffset, differentData.count)
                }
            }
        }
        
        if modified.fileSize > original.fileSize {
            if let lastRecord = patch.records.last {
                let lastOffset = Int(lastRecord.offset) + Int(lastRecord.length)
                
                if lastOffset < modified.fileSize {
                    patch.addSimpleRecord(offset: UInt32(modified.fileSize - 1), data: [0x00])
                }
            }
        }
        
        return patch
    }
    
    // MARK: - Helper Methods
    
    /// Adds a simple record to the patch
    private func addSimpleRecord(offset: UInt32, data: [UInt8]) {
        records.append(IPSRecord(offset: offset, type: .simple, length: UInt16(data.count), data: data, byte: 0))
    }
    
    /// Adds an RLE record to the patch
    private func addRLERecord(offset: UInt32, length: UInt16, byte: UInt8) {
        records.append(IPSRecord(offset: offset, type: .rle, length: length, data: [], byte: byte))
    }
}
