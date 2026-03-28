import Foundation
import SwiftProtobuf

// MARK: - Configuration

let defaultProCorePath =
    "/Applications/ProPresenter.app/Contents/Frameworks/ProCore.framework/ProCore"
let rootProto = "presentation.proto"

@main
enum ProtoExtractor {
    static func main() throws {
        let proCorePath = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : defaultProCorePath

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ProtoExtractor.swift → Sources/
            .deletingLastPathComponent() // Sources/ → ProtoExtractor/
            .deletingLastPathComponent() // ProtoExtractor/ → Tools/
            .deletingLastPathComponent() // Tools/ → repo root

        let outputDir = repoRoot.appendingPathComponent("Proto/v21")

        print("Reading \(proCorePath)...")
        let data = try Data(contentsOf: URL(fileURLWithPath: proCorePath))
        print("Binary size: \(data.count / 1024 / 1024) MB")

        print("Extracting proto descriptors...")
        let allDescs = extractDescriptors(from: data)
        print("Found \(allDescs.count) unique descriptors")

        print("Walking dependency tree from \(rootProto)...")
        let needed = walkDependencies(from: rootProto, in: allDescs)
        print("Need \(needed.count) files")

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        print("Reconstructing .proto text files...")
        for name in needed.sorted() {
            guard let desc = allDescs[name] else {
                print("  WARNING: \(name) not found in extracted descriptors, skipping")
                continue
            }
            let text = reconstructProtoText(desc)
            let filePath = outputDir.appendingPathComponent(name)
            try text.write(to: filePath, atomically: true, encoding: .utf8)
            let msgs = desc.messageType.map(\.name)
            let enums = desc.enumType.map(\.name)
            let items = (msgs + enums).prefix(4).joined(separator: ", ")
            print("  \(name) — \(items)")
        }

        print("\nWrote \(needed.count) .proto files to \(outputDir.path)")
    }
}

// MARK: - Binary Scanning

func extractDescriptors(
    from data: Data
) -> [String: Google_Protobuf_FileDescriptorProto] {
    let bytes = [UInt8](data)
    var best: [String: (score: Int, desc: Google_Protobuf_FileDescriptorProto)] = [:]

    // Find all potential FileDescriptorProto starts:
    // Field 1 (name) = tag 0x0a, followed by length, then string ending in ".proto",
    // then field 2 (package) = tag 0x12
    let protoSuffix = Array(".proto".utf8)

    for i in 0 ..< (bytes.count - 20) {
        guard bytes[i] == 0x0A else { continue } // field 1, wire type 2
        let nameLen = Int(bytes[i + 1])
        guard nameLen > 6, nameLen < 128 else { continue } // reasonable name length
        guard i + 2 + nameLen < bytes.count else { continue }

        // Check .proto suffix
        let suffixStart = i + 2 + nameLen - protoSuffix.count
        guard bytes[suffixStart ..< suffixStart + protoSuffix.count].elementsEqual(protoSuffix) else {
            continue
        }

        // Check next byte is field 2 tag (0x12)
        guard bytes[i + 2 + nameLen] == 0x12 else { continue }

        // Check name is ASCII alphanumeric + _/
        let nameBytes = bytes[i + 2 ..< i + 2 + nameLen]
        guard nameBytes.allSatisfy({ isValidProtoNameByte($0) }) else { continue }

        let name = String(bytes: nameBytes, encoding: .ascii)!

        // Find the end by walking protobuf fields
        let end = findDescriptorEnd(bytes: bytes, start: i)
        let chunk = Data(bytes[i ..< end])

        guard let desc = try? Google_Protobuf_FileDescriptorProto(serializedBytes: chunk),
              desc.name == name
        else { continue }

        let score = scoreDescriptor(desc)
        if score > (best[name]?.score ?? -1) {
            best[name] = (score, desc)
        }
    }

    return best.mapValues(\.desc)
}

func isValidProtoNameByte(_ b: UInt8) -> Bool {
    (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
        || (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
        || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
        || b == UInt8(ascii: "_")
        || b == UInt8(ascii: "/")
        || b == UInt8(ascii: ".")
}

func scoreDescriptor(_ desc: Google_Protobuf_FileDescriptorProto) -> Int {
    var score = desc.messageType.count + desc.enumType.count + desc.extension.count
    for m in desc.messageType {
        score += scoreMessage(m)
    }
    return score
}

func scoreMessage(_ msg: Google_Protobuf_DescriptorProto) -> Int {
    var score = msg.field.count + msg.nestedType.count + msg.enumType.count + msg.oneofDecl.count
    for nested in msg.nestedType {
        score += scoreMessage(nested)
    }
    return score
}

/// Walk protobuf field tags to find where a FileDescriptorProto ends.
func findDescriptorEnd(bytes: [UInt8], start: Int) -> Int {
    // Valid field numbers for FileDescriptorProto: 1-9, 12
    let validFields: Set = [1, 2, 3, 4, 5, 6, 7, 8, 9, 12]
    var pos = start
    let end = min(start + 200_000, bytes.count)

    while pos < end {
        guard let (tag, newPos) = decodeVarint(bytes: bytes, offset: pos) else { return pos }
        let fieldNumber = tag >> 3
        let wireType = tag & 0x07

        guard fieldNumber > 0, validFields.contains(fieldNumber) else { return pos }
        pos = newPos

        switch wireType {
        case 0: // varint
            while pos < end, bytes[pos] & 0x80 != 0 {
                pos += 1
            }
            pos += 1
        case 1: // 64-bit
            pos += 8
        case 2: // length-delimited
            guard let (length, newPos2) = decodeVarint(bytes: bytes, offset: pos) else { return pos }
            pos = newPos2 + length
        case 5: // 32-bit
            pos += 4
        default:
            return pos
        }
    }
    return pos
}

func decodeVarint(bytes: [UInt8], offset: Int) -> (Int, Int)? {
    var result = 0
    var shift = 0
    var pos = offset
    while pos < bytes.count {
        let b = Int(bytes[pos])
        result |= (b & 0x7F) << shift
        pos += 1
        if b & 0x80 == 0 { return (result, pos) }
        shift += 7
        if shift >= 64 { return nil }
    }
    return nil
}

// MARK: - Dependency Walking

func walkDependencies(
    from root: String,
    in allDescs: [String: Google_Protobuf_FileDescriptorProto]
) -> Set<String> {
    var needed = Set<String>()

    func walk(_ name: String) {
        guard !needed.contains(name), allDescs[name] != nil else { return }
        // Skip google/ well-known types (protoc provides these)
        guard !name.hasPrefix("google/") else { return }
        needed.insert(name)
        for dep in allDescs[name]!.dependency {
            walk(dep)
        }
    }

    walk(root)
    return needed
}

// MARK: - Proto Text Reconstruction

func reconstructProtoText(_ desc: Google_Protobuf_FileDescriptorProto) -> String {
    var lines: [String] = []

    lines.append("syntax = \"proto3\";")
    lines.append("")

    if !desc.package.isEmpty {
        lines.append("package \(desc.package);")
        lines.append("")
    }

    // Options
    if desc.options.ccEnableArenas {
        lines.append("option cc_enable_arenas = true;")
    }
    if !desc.options.csharpNamespace.isEmpty {
        lines.append("option csharp_namespace = \"\(desc.options.csharpNamespace)\";")
    }
    if !desc.options.swiftPrefix.isEmpty {
        lines.append("option swift_prefix = \"\(desc.options.swiftPrefix)\";")
    }
    if desc.options.ccEnableArenas || !desc.options.csharpNamespace.isEmpty || !desc.options.swiftPrefix.isEmpty {
        lines.append("")
    }

    // Imports
    for dep in desc.dependency {
        lines.append("import \"\(dep)\";")
    }
    if !desc.dependency.isEmpty {
        lines.append("")
    }

    // Enums (top-level)
    for enumType in desc.enumType {
        emitEnum(enumType, indent: 0, into: &lines)
        lines.append("")
    }

    // Extensions (top-level, e.g. customOptions.proto)
    for ext in desc.extension {
        emitExtension(ext, indent: 0, into: &lines)
    }
    if !desc.extension.isEmpty {
        lines.append("")
    }

    // Messages
    for msg in desc.messageType {
        emitMessage(msg, indent: 0, package: desc.package, into: &lines)
        lines.append("")
    }

    // Remove trailing blank lines
    while lines.last?.isEmpty == true {
        lines.removeLast()
    }
    lines.append("") // single trailing newline

    return lines.joined(separator: "\n")
}

func emitMessage(
    _ msg: Google_Protobuf_DescriptorProto,
    indent: Int,
    package: String,
    into lines: inout [String]
) {
    let pad = String(repeating: "  ", count: indent)
    lines.append("\(pad)message \(msg.name) {")

    // Reserved fields
    for reserved in msg.reservedRange {
        if reserved.start + 1 == reserved.end {
            lines.append("\(pad)  reserved \(reserved.start);")
        } else {
            lines.append("\(pad)  reserved \(reserved.start) to \(reserved.end - 1);")
        }
    }
    for name in msg.reservedName {
        lines.append("\(pad)  reserved \"\(name)\";")
    }

    // Nested enums
    for enumType in msg.enumType {
        emitEnum(enumType, indent: indent + 1, into: &lines)
        lines.append("")
    }

    // Nested messages
    for nested in msg.nestedType {
        emitMessage(nested, indent: indent + 1, package: package, into: &lines)
        lines.append("")
    }

    // Collect oneof fields
    var oneofFields: [Int32: [Google_Protobuf_FieldDescriptorProto]] = [:]
    for field in msg.field {
        if field.hasOneofIndex {
            oneofFields[field.oneofIndex, default: []].append(field)
        }
    }

    // Emit non-oneof fields and oneof blocks
    var emittedOneofs = Set<Int32>()
    for field in msg.field {
        if field.hasOneofIndex {
            let idx = field.oneofIndex
            guard !emittedOneofs.contains(idx) else { continue }
            emittedOneofs.insert(idx)

            let oneofName = msg.oneofDecl[Int(idx)].name
            lines.append("\(pad)  oneof \(oneofName) {")
            for oneofField in oneofFields[idx]! {
                let fieldLine = formatField(oneofField, package: package)
                lines.append("\(pad)    \(fieldLine)")
            }
            lines.append("\(pad)  }")
        } else {
            let fieldLine = formatField(field, package: package)
            lines.append("\(pad)  \(fieldLine)")
        }
    }

    // Extensions within message
    for ext in msg.extension {
        emitExtension(ext, indent: indent + 1, into: &lines)
    }

    lines.append("\(pad)}")
}

func emitEnum(
    _ enumType: Google_Protobuf_EnumDescriptorProto,
    indent: Int,
    into lines: inout [String]
) {
    let pad = String(repeating: "  ", count: indent)
    lines.append("\(pad)enum \(enumType.name) {")
    for value in enumType.value {
        lines.append("\(pad)  \(value.name) = \(value.number);")
    }
    lines.append("\(pad)}")
}

func emitExtension(
    _ ext: Google_Protobuf_FieldDescriptorProto,
    indent: Int,
    into lines: inout [String]
) {
    let pad = String(repeating: "  ", count: indent)
    let typeName = protoTypeName(for: ext)
    lines.append("\(pad)extend \(ext.extendee) {")
    lines.append("\(pad)  \(typeName) \(ext.name) = \(ext.number);")
    lines.append("\(pad)}")
}

func formatField(
    _ field: Google_Protobuf_FieldDescriptorProto,
    package _: String
) -> String {
    let typeName = protoTypeName(for: field)
    let label = field.label == .repeated ? "repeated " : ""
    return "\(label)\(typeName) \(field.name) = \(field.number);"
}

func protoTypeName(for field: Google_Protobuf_FieldDescriptorProto) -> String {
    switch field.type {
    case .double: "double"
    case .float: "float"
    case .int64: "int64"
    case .uint64: "uint64"
    case .int32: "int32"
    case .fixed64: "fixed64"
    case .fixed32: "fixed32"
    case .bool: "bool"
    case .string: "string"
    case .bytes: "bytes"
    case .uint32: "uint32"
    case .sfixed32: "sfixed32"
    case .sfixed64: "sfixed64"
    case .sint32: "sint32"
    case .sint64: "sint64"
    case .message, .enum:
        field.typeName
    case .group:
        fatalError("Unsupported proto feature: group in field \(field.name)")
    }
}
