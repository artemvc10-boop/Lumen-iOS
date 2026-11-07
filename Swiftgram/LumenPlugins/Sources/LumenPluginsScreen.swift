import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Display
import LegacyUI
import TelegramPresentationData
import SGSwiftUI

// MARK: Lumen plugins screen

@available(iOS 14.0, *)
private struct LumenPluginSettingsView: View {
    let plugin: LumenPluginInfo
    @ObservedObject var manager: LumenPluginManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                if !plugin.description.isEmpty {
                    Section {
                        Text(plugin.description)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                if plugin.settings.isEmpty {
                    Section {
                        Text("У плагина нет настроек")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section {
                        ForEach(plugin.settings) { setting in
                            LumenPluginSettingRow(pluginId: plugin.id, setting: setting, manager: manager)
                        }
                    }
                }
            }
            .navigationBarTitle(Text(plugin.name), displayMode: .inline)
            .navigationBarItems(trailing: Button("Готово") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

@available(iOS 14.0, *)
private struct LumenPluginSettingRow: View {
    let pluginId: String
    let setting: LumenPluginSetting
    @ObservedObject var manager: LumenPluginManager
    @State private var text: String = ""
    @State private var isOn: Bool = false

    var body: some View {
        switch setting.kind {
        case .toggle:
            Toggle(setting.title, isOn: Binding(get: {
                return isOn
            }, set: { value in
                isOn = value
                manager.setSettingValue(id: pluginId, key: setting.key, value: value)
            }))
            .onAppear {
                isOn = (manager.settingValue(id: pluginId, key: setting.key) as? Bool) ?? false
            }
        case .text:
            VStack(alignment: .leading, spacing: 4.0) {
                Text(setting.title)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                TextField(setting.title, text: $text, onCommit: {
                    manager.setSettingValue(id: pluginId, key: setting.key, value: text)
                })
            }
            .onAppear {
                text = (manager.settingValue(id: pluginId, key: setting.key) as? String) ?? ""
            }
            .onDisappear {
                manager.setSettingValue(id: pluginId, key: setting.key, value: text)
            }
        }
    }
}

@available(iOS 14.0, *)
private struct LumenPluginsView: View {
    @ObservedObject var manager: LumenPluginManager
    @State private var isImporting = false
    @State private var settingsPlugin: LumenPluginInfo?

    var body: some View {
        List {
            Section(header: Text("ПЛАГИНЫ"), footer: Text("Плагины на JavaScript: перехват отправки, ответы на входящие, пункты в меню сообщения (долгое нажатие → Lumen). Устанавливайте только плагины, которым доверяете: они видят ваши сообщения.")) {
                if manager.plugins.isEmpty {
                    Text("Плагинов пока нет")
                        .foregroundColor(.secondary)
                }
                ForEach(manager.plugins) { plugin in
                    VStack(alignment: .leading, spacing: 4.0) {
                        Toggle(isOn: Binding(get: {
                            return plugin.isEnabled
                        }, set: { value in
                            manager.setEnabled(id: plugin.id, enabled: value)
                        })) {
                            VStack(alignment: .leading, spacing: 2.0) {
                                Text(plugin.name)
                                    .font(.headline)
                                let meta = [plugin.version.isEmpty ? nil : "v" + plugin.version, plugin.author.isEmpty ? nil : plugin.author].compactMap { $0 }.joined(separator: " · ")
                                if !meta.isEmpty {
                                    Text(meta)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        if !plugin.description.isEmpty {
                            Text(plugin.description)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        if let error = plugin.error, plugin.isEnabled {
                            Text("⚠️ " + error)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                        if plugin.isEnabled && !plugin.settings.isEmpty {
                            Button("Настройки") {
                                settingsPlugin = plugin
                            }
                            .font(.footnote)
                        }
                    }
                    .padding(.vertical, 4.0)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        manager.remove(id: manager.plugins[index].id)
                    }
                }
                Button("Установить из файла (.js)") {
                    isImporting = true
                }
            }
            Section(header: Text("ЖУРНАЛ")) {
                if manager.log.isEmpty {
                    Text("Пусто")
                        .foregroundColor(.secondary)
                }
                ForEach(Array(manager.log.suffix(50).reversed().enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [UTType.javaScript, UTType.plainText, UTType.data], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                manager.install(from: url)
            }
        }
        .sheet(item: $settingsPlugin) { plugin in
            LumenPluginSettingsView(plugin: plugin, manager: manager)
        }
        .onAppear {
            manager.start()
        }
    }
}

@available(iOS 14.0, *)
public func lumenPluginsController(presentationData: PresentationData) -> ViewController {
    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: presentationData.theme,
        strings: presentationData.strings
    )
    legacyController.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
    legacyController.title = "Плагины"

    let swiftUIView = SGSwiftUIView<LumenPluginsView>(
        legacyController: legacyController,
        manageSafeArea: true,
        content: {
            LumenPluginsView(manager: LumenPluginManager.shared)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)
    return legacyController
}
