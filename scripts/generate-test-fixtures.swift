#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Tests/Fixtures/Malformed", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

let fixtures: [(String, [UInt8])] = [
    ("truncated.jpg", [0xFF, 0xD8, 0xFF]),
    ("truncated.png", [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    ("truncated.gif", Array("GIF89a".utf8)),
    ("truncated.webp", Array("RIFF\0\0\0\0WEBP".utf8)),
]
for (name, bytes) in fixtures {
    try Data(bytes).write(to: root.appendingPathComponent(name), options: .atomic)
}
print("Generated \(fixtures.count) malformed fixtures in \(root.path)")
