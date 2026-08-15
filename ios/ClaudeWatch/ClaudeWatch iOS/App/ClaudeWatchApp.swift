import SwiftUI

@main
struct ClaudeWatchApp: App {

    @StateObject private var sessionManager = WatchSessionManager.shared
    @StateObject private var relayService = RelayService.shared

    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if relayService.isPaired {
                    ConnectionStatusView()
                } else {
                    PairingView()
                }
            }
            .environmentObject(sessionManager)
            .environmentObject(relayService)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Format: agentwatch://pair?url=<endpoint>&code=<code>&token=<ingress_token>
        guard url.scheme == "agentwatch",
              url.host == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        let queryItems = components.queryItems ?? []
        guard let endpoint = queryItems.first(where: { $0.name == "url" })?.value,
              let code = queryItems.first(where: { $0.name == "code" })?.value else {
            return
        }

        // Set ingress token if provided
        if let token = queryItems.first(where: { $0.name == "token" })?.value {
            relayService.setIngressToken(token)
        }

        // Trigger pairing
        Task {
            do {
                try await relayService.pairWithEndpoint(endpoint, code: code)
            } catch {
                print("[DeepLink] Pairing failed: \(error)")
            }
        }
    }
}
