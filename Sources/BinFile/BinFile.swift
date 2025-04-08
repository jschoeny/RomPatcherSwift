import Foundation
import CryptoKit

/// A class for reading and writing binary data with sequential access
public class BinFile {
    // MARK: - Properties
    
    /// The underlying data buffer
    public var _u8array: [UInt8]
    
    /// Current read/write position
    public private(set) var offset: Int = 0
    
    /// Stack for saving/restoring positions
    private var offsetStack: [Int] = []
    
    /// Last read value
    private var _lastRead: Any?
    
    /// File name
    public private(set) var fileName: String
    
    /// File type (MIME type)
    public private(set) var fileType: String
    
    /// File size in bytes
    public var fileSize: Int {
        return _u8array.count
    }
    
    /// Endianness for multi-byte operations
    public var littleEndian: Bool = false
    
    // MARK: - Initialization
    
    /// Creates a new BinFile from various sources
    /// - Parameters:
    ///   - source: The source of the binary data (Data, file path, or size for empty file)
    ///   - fileName: Optional file name
    ///   - fileType: Optional file type (MIME type)
    public init(source: Any, fileName: String? = nil, fileType: String? = nil) throws {
        switch source {
        case let data as Data:
            self._u8array = Array(data)
            self.fileName = fileName ?? "file.bin"
            self.fileType = fileType ?? "application/octet-stream"
            
        case let path as String:
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            self._u8array = Array(data)
            self.fileName = fileName ?? URL(fileURLWithPath: path).lastPathComponent
            self.fileType = fileType ?? "application/octet-stream"
            
        case let size as Int:
            self._u8array = [UInt8](repeating: 0, count: size)
            self.fileName = fileName ?? "file.bin"
            self.fileType = fileType ?? "application/octet-stream"
            
        case let array as [UInt8]:
            self._u8array = array
            self.fileName = fileName ?? "file.bin"
            self.fileType = fileType ?? "application/octet-stream"
            
        default:
            throw BinFileError.invalidSource
        }
    }
    
    // MARK: - Position Management
    
    /// Saves the current position to the stack
    public func push() {
        offsetStack.append(offset)
    }
    
    /// Restores the last saved position from the stack
    public func pop() {
        if let lastOffset = offsetStack.popLast() {
            seek(to: lastOffset)
        }
    }
    
    /// Moves the current position to the specified offset
    /// - Parameter offset: The new position
    public func seek(to offset: Int) {
        self.offset = offset
    }
    
    /// Advances the current position by the specified number of bytes
    /// - Parameter bytes: Number of bytes to skip
    public func skip(_ bytes: Int) {
        offset += bytes
    }
    
    /// Checks if the current position is at the end of the file
    public func isEOF() -> Bool {
        return offset >= fileSize
    }
    
    // MARK: - Data Operations
    
    /// Creates a new BinFile containing a slice of the current file
    /// - Parameters:
    ///   - offset: Starting offset
    ///   - length: Length of the slice
    /// - Returns: A new BinFile containing the slice
    public func slice(offset: Int = 0, length: Int? = nil) throws -> BinFile {
        let actualLength = length ?? (fileSize - offset)
        guard offset >= 0 && offset < fileSize else {
            throw BinFileError.outOfBounds
        }
        guard actualLength > 0 && (offset + actualLength) <= fileSize else {
            throw BinFileError.invalidLength
        }
        
        let sliceData = Array(_u8array[offset..<(offset + actualLength)])
        let newFile = try BinFile(source: sliceData)
        newFile.littleEndian = littleEndian
        return newFile
    }
    
    /// Copies data from this file to another BinFile
    /// - Parameters:
    ///   - target: The target BinFile
    ///   - sourceOffset: Starting offset in this file
    ///   - length: Number of bytes to copy
    ///   - targetOffset: Starting offset in the target file
    public func copyTo(target: BinFile, sourceOffset: Int, length: Int, targetOffset: Int? = nil) throws {
        let actualTargetOffset = targetOffset ?? sourceOffset
        let actualLength = length > 0 ? length : (fileSize - sourceOffset)
        
        // Ensure we don't exceed array bounds
        guard sourceOffset >= 0 && sourceOffset + actualLength <= fileSize else {
            throw BinFileError.outOfBounds
        }
        guard actualTargetOffset >= 0 && actualTargetOffset + actualLength <= target.fileSize else {
            throw BinFileError.outOfBounds
        }
        
        // Direct array access with bounds checking
        for i in 0..<actualLength {
            target._u8array[actualTargetOffset + i] = _u8array[sourceOffset + i]
        }
    }
    
    /// Efficiently copies data from this file to a target array
    /// - Parameters:
    ///   - target: The target array
    ///   - sourceOffset: Starting offset in this file
    ///   - length: Number of bytes to copy
    ///   - targetOffset: Starting offset in the target array
    public func copyToArray(_ target: inout [UInt8], sourceOffset: Int, length: Int, targetOffset: Int = 0) throws {
        let actualLength = length > 0 ? length : (fileSize - sourceOffset)
        
        // Ensure we don't exceed array bounds
        guard sourceOffset >= 0 && sourceOffset + actualLength <= fileSize else {
            throw BinFileError.outOfBounds
        }
        guard targetOffset >= 0 && targetOffset + actualLength <= target.count else {
            throw BinFileError.outOfBounds
        }
        
        // Direct array access with bounds checking
        for i in 0..<actualLength {
            target[targetOffset + i] = _u8array[sourceOffset + i]
        }
    }
    
    /// Efficiently copies data from a source array to this file
    /// - Parameters:
    ///   - source: The source array
    ///   - sourceOffset: Starting offset in the source array
    ///   - length: Number of bytes to copy
    ///   - targetOffset: Starting offset in this file
    public func copyFromArray(_ source: [UInt8], sourceOffset: Int = 0, length: Int? = nil, targetOffset: Int = 0) throws {
        let actualLength = length ?? (source.count - sourceOffset)
        
        // Ensure we don't exceed array bounds
        guard sourceOffset >= 0 && sourceOffset + actualLength <= source.count else {
            throw BinFileError.outOfBounds
        }
        guard targetOffset >= 0 && targetOffset + actualLength <= fileSize else {
            throw BinFileError.outOfBounds
        }
        
        // Direct array access with bounds checking
        for i in 0..<actualLength {
            _u8array[targetOffset + i] = source[sourceOffset + i]
        }
    }
    
    /// Efficiently reads a range of bytes into an array
    /// - Parameters:
    ///   - offset: Starting offset
    ///   - length: Number of bytes to read
    /// - Returns: Array of bytes
    public func readBytesToArray(offset: Int, length: Int) throws -> [UInt8] {
        guard offset >= 0 && offset + length <= fileSize else {
            throw BinFileError.outOfBounds
        }
        
        return Array(_u8array[offset..<(offset + length)])
    }
    
    /// Efficiently writes an array of bytes at the current offset
    /// - Parameter bytes: The bytes to write
    public func writeBytes(_ bytes: [UInt8]) throws {
        guard offset + bytes.count <= fileSize else {
            throw BinFileError.endOfFile
        }
        
        if bytes.count >= 4 {
            // Use memcpy for larger blocks
            memcpy(&_u8array[offset], bytes, bytes.count)
        } else {
            // Direct array access with bounds checking for small blocks
            for i in 0..<bytes.count {
                _u8array[offset + i] = bytes[i]
            }
        }
        offset += bytes.count
    }
    
    // MARK: - Reading Methods
    
    /// Reads a single byte
    public func readU8() throws -> UInt8 {
        guard offset < fileSize else {
            throw BinFileError.endOfFile
        }
        let value = _u8array[offset]
        offset += 1
        return value
    }
    
    /// Reads a 16-bit unsigned integer
    public func readU16() throws -> UInt16 {
        guard offset + 1 < fileSize else {
            throw BinFileError.endOfFile
        }
        
        let value: UInt16
        if littleEndian {
            value = UInt16(_u8array[offset]) | (UInt16(_u8array[offset + 1]) << 8)
        } else {
            value = (UInt16(_u8array[offset]) << 8) | UInt16(_u8array[offset + 1])
        }
        _lastRead = value
        offset += 2
        return value
    }
    
    /// Reads a 24-bit unsigned integer
    public func readU24() throws -> UInt32 {
        guard offset + 2 < fileSize else {
            throw BinFileError.endOfFile
        }
        
        let value: UInt32
        if littleEndian {
            value = UInt32(_u8array[offset]) | (UInt32(_u8array[offset + 1]) << 8) | (UInt32(_u8array[offset + 2]) << 16)
        } else {
            value = (UInt32(_u8array[offset]) << 16) | (UInt32(_u8array[offset + 1]) << 8) | UInt32(_u8array[offset + 2])
        }
        _lastRead = value
        offset += 3
        return value
    }
    
    /// Reads a 32-bit unsigned integer
    public func readU32() throws -> UInt32 {
        guard offset + 3 < fileSize else {
            throw BinFileError.endOfFile
        }
        
        let value: UInt32
        if littleEndian {
            value = UInt32(_u8array[offset]) | (UInt32(_u8array[offset + 1]) << 8) | (UInt32(_u8array[offset + 2]) << 16) | (UInt32(_u8array[offset + 3]) << 24)
        } else {
            value = (UInt32(_u8array[offset]) << 24) | (UInt32(_u8array[offset + 1]) << 16) | (UInt32(_u8array[offset + 2]) << 8) | UInt32(_u8array[offset + 3])
        }
        _lastRead = value
        offset += 4
        return value
    }
    
    /// Reads a specified number of bytes
    /// - Parameter length: Number of bytes to read
    public func readBytes(_ length: Int) throws -> [UInt8] {
        guard offset + length <= fileSize else {
            throw BinFileError.endOfFile
        }
        
        // Direct array slicing with bounds checking
        let bytes = Array(_u8array[offset..<(offset + length)])
        offset += length
        return bytes
    }
    
    /// Reads a string of specified length
    /// - Parameter length: Maximum length of the string
    public func readString(_ length: Int) throws -> String {
        guard offset + length <= fileSize else {
            throw BinFileError.endOfFile
        }
        
        var result = ""
        for i in 0..<length {
            let byte = _u8array[offset + i]
            if byte == 0 { break }
            result.append(Character(UnicodeScalar(byte)))
        }
        offset += length
        return result
    }
    
    // MARK: - Writing Methods
    
    /// Writes a single byte
    /// - Parameter value: The byte to write
    public func writeU8(_ value: UInt8) throws {
        guard offset < fileSize else {
            throw BinFileError.endOfFile
        }
        _u8array[offset] = value
        offset += 1
    }
    
    /// Writes a 16-bit unsigned integer
    /// - Parameter value: The value to write
    public func writeU16(_ value: UInt16) throws {
        guard offset + 1 < fileSize else {
            throw BinFileError.endOfFile
        }
        
        if littleEndian {
            _u8array[offset] = UInt8(value & 0xFF)
            _u8array[offset + 1] = UInt8(value >> 8)
        } else {
            _u8array[offset] = UInt8(value >> 8)
            _u8array[offset + 1] = UInt8(value & 0xFF)
        }
        offset += 2
    }
    
    /// Writes a 24-bit unsigned integer
    /// - Parameter value: The value to write
    public func writeU24(_ value: UInt32) throws {
        guard offset + 2 < fileSize else {
            throw BinFileError.endOfFile
        }
        
        if littleEndian {
            _u8array[offset] = UInt8(value & 0xFF)
            _u8array[offset + 1] = UInt8((value >> 8) & 0xFF)
            _u8array[offset + 2] = UInt8((value >> 16) & 0xFF)
        } else {
            _u8array[offset] = UInt8((value >> 16) & 0xFF)
            _u8array[offset + 1] = UInt8((value >> 8) & 0xFF)
            _u8array[offset + 2] = UInt8(value & 0xFF)
        }
        offset += 3
    }
    
    /// Writes a 32-bit unsigned integer
    /// - Parameter value: The value to write
    public func writeU32(_ value: UInt32) throws {
        guard offset + 3 < fileSize else {
            throw BinFileError.endOfFile
        }
        
        if littleEndian {
            _u8array[offset] = UInt8(value & 0xFF)
            _u8array[offset + 1] = UInt8((value >> 8) & 0xFF)
            _u8array[offset + 2] = UInt8((value >> 16) & 0xFF)
            _u8array[offset + 3] = UInt8((value >> 24) & 0xFF)
        } else {
            _u8array[offset] = UInt8((value >> 24) & 0xFF)
            _u8array[offset + 1] = UInt8((value >> 16) & 0xFF)
            _u8array[offset + 2] = UInt8((value >> 8) & 0xFF)
            _u8array[offset + 3] = UInt8(value & 0xFF)
        }
        offset += 4
    }
    
    /// Writes a string
    /// - Parameters:
    ///   - string: The string to write
    ///   - length: The maximum length to write (padded with zeros if needed)
    public func writeString(_ string: String, length: Int? = nil) throws {
        let maxLength = length ?? string.count
        guard offset + maxLength <= fileSize else {
            throw BinFileError.endOfFile
        }
        
        var bytes = string.utf8.map { $0 }
        while bytes.count < maxLength {
            bytes.append(0)
        }
        try writeBytes(bytes)
    }
    
    // MARK: - File Operations
    
    /// Saves the file to disk
    /// - Parameter path: Optional path to save the file
    public func save(to path: String? = nil) throws {
        let savePath = path ?? fileName
        try Data(_u8array).write(to: URL(fileURLWithPath: savePath))
    }
    
    /// Gets the file extension
    public func getExtension() -> String {
        return (fileName as NSString).pathExtension.lowercased()
    }
    
    /// Gets the file name without extension
    public func getName() -> String {
        return (fileName as NSString).deletingPathExtension
    }
    
    /// Sets the file extension
    /// - Parameter newExtension: The new extension
    public func setExtension(_ newExtension: String) {
        fileName = getName() + "." + newExtension
    }
    
    /// Sets the file name
    /// - Parameter newName: The new name
    public func setName(_ newName: String) {
        fileName = newName + "." + getExtension()
    }
    
    /// Sets both the base name and extension at once
    /// - Parameters:
    ///   - newName: The new base name
    ///   - newExtension: The new extension
    public func setFullName(newName: String, newExtension: String) {
        fileName = newName + "." + newExtension
    }
    
    // MARK: - Hash Methods
    
    /// Calculates SHA-1 hash of the file or a portion of it
    /// - Parameters:
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire file)
    /// - Returns: SHA-1 hash as a hex string
    public func hashSHA1(start: Int = 0, length: Int? = nil) -> String {
        return HashCalculator.sha1(data: Data(_u8array), start: start, length: length)
    }
    
    /// Calculates MD5 hash of the file or a portion of it
    /// - Parameters:
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire file)
    /// - Returns: MD5 hash as a hex string
    public func hashMD5(start: Int = 0, length: Int? = nil) -> String {
        return HashCalculator.md5(data: Data(_u8array), start: start, length: length)
    }
    
    /// Calculates CRC32 hash of the file or a portion of it
    /// - Parameters:
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire file)
    /// - Returns: CRC32 hash as a UInt32
    public func hashCRC32(start: Int = 0, length: Int? = nil) -> UInt32 {
        let actualLength = length ?? (fileSize - start)
        return HashCalculator.crc32FromBytes(_u8array, start: start, length: actualLength)
    }
    
    /// Calculates Adler-32 hash of the file or a portion of it
    /// - Parameters:
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire file)
    /// - Returns: Adler-32 hash as a UInt32
    public func hashAdler32(start: Int = 0, length: Int? = nil) -> UInt32 {
        return HashCalculator.adler32(data: Data(_u8array), start: start, length: length)
    }
    
    /// Calculates CRC16/CCITT-FALSE hash of the file or a portion of it
    /// - Parameters:
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire file)
    /// - Returns: CRC16 hash as a UInt16
    public func hashCRC16(start: Int = 0, length: Int? = nil) -> UInt16 {
        return HashCalculator.crc16(data: Data(_u8array), start: start, length: length)
    }
    
    /// Prepends bytes to the file
    public func prependBytes(_ bytes: [UInt8]) throws {
        let newFile = try BinFile(source: fileSize + bytes.count)
        try newFile.writeBytes(bytes)
        try copyTo(target: newFile, sourceOffset: 0, length: fileSize, targetOffset: bytes.count)
        
        self._u8array = newFile._u8array
    }
    
    /// Removes leading bytes from the file
    public func removeLeadingBytes(_ count: Int) throws -> [UInt8] {
        seek(to: 0)
        let oldData = try readBytes(count)
        let newFile = try slice(offset: count)
        self._u8array = newFile._u8array
        return oldData
    }
    
    /// Swaps bytes in the file
    public func swapBytes(swapSize: Int = 4, createNewFile: Bool = false) throws -> BinFile {
        guard fileSize % swapSize == 0 else {
            throw BinFileError.invalidLength
        }
        
        let swappedFile = try BinFile(source: fileSize)
        seek(to: 0)
        while !isEOF() {
            let bytes = try readBytes(swapSize)
            try swappedFile.writeBytes(bytes.reversed())
        }
        
        if createNewFile {
            swappedFile.fileName = fileName
            swappedFile.fileType = fileType
            return swappedFile
        } else {
            self._u8array = swappedFile._u8array
            return self
        }
    }
}

// MARK: - Error Types

/// Errors that can occur during BinFile operations
public enum BinFileError: Error {
    case invalidSource
    case outOfBounds
    case invalidLength
    case endOfFile
    case writeError
}
