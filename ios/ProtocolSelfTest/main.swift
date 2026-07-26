import Foundation

let challenge = Data([0x00, 0xB6, 0xE0, 0x80, 0xEC, 0xAF, 0xF3, 0x22, 0x91, 0x6D, 0x88, 0xFA, 0xD5, 0xAA, 0x34, 0xC2, 0xAC])
let expected = Data([0x01, 0x1D, 0x88, 0x97, 0xAC, 0x46, 0x04, 0xD3, 0x32, 0xE8, 0x17, 0x5E, 0x81, 0xBB, 0x29, 0x25, 0x24])
let actual = try JieliAuth.encryptedResponse(to: challenge)
guard actual == expected else {
    fatalError("Jieli cipher vector mismatch: \(actual.map { String(format: "%02x", $0) }.joined())")
}

let sample = Data("123456789".utf8)
guard E87Codec.crc16Xmodem(sample) == 0x31C3 else {
    fatalError("CRC-16/XMODEM vector mismatch")
}

let body = Data([1, 2, 3])
guard let parsed = E87Codec.parse(E87Codec.frame(flag: 0xC0, command: 0x21, body: body)), parsed.body == body else {
    fatalError("FE frame round-trip failed")
}

print("Protocol self-test passed")
