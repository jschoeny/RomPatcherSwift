import Foundation
import BinFile

/// Represents a ROM header format with its properties
struct RomHeaderInfo {
    let extensions: [String]
    let size: Int
    let romSizeMultiple: Int
    let name: String
}

/// Represents a ROM system type
public enum RomSystem {
    case gameBoy
    case segaGenesis
    case nintendo64
    case famicomDiskSystem
}

/// Main ROM patcher class that handles patching operations
public class RomPatcher {
    // MARK: - Constants
    
    /// Size threshold for ROMs considered too big
    private static let tooBigRomSize = 64 * 1024 * 1024 // 64MB
    
    /// Nintendo logo data for Game Boy ROMs
    private static let gameBoyNintendoLogo: [UInt8] = [
        0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
        0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
        0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
        0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99
    ]
    
    /// Information about different ROM header formats
    static let headersInfo: [RomHeaderInfo] = [
        RomHeaderInfo(extensions: ["nes"], size: 16, romSizeMultiple: 1024, name: "iNES"), // https://www.nesdev.org/wiki/INES
        RomHeaderInfo(extensions: ["fds"], size: 16, romSizeMultiple: 65500, name: "fwNES"), // https://www.nesdev.org/wiki/FDS_file_format
        RomHeaderInfo(extensions: ["lnx"], size: 64, romSizeMultiple: 1024, name: "LNX"),
        RomHeaderInfo(extensions: ["sfc", "smc", "swc", "fig"], size: 512, romSizeMultiple: 262144, name: "SNES copier")
    ]
    
    // MARK: - Properties
    
    /// The original patch file
    private var originalPatchFile: BinFile?
    
    // MARK: - Initialization
    
    /// Creates a new RomPatcher instance
    public init() {}
    
    // MARK: - Public Methods
    
    /// Detects the ROM system type from a binary file
    /// - Parameter binFile: The binary file to analyze
    /// - Returns: The detected ROM system type, or nil if unknown
    public func getRomSystem(from binFile: BinFile) -> RomSystem? {
        // Check if file is large enough for basic validation
        guard binFile.fileSize > 0x200 else { return nil }
        
        // Check for Game Boy ROM
        if binFile.fileSize >= 0x150 {
            do {
                // Check Nintendo logo at offset 0x104
                binFile.seek(to: 0x104)
                let logoData = try binFile.readBytes(RomPatcher.gameBoyNintendoLogo.count)
                if logoData == RomPatcher.gameBoyNintendoLogo {
                    return .gameBoy
                }
            } catch {
                // Continue checking other formats
            }
        }
        
        // Check for Sega Genesis ROM
        if binFile.fileSize > 0x100 {
            do {
                binFile.seek(to: 0x100)
                let segaString = try binFile.readString(12)
                if segaString.contains("SEGA") || segaString.contains("GENESIS") || segaString.contains("MEGA DR") {
                    return .segaGenesis
                }
            } catch {
                // Continue checking other formats
            }
        }
        
        // Check for Nintendo 64 ROM
        if binFile.fileSize >= 0x40 {
            do {
                // Check for N64 ROM header
                let n64Magic = try binFile.slice(offset: 0, length: 4)
                let magicData = try n64Magic.readBytes(4)
                if magicData == [0x80, 0x37, 0x12, 0x40] ||
                   magicData == [0x37, 0x80, 0x40, 0x12] ||
                   magicData == [0x40, 0x12, 0x37, 0x80] {
                    return .nintendo64
                }
            } catch {
                // Continue checking other formats
            }
        }
        
        // Check for Famicom Disk System ROM
        if binFile.fileSize == 65500 {
            return .famicomDiskSystem
        }

        // TODO: Add more systems
        
        return nil
    }
    
    /// Gets additional checksum information for a ROM
    /// - Parameter binFile: The binary file to analyze
    /// - Returns: Additional checksum information as a string, or nil if not available
    public func getRomAdditionalChecksum(from binFile: BinFile) -> String? {
        guard let romSystem = getRomSystem(from: binFile) else { return nil }
        
        switch romSystem {
        case .nintendo64:
            do {
                // Get cartridge ID (3 bytes at offset 0x3C)
                binFile.seek(to: 0x3C)
                let cartId = try binFile.readString(3)
                
                // Get CRC (8 bytes at offset 0x10)
                binFile.seek(to: 0x10)
                let crcBytes = try binFile.readBytes(8)
                let crcString = crcBytes.map { String(format: "%02x", $0) }.joined()
                
                return "\(cartId) (\(crcString))"
            } catch {
                return nil
            }
            
        case .gameBoy:
            do {
                // Calculate header checksum (bytes 0x134-0x14C)
                binFile.seek(to: 0x134)
                var checksum: UInt8 = 0
                for _ in 0...0x18 {
                    let byte = try binFile.readU8()
                    checksum = checksum &- byte &- 1
                }
                return String(format: "Header Checksum: 0x%02x", checksum)
            } catch {
                return nil
            }
            
        case .segaGenesis:
            do {
                guard binFile.fileSize >= 0x200 else { return nil }
                
                binFile.seek(to: 0x200)
                var checksum: UInt16 = 0
                while !binFile.isEOF() {
                    let value = try binFile.readU16()
                    checksum = checksum &+ value
                }
                return String(format: "ROM Checksum: 0x%04x", checksum)
            } catch {
                return nil
            }
            
        case .famicomDiskSystem:
            return nil
        }
    }
    
    /// Checks if a ROM is too big to patch
    /// - Parameter binFile: The binary file to check
    /// - Returns: True if the ROM is too big, false otherwise
    public func isRomTooBig(_ binFile: BinFile) -> Bool {
        return binFile.fileSize > RomPatcher.tooBigRomSize
    }
    
    // MARK: - Patch Operations
    
    /// Parses a patch file
    /// - Parameter patchFile: The patch file to parse
    /// - Returns: A parsed patch object
    public func parsePatchFile(_ patchFile: BinFile) throws -> Patch {
        
        // Read initial header
        patchFile.seek(to: 0)
        let header = try patchFile.readString(6)
        
        // Check for IPS patch
        if header.starts(with: IPS.magic) {
            patchFile.seek(to: 0)
            return try IPS.fromFile(patchFile)
        }
        
        // Check for BPS patch
        if header.starts(with: BPS.magic) {
            patchFile.seek(to: 0)
            return try BPS.fromFile(patchFile)
        }
        
        // Check for UPS patch
        if header.starts(with: UPS.magic) {
            patchFile.seek(to: 0)
            return try UPS.fromFile(patchFile)
        }
        
        print("No valid patch format found")
        throw RomPatcherError.unknownPatchFormat
    }
    
    /// Applies a patch to a ROM file
    /// - Parameters:
    ///   - romFile: The ROM file to patch
    ///   - patch: The patch to apply
    ///   - options: Patch application options
    /// - Returns: The patched ROM file
    public func applyPatch(romFile: BinFile, patch: Patch, options: [String: Bool]) throws -> BinFile {
        // Handle header options
        var extractedHeader: BinFile?
        var fakeHeaderSize = 0
        var workingRomFile = romFile
        
        if options["--remove-header"] == true {
            if isRomHeadered(workingRomFile) != nil {
                let splitData = try removeHeader(workingRomFile)
                extractedHeader = splitData.header
                workingRomFile = splitData.rom
            }
        } else if options["--add-header"] == true {
            if let headerInfo = canRomGetHeader(workingRomFile) {
                fakeHeaderSize = headerInfo.size
                workingRomFile = try addFakeHeader(workingRomFile)
            }
        }
        
        // Validate ROM if requested
        if options["--validate-checksum"] == true {
            if !patch.validateSource(workingRomFile, headerSize: 0) {
                throw RomPatcherError.patchFailed("Invalid input ROM checksum")
            }
        }
        
        // Apply the patch
        var patchedRom = try patch.apply(to: workingRomFile, validate: options["--validate-checksum"] == true)
        
        // Handle header restoration
        if let header = extractedHeader {
            if options["--fix-checksum"] == true {
                try fixRomHeaderChecksum(patchedRom)
            }
            
            let patchedRomWithHeader = try BinFile(source: header.fileSize + patchedRom.fileSize)
            try header.copyTo(target: patchedRomWithHeader, sourceOffset: 0, length: header.fileSize)
            try patchedRom.copyTo(target: patchedRomWithHeader, sourceOffset: 0, length: patchedRom.fileSize, targetOffset: header.fileSize)
            
            patchedRom = patchedRomWithHeader
        } else if fakeHeaderSize > 0 {
            let patchedRomWithoutFakeHeader = try patchedRom.slice(offset: fakeHeaderSize)
            
            if options["--fix-checksum"] == true {
                try fixRomHeaderChecksum(patchedRomWithoutFakeHeader)
            }
            
            patchedRom = patchedRomWithoutFakeHeader
        } else if options["--fix-checksum"] == true {
            try fixRomHeaderChecksum(patchedRom)
        }
        
        // Handle output suffix
        if options["--output-suffix"] == true {
            patchedRom.setName(patchedRom.getName() + " (patched)")
        }
        
        return patchedRom
    }
    
    /// Creates a patch from two ROM files
    /// - Parameters:
    ///   - originalFile: The original ROM file
    ///   - modifiedFile: The modified ROM file
    ///   - format: The patch format to use
    /// - Returns: The created patch
    public func createPatch(originalFile: BinFile, modifiedFile: BinFile, format: String) throws -> Patch {
        switch format.lowercased() {
        case "ips":
            return try IPS.buildFromRoms(original: originalFile, modified: modifiedFile)
        case "bps":
            return try BPS.buildFromRoms(original: originalFile, modified: modifiedFile, deltaMode: originalFile.fileSize <= 4 * 1024 * 1024)
        case "ups":
            return try UPS.buildFromRoms(original: originalFile, modified: modifiedFile)
        default:
            throw RomPatcherError.patchFailed("Unsupported patch format: \(format)")
        }
    }
    
    /// Checks if a ROM has a known header
    private func isRomHeadered(_ romFile: BinFile) -> RomHeaderInfo? {
        if romFile.fileSize <= 0x600200 && romFile.fileSize % 1024 != 0 {
            let compatibleHeader = RomPatcher.headersInfo.first { headerInfo in
                headerInfo.extensions.contains(romFile.fileType) &&
                (romFile.fileSize - headerInfo.size) % headerInfo.romSizeMultiple == 0
            }
            return compatibleHeader
        }
        return nil
    }
    
    /// Removes a ROM header
    private func removeHeader(_ romFile: BinFile) throws -> (header: BinFile, rom: BinFile) {
        guard let headerInfo = isRomHeadered(romFile) else {
            throw RomPatcherError.patchFailed("No compatible header found")
        }
        
        let header = try romFile.slice(offset: 0, length: headerInfo.size)
        let rom = try romFile.slice(offset: headerInfo.size)
        return (header, rom)
    }
    
    /// Checks if a ROM can get a header
    private func canRomGetHeader(_ romFile: BinFile) -> RomHeaderInfo? {
        if romFile.fileSize <= 0x600000 {
            let compatibleHeader = RomPatcher.headersInfo.first { headerInfo in
                headerInfo.extensions.contains(romFile.fileType) &&
                romFile.fileSize % headerInfo.romSizeMultiple == 0
            }
            return compatibleHeader
        }
        return nil
    }
    
    /// Adds a fake header to a ROM
    private func addFakeHeader(_ romFile: BinFile) throws -> BinFile {
        guard let headerInfo = canRomGetHeader(romFile) else {
            throw RomPatcherError.patchFailed("Cannot add header to this ROM")
        }
        
        let romWithFakeHeader = try BinFile(source: headerInfo.size + romFile.fileSize)
        try romFile.copyTo(target: romWithFakeHeader, sourceOffset: 0, length: romFile.fileSize, targetOffset: headerInfo.size)
        
        // Add a correct FDS header if needed
        if getRomSystem(from: romWithFakeHeader) == .famicomDiskSystem {
            romWithFakeHeader.seek(to: 0)
            try romWithFakeHeader.writeBytes([0x46, 0x44, 0x53, 0x1a, UInt8(romFile.fileSize / 65500)])
        }
        
        return romWithFakeHeader
    }
    
    /// Fixes ROM header checksum
    private func fixRomHeaderChecksum(_ romFile: BinFile) throws {
        guard let romSystem = getRomSystem(from: romFile) else { return }
        
        switch romSystem {
        case .gameBoy:
            // Get current checksum
            romFile.seek(to: 0x014d)
            let currentChecksum = try romFile.readU8()
            
            // Calculate checksum
            var newChecksum: UInt8 = 0x00
            romFile.seek(to: 0x0134)
            for _ in 0...0x18 {
                let byte = try romFile.readU8()
                newChecksum = newChecksum &- byte &- 1
            }
            
            // Fix checksum if needed
            if currentChecksum != newChecksum {
                romFile.seek(to: 0x014d)
                try romFile.writeU8(newChecksum)
            }
            
        case .segaGenesis:
            // Get current checksum
            romFile.seek(to: 0x018e)
            let currentChecksum = try romFile.readU16()
            
            // Calculate checksum
            var newChecksum: UInt16 = 0x0000
            romFile.seek(to: 0x0200)
            while !romFile.isEOF() {
                let value = try romFile.readU16()
                newChecksum = newChecksum &+ value
            }
            
            // Fix checksum if needed
            if currentChecksum != newChecksum {
                romFile.seek(to: 0x018e)
                try romFile.writeU16(newChecksum)
            }
            
        default:
            break
        }
    }
}

// MARK: - Error Types

/// Errors that can occur during ROM patching
public enum RomPatcherError: Error {
    case unknownPatchFormat
    case patchFailed(String)
}

// MARK: - Patch Protocol

/// Protocol for patch formats
public protocol Patch {
    /// Exports the patch to a BinFile
    func export() throws -> BinFile
    
    /// Validates the source ROM
    func validateSource(_ romFile: BinFile, headerSize: Int) -> Bool
    
    /// Gets validation information
    func getValidationInfo() -> String
    
    /// Applies the patch to a ROM file
    func apply(to romFile: BinFile, validate: Bool) throws -> BinFile
}
