import Foundation

/// Cross-process signaling between the app and the keyboard extension via
/// Darwin notifications. Darwin notifications carry no payload — the actual
/// data travels through `DictationBridge` (App Group defaults); a notification
/// just means "go read the bridge".
enum DarwinNotification: String, CaseIterable {
    case commandPosted = "com.shuaiwang.openvoicetyper.command"
    case statePosted = "com.shuaiwang.openvoicetyper.state"
    case resultPosted = "com.shuaiwang.openvoicetyper.result"
    case sessionChanged = "com.shuaiwang.openvoicetyper.session"

    var cfName: CFNotificationName {
        CFNotificationName(rawValue as CFString)
    }
}

enum DarwinNotifier {
    static func post(_ notification: DarwinNotification) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notification.cfName,
            nil, nil, true
        )
    }

    /// Observes a Darwin notification for the lifetime of the returned token.
    static func observe(_ notification: DarwinNotification, handler: @escaping @Sendable () -> Void) -> ObservationToken {
        let token = ObservationToken(name: notification.cfName, handler: handler)
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(token).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let token = Unmanaged<ObservationToken>.fromOpaque(observer).takeUnretainedValue()
                token.handler()
            },
            notification.rawValue as CFString,
            nil,
            .deliverImmediately
        )
        return token
    }

    final class ObservationToken: @unchecked Sendable {
        fileprivate let name: CFNotificationName
        fileprivate let handler: @Sendable () -> Void

        fileprivate init(name: CFNotificationName, handler: @escaping @Sendable () -> Void) {
            self.name = name
            self.handler = handler
        }

        deinit {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                name,
                nil
            )
        }
    }
}
