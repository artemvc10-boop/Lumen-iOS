import Foundation
import UserNotifications
import TelegramCore
import AccountContext
import TelegramStringFormatting
import LocalizedPeerData

// MARK: Lumen

/// Shows a system notification for messages that arrive while Lumen runs in the background
/// (see LumenBackgroundKeeper). Telegram normally does this with push, which never reaches a
/// sideloaded build. The payload uses the keys AppDelegate already understands, so a tap
/// opens the chat.
func lumenPostBackgroundNotification(context: AccountContext, messages: [EngineMessage], threadData: MessageHistoryThreadData?, displayPreview: Bool) {
    guard let message = messages.first else {
        return
    }
    let peerId = message.id.peerId
    if message.flags.contains(.Incoming) == false && !message.flags.contains(.WasScheduled) {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let strings = presentationData.strings
    let nameOrder = presentationData.nameDisplayOrder

    let content = UNMutableNotificationContent()
    var title = ""
    if let peer = message.peers[peerId] {
        title = EnginePeer(peer).displayTitle(strings: strings, displayOrder: nameOrder)
    }
    if let threadData {
        title = title.isEmpty ? threadData.info.title : "\(title) › \(threadData.info.title)"
    }

    if displayPreview {
        var body = ""
        let contentSettings = context.currentContentSettings.with { $0 }
        for item in messages.prefix(1) {
            body = descriptionStringForMessage(contentSettings: contentSettings, message: item, strings: strings, nameDisplayOrder: nameOrder, dateTimeFormat: presentationData.dateTimeFormat, accountPeerId: context.account.peerId).0.string
        }
        if messages.count > 1 && body.isEmpty {
            body = "\(messages.count) 📎"
        }
        let isGroup = peerId.namespace == Namespaces.Peer.CloudGroup || (peerId.namespace == Namespaces.Peer.CloudChannel && !((message.peers[peerId] as? TelegramChannel).map { channel -> Bool in
            if case .broadcast = channel.info {
                return true
            }
            return false
        } ?? false))
        if isGroup, let author = message.author {
            content.subtitle = author.displayTitle(strings: strings, displayOrder: nameOrder)
        }
        content.title = title
        content.body = body.isEmpty ? " " : body
    } else {
        content.title = "Lumen"
        content.body = (Locale.preferredLanguages.first ?? "").hasPrefix("ru") ? "Новое сообщение" : "New message"
    }
    content.sound = .default
    content.threadIdentifier = "\(peerId.toInt64())"
    var userInfo: [AnyHashable: Any] = [
        "accountId": context.account.id.int64,
        "peerId": peerId.toInt64(),
        "messageId.namespace": message.id.namespace,
        "messageId.id": message.id.id,
        "lumenLocal": true,
    ]
    if threadData != nil, let threadId = message.threadId {
        userInfo["threadId"] = threadId
    }
    content.userInfo = userInfo

    let request = UNNotificationRequest(identifier: "lumen-\(peerId.toInt64())-\(message.id.namespace)-\(message.id.id)", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request, withCompletionHandler: { error in
        if let error {
            Logger.shared.log("Lumen", "local notification failed: \(error)")
        }
    })
}

/// Clears the notifications Lumen posted once the app is open again (Telegram does the same
/// with push notifications of chats that were read).
func lumenRemoveBackgroundNotifications() {
    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications(completionHandler: { notifications in
        let ids = notifications.filter { $0.request.content.userInfo["lumenLocal"] != nil }.map(\.request.identifier)
        if !ids.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    })
}
