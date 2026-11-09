import Foundation
import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: Lumen: meme_library.plugin implemented natively for iOS. Installing the plugin (or
// enabling it in the list) turns this on instead of running its Android interface.

final class LumenMemeLibraryPlugin: LumenNativePlugin {
    let pluginId = LumenMemeStore.pluginId
    private weak var manager: LumenPluginManager?
    private let store: LumenMemeStore

    private enum Item: String {
        case save = "meme_library:save"
        case library = "meme_library:library"
    }

    private enum Setting: Int {
        case export = 1
        case importZip
        case resetTutorial
        case clear
    }

    init(manager: LumenPluginManager) {
        self.manager = manager
        self.store = LumenMemeStore(manager: manager)
    }

    func menuItems() -> [LumenPluginMenuItem] {
        return [
            LumenPluginMenuItem(pluginId: self.pluginId, itemId: Item.save.rawValue, kind: .message, title: "Сохранить в мемы", subtitle: "Локально"),
            LumenPluginMenuItem(pluginId: self.pluginId, itemId: Item.library.rawValue, kind: .chat, title: "Библиотека мемов", subtitle: nil),
        ]
    }

    func performMenuItem(itemId: String, context: LumenPluginMessageContext) {
        guard #available(iOS 15.0, *) else {
            LumenToast.show("Библиотека мемов работает на iOS 15 и новее", kind: .error)
            return
        }
        guard let item = Item(rawValue: itemId) else {
            return
        }
        switch item {
        case .save:
            guard let path = context.mediaPath, FileManager.default.fileExists(atPath: path) else {
                LumenToast.show("Файл не найден. Откройте медиа, чтобы оно скачалось.", kind: .error)
                return
            }
            self.presentSaveForm(url: URL(fileURLWithPath: path), sourceDialogId: context.dialogId, sourceMessageId: context.messageId)
        case .library:
            self.openLibrary(dialogId: context.dialogId, accountPeerId: context.accountPeerId, replyToMessageId: context.replyToMessageId)
        }
    }

    @available(iOS 15.0, *)
    func openLibrary(dialogId: Int64, accountPeerId: Int64, replyToMessageId: Int32 = 0) {
        let store = self.store
        store.reload()
        var hosting: UIViewController?
        let view = LumenMemeLibraryView(store: store, dialogId: dialogId, accountPeerId: accountPeerId, replyToMessageId: replyToMessageId, close: {
            hosting?.dismiss(animated: true)
        })
        let controller = UIHostingController(rootView: view)
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        hosting = controller
        LumenPresentation.present(controller)
    }

    @available(iOS 15.0, *)
    private func presentSaveForm(url: URL, sourceDialogId: Int64 = 0, sourceMessageId: Int32 = 0) {
        let store = self.store
        store.reload()
        let view = LumenMemeFormView(title: "Сохранить в мемы", imageURL: url, categories: store.categories, category: "", description: "") { category, description in
            do {
                try store.add(source: url, category: category, description: description, sourceDialogId: sourceDialogId, sourceMessageId: sourceMessageId)
                LumenToast.show("Мем сохранён!", kind: .success)
            } catch LumenMemeStore.SaveError.categoryLimit {
                LumenToast.show("Лимит категорий (\(LumenMemeStore.maxCategories)) достигнут", kind: .error)
            } catch {
                LumenToast.show("Не удалось сохранить мем", kind: .error)
            }
        }
        let controller = UIHostingController(rootView: view)
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        LumenPresentation.present(controller)
    }

    // MARK: Settings page

    func settingsItems() -> [LumenPluginSettingItem] {
        func text(_ handle: Setting, _ title: String, red: Bool = false) -> LumenPluginSettingItem {
            return LumenPluginSettingItem(handle: handle.rawValue, type: "text", key: nil, text: title, subtext: nil, defaultBool: nil, defaultString: nil, defaultInt: nil, items: [], red: red, clickable: true, hasSubpage: false, multiline: false)
        }
        func header(_ handle: Int, _ title: String) -> LumenPluginSettingItem {
            return LumenPluginSettingItem(handle: handle, type: "header", key: nil, text: title, subtext: nil, defaultBool: nil, defaultString: nil, defaultInt: nil, items: [], red: false, clickable: false, hasSubpage: false, multiline: false)
        }
        func divider(_ handle: Int, _ title: String) -> LumenPluginSettingItem {
            return LumenPluginSettingItem(handle: handle, type: "divider", key: nil, text: title, subtext: nil, defaultBool: nil, defaultString: nil, defaultInt: nil, items: [], red: false, clickable: false, hasSubpage: false, multiline: false)
        }
        let count = self.store.memes.count
        return [
            header(100, "Библиотека (\(count))"),
            text(.export, "Экспортировать библиотеку"),
            text(.importZip, "Импортировать библиотеку"),
            divider(101, "ZIP совместим с Android-версией плагина. Экспорт сохраняется в «Файлы» → На iPhone → Lumen → Download."),
            header(102, "Прочее"),
            text(.resetTutorial, "Сбросить туториал"),
            text(.clear, "Очистить библиотеку", red: true),
        ]
    }

    func handleSettingEvent(handle: Int, value: Any?) {
        guard let setting = Setting(rawValue: handle) else {
            return
        }
        DispatchQueue.main.async {
            switch setting {
            case .export:
                if let url = self.store.exportZip() {
                    LumenToast.show("Готово: \(self.store.memes.count) мемов", kind: .success)
                    LumenPresentation.share(fileURL: url)
                } else {
                    LumenToast.show("Библиотека пуста — нечего экспортировать", kind: .info)
                }
            case .importZip:
                self.presentImportPicker()
            case .resetTutorial:
                self.store.tutorialDone = false
                LumenToast.show("Туториал сброшен", kind: .success)
            case .clear:
                let memes = self.store.memes.count
                let categories = self.store.categories.count
                let alert = UIAlertController(title: "Очистить библиотеку?", message: "Будут удалены \(memes) мемов и \(categories) категорий.\nЭто действие нельзя отменить.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { _ in
                    self.store.clear()
                    LumenToast.show("Библиотека очищена", kind: .success)
                })
                LumenPresentation.present(alert)
            }
        }
    }

    private var importDelegate: LumenMemeImportDelegate?

    private func presentImportPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip], asCopy: true)
        let delegate = LumenMemeImportDelegate { [weak self] url in
            guard let self, let url else {
                return
            }
            do {
                let added = try self.store.importZip(url)
                LumenToast.show("Импортировано: \(added) мемов", kind: .success)
            } catch {
                LumenToast.show("Ошибка: в ZIP нет memes_db.json или он повреждён", kind: .error)
            }
            self.importDelegate = nil
        }
        self.importDelegate = delegate
        picker.delegate = delegate
        LumenPresentation.present(picker)
    }
}

final class LumenMemeImportDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion(nil)
    }
}
