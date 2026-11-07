import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings
internal import TelegramApi

// MARK: Lumen

private final class LumenWeakAccount {
    weak var account: Account?

    init(_ account: Account) {
        self.account = account
    }
}

private let lumenAccounts = Atomic<[PeerId: LumenWeakAccount]>(value: [:])

/// Lets plugins send messages from this account. Called for main-app accounts only.
func lumenRegisterAccount(_ account: Account) {
    let _ = lumenAccounts.modify { current in
        var current = current.filter { $0.value.account != nil }
        current[account.peerId] = LumenWeakAccount(account)
        return current
    }
    if LumenHooks.sendText == nil {
        LumenHooks.sendText = { accountPeerId, peerId, text in
            guard let account = lumenAccounts.with({ $0[PeerId(accountPeerId)]?.account }) else {
                return
            }
            let _ = enqueueMessages(account: account, peerId: PeerId(peerId), messages: [.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])]).start()
        }
    }
}

/// In ghost mode, replying to a chat still marks it read: answering a message while it
/// shows as unread would give ghost mode away.
func lumenReadOnReply(account: Account, peerId: PeerId) {
    guard LumenSettings.shared.readOnReply, !LumenSettings.shared.sendReadReceipts else {
        return
    }
    if peerId.namespace == Namespaces.Peer.SecretChat {
        return
    }
    let network = account.network
    let _ = (account.postbox.transaction { transaction -> (Peer, Int32)? in
        guard let peer = transaction.getPeer(peerId), let topId = transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud) else {
            return nil
        }
        return (peer, topId.id)
    }
    |> mapToSignal { value -> Signal<Never, NoError> in
        guard let value else {
            return .complete()
        }
        let (peer, maxId) = value
        if peerId.namespace == Namespaces.Peer.CloudChannel {
            guard let inputChannel = apiInputChannel(peer) else {
                return .complete()
            }
            return network.request(Api.functions.channels.readHistory(channel: inputChannel, maxId: maxId))
            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                return .complete()
            }
            |> ignoreValues
        } else {
            guard let inputPeer = apiInputPeer(peer) else {
                return .complete()
            }
            return network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: maxId))
            |> `catch` { _ -> Signal<Api.messages.AffectedMessages, NoError> in
                return .complete()
            }
            |> ignoreValues
        }
    }).start()
}

/// Runs the plugins' outgoing-text transform over the messages about to be sent.
func lumenApplyOutgoingHook(accountPeerId: PeerId, peerId: PeerId, messages: [EnqueueMessage]) -> [EnqueueMessage] {
    guard let transform = LumenHooks.transformOutgoingText else {
        return messages
    }
    return messages.compactMap { message -> EnqueueMessage? in
        guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message, !text.isEmpty else {
            return message
        }
        guard let updatedText = transform(accountPeerId.toInt64(), peerId.toInt64(), text) else {
            return nil
        }
        if updatedText == text {
            return message
        }
        // Formatting entities point into the old text; they would be wrong for the new one.
        let updatedAttributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
        return .message(text: updatedText, attributes: updatedAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
    }
}

private func lumenChatType(transaction: Transaction, peerId: PeerId) -> String {
    switch peerId.namespace {
    case Namespaces.Peer.CloudUser:
        return "private"
    case Namespaces.Peer.SecretChat:
        return "secret"
    case Namespaces.Peer.CloudChannel:
        if let channel = transaction.getPeer(peerId) as? TelegramChannel, case .broadcast = channel.info {
            return "channel"
        }
        return "group"
    default:
        return "group"
    }
}

/// Hands newly arrived messages to the plugins.
func lumenReportIncomingMessages(transaction: Transaction, accountPeerId: PeerId, ids: [MessageId]) {
    guard let observer = LumenHooks.incomingMessages, !ids.isEmpty else {
        return
    }
    var result: [LumenIncomingMessage] = []
    for id in ids {
        if let message = transaction.getMessage(id) {
            result.append(LumenIncomingMessage(accountPeerId: accountPeerId.toInt64(), peerId: id.peerId.toInt64(), authorId: message.author?.id.toInt64(), messageId: id.id, text: message.text, chatType: lumenChatType(transaction: transaction, peerId: id.peerId)))
        }
    }
    if !result.isEmpty {
        observer(result)
    }
}
