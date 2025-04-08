#!/usr/bin/swift

import Foundation
import BinFile
import RomPatcherCore

// Import our custom modules
@_exported import BinFile
@_exported import RomPatcherCore

enum RomPatcherError: Error {
    case invalidArguments
    case invalidPatchFile
    case fileNotFound(String)
    case patchFailed(String)
}

func printUsage() {
    print("""
    Usage:
        rom-patcher patch <rom_file> <patch_file> [options]
        rom-patcher create <original_rom> <modified_rom> [options]
    
    Options:
        --validate-checksum    Validate checksum
        --add-header          Add temporary header
        --remove-header       Remove ROM header temporarily
        --fix-checksum        Fix known ROM header checksum
        --format <format>     Patch format (ips, bps, ups)
    """)
}

func handlePatchCommand(romPath: String, patchPath: String, options: [String: Bool]) throws {
    do {
        // Load ROM and patch files
        let romFile = try BinFile(source: romPath)
        let patchFile = try BinFile(source: patchPath)
        
        // Create RomPatcher instance
        let patcher = RomPatcher()
        
        // Parse and apply patch
        let patch = try patcher.parsePatchFile(patchFile)
        let patchedRom = try patcher.applyPatch(romFile: romFile, patch: patch, options: options)
        
        // Save patched ROM
        let romExtension = (romPath as NSString).pathExtension
        let patchName = (patchPath as NSString).lastPathComponent
        let baseName = (patchName as NSString).deletingPathExtension
        patchedRom.setFullName(newName: baseName, newExtension: romExtension)
        try patchedRom.save()
        
        print("Successfully saved to \(patchedRom.fileName)")
    } catch BinFileError.invalidSource {
        throw RomPatcherError.fileNotFound("Could not read file")
    } catch {
        throw RomPatcherError.patchFailed(error.localizedDescription)
    }
}

func handleCreateCommand(originalPath: String, modifiedPath: String, format: String?) throws {
    do {
        // Load original and modified ROMs
        let originalFile = try BinFile(source: originalPath)
        let modifiedFile = try BinFile(source: modifiedPath)
        
        // Create RomPatcher instance
        let patcher = RomPatcher()
        
        // Create patch
        let patch = try patcher.createPatch(originalFile: originalFile, modifiedFile: modifiedFile, format: format ?? "bps")
        let patchFile = try patch.export()
        
        // Save patch file
        patchFile.setName(modifiedFile.getName())
        try patchFile.save()
        
        print("Successfully created patch file: \(patchFile.fileName)")
    } catch BinFileError.invalidSource {
        throw RomPatcherError.fileNotFound("Could not read file")
    } catch {
        throw RomPatcherError.patchFailed(error.localizedDescription)
    }
}

func main() {
    let arguments = CommandLine.arguments
    
    guard arguments.count >= 2 else {
        printUsage()
        exit(1)
    }
    
    let command = arguments[1]
    
    do {
        switch command {
        case "patch":
            guard arguments.count >= 4 else {
                throw RomPatcherError.invalidArguments
            }
            
            let romPath = arguments[2]
            let patchPath = arguments[3]
            var options: [String: Bool] = [:]
            
            // Parse options
            for i in 4..<arguments.count {
                let option = arguments[i]
                options[option] = true
            }
            
            try handlePatchCommand(romPath: romPath, patchPath: patchPath, options: options)
            
        case "create":
            guard arguments.count >= 4 else {
                throw RomPatcherError.invalidArguments
            }
            
            let originalPath = arguments[2]
            let modifiedPath = arguments[3]
            var format: String?
            
            // Parse format option if present
            if let formatIndex = arguments.firstIndex(of: "--format"),
               formatIndex + 1 < arguments.count {
                format = arguments[formatIndex + 1]
            }
            
            try handleCreateCommand(originalPath: originalPath, modifiedPath: modifiedPath, format: format)
            
        default:
            printUsage()
            exit(1)
        }
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

main()
