import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Speech

/// The macOS permissions that earshot needs.
public enum Permission: String, CaseIterable, Sendable, Identifiable {
    case accessibility, microphone, speech, inputMonitoring
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .microphone: return "Microphone"
        case .speech: return "Speech recognition"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    /// Why earshot needs the permission.
    public var reason: String {
        switch self {
        case .accessibility: return "Read the screen, focus fields, type and click."
        case .microphone: return "Hear commands. Audio stays on this Mac."
        case .speech: return "Use the Apple speech engine on this Mac."
        case .inputMonitoring: return "Read the hold key while another app is in front."
        }
    }

    /// The pane in System Settings, Privacy & Security.
    public var settingsURL: URL {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .microphone: anchor = "Privacy_Microphone"
        case .speech: anchor = "Privacy_SpeechRecognition"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    /// The Info.plist key that macOS needs before the app can ask. Without it, macOS stops the app when it asks.
    public var usageKey: String? {
        switch self {
        case .microphone: return "NSMicrophoneUsageDescription"
        case .speech: return "NSSpeechRecognitionUsageDescription"
        case .accessibility, .inputMonitoring: return nil
        }
    }
}

public enum PermissionState: String, Sendable {
    case granted, denied, notAsked
    public var text: String {
        switch self {
        case .granted: return "On"
        case .denied: return "Off"
        case .notAsked: return "Not asked yet"
        }
    }
}

public enum Permissions {
    public static func state(_ p: Permission) -> PermissionState {
        switch p {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .inputMonitoring:
            return CGPreflightListenEventAccess() ? .granted : .denied
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        }
    }

    /// True if the app can show the macOS request for this permission.
    public static func canAsk(_ p: Permission, info: [String: Any]? = Bundle.main.infoDictionary) -> Bool {
        guard let key = p.usageKey else { return true }
        return (info?[key] as? String)?.isEmpty == false
    }

    /// Shows the macOS request. Call only if `canAsk` is true.
    public static func ask(_ p: Permission) {
        switch p {
        case .accessibility:
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .speech:
            SFSpeechRecognizer.requestAuthorization { _ in }
        }
    }
}
