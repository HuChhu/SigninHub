import Foundation
import Security

/// iOS 侧凭据存储。对应 Android 的 SecretBox（Keystore + AES/GCM）。
///
/// iOS 不需要自己管 AES：Keychain 本身就是硬件保护的 KV 存储，
/// kSecAttrAccessibleWhenUnlockedThisDeviceOnly 同时满足
/// 「锁屏不可读」和「不随 iCloud 备份跑到别的机器」这两点，
/// 正是 SecretBox 注释里担心的那个泄露面。
enum KeychainBox {

    private static let service = "app.signhub.secrets"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        var q = query(account)
        SecItemDelete(q as CFDictionary)

        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

