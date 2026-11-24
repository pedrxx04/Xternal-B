import Foundation

/// Single place to point the app at your key-verification endpoint.
///
/// EDIT THIS: replace `verifyURL` with the real HTTPS address of the
/// `/api/app/verify` route added to your bot's aiohttp server (see
/// `dist/bot_key_endpoint_patch.py` for the server side). It must be
/// HTTPS — iOS blocks plain HTTP by default (App Transport Security) and
/// this app does not add an exception for it.
enum KeyGateConfig {
    /// Example once your VPS has HTTPS (via Caddy + nip.io, see the
    /// deployment guide): "https://203-0-113-10.nip.io/api/app/verify"
    static let verifyURL = URL(string: "https://REEMPLAZA-CON-TU-DOMINIO/api/app/verify")!

    /// Shared secret sent in the `X-App-Secret` header so random internet
    /// scanners cannot hammer the endpoint guessing keys. Must match
    /// `APP_KEY_SHARED_SECRET` in the bot's `config.py`. This is NOT the
    /// license key itself — it is a fixed value baked into the app build.
    static let sharedSecret = "REEMPLAZA-CON-UN-SECRETO-LARGO"

    /// How often a successfully-unlocked app re-checks the key with the
    /// server while it keeps running/foregrounding (minutes). Keeps a
    /// revoked key from working indefinitely once the device goes back
    /// online, without hitting the server on every single foreground.
    static let revalidationInterval: TimeInterval = 30 * 60

    /// If the server cannot be reached (no signal, VPS down, etc.) but the
    /// key was valid last time we did reach it, how long the app keeps
    /// working anyway before it insists on a successful check again.
    static let offlineGracePeriod: TimeInterval = 3 * 24 * 60 * 60
}
