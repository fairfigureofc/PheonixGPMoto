import Foundation

let challenge = Data([0x00, 0xb6, 0xe0, 0x80, 0xec, 0xaf, 0xf3, 0x22, 0x91, 0x6d, 0x88, 0xfa, 0xd5, 0xaa, 0x34, 0xc2, 0xac])
let expected = Data([0x01, 0x1d, 0x88, 0x97, 0xac, 0x46, 0x04, 0xd3, 0x32, 0xe8, 0x17, 0x5e, 0x81, 0xbb, 0x29, 0x25, 0x24])
let actual = try JieliAuth.encryptedResponse(to: challenge)
guard actual == expected else {
    fatalError("Jieli cipher vector mismatch: \(actual.map { String(format: "%02x", $0) }.joined())")
}

let sample = Data("123456789".utf8)
guard E87Codec.crc16Xmodem(sample) == 0x31c3 else {
    fatalError("CRC-16/XMODEM vector mismatch")
}

let body = Data([1, 2, 3])
guard let parsed = E87Codec.parse(E87Codec.frame(flag: 0xc0, command: 0x21, body: body)), parsed.body == body else {
    fatalError("FE frame round-trip failed")
}

print("Protocol self-test passed")
