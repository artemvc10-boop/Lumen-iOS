import Foundation
import ImageIO
import Postbox
import SwiftSignalKit
import MtProtoKit
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

/// The chat in the Android client's convention, which exteraGram plugins use: a user is its
/// id, a group or channel is minus its id. Secret chats keep the full 64-bit peer id.
public func lumenDialogId(peerId: PeerId) -> Int64 {
    let id = peerId.id._internalGetInt64Value()
    switch peerId.namespace {
    case Namespaces.Peer.CloudUser:
        return id
    case Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel:
        return -id
    default:
        return peerId.toInt64()
    }
}

private func lumenResolveDialog(transaction: Transaction, dialogId: Int64) -> PeerId? {
    if dialogId > 0 {
        let userId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(dialogId))
        if transaction.getPeer(userId) != nil {
            return userId
        }
    } else if dialogId < 0 {
        let id = PeerId.Id._internalFromInt64Value(-dialogId)
        let channelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: id)
        if transaction.getPeer(channelId) != nil {
            return channelId
        }
        let groupId = PeerId(namespace: Namespaces.Peer.CloudGroup, id: id)
        if transaction.getPeer(groupId) != nil {
            return groupId
        }
    }
    // A full 64-bit peer id, as used for secret chats.
    let raw = PeerId(dialogId)
    if transaction.getPeer(raw) != nil {
        return raw
    }
    return nil
}

private func lumenEnqueue(accountPeerId: Int64, dialogId: Int64, makeMessages: @escaping (Account) -> [EnqueueMessage]) {
    guard let account = lumenAccounts.with({ $0[PeerId(accountPeerId)]?.account }) else {
        return
    }
    let _ = (account.postbox.transaction { transaction -> PeerId? in
        return lumenResolveDialog(transaction: transaction, dialogId: dialogId)
    }
    |> mapToSignal { peerId -> Signal<[MessageId?], NoError> in
        guard let peerId else {
            return .single([])
        }
        let messages = makeMessages(account)
        if messages.isEmpty {
            return .single([])
        }
        return enqueueMessages(account: account, peerId: peerId, messages: messages)
    }).start()
}

private func lumenTextMessage(_ text: String) -> EnqueueMessage {
    return .message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
}

private func lumenFileMessage(account: Account, path: String, kind: String, caption: String) -> EnqueueMessage? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else {
        return nil
    }
    let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: Int64(data.count))
    account.postbox.mediaBox.storeResourceData(resource.id, data: data, synchronous: true)
    let fileName = (path as NSString).lastPathComponent
    let pathExtension = (fileName as NSString).pathExtension.lowercased()

    var dimensions: PixelDimensions?
    if let source = CGImageSourceCreateWithData(data as CFData, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
        if let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            dimensions = PixelDimensions(width: Int32(width), height: Int32(height))
        }
    }

    let media: Media
    if kind == "photo", let dimensions, ["jpg", "jpeg", "png", "heic", "webp"].contains(pathExtension) {
        media = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)), representations: [TelegramMediaImageRepresentation(dimensions: dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
    } else {
        var attributes: [TelegramMediaFileAttribute] = [.FileName(fileName: fileName)]
        let mimeType: String
        switch pathExtension {
        case "mp4", "mov", "m4v":
            mimeType = pathExtension == "mov" ? "video/quicktime" : "video/mp4"
            if kind == "video" || kind == "photo" {
                attributes.append(.Video(duration: 0.0, size: dimensions ?? PixelDimensions(width: 640, height: 640), flags: [.supportsStreaming], preloadSize: nil, coverTime: nil, videoCodec: nil))
            }
        case "gif":
            mimeType = "image/gif"
        case "webp":
            mimeType = "image/webp"
        case "png":
            mimeType = "image/png"
        case "jpg", "jpeg":
            mimeType = "image/jpeg"
        case "zip":
            mimeType = "application/zip"
        default:
            mimeType = "application/octet-stream"
        }
        if let dimensions, mimeType.hasPrefix("image/") {
            attributes.append(.ImageSize(size: dimensions))
        }
        media = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: Int64(data.count), attributes: attributes, alternativeRepresentations: [])
    }
    return .message(text: caption, attributes: [], inlineStickers: [:], mediaReference: .standalone(media: media), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
}

/// Lets plugins send messages from this account. Called for main-app accounts only.
func lumenRegisterAccount(_ account: Account) {
    account.network.lumenAccountPeerId = account.peerId.toInt64()
    let _ = lumenAccounts.modify { current in
        var current = current.filter { $0.value.account != nil }
        current[account.peerId] = LumenWeakAccount(account)
        return current
    }
    if LumenHooks.sendText == nil {
        LumenHooks.sendText = { accountPeerId, dialogId, text in
            lumenEnqueue(accountPeerId: accountPeerId, dialogId: dialogId, makeMessages: { _ in
                return [lumenTextMessage(text)]
            })
        }
    }
    if LumenHooks.sendTLRequest == nil {
        LumenHooks.sendTLRequest = { accountPeerId, json, completion in
            // No account yet (a request from on_plugin_load): use any signed-in one.
            guard let account = lumenAccounts.with({ $0[PeerId(accountPeerId)]?.account ?? $0.values.compactMap({ $0.account }).first }) else {
                completion(nil, 400, "LUMEN_NO_ACCOUNT")
                return
            }
            guard let object = LumenTLJSON.jsonObject(json), let call = LumenTLJSON.functionCall(object) else {
                completion(nil, 400, "LUMEN_BAD_REQUEST")
                return
            }
            let _ = account.network.request(call).start(next: { value in
                let encoded = LumenTLJSON.encodeValue(value).flatMap { LumenTLJSON.jsonString(["result": $0]) }
                completion(encoded ?? "{\"result\": null}", 0, nil)
            }, error: { error in
                completion(nil, error.errorCode, error.errorDescription)
            })
        }
    }
    if LumenHooks.sendFile == nil {
        LumenHooks.sendFile = { accountPeerId, dialogId, path, kind, caption in
            lumenEnqueue(accountPeerId: accountPeerId, dialogId: dialogId, makeMessages: { account in
                guard let message = lumenFileMessage(account: account, path: path, kind: kind, caption: caption) else {
                    return []
                }
                return [message]
            })
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
    let dialogId = lumenDialogId(peerId: peerId)
    return messages.compactMap { message -> EnqueueMessage? in
        guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message, !text.isEmpty else {
            return message
        }
        guard let updatedText = transform(accountPeerId.toInt64(), dialogId, text) else {
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
            result.append(LumenIncomingMessage(
                accountPeerId: accountPeerId.toInt64(),
                peerId: id.peerId.toInt64(),
                dialogId: lumenDialogId(peerId: id.peerId),
                authorId: message.author.flatMap { lumenDialogId(peerId: $0.id) },
                messageId: id.id,
                date: message.timestamp,
                text: message.text,
                chatType: lumenChatType(transaction: transaction, peerId: id.peerId),
                isChannel: id.peerId.namespace == Namespaces.Peer.CloudChannel,
                isOutgoing: !message.flags.contains(.Incoming)
            ))
        }
    }
    if !result.isEmpty {
        observer(result)
    }
}

// MARK: Raw TL hooks (exteraGram's pre_request_hook / post_request_hook / on_update_hook)

/// The Android class name of a request if a plugin subscribed to it, else nil.
func lumenHookedRequestName(network: Network, function: FunctionDescription) -> String? {
    guard network.lumenAccountPeerId != 0, LumenHooks.preRequest != nil, !LumenHooks.tlHookFilter.isEmpty else {
        return nil
    }
    let name = lumenAndroidTLName(function.name)
    return LumenHooks.tlHookFilter.matches(name) ? name : nil
}

/// The request as the plugins leave it: unchanged, rewritten, or failed (cancelled).
func lumenApplyPreRequestHook<T>(accountPeerId: Int64, name: String, data: (FunctionDescription, Buffer, DeserializeFunctionResponse<T>)) -> Signal<(FunctionDescription, Buffer, DeserializeFunctionResponse<T>), MTRpcError> {
    guard let hook = LumenHooks.preRequest, let json = LumenTLJSON.decodeFunction(data.1), let text = LumenTLJSON.jsonString(json) else {
        return .single(data)
    }
    return Signal { subscriber in
        hook(accountPeerId, name, text) { decision in
            switch decision {
            case .keep:
                subscriber.putNext(data)
                subscriber.putCompletion()
            case .cancel:
                subscriber.putError(MTRpcError(errorCode: 400, errorDescription: "LUMEN_PLUGIN_CANCELLED"))
            case let .error(code, text):
                subscriber.putError(MTRpcError(errorCode: code, errorDescription: text))
            case let .replace(updated):
                if let object = LumenTLJSON.jsonObject(updated), let buffer = LumenTLJSON.encodeFunction(object, expectedName: data.0.name) {
                    subscriber.putNext((data.0, buffer, data.2))
                } else {
                    Logger.shared.log("Lumen", "plugin request rewrite of \(name) does not fit the schema; sent unchanged")
                    subscriber.putNext(data)
                }
                subscriber.putCompletion()
            }
        }
        return EmptyDisposable
    }
}

private func lumenParseReplacement<T>(_ updated: String, parse: DeserializeFunctionResponse<T>) -> T? {
    guard let object = LumenTLJSON.jsonObject(updated), let buffer = LumenTLJSON.encodeObject(object) else {
        return nil
    }
    return parse.parse(buffer)
}

/// A response as the plugins leave it.
func lumenApplyPostRequestHook<T>(accountPeerId: Int64, name: String, parse: DeserializeFunctionResponse<T>, result: T) -> Signal<T, MTRpcError> {
    guard let hook = LumenHooks.postRequest, let encoded = LumenTLJSON.encodeValue(result), let text = LumenTLJSON.jsonString(["result": encoded]) else {
        return .single(result)
    }
    return Signal { subscriber in
        hook(accountPeerId, name, text, 0, nil) { decision in
            switch decision {
            case .keep, .cancel:
                subscriber.putNext(result)
                subscriber.putCompletion()
            case let .error(code, text):
                subscriber.putError(MTRpcError(errorCode: code, errorDescription: text))
            case let .replace(updated):
                subscriber.putNext(lumenParseReplacement(updated, parse: parse) ?? result)
                subscriber.putCompletion()
            }
        }
        return EmptyDisposable
    }
}

/// An error response as the plugins leave it: still an error, another error, or a result.
func lumenApplyPostRequestErrorHook<T>(accountPeerId: Int64, name: String, parse: DeserializeFunctionResponse<T>, error: MTRpcError) -> Signal<T, MTRpcError> {
    guard let hook = LumenHooks.postRequest, error.errorDescription != "LUMEN_PLUGIN_CANCELLED" else {
        return .fail(error)
    }
    return Signal { subscriber in
        hook(accountPeerId, name, nil, error.errorCode, error.errorDescription) { decision in
            switch decision {
            case .keep, .cancel:
                subscriber.putError(error)
            case let .error(code, text):
                subscriber.putError(MTRpcError(errorCode: code, errorDescription: text))
            case let .replace(updated):
                if let value = lumenParseReplacement(updated, parse: parse) {
                    subscriber.putNext(value)
                    subscriber.putCompletion()
                } else {
                    subscriber.putError(error)
                }
            }
        }
        return EmptyDisposable
    }
}

/// Runs the plugins' update hooks. New messages are left out: plugins get those through
/// the message-level hook (lumenReportIncomingMessages), which also covers short updates
/// and differences. Updates carrying a pts cannot be dropped without breaking the sequence,
/// so a cancel of one is ignored.
func lumenFilterUpdates(accountPeerId: PeerId, _ updates: [Api.Update]) -> [Api.Update] {
    guard let hook = LumenHooks.update, !LumenHooks.tlHookFilter.isEmpty else {
        return updates
    }
    var result: [Api.Update] = []
    result.reserveCapacity(updates.count)
    for update in updates {
        guard let constructor = LumenTLJSON.constructorName(update), constructor != "updateNewMessage", constructor != "updateNewChannelMessage" else {
            result.append(update)
            continue
        }
        let name = lumenAndroidTLName(constructor)
        guard LumenHooks.tlHookFilter.matches(name), let json = LumenTLJSON.encodeValue(update), let text = LumenTLJSON.jsonString(json) else {
            result.append(update)
            continue
        }
        switch hook(accountPeerId.toInt64(), name, text) {
        case .keep, .error:
            result.append(update)
        case .cancel:
            if LumenTLJSON.constructorHasPts(constructor) {
                result.append(update)
            }
        case let .replace(updated):
            if let object = LumenTLJSON.jsonObject(updated), let parsed = LumenTLJSON.parseObject(object) as? Api.Update {
                result.append(parsed)
            } else {
                result.append(update)
            }
        }
    }
    return result
}
