import Foundation
import UIKit
import SwiftUI
import SGSimpleSettings

// MARK: Lumen: the sheet shown before a .plugin is installed — tapped in a chat, or picked
// from a file. It shows what the plugin is and what it can reach, and makes the person turn
// on unverified sources (with a warning) before a plugin from outside the catalog goes in.

public enum LumenInstallCoordinator {
    public static func present(fileURL: URL) {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        let source = try? String(contentsOf: fileURL, encoding: .utf8)
        if accessing {
            fileURL.stopAccessingSecurityScopedResource()
        }
        guard let source else {
            LumenToast.show("Не удалось прочитать файл", kind: .error)
            return
        }
        present(source: source, suggestedName: fileURL.deletingPathExtension().lastPathComponent)
    }

    public static func present(source: String, suggestedName: String) {
        DispatchQueue.main.async {
            guard #available(iOS 14.0, *) else {
                LumenToast.show("Плагины требуют iOS 14+", kind: .error)
                return
            }
            let meta = LumenPluginMetadata.parse(source: source, fallbackId: suggestedName)
            let notes = LumenPluginNotes.summarize(source: source)
            let view = LumenInstallSheet(meta: meta, notes: notes, source: source)
            let controller = UIHostingController(rootView: view)
            if #available(iOS 15.0, *), let sheet = controller.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
            LumenPresentation.present(controller)
        }
    }
}

@available(iOS 14.0, *)
private struct LumenInstallSheet: View {
    let meta: LumenPluginMetadata
    let notes: LumenPluginNotes
    let source: String
    @Environment(\.presentationMode) var presentationMode
    @State private var showUnverifiedWarning = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6.0) {
                        Text(meta.name).font(.title3).bold()
                        let line = [meta.version.isEmpty ? nil : "v" + meta.version, meta.author.isEmpty ? nil : meta.author].compactMap { $0 }.joined(separator: " · ")
                        if !line.isEmpty {
                            Text(line).font(.caption).foregroundColor(.secondary)
                        }
                        if !meta.description.isEmpty {
                            Text(meta.description).font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4.0)
                }

                Section(header: Text("ДОСТУП")) {
                    if notes.access.isEmpty {
                        accessRow("checkmark.shield", "Только меню и настройки", .green)
                    } else {
                        ForEach(notes.access, id: \.self) { item in
                            accessLine(item)
                        }
                    }
                    if notes.willNotRun {
                        accessRow("exclamationmark.triangle", "Использует синтаксис, который Lumen не выполнит — плагин может не заработать", .orange)
                    }
                }

                Section(footer: Text("Непроверенный источник — файл не из каталога Lumen. Проверьте, что доверяете автору.")) {
                    HStack {
                        Image(systemName: "questionmark.shield").foregroundColor(.orange)
                        Text("Непроверенный источник").font(.footnote)
                    }
                }

                Section {
                    Button {
                        install()
                    } label: {
                        Text("Установить и включить").bold()
                    }
                }
            }
            .navigationBarTitle(Text("Установка плагина"), displayMode: .inline)
            .navigationBarItems(trailing: Button("Отмена") {
                presentationMode.wrappedValue.dismiss()
            })
            .alert(isPresented: $showUnverifiedWarning) {
                Alert(
                    title: Text("Это опасно"),
                    message: Text("Плагин из непроверенного источника может читать и отправлять ваши сообщения, читать файлы и обращаться в сеть. Устанавливая, вы берёте ответственность на себя."),
                    primaryButton: .destructive(Text("Установить")) {
                        LumenSettings.shared.set(true, for: .allowUnverifiedPlugins)
                        doInstall()
                    },
                    secondaryButton: .cancel(Text("Отмена"))
                )
            }
        }
    }

    private func accessLine(_ item: LumenPluginNotes.Access) -> some View {
        switch item {
        case .network:
            return accessRow("network", "Выход в интернет", .orange)
        case .files:
            return accessRow("folder", "Чтение и запись файлов", .orange)
        case .sending:
            return accessRow("paperplane", "Отправка сообщений и файлов от вашего имени", .orange)
        case .clipboard:
            return accessRow("doc.on.clipboard", "Буфер обмена", .secondary)
        case .androidOnly:
            return accessRow("xmark.circle", "Часть для Android — на iPhone не работает", .secondary)
        }
    }

    private func accessRow(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 10.0) {
            Image(systemName: icon).foregroundColor(color).frame(width: 22.0)
            Text(text).font(.footnote)
        }
    }

    private func install() {
        if LumenSettings.shared.allowUnverifiedPlugins {
            doInstall()
        } else {
            showUnverifiedWarning = true
        }
    }

    private func doInstall() {
        LumenPluginManager.shared.install(source: source, suggestedName: meta.id, enable: true) { installed in
            LumenToast.show("Плагин «\(installed.name)» установлен", kind: .success)
        }
        presentationMode.wrappedValue.dismiss()
    }
}
