import Foundation

@main
enum TunnelHandoffCheck {
    static func main() {
        let choices = TunnelHandoffApp.allCases
        precondition(choices == [.localDevVPN, .shadowrocket, .surge, .loon, .quantumultX])
        precondition(choices.map(\.launchURL.scheme) == ["localdevvpn", "shadowrocket", "surge", "loon", "quantumult-x"])
        precondition(TunnelHandoffApp.localDevVPN.launchURL.host == "enable")
        precondition(TunnelHandoffApp.localDevVPN.launchURL.query == "scheme=wrappin")
        precondition(TunnelHandoffApp.shadowrocket.launchURL.host == "connect")
        precondition(TunnelHandoffApp.shadowrocket.launchURL.query == nil)
        precondition(TunnelHandoffApp.surge.launchURL.path == "/start")
        precondition(TunnelHandoffApp.surge.launchURL.host == nil)
        precondition(TunnelHandoffApp.loon.launchURL.host == "on")

        let stored = TunnelHandoffApp.shadowrocket.rawValue
        precondition(TunnelHandoffApp(rawValue: stored) == .shadowrocket)
        precondition(TunnelHandoffApp(rawValue: "unknown") ?? .localDevVPN == .localDevVPN)

        precondition(TunnelHandoffPolicy.offersMobileDataWorkaround(for: .localDevVPN))
        precondition(!TunnelHandoffPolicy.usesAirplaneModeForMobileData(.localDevVPN))
        precondition(TunnelHandoffPolicy.offersMobileDataWorkaround(for: .shadowrocket))
        precondition(TunnelHandoffPolicy.usesAirplaneModeForMobileData(.shadowrocket))
        precondition(TunnelHandoffPolicy.offersMobileDataWorkaround(for: .surge))
        precondition(TunnelHandoffPolicy.usesAirplaneModeForMobileData(.surge))
        precondition(TunnelHandoffPolicy.offersMobileDataWorkaround(for: .loon))
        precondition(TunnelHandoffPolicy.usesAirplaneModeForMobileData(.loon))
        precondition(TunnelHandoffPolicy.recommendsWiFiWhenUnavailable(for: .shadowrocket))
        precondition(TunnelHandoffPolicy.recommendsWiFiWhenUnavailable(for: .surge))
        precondition(TunnelHandoffPolicy.recommendsWiFiWhenUnavailable(for: .loon))
        precondition(TunnelHandoffPolicy.recommendsWiFiWhenUnavailable(for: .quantumultX))
        precondition(TunnelHandoffPolicy.offersMobileDataWorkaround(for: .quantumultX))
        precondition(TunnelHandoffPolicy.usesAirplaneModeForMobileData(.quantumultX))
        precondition(!TunnelHandoffPolicy.recommendsWiFiWhenUnavailable(for: .localDevVPN))
        precondition(TunnelHandoffPolicy.requiresLocalDevVPNCellularHandoff(
            app: .localDevVPN, isWiFiPathKnown: true, isWiFiSatisfied: false
        ))
        precondition(!TunnelHandoffPolicy.requiresLocalDevVPNCellularHandoff(
            app: .localDevVPN, isWiFiPathKnown: true, isWiFiSatisfied: true
        ))
        precondition(!TunnelHandoffPolicy.requiresLocalDevVPNCellularHandoff(
            app: .shadowrocket, isWiFiPathKnown: true, isWiFiSatisfied: false
        ))
        precondition(!TunnelHandoffPolicy.requiresLocalDevVPNCellularHandoff(
            app: .surge, isWiFiPathKnown: true, isWiFiSatisfied: false
        ))
        precondition(!TunnelHandoffPolicy.requiresLocalDevVPNCellularHandoff(
            app: .loon, isWiFiPathKnown: true, isWiFiSatisfied: false
        ))
        precondition(!TunnelHandoffPolicy.requiresLocalDevVPNCellularHandoff(
            app: .localDevVPN, isWiFiPathKnown: false, isWiFiSatisfied: false
        ))

        print("Tunnel handoff: LocalDevVPN callback, Shadowrocket connect, Surge start, Loon start, selection and mobile guidance passed")
    }
}
