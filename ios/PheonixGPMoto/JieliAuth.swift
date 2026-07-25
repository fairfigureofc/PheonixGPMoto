import Foundation

enum JieliAuth {
    static let staticKey: [UInt8] = [
        0x06, 0x77, 0x5f, 0x87, 0x91, 0x8d, 0xd4, 0x23,
        0x00, 0x5d, 0xf1, 0xd8, 0xcf, 0x0c, 0x14, 0x2b,
    ]
    static let magic: [UInt8] = [0x11, 0x22, 0x33, 0x33, 0x22, 0x11]
    private static let mask: UInt16 = 0x9999

    static func randomRequest() -> Data {
        Data([0] + (0..<16).map { _ in UInt8.random(in: .min ... .max) })
    }

    static func encryptedResponse(to challenge: Data) throws -> Data {
        guard challenge.count == 17, challenge[0] == 0 else { throw E87Error.authenticationFailed }
        let encrypted = functionE1Test(key6: magic, input16: Array(challenge.dropFirst()), seed16: staticKey)
        return Data([0x01] + encrypted)
    }

    static func functionE1Test(key6: [UInt8], input16: [UInt8], seed16: [UInt8]) -> [UInt8] {
        let expandedKey = (0..<16).map { key6[$0 % 6] }
        let firstSchedule = keySchedule(Array(seed16.prefix(16)))
        var cipher = blockCipher(Array(input16.prefix(16)), schedule: firstSchedule, mode: 0)
        for index in 0..<16 {
            cipher[index] = expandedKey[index] &+ (cipher[index] ^ input16[index])
        }
        let obfuscated: [UInt8] = [
            seed16[0] &- 0x17, seed16[1] ^ 0xe5, seed16[2] &- 0x21, seed16[3] ^ 0xc1,
            seed16[4] &- 0x4d, seed16[5] ^ 0xa7, seed16[6] &- 0x6b, seed16[7] ^ 0x83,
            seed16[8] ^ 0xe9, seed16[9] &- 0x1b, seed16[10] ^ 0xdf, seed16[11] &- 0x3f,
            seed16[12] ^ 0xb3, seed16[13] &- 0x59, seed16[14] ^ 0x95, seed16[15] &- 0x7d,
        ]
        return blockCipher(cipher, schedule: keySchedule(obfuscated), mode: 1)
    }

    private static func keySchedule(_ input: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: 272)
        output.replaceSubrange(0..<16, with: input)
        var buffer = input
        buffer.append(input.reduce(0, ^))
        for round in 0..<16 {
            for index in buffer.indices { buffer[index] = (buffer[index] << 3) | (buffer[index] >> 5) }
            var readPosition = (round + 1) % 17
            for index in 0..<16 {
                let tableIndex = 15 + round * 16 - index
                output[16 + round * 16 + index] = JieliTables.keySchedule[tableIndex] &+ buffer[readPosition]
                readPosition = (readPosition + 1) % 17
            }
        }
        return output
    }

    private static func conditionalMix(_ state: [UInt8], key: ArraySlice<UInt8>, phase: Int) -> [UInt8] {
        var result = state
        for index in 0..<16 {
            let bitSet = (mask & (UInt16(1) << index)) != 0
            if phase == 3 {
                result[index] = bitSet ? state[index] ^ key[key.startIndex + index] : key[key.startIndex + index] &+ state[index]
            } else {
                result[index] = bitSet ? key[key.startIndex + index] &+ state[index] : state[index] ^ key[key.startIndex + index]
            }
        }
        return result
    }

    private static func substitute(_ state: [UInt8]) -> [UInt8] {
        var result = state
        for index in [0, 3, 4, 7, 8, 11, 12, 15] { result[index] = JieliTables.sbox[Int(result[index])] }
        for index in [1, 2, 5, 6, 9, 10, 13, 14] { result[index] = JieliTables.inverseSbox[Int(result[index])] }
        return result
    }

    private static func blockCipher(_ input: [UInt8], schedule: [UInt8], mode: Int) -> [UInt8] {
        var state = input
        let initial = input
        state = conditionalMix(state, key: schedule[0..<16], phase: 3)
        state = substitute(state)
        state = conditionalMix(state, key: schedule[16..<32], phase: 5)
        for round in 1...8 {
            state = fibonacciMix(state)
            if round == 8 {
                state = conditionalMix(state, key: schedule[256..<272], phase: 3)
                break
            }
            if mode != 0 && round == 2 {
                for index in 0..<16 {
                    let bitSet = (mask & (UInt16(1) << index)) != 0
                    state[index] = bitSet ? state[index] ^ initial[index] : initial[index] &+ state[index]
                }
            }
            let offset = round * 32
            state = conditionalMix(state, key: schedule[offset..<(offset + 16)], phase: 3)
            state = substitute(state)
            state = conditionalMix(state, key: schedule[(offset + 16)..<(offset + 32)], phase: 5)
        }
        return state
    }

    private static func fibonacciMix(_ s: [UInt8]) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 29)
        r[16]=s[0]; r[17]=s[1]; r[3]=s[2]; r[4]=s[3]; r[5]=s[4]; r[6]=s[5]; r[7]=s[6]; r[19]=s[7]
        r[20]=s[8]; r[21]=s[9]; r[22]=s[10]; r[23]=s[11]; r[24]=s[12]; r[25]=s[13]; r[26]=s[14]; r[27]=s[15]
        func twice(_ value: UInt8) -> UInt8 { value &* 2 }
        r[28]=r[17]&+twice(r[16]); r[16]=r[17]&+r[16]; r[17]=r[4]&+twice(r[3]); r[3]=r[4]&+r[3]
        r[4]=r[6]&+twice(r[5]); r[5]=r[6]&+r[5]; r[6]=r[19]&+twice(r[7]); r[7]=r[19]&+r[7]
        r[19]=r[21]&+twice(r[20]); r[20]=r[21]&+r[20]; r[21]=r[23]&+twice(r[22]); r[22]=r[23]&+r[22]
        r[23]=r[25]&+twice(r[24]); r[24]=r[25]&+r[24]; r[25]=r[27]&+twice(r[26]); r[26]=r[27]&+r[26]
        r[27]=r[22]&+twice(r[19]); r[19]=r[22]&+r[19]; r[22]=r[26]&+twice(r[23]); r[23]=r[26]&+r[23]
        r[26]=r[16]&+twice(r[17]); r[16]=r[17]&+r[16]; r[17]=r[5]&+twice(r[6]); r[5]=r[6]&+r[5]
        r[6]=r[20]&+twice(r[21]); r[20]=r[21]&+r[20]; r[21]=r[24]&+twice(r[25]); r[24]=r[25]&+r[24]
        r[25]=r[7]&+twice(r[28]); r[7]=r[7]&+r[28]; r[28]=r[3]&+twice(r[4]); r[3]=r[4]&+r[3]
        r[4]=r[24]&+twice(r[6]); r[6]=r[24]&+r[6]; r[24]=r[3]&+twice(r[25]); r[3]=r[25]&+r[3]
        r[25]=r[19]&+twice(r[22]); r[19]=r[22]&+r[19]; r[22]=r[16]&+twice(r[17]); r[16]=r[17]&+r[16]
        r[17]=r[20]&+twice(r[21]); r[20]=r[21]&+r[20]; r[21]=r[7]&+twice(r[28]); r[7]=r[7]&+r[28]
        r[28]=r[5]&+twice(r[27]); r[5]=r[27]&+r[5]; r[27]=r[23]&+twice(r[26]); r[23]=r[23]&+r[26]
        r[26]=r[7]&+twice(r[17]); r[17]=r[17]&+r[7]; r[7]=r[23]&+twice(r[28]); r[23]=r[23]&+r[28]
        r[28]=r[6]&+twice(r[24]); r[6]=r[6]&+r[24]; r[24]=r[19]&+twice(r[22]); r[19]=r[19]&+r[22]
        r[22]=r[20]&+twice(r[21]); r[20]=r[20]&+r[21]; r[21]=r[5]&+twice(r[27]); r[5]=r[27]&+r[5]
        r[27]=r[16]&+twice(r[4]); r[16]=r[4]&+r[16]; r[4]=r[3]&+twice(r[25]); r[3]=r[25]&+r[3]
        return [r[26],r[17],r[7],r[23],r[28],r[6],r[24],r[19],r[22],r[20],r[21],r[5],r[27],r[16],r[4],r[3]]
    }
}
