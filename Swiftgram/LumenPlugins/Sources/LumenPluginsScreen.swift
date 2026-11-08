import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Display
import LegacyUI
import TelegramPresentationData
import SGSwiftUI
import SGSimpleSettings

// MARK: Lumen plugins screen

@available(iOS 14.0, *)
private struct LumenPluginSettingsView: View {
    let plugin: LumenPluginInfo
    @ObservedObject var manager: LumenPluginManager
    @Environment(\.presentationMode) var presentationMode
    @State private var items: [LumenPluginSettingItem] = []

    var body: some View {
        NavigationView {
            Form {
                if !plugin.description.isEmpty {
                    Section {
                        Text(plugin.description).font(.footnote).foregroundColor(.secondary)
                    }
                }
                if items.isEmpty {
                    Section {
                        Text("У плагина нет настроек").foregroundColor(.secondary)
                    }
                }
                LumenSettingsItemList(pluginId: plugin.id, items: items, manager: manager)
            }
            .navigationBarTitle(Text(plugin.name), displayMode: .inline)
            .navigationBarItems(trailing: Button("Готово") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                items = manager.settingsItems(id: plugin.id)
            }
        }
    }
}

@available(iOS 14.0, *)
private struct LumenSettingsItemList: View {
    let pluginId: String
    let items: [LumenPluginSettingItem]
    @ObservedObject var manager: LumenPluginManager

    var body: some View {
        let groups = groupedSections()
        return ForEach(groups.indices, id: \.self) { index in
            section(groups[index])
        }
    }

    @ViewBuilder
    private func section(_ group: Group) -> some View {
        if let header = group.header, let footer = group.footer {
            Section(header: Text(header), footer: Text(footer)) { rows(group) }
        } else if let header = group.header {
            Section(header: Text(header)) { rows(group) }
        } else if let footer = group.footer {
            Section(footer: Text(footer)) { rows(group) }
        } else {
            Section { rows(group) }
        }
    }

    private func rows(_ group: Group) -> some View {
        ForEach(group.rows) { item in
            LumenPluginSettingRow(pluginId: pluginId, item: item, manager: manager)
        }
    }

    private struct Group {
        var header: String?
        var footer: String?
        var rows: [LumenPluginSettingItem]
    }

    private func groupedSections() -> [Group] {
        var groups: [Group] = []
        var current = Group(header: nil, footer: nil, rows: [])
        for item in items {
            switch item.type {
            case "header":
                if !current.rows.isEmpty || current.header != nil {
                    groups.append(current)
                }
                current = Group(header: item.text, footer: nil, rows: [])
            case "divider":
                current.footer = item.text.isEmpty ? nil : item.text
                groups.append(current)
                current = Group(header: nil, footer: nil, rows: [])
            default:
                current.rows.append(item)
            }
        }
        if !current.rows.isEmpty || current.header != nil {
            groups.append(current)
        }
        return groups
    }
}

@available(iOS 14.0, *)
private struct LumenPluginSettingRow: View {
    let pluginId: String
    let item: LumenPluginSettingItem
    @ObservedObject var manager: LumenPluginManager
    @State private var text: String = ""
    @State private var isOn: Bool = false
    @State private var selection: Int = 0

    var body: some View {
        switch item.type {
        case "switch":
            Toggle(isOn: Binding(get: { isOn }, set: { value in
                isOn = value
                if let key = item.key {
                    manager.setSettingValue(id: pluginId, key: key, value: value)
                    manager.fireSettingEvent(id: pluginId, handle: item.handle, value: value)
                }
            })) {
                settingLabel
            }
            .onAppear {
                if let key = item.key {
                    isOn = (manager.settingValue(id: pluginId, key: key) as? Bool) ?? item.defaultBool ?? false
                }
            }
        case "input", "edit_text":
            VStack(alignment: .leading, spacing: 4.0) {
                if !item.text.isEmpty {
                    Text(item.text).font(.footnote).foregroundColor(.secondary)
                }
                TextField(item.text, text: $text, onCommit: { commitText() })
            }
            .onAppear {
                if let key = item.key {
                    text = (manager.settingValue(id: pluginId, key: key) as? String) ?? item.defaultString ?? ""
                }
            }
            .onDisappear { commitText() }
        case "selector":
            Picker(item.text, selection: Binding(get: { selection }, set: { value in
                selection = value
                if let key = item.key {
                    manager.setSettingValue(id: pluginId, key: key, value: value)
                    manager.fireSettingEvent(id: pluginId, handle: item.handle, value: value)
                }
            })) {
                ForEach(item.items.indices, id: \.self) { i in
                    Text(item.items[i]).tag(i)
                }
            }
            .onAppear {
                if let key = item.key {
                    selection = (manager.settingValue(id: pluginId, key: key) as? Int) ?? item.defaultInt ?? 0
                }
            }
        case "text":
            Button(action: {
                manager.fireSettingEvent(id: pluginId, handle: item.handle, value: nil)
            }) {
                HStack {
                    Text(item.text).foregroundColor(item.red ? .red : .accentColor)
                    Spacer()
                    if item.hasSubpage {
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .disabled(!item.clickable && !item.hasSubpage)
        default:
            EmptyView()
        }
    }

    private var settingLabel: some View {
        VStack(alignment: .leading, spacing: 2.0) {
            Text(item.text)
            if let subtext = item.subtext, !subtext.isEmpty {
                Text(subtext).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func commitText() {
        if let key = item.key {
            manager.setSettingValue(id: pluginId, key: key, value: text)
            manager.fireSettingEvent(id: pluginId, handle: item.handle, value: text)
        }
    }
}

@available(iOS 14.0, *)
struct LumenPluginsView: View {
    @ObservedObject var manager: LumenPluginManager
    @State private var isImporting = false
    @State private var settingsPlugin: LumenPluginInfo?
    @State private var unverified = LumenSettings.shared.allowUnverifiedPlugins
    @State private var showUnverifiedWarning = false

    var body: some View {
        List {
            Section(header: Text("ПЛАГИНЫ"), footer: Text("Плагины формата .plugin (как в exteraGram) на Python. Они видят ваши сообщения и то, что вы отправляете. Устанавливайте только те, которым доверяете.")) {
                if manager.plugins.isEmpty {
                    Text("Плагинов пока нет").foregroundColor(.secondary)
                }
                ForEach(manager.plugins) { plugin in
                    pluginRow(plugin)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        manager.remove(id: manager.plugins[index].id)
                    }
                }
                Button {
                    isImporting = true
                } label: {
                    Label("Установить из файла", systemImage: "plus")
                }
            }

            Section(footer: Text("Непроверенные источники — это любой файл не из каталога Lumen. Плагин на Python может читать ваши сообщения, файлы и обращаться в сеть. Включайте, только если доверяете источнику: вся ответственность на вас.")) {
                Toggle(isOn: Binding(get: { unverified }, set: { value in
                    if value {
                        showUnverifiedWarning = true
                    } else {
                        unverified = false
                        LumenSettings.shared.set(false, for: .allowUnverifiedPlugins)
                    }
                })) {
                    Text("Непроверенные источники")
                }
            }

            Section(header: Text("ЖУРНАЛ")) {
                if manager.logLines.isEmpty {
                    Text("Пусто").foregroundColor(.secondary)
                } else {
                    Button("Очистить журнал") { manager.clearLog() }.font(.footnote)
                }
                ForEach(Array(manager.logLines.suffix(50).reversed().enumerated()), id: \.offset) { item in
                    Text(item.element).font(.system(.caption, design: .monospaced))
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .fileImporter(isPresented: $isImporting, allowedContentTypes: lumenPluginContentTypes, allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                LumenInstallCoordinator.present(fileURL: url)
            }
        }
        .sheet(item: $settingsPlugin) { plugin in
            LumenPluginSettingsView(plugin: plugin, manager: manager)
        }
        .alert(isPresented: $showUnverifiedWarning) {
            Alert(
                title: Text("Это опасно"),
                message: Text("Плагин из непроверенного источника может читать и отправлять ваши сообщения, читать файлы и обращаться в сеть. Включая это, вы берёте ответственность на себя."),
                primaryButton: .destructive(Text("Понимаю, включить")) {
                    unverified = true
                    LumenSettings.shared.set(true, for: .allowUnverifiedPlugins)
                },
                secondaryButton: .cancel(Text("Отмена")) {
                    unverified = false
                }
            )
        }
        .onAppear {
            manager.start()
            unverified = LumenSettings.shared.allowUnverifiedPlugins
        }
    }

    private func pluginRow(_ plugin: LumenPluginInfo) -> some View {
        VStack(alignment: .leading, spacing: 4.0) {
            Toggle(isOn: Binding(get: { plugin.isEnabled }, set: { value in
                manager.setEnabled(id: plugin.id, enabled: value)
            })) {
                VStack(alignment: .leading, spacing: 2.0) {
                    HStack(spacing: 6.0) {
                        Text(plugin.name).font(.headline)
                        if plugin.isNative {
                            Text("встроенный").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    let meta = [plugin.version.isEmpty ? nil : "v" + plugin.version, plugin.author.isEmpty ? nil : plugin.author].compactMap { $0 }.joined(separator: " · ")
                    if !meta.isEmpty {
                        Text(meta).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            if !plugin.description.isEmpty {
                Text(plugin.description).font(.footnote).foregroundColor(.secondary)
            }
            if let error = plugin.error, plugin.isEnabled {
                Text("⚠️ " + error).font(.footnote).foregroundColor(.red)
            }
            if plugin.isEnabled {
                Button("Настройки") { settingsPlugin = plugin }.font(.footnote)
            }
        }
        .padding(.vertical, 4.0)
    }
}

@available(iOS 14.0, *)
var lumenPluginContentTypes: [UTType] {
    var types: [UTType] = []
    if let plugin = UTType(filenameExtension: "plugin") {
        types.append(plugin)
    }
    types.append(contentsOf: [UTType.pythonScript, UTType.plainText, UTType.data])
    return types
}

extension UTType {
    static var pythonScript: UTType {
        return UTType(filenameExtension: "py") ?? UTType.plainText
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
