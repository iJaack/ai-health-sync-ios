#!/usr/bin/env swift
// Quick test: generate the same DER cert as the app and see if SecCertificateCreateWithData accepts it.

import Foundation
import Security
import CryptoKit

// === DEREncoder (copy from app) ===
enum DEREncoder {
    static func sequence(_ elements: [Data]) -> Data {
        wrap(tag: 0x30, content: elements.joined())
    }
    static func set(_ elements: [Data]) -> Data {
        wrap(tag: 0x31, content: elements.joined())
    }
    static func integer(_ bytes: [UInt8]) -> Data {
        var value = bytes
        if let first = value.first, first & 0x80 != 0 {
            value.insert(0x00, at: 0)
        }
        return wrap(tag: 0x02, content: Data(value))
    }
    static func integer(_ value: Int) -> Data {
        var bytes = [UInt8]()
        var v = value
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v > 0
        return integer(bytes)
    }
    static func objectIdentifier(_ oid: [UInt64]) -> Data {
        guard oid.count >= 2 else { return Data() }
        var bytes = [UInt8]()
        bytes.append(UInt8(oid[0] * 40 + oid[1]))
        for component in oid.dropFirst(2) {
            bytes.append(contentsOf: encodeBase128(component))
        }
        return wrap(tag: 0x06, content: Data(bytes))
    }
    static func utf8String(_ value: String) -> Data {
        wrap(tag: 0x0C, content: Data(value.utf8))
    }
    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        let value = formatter.string(from: date)
        return wrap(tag: 0x17, content: Data(value.utf8))
    }
    static func bitString(_ data: Data) -> Data {
        var content = Data([0x00])
        content.append(data)
        return wrap(tag: 0x03, content: content)
    }
    static func null() -> Data {
        wrap(tag: 0x05, content: Data())
    }
    static func contextSpecific(_ tag: UInt8, content: Data) -> Data {
        wrap(tag: 0xA0 | tag, content: content)
    }
    private static func wrap(tag: UInt8, content: Data) -> Data {
        var data = Data([tag])
        data.append(contentsOf: encodeLength(content.count))
        data.append(content)
        return data
    }
    private static func encodeLength(_ length: Int) -> [UInt8] {
        if length < 128 { return [UInt8(length)] }
        var bytes = [UInt8]()
        var value = length
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        var result = [UInt8(0x80 | UInt8(bytes.count))]
        result.append(contentsOf: bytes)
        return result
    }
    private static func encodeBase128(_ value: UInt64) -> [UInt8] {
        var bytes = [UInt8]()
        var v = value
        repeat {
            bytes.insert(UInt8(v & 0x7F), at: 0)
            v >>= 7
        } while v > 0
        for i in 0..<(bytes.count - 1) { bytes[i] |= 0x80 }
        return bytes
    }
}
private extension Array where Element == Data {
    func joined() -> Data { reduce(into: Data()) { $0.append($1) } }
}

extension UInt64 {
    var certBytes: [UInt8] {
        var value = self
        var bytes = [UInt8]()
        repeat {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        } while value > 0
        return bytes
    }
}

// === Generate key ===
let keyAttrs: [String: Any] = [
    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
    kSecAttrKeySizeInBits as String: 256
]
var keyError: Unmanaged<CFError>?
guard let privateKey = SecKeyCreateRandomKey(keyAttrs as CFDictionary, &keyError) else {
    print("FAIL: key generation: \(keyError!.takeRetainedValue())")
    exit(1)
}
guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
    print("FAIL: SecKeyCopyPublicKey")
    exit(1)
}
print("✅ Key pair generated")

guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
    print("FAIL: export public key")
    exit(1)
}
print("✅ Public key exported (\(publicKeyData.count) bytes)")

// === Build cert (same as app, WITH null removed) ===
func buildTBS(serial: UInt64, publicKeyData: Data, notBefore: Date, notAfter: Date) -> Data {
    let version = DEREncoder.contextSpecific(0, content: DEREncoder.integer(2))
    let serialNumber = DEREncoder.integer(serial.certBytes)
    let signatureAlgorithm = DEREncoder.sequence([
        DEREncoder.objectIdentifier([1, 2, 840, 10045, 4, 3, 2])
    ])
    let name = DEREncoder.sequence([
        DEREncoder.set([
            DEREncoder.sequence([
                DEREncoder.objectIdentifier([2, 5, 4, 3]),
                DEREncoder.utf8String("HealthSync Local")
            ])
        ])
    ])
    let validity = DEREncoder.sequence([
        DEREncoder.utcTime(notBefore),
        DEREncoder.utcTime(notAfter)
    ])
    let publicKeyAlgorithm = DEREncoder.sequence([
        DEREncoder.objectIdentifier([1, 2, 840, 10045, 2, 1]),
        DEREncoder.objectIdentifier([1, 2, 840, 10045, 3, 1, 7])
    ])
    let subjectPublicKeyInfo = DEREncoder.sequence([
        publicKeyAlgorithm,
        DEREncoder.bitString(publicKeyData)
    ])
    return DEREncoder.sequence([
        version, serialNumber, signatureAlgorithm,
        name, validity, name, subjectPublicKeyInfo
    ])
}

let notBefore = Date()
let notAfter = Calendar.current.date(byAdding: .day, value: 365, to: notBefore)!
let serial = UInt64.random(in: 1...UInt64.max)
let tbs = buildTBS(serial: serial, publicKeyData: publicKeyData, notBefore: notBefore, notAfter: notAfter)
print("✅ TBS built (\(tbs.count) bytes)")

// Sign
let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
var sigError: Unmanaged<CFError>?
guard let signature = SecKeyCreateSignature(privateKey, algorithm, tbs as CFData, &sigError) as Data? else {
    print("FAIL: sign: \(sigError!.takeRetainedValue())")
    exit(1)
}
print("✅ Signature created (\(signature.count) bytes)")

// Version WITHOUT null
let sigAlgNoNull = DEREncoder.sequence([
    DEREncoder.objectIdentifier([1, 2, 840, 10045, 4, 3, 2])
])
let certNoNull = DEREncoder.sequence([tbs, sigAlgNoNull, DEREncoder.bitString(signature)])

// Version WITH null
let tbsWithNull = { () -> Data in
    let version = DEREncoder.contextSpecific(0, content: DEREncoder.integer(2))
    let serialNumber = DEREncoder.integer(serial.certBytes)
    let signatureAlgorithm = DEREncoder.sequence([
        DEREncoder.objectIdentifier([1, 2, 840, 10045, 4, 3, 2]),
        DEREncoder.null()
    ])
    let name = DEREncoder.sequence([
        DEREncoder.set([
            DEREncoder.sequence([
                DEREncoder.objectIdentifier([2, 5, 4, 3]),
                DEREncoder.utf8String("HealthSync Local")
            ])
        ])
    ])
    let validity = DEREncoder.sequence([
        DEREncoder.utcTime(notBefore),
        DEREncoder.utcTime(notAfter)
    ])
    let publicKeyAlgorithm = DEREncoder.sequence([
        DEREncoder.objectIdentifier([1, 2, 840, 10045, 2, 1]),
        DEREncoder.objectIdentifier([1, 2, 840, 10045, 3, 1, 7])
    ])
    let subjectPublicKeyInfo = DEREncoder.sequence([
        publicKeyAlgorithm,
        DEREncoder.bitString(publicKeyData)
    ])
    return DEREncoder.sequence([
        version, serialNumber, signatureAlgorithm,
        name, validity, name, subjectPublicKeyInfo
    ])
}()
// Re-sign with the WITH-null TBS
guard let sigWithNull = SecKeyCreateSignature(privateKey, algorithm, tbsWithNull as CFData, &sigError) as Data? else {
    print("FAIL: sign with-null TBS")
    exit(1)
}
let sigAlgWithNull = DEREncoder.sequence([
    DEREncoder.objectIdentifier([1, 2, 840, 10045, 4, 3, 2]),
    DEREncoder.null()
])
let certWithNull = DEREncoder.sequence([tbsWithNull, sigAlgWithNull, DEREncoder.bitString(sigWithNull)])

print("\n--- Testing SecCertificateCreateWithData ---")
print("Without NULL (\(certNoNull.count) bytes):")
if let cert = SecCertificateCreateWithData(nil, certNoNull as CFData) {
    print("  ✅ ACCEPTED: \(SecCertificateCopySubjectSummary(cert) ?? "?" as CFString)")
} else {
    print("  ❌ REJECTED")
    // Dump first 64 bytes hex
    print("  First 64 bytes: \(certNoNull.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " "))")
}

print("With NULL (\(certWithNull.count) bytes):")
if let cert = SecCertificateCreateWithData(nil, certWithNull as CFData) {
    print("  ✅ ACCEPTED: \(SecCertificateCopySubjectSummary(cert) ?? "?" as CFString)")
} else {
    print("  ❌ REJECTED")
    print("  First 64 bytes: \(certWithNull.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " "))")
}

// Also try with openssl-style: generate a real cert using openssl and compare
print("\n--- Trying openssl-generated cert for reference ---")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
proc.arguments = ["req", "-new", "-x509", "-nodes", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
                   "-keyout", "/dev/null", "-out", "/tmp/test_cert.der", "-outform", "DER",
                   "-days", "365", "-subj", "/CN=TestCert"]
proc.standardOutput = FileHandle.nullDevice
proc.standardError = FileHandle.nullDevice
try? proc.run()
proc.waitUntilExit()
if let opensslCert = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/test_cert.der")) {
    if let cert = SecCertificateCreateWithData(nil, opensslCert as CFData) {
        print("  ✅ OpenSSL cert accepted: \(SecCertificateCopySubjectSummary(cert) ?? "?" as CFString)")
        // Compare structure
        print("  OpenSSL cert size: \(opensslCert.count) bytes")
        print("  First 32 bytes: \(opensslCert.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))")
    } else {
        print("  ❌ OpenSSL cert also rejected")
    }
} else {
    print("  ⚠️ Could not generate openssl cert")
}
