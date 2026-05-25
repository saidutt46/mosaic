//
//  USDZArchive.swift
//  Mosaic
//
//  Packages a single USD layer (.usdc/.usda) into a .usdz. ModelIO on
//  iOS can write USD but not the zipped USDZ wrapper, so we build the
//  archive by hand — no third-party deps.
//
//  USDZ is a plain ZIP with two hard constraints from the spec:
//    1. Entries are STORED, never compressed (so they can be mmap'd).
//    2. Each entry's file *data* begins on a 64-byte boundary, achieved
//       by padding the local header's extra field.
//  Single-entry archive, no Zip64, no data descriptor.
//

import Foundation
import os

enum USDZArchive {

    private static let alignment = 64

    /// Write `usdData` (a USD layer) as the sole, 64-byte-aligned,
    /// uncompressed entry of a USDZ archive at `url`.
    static func write(usdData: Data, innerName: String, to url: URL) throws {
        let name = Array(innerName.utf8)
        let crc = crc32(usdData)
        let size = UInt32(usdData.count)

        // Pad the extra field so file data lands on a 64-byte boundary.
        // A valid extra field is ≥ 4 bytes (2-byte id + 2-byte length),
        // so if the needed pad is 1–3 bytes, bump by one alignment unit.
        let preDataLen = 30 + name.count                 // fixed local header + name
        var extraLen = (alignment - (preDataLen % alignment)) % alignment
        if extraLen != 0 && extraLen < 4 { extraLen += alignment }

        var extra = [UInt8]()
        if extraLen >= 4 {
            extra += le16(0x1986)                        // arbitrary unused extra-field id
            extra += le16(UInt16(extraLen - 4))
            extra += [UInt8](repeating: 0, count: extraLen - 4)
        }

        var out = Data()

        // Local file header
        out += le32(0x04034b50)
        out += le16(20)                                  // version needed
        out += le16(0)                                   // flags
        out += le16(0)                                   // method: STORE
        out += le16(0)                                   // mod time
        out += le16(0)                                   // mod date
        out += le32(crc)
        out += le32(size)                                // compressed size
        out += le32(size)                                // uncompressed size
        out += le16(UInt16(name.count))
        out += le16(UInt16(extraLen))
        out += name
        out += extra

        assert(out.count % alignment == 0, "USDZ entry data must be 64-byte aligned")
        out.append(usdData)

        // Central directory
        let cdOffset = out.count
        out += le32(0x02014b50)
        out += le16(20)                                  // version made by
        out += le16(20)                                  // version needed
        out += le16(0)                                   // flags
        out += le16(0)                                   // method: STORE
        out += le16(0)                                   // mod time
        out += le16(0)                                   // mod date
        out += le32(crc)
        out += le32(size)
        out += le32(size)
        out += le16(UInt16(name.count))
        out += le16(0)                                   // extra len
        out += le16(0)                                   // comment len
        out += le16(0)                                   // disk number start
        out += le16(0)                                   // internal attrs
        out += le32(0)                                   // external attrs
        out += le32(0)                                   // local header offset
        out += name
        let cdSize = out.count - cdOffset

        // End of central directory
        out += le32(0x06054b50)
        out += le16(0)                                   // this disk
        out += le16(0)                                   // disk with cd
        out += le16(1)                                   // entries this disk
        out += le16(1)                                   // total entries
        out += le32(UInt32(cdSize))
        out += le32(UInt32(cdOffset))
        out += le16(0)                                   // comment len

        try out.write(to: url)
    }

    // MARK: - Byte helpers

    private static func le16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
    }

    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
         UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    // MARK: - CRC-32 (IEEE 802.3, the ZIP polynomial)

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
