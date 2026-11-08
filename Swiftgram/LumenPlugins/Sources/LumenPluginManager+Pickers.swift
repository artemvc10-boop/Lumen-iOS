import Foundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers

// MARK: Lumen: what Android plugins get from startActivityForResult — a photo or a file,
// picked with the iOS pickers, copied into the plugin's folder and handed back through
// the plugin's onActivityResult hook. Plus sharing files and screen metrics.

enum LumenScreenInfo {
    // Read on the main queue and cached: the plugin queue must never wait on main (the send
    // hook already waits on the plugin queue from main).
    private static let lock = NSLock()
    private static var cached: [String: Any] = ["width": 390, "height": 844, "statusBar": 47, "bottomInset": 34]

    static func refresh() {
        guard Thread.isMainThread, let window = LumenPresentation.keyWindow() else {
            return
        }
        let value: [String: Any] = [
            "width": Int(window.bounds.width),
            "height": Int(window.bounds.height),
            "statusBar": Int(window.safeAreaInsets.top),
            "bottomInset": Int(window.safeAreaInsets.bottom),
        ]
        self.lock.lock()
        self.cached = value
        self.lock.unlock()
    }

    static func current() -> [String: Any] {
        if Thread.isMainThread {
            self.refresh()
        }
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.cached
    }
}

extension LumenPluginManager {
    func presentPicker(pluginId: String, requestCode: Int, mime: String) {
        let folder = self.dataDirectory(id: pluginId).appendingPathComponent("picked", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let wantsMedia = mime.hasPrefix("image/") || mime.hasPrefix("video/")
        DispatchQueue.main.async {
            let delegate = LumenPickerDelegate(manager: self, requestCode: requestCode, folder: folder)
            self.activePickerDelegate = delegate
            if wantsMedia, #available(iOS 14.0, *) {
                var configuration = PHPickerConfiguration()
                configuration.selectionLimit = 1
                configuration.filter = mime.hasPrefix("video/") ? .videos : (mime == "image/*" ? .any(of: [.images, .videos]) : .images)
                let picker = PHPickerViewController(configuration: configuration)
                picker.delegate = delegate
                LumenPresentation.present(picker)
            } else {
                var types: [UTType] = [.data]
                if mime.contains("zip") {
                    types = [.zip, .data]
                } else if mime.hasPrefix("image/") {
                    types = [.image]
                }
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
                picker.delegate = delegate
                LumenPresentation.present(picker)
            }
        }
    }

    func deliverPickerResult(requestCode: Int, url: URL?, mime: String?) {
        self.queue.async {
            var payload: [String: Any] = ["requestCode": requestCode]
            if let url {
                payload["path"] = url.path
                payload["mime"] = mime ?? "*/*"
            }
            self.hostCall("activity_result", payload)
            self.runDeferred()
            DispatchQueue.main.async {
                self.activePickerDelegate = nil
            }
        }
    }

    func share(urls: [URL], text: String?) {
        DispatchQueue.main.async {
            var items: [Any] = urls
            if let text, !text.isEmpty {
                items.append(text)
            }
            if items.isEmpty {
                return
            }
            guard let top = LumenPresentation.topViewController() else {
                return
            }
            let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1.0, height: 1.0)
            }
            top.present(controller, animated: true)
        }
    }
}

final class LumenPickerDelegate: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    private weak var manager: LumenPluginManager?
    private let requestCode: Int
    private let folder: URL
    private var delivered = false

    init(manager: LumenPluginManager, requestCode: Int, folder: URL) {
        self.manager = manager
        self.requestCode = requestCode
        self.folder = folder
    }

    private func finish(_ url: URL?, mime: String?) {
        if self.delivered {
            return
        }
        self.delivered = true
        self.manager?.deliverPickerResult(requestCode: self.requestCode, url: url, mime: mime)
    }

    /// Copies a temporary file the picker gave us into the plugin's folder.
    private func keep(_ source: URL, preferredExtension: String?) -> URL? {
        var ext = source.pathExtension
        if ext.isEmpty, let preferredExtension {
            ext = preferredExtension
        }
        let name = "picked_\(Int(Date().timeIntervalSince1970 * 1000))" + (ext.isEmpty ? "" : "." + ext.lowercased())
        let target = self.folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.copyItem(at: source, to: target)
            return target
        } catch {
            return nil
        }
    }

    private static func mime(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    @available(iOS 14.0, *)
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            self.finish(nil, mime: nil)
            return
        }
        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            typeIdentifier = UTType.movie.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
            typeIdentifier = UTType.gif.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
            typeIdentifier = UTType.png.identifier
        } else if provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
            typeIdentifier = UTType.jpeg.identifier
        } else {
            typeIdentifier = UTType.image.identifier
        }
        let preferredExtension = UTType(typeIdentifier)?.preferredFilenameExtension
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, _ in
            guard let self else {
                return
            }
            guard let url, let kept = self.keep(url, preferredExtension: preferredExtension) else {
                self.finish(nil, mime: nil)
                return
            }
            // HEIC photos become JPEG, which Android-written plugins expect.
            if kept.pathExtension.lowercased() == "heic", let image = UIImage(contentsOfFile: kept.path), let data = image.jpegData(compressionQuality: 0.92) {
                let jpeg = kept.deletingPathExtension().appendingPathExtension("jpg")
                try? data.write(to: jpeg)
                try? FileManager.default.removeItem(at: kept)
                self.finish(jpeg, mime: "image/jpeg")
                return
            }
            self.finish(kept, mime: LumenPickerDelegate.mime(for: kept))
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            self.finish(nil, mime: nil)
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        let kept = self.keep(url, preferredExtension: nil)
        if accessing {
            url.stopAccessingSecurityScopedResource()
        }
        self.finish(kept, mime: kept.map { LumenPickerDelegate.mime(for: $0) })
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.finish(nil, mime: nil)
    }
}
