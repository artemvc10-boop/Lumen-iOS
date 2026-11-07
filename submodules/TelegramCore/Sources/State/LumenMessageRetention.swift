import Foundation
import Postbox
import SGSimpleSettings

// MARK: Lumen

private func lumenStoreMessage(_ message: Message, attributes: [MessageAttribute]) -> StoreMessage {
    var storeForwardInfo: StoreMessageForwardInfo?
    if let forwardInfo = message.forwardInfo {
        storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
    }
    return StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: storeForwardInfo, authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media)
}

/// Instead of deleting messages the server reports as deleted, marks them and keeps them.
/// Returns the ids that must still be deleted the normal way.
func lumenRetainDeletedMessages(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
    guard LumenSettings.shared.saveDeletedMessages else {
        return ids
    }
    let now = Int32(Date().timeIntervalSince1970)
    var remaining: [MessageId] = []
    for id in ids {
        guard let message = transaction.getMessage(id) else {
            remaining.append(id)
            continue
        }
        // Service messages ("X joined", pinned notices) are not worth keeping, and a
        // message that is already marked was kept on an earlier deletion.
        if message.media.contains(where: { $0 is TelegramMediaAction }) {
            remaining.append(id)
            continue
        }
        if message.lumenDeletedDate != nil {
            continue
        }
        transaction.updateMessage(id, update: { current in
            var attributes = current.attributes.filter { !($0 is LumenDeletedMessageAttribute) }
            attributes.append(LumenDeletedMessageAttribute(date: now))
            return .update(lumenStoreMessage(current, attributes: attributes))
        })
    }
    return remaining
}

/// Carries Lumen's local attributes across server updates of a message and records the
/// previous text when the update is an edit.
func lumenMergedAttributes(previous: Message, updatedText: String, attributes: [MessageAttribute]) -> [MessageAttribute] {
    var result = attributes.filter { !($0 is LumenEditHistoryAttribute) && !($0 is LumenDeletedMessageAttribute) }
    var history = previous.lumenEditHistory
    if previous.text != updatedText && !previous.text.isEmpty && LumenSettings.shared.saveEditHistory {
        let editDate = (attributes.first(where: { $0 is EditedMessageAttribute }) as? EditedMessageAttribute)?.date ?? Int32(Date().timeIntervalSince1970)
        history.append(LumenEditHistoryAttribute.Entry(text: previous.text, date: editDate))
    }
    if !history.isEmpty {
        result.append(LumenEditHistoryAttribute(entries: history))
    }
    if let deletedDate = previous.lumenDeletedDate {
        result.append(LumenDeletedMessageAttribute(date: deletedDate))
    }
    return result
}
