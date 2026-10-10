import Foundation
import Compression

/// CRC-32 as ZIP uses it.
enum CRC32 {
    static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for byte in bytes { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }
}

/// A small ZIP writer (enough for DOCX and zipped FB2): deflate through the system's Compression framework,
/// stored when that does not make a file smaller, UTF-8 names, no ZIP64 (files under 4 GB).
public struct ZipWriter {
    private struct Entry {
        var name: [UInt8]
        var crc: UInt32
        var compressedSize: Int
        var size: Int
        var method: UInt16
        var offset: Int
    }

    private var data = Data()
    private var entries: [Entry] = []
    private let dosTime: UInt16
    private let dosDate: UInt16

    public init(date: Date = Date()) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let year = max(1980, c.year ?? 1980)
        dosTime = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        dosDate = UInt16(((year - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
    }

    private mutating func u16(_ v: UInt16, to out: inout Data) { out.append(UInt8(v & 0xFF)); out.append(UInt8(v >> 8)) }
    private mutating func u32(_ v: UInt32, to out: inout Data) { for i in 0..<4 { out.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }

    public mutating func add(_ name: String, _ content: Data) {
        var stored = content
        var method: UInt16 = 0
        if content.count > 64 {
            var out = [UInt8](repeating: 0, count: content.count)
            let n = content.withUnsafeBytes { src -> Int in
                compression_encode_buffer(&out, out.count, src.bindMemory(to: UInt8.self).baseAddress!, content.count, nil, COMPRESSION_ZLIB)
            }
            if n > 0, n < content.count { stored = Data(out[0..<n]); method = 8 }
        }
        let nameBytes = Array(name.utf8)
        let crc = CRC32.checksum(content)
        let entry = Entry(name: nameBytes, crc: crc, compressedSize: stored.count, size: content.count, method: method, offset: data.count)
        var header = Data()
        u32(0x0403_4B50, to: &header)
        u16(20, to: &header)
        u16(0x0800, to: &header)               // names are UTF-8
        u16(method, to: &header)
        u16(dosTime, to: &header); u16(dosDate, to: &header)
        u32(crc, to: &header)
        u32(UInt32(stored.count), to: &header)
        u32(UInt32(content.count), to: &header)
        u16(UInt16(nameBytes.count), to: &header)
        u16(0, to: &header)
        header.append(contentsOf: nameBytes)
        data.append(header)
        data.append(stored)
        entries.append(entry)
    }

    public mutating func add(_ name: String, text: String) { add(name, Data(text.utf8)) }

    public mutating func finish() -> Data {
        let start = data.count
        var central = Data()
        for e in entries {
            u32(0x0201_4B50, to: &central)
            u16(20, to: &central); u16(20, to: &central)
            u16(0x0800, to: &central)
            u16(e.method, to: &central)
            u16(dosTime, to: &central); u16(dosDate, to: &central)
            u32(e.crc, to: &central)
            u32(UInt32(e.compressedSize), to: &central)
            u32(UInt32(e.size), to: &central)
            u16(UInt16(e.name.count), to: &central)
            u16(0, to: &central); u16(0, to: &central)   // extra, comment
            u16(0, to: &central); u16(0, to: &central)   // disk, internal attributes
            u32(0, to: &central)
            u32(UInt32(e.offset), to: &central)
            central.append(contentsOf: e.name)
        }
        data.append(central)
        var end = Data()
        u32(0x0605_4B50, to: &end)
        u16(0, to: &end); u16(0, to: &end)
        u16(UInt16(entries.count), to: &end); u16(UInt16(entries.count), to: &end)
        u32(UInt32(central.count), to: &end)
        u32(UInt32(start), to: &end)
        u16(0, to: &end)
        data.append(end)
        return data
    }
}
