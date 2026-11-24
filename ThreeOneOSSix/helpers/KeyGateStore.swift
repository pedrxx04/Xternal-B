import Foundation
import UIKit

/// Drives the "enter your key" gate shown before anything else in the app.
///
/// Flow: a stored key is revalidated on launch and periodically while the
/// app runs; an explicit "invalid/revoked/expired" answer from the server
/// locks the app and clears the stored key; a server/network failure does
/// NOT lock the app immediately if the key worked recently (see
/// `KeyGateConfig.offlineGracePeriod`) — a flaky VPS or bad signal should
/// not strand a paying user who already unlocked successfully.
@MainActor
final class KeyGateStore: ObservableObject {
    enum State: Equatable {
        /// First run, or the stored key was cleared — show the entry form.
        case needsKey(error: String?)
        /// Checking a key (either just typed, or the one saved from last time).
        case checking
        /// Verified; the real app can render.
        case unlocked
    }

    @Published private(set) var state: State = .needsKey(error: nil)
    @Published var isRetrying = false

    private let defaults = UserDefaults.standard
    private let keyDefaultsKey = "xb.licenseKey"
    private let lastValidDefaultsKey = "xb.licenseLastValidAt"
    private var lastCheckAt: Date = .distantPast

    private var storedKey: String? {
        get { defaults.string(forKey: keyDefaultsKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: keyDefaultsKey)
            } else {
                defaults.removeObject(forKey: keyDefaultsKey)
            }
        }
    }

    private var lastValidAt: Date? {
        get {
            let value = defaults.double(forKey: lastValidDefaultsKey)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: lastValidDefaultsKey)
            } else {
                defaults.removeObject(forKey: lastValidDefaultsKey)
            }
        }
    }

    /// Call once at app launch.
    func bootstrap() async {
        guard let key = storedKey, !key.isEmpty else {
            state = .needsKey(error: nil)
            return
        }
        state = .checking
        await verify(key: key, isInitialBootstrap: true)
    }

    /// Call when the user types a key into the gate and taps "Unlock".
    func submit(key rawKey: String) async {
        let key = Self.normalize(rawKey)
        guard !key.isEmpty else {
            state = .needsKey(error: "key.gate.error_empty")
            return
        }
        state = .checking
        storedKey = key
        await verify(key: key, isInitialBootstrap: false)
    }

    /// Call on scene-phase-active and after long foreground sessions.
    /// Throttled; silently does nothing most of the time.
    func revalidateIfNeeded() {
        guard state == .unlocked, let key = storedKey else { return }
        guard Date().timeIntervalSince(lastCheckAt) >= KeyGateConfig.revalidationInterval else { return }
        Task { await verify(key: key, isInitialBootstrap: false, silent: true) }
    }

    func reset() {
        storedKey = nil
        lastValidAt = nil
        state = .needsKey(error: nil)
    }

    // MARK: - Networking

    private struct VerifyResponse: Decodable {
        let ok: Bool
        let error: String?
    }

    private func verify(key: String, isInitialBootstrap: Bool, silent: Bool = false) async {
        lastCheckAt = Date()
        var request = URLRequest(url: KeyGateConfig.verifyURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(KeyGateConfig.sharedSecret, forHTTPHeaderField: "X-App-Secret")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "key": key,
            "device": UIDeviceIdentifier.vendorID,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                handleUnreachable(isInitialBootstrap: isInitialBootstrap, silent: silent)
                return
            }
            if (200..<300).contains(http.statusCode) {
                let decoded = try? JSONDecoder().decode(VerifyResponse.self, from: data)
                if decoded?.ok == true {
                    lastValidAt = Date()
                    state = .unlocked
                    log("keygate: key accepted")
                } else {
                    handleRejected(reason: decoded?.error, silent: silent)
                }
            } else if http.statusCode == 403 || http.statusCode == 404 || http.statusCode == 410 {
                let decoded = try? JSONDecoder().decode(VerifyResponse.self, from: data)
                handleRejected(reason: decoded?.error, silent: silent)
            } else {
                // Server reachable but erroring (5xx, rate limit, misconfigured
                // secret) — treat like "unreachable", not "this key is bad".
                handleUnreachable(isInitialBootstrap: isInitialBootstrap, silent: silent)
            }
        } catch {
            log("keygate: verify request failed — \(error.localizedDescription)")
            handleUnreachable(isInitialBootstrap: isInitialBootstrap, silent: silent)
        }
    }

    private func handleRejected(reason: String?, silent: Bool) {
        storedKey = nil
        lastValidAt = nil
        let key: String
        switch reason {
        case "revoked": key = "key.gate.error_revoked"
        case "expired": key = "key.gate.error_expired"
        case "not_found": key = "key.gate.error_invalid"
        default: key = "key.gate.error_invalid"
        }
        log("keygate: key rejected — \(reason ?? "unknown")")
        state = .needsKey(error: key)
    }

    private func handleUnreachable(isInitialBootstrap: Bool, silent: Bool) {
        if let lastValidAt, Date().timeIntervalSince(lastValidAt) < KeyGateConfig.offlineGracePeriod {
            // Recently-good key, server just not reachable right now — do not
            // interrupt someone already using the app over a periodic recheck,
            // and let a fresh launch through too.
            state = .unlocked
            log("keygate: server unreachable, using offline grace period")
            return
        }
        guard !silent else {
            // A periodic background recheck failed outside the grace window —
            // still drop back to the gate so an abandoned/expired install does
            // not run unlicensed indefinitely, but it is not a "bad key"
            // message, it is a "could not confirm" one.
            state = .needsKey(error: "key.gate.error_offline")
            return
        }
        state = .needsKey(error: "key.gate.error_offline")
    }

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

/// Stable per-install identifier sent alongside the key purely so you can see
/// in the bot/admin side which device last used a given key. Not enforced as
/// a device lock by the client — any enforcement happens server-side if you
/// add it later.
enum UIDeviceIdentifier {
    static var vendorID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }
}
