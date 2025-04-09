# RomPatcherSwift

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20iOS-lightgrey.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

A Swift port of [Rom Patcher JS](https://github.com/marcrobledo/RomPatcher.js) by Marc Robledo. This project provides a Swift package for applying and creating ROM patches, with a command-line interface provided as an example implementation.

## Project Overview

RomPatcherSwift is a Swift package that enables ROM patching functionality in Swift applications. It's a direct port of the popular Rom Patcher JS library with Swift-specific features and optimizations, maintaining compatibility with the same patch formats and features.

### Key Features
- Support for multiple patch formats (BPS, UPS, IPS)
- Efficient binary file handling with `BinFile` class
- Built-in performance monitoring
- Consistent API across patch formats
- Example CLI implementation
- Cross-platform support (macOS, iOS)

## Installation

### Prerequisites
- Swift 5.9 or later
- macOS 13.0+ or iOS 16.0+

### Swift Package Manager
Add RomPatcherSwift to your project's dependencies in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/jschoeny/RomPatcherSwift.git", from: "1.0.0")
]
```

### Building from Source
1. Clone the repository:
```bash
git clone https://github.com/jschoeny/RomPatcherSwift.git
cd RomPatcherSwift
```

2. Build the package:
```bash
# Debug build
swift build

# Release build
swift build -c release
```

### Testing
The CLI tool is provided for easy testing of the package.

```bash
.build/release/rom-patcher --help

Usage:
    rom-patcher patch <rom_file> <patch_file> [options]
    rom-patcher create <original_rom> <modified_rom> [options]

Options:
    --validate-checksum    Validate checksum
    --add-header          Add temporary header
    --remove-header       Remove ROM header temporarily
    --fix-checksum        Fix known ROM header checksum
    --format <format>     Patch format (ips, bps, ups)
```

## Usage

### Package Integration
The package provides a consistent API through three main components:

1. **BinFile**: Core binary file handling with methods for:
   - Reading/writing different data types
   - File operations (save, slice, copy)
   - Hash calculations (CRC32, MD5, SHA-1)

2. **Patch Protocol**: Standard interface implemented by all patch formats:
   - `apply(to:validate:)` - Apply patch to ROM
   - `export()` - Create patch file
   - `validateSource(_:headerSize:)` - Validate source ROM
   - `getValidationInfo()` - Get validation details

3. **Format Implementations**: Each patch format follows the same pattern:
   - Consistent error handling
   - Format-specific optimizations
   - Validation and checksum support (when applicable)

Basic usage example:
```swift
import BinFile
import RomPatcherCore

// Load ROM and patch files
let romFile = try BinFile(source: "original.rom")
let patchFile = try BinFile(source: "patch.bps")

// Create patcher instance
let patcher = RomPatcher()

// Parse and apply patch
let patch = try patcher.parsePatchFile(patchFile)
let patchedRom = try patcher.applyPatch(romFile: romFile, patch: patch)

// Save patched ROM
try patchedRom.setFullName(newName: "patched", newExtension: "rom")
try patchedRom.save()
```

## Development

### Building the Project
```bash
# Build the package
swift build

# Build with optimizations
swift build -c release
```

### Performance Monitoring
The package includes a `PerformanceMonitor` class for identifying bottlenecks:
```swift
let monitor = PerformanceMonitor(functionName: "myFunction")
// ... code to monitor ...
monitor.measure("operation name")
monitor.printMeasurementResults()
```
Only available in the debug build. Automatically disabled in release builds.

### Contributing Guidelines
1. Fork the repository
2. Create a feature branch
3. Implement your changes
4. Submit a pull request

Please ensure:
- Code follows Swift style guidelines
- New features include performance monitoring when applicable
- Documentation is updated

## License and Credits

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

### Original Project
- [Rom Patcher JS](https://github.com/marcrobledo/RomPatcher.js) by Marc Robledo
- Licensed under MIT License
- Copyright (c) 2017-2024 Marc Robledo

### This Port
- Copyright (c) 2025 Jared Schoeny
- Maintains MIT License
- Includes Swift-specific optimizations and language features

### Contributors
- Jared Schoeny (Port maintainer)
- Marc Robledo (Original author)
