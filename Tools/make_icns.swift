import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift make_icns.swift <iconset-directory> <output.icns>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(type: String, filename: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

var payload = Data()
for entry in entries {
    let pngURL = iconsetURL.appendingPathComponent(entry.filename)
    let png = try Data(contentsOf: pngURL)
    payload.append(contentsOf: entry.type.utf8)
    appendBigEndian(UInt32(png.count + 8), to: &payload)
    payload.append(png)
}

var output = Data("icns".utf8)
appendBigEndian(UInt32(payload.count + 8), to: &output)
output.append(payload)
try output.write(to: outputURL, options: .atomic)
print(outputURL.path)
