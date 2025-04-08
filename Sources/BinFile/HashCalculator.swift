import Foundation
import CryptoKit

/// A class for calculating various hash functions
public class HashCalculator {
    // MARK: - Constants
    
    /// Hex characters for string conversion
    private static let hexChars: [Character] = Array("0123456789abcdef")
    
    /// CRC32 lookup table
    private static let crc32Table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = ((c & 1) != 0) ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
            }
            table[n] = c
        }
        return table
    }()
    
    /// Adler-32 modulus
    private static let adler32Mod: UInt32 = 0xfff1
    
    // MARK: - Public Methods
    
    /// Calculates SHA-1 hash of the data
    /// - Parameters:
    ///   - data: The data to hash
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire data)
    /// - Returns: SHA-1 hash as a hex string
    public static func sha1(data: Data, start: Int = 0, length: Int? = nil) -> String {
        let end = length.map { start + $0 } ?? data.count
        let range = start..<end
        let subdata = data.subdata(in: range)
        let hash = Insecure.SHA1.hash(data: subdata)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Calculates MD5 hash of the data
    /// - Parameters:
    ///   - data: The data to hash
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire data)
    /// - Returns: MD5 hash as a hex string
    public static func md5(data: Data, start: Int = 0, length: Int? = nil) -> String {
        let end = length.map { start + $0 } ?? data.count
        let range = start..<end
        let subdata = data.subdata(in: range)
        let hash = Insecure.MD5.hash(data: subdata)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Calculates CRC32 hash of the data
    /// - Parameters:
    ///   - data: The data to hash
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire data)
    /// - Returns: CRC32 hash as a UInt32
    public static func crc32(data: Data, start: Int = 0, length: Int? = nil) -> UInt32 {
        let end = length.map { start + $0 } ?? data.count
        var crc: UInt32 = 0xffffffff
        
        // Convert Data to [UInt8] for direct access
        let bytes = Array(data[start..<end])
        var i = 0
        let count = bytes.count
        
        // Process 8 bytes at a time
        while i + 7 < count {
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 1])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 2])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 3])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 4])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 5])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 6])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 7])) & 0xff)]
            i += 8
        }
        
        // Process remaining bytes
        while i < count {
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i])) & 0xff)]
            i += 1
        }
        
        return crc ^ 0xffffffff
    }
    
    /// Calculates CRC32 hash directly from a byte array
    /// - Parameters:
    ///   - bytes: The byte array to hash
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire array)
    /// - Returns: CRC32 hash as a UInt32
    public static func crc32FromBytes(_ bytes: [UInt8], start: Int = 0, length: Int? = nil) -> UInt32 {
        let end = length.map { start + $0 } ?? bytes.count
        var crc: UInt32 = 0xffffffff
        var i = start
        
        // Process 8 bytes at a time
        while i + 7 < end {
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 1])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 2])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 3])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 4])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 5])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 6])) & 0xff)]
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i + 7])) & 0xff)]
            i += 8
        }
        
        // Process remaining bytes
        while i < end {
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(bytes[i])) & 0xff)]
            i += 1
        }
        
        return crc ^ 0xffffffff
    }
    
    /// Calculates Adler-32 hash of the data
    /// - Parameters:
    ///   - data: The data to hash
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire data)
    /// - Returns: Adler-32 hash as a UInt32
    public static func adler32(data: Data, start: Int = 0, length: Int? = nil) -> UInt32 {
        let end = length.map { start + $0 } ?? data.count
        var a: UInt32 = 1
        var b: UInt32 = 0
        
        for i in start..<end {
            a = (a + UInt32(data[i])) % adler32Mod
            b = (b + a) % adler32Mod
        }
        
        return (b << 16) | a
    }
    
    /// Calculates CRC16/CCITT-FALSE hash of the data
    /// - Parameters:
    ///   - data: The data to hash
    ///   - start: Starting offset (default: 0)
    ///   - length: Length of data to hash (default: entire data)
    /// - Returns: CRC16 hash as a UInt16
    public static func crc16(data: Data, start: Int = 0, length: Int? = nil) -> UInt16 {
        let end = length.map { start + $0 } ?? data.count
        var crc: UInt16 = 0xffff
        
        for i in start..<end {
            crc ^= UInt16(data[i]) << 8
            for _ in 0..<8 {
                crc = ((crc & 0x8000) != 0) ? ((crc << 1) ^ 0x1021) : (crc << 1)
            }
        }
        
        return crc & 0xffff
    }
}
