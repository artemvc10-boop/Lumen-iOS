import Foundation
import UIKit
import SwiftUI

// MARK: Lumen: renders a plugin's declarative screen (lumen/ui.py) as a native iOS screen —
// lists, forms, grids, search — and sends taps, edits and selections back. This is how a full
// plugin interface ships as a .plugin file, with no app rebuild.

@available(iOS 15.0, *)
final class LumenPluginScreenModel: ObservableObject {
    let screenId: String
    let pluginId: String
    @Published var spec: [String: Any]
    @Published var searchText: String = ""
    private weak var manager: LumenPluginManager?

    init(screenId: String, pluginId: String, spec: [String: Any], manager: LumenPluginManager?) {
        self.screenId = screenId
        self.pluginId = pluginId
        self.spec = spec
        self.manager = manager
        self.searchText = spec["searchText"] as? String ?? ""
    }

    func send(type: String, id: String?, value: Any? = nil) {
        self.manager?.sendScreenEvent(screenId: self.screenId, pluginId: self.pluginId, type: type, id: id, value: value)
    }

    func imageURL(_ path: String) -> URL? {
        return self.manager?.resolveImagePath(path, pluginId: self.pluginId)
    }
}

@available(iOS 15.0, *)
struct LumenPluginScreenView: View {
    @ObservedObject var model: LumenPluginScreenModel
    let close: () -> Void

    private var sections: [[String: Any]] {
        return model.spec["sections"] as? [[String: Any]] ?? []
    }

    var body: some View {
        NavigationView {
            content
                .navigationTitle(model.spec["title"] as? String ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Закрыть") { close() }
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        ForEach(toolbarItems.indices, id: \.self) { index in
                            let item = toolbarItems[index]
                            Button {
                                model.send(type: "tap", id: item["id"] as? String)
                            } label: {
                                Image(systemName: item["icon"] as? String ?? "ellipsis")
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let button = model.spec["bottomButton"] as? [String: Any], let title = button["title"] as? String {
                        Button {
                            model.send(type: "tap", id: button["id"] as? String)
                        } label: {
                            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background((button["style"] as? String == "destructive") ? Color.red : Color.accentColor)
                                .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                }
        }
        .navigationViewStyle(.stack)
    }

    private var toolbarItems: [[String: Any]] {
        return model.spec["toolbar"] as? [[String: Any]] ?? []
    }

    @ViewBuilder
    private var content: some View {
        let list = List {
            ForEach(sections.indices, id: \.self) { index in
                sectionView(sections[index])
            }
        }
        .listStyle(.insetGrouped)
        if (model.spec["search"] as? Bool) == true {
            list.searchable(text: Binding(get: { model.searchText }, set: { value in
                model.searchText = value
                model.send(type: "search", id: nil, value: value)
            }), prompt: model.spec["searchPrompt"] as? String ?? "Поиск")
        } else {
            list
        }
    }

    @ViewBuilder
    private func sectionView(_ section: [String: Any]) -> some View {
        let rows = section["rows"] as? [[String: Any]] ?? []
        Section {
            ForEach(rows.indices, id: \.self) { index in
                rowView(rows[index])
            }
        } header: {
            if let header = section["header"] as? String { Text(header) }
        } footer: {
            if let footer = section["footer"] as? String { Text(footer) }
        }
    }

    @ViewBuilder
    private func rowView(_ row: [String: Any]) -> some View {
        let id = row["id"] as? String
        switch row["type"] as? String {
        case "switch":
            LumenScreenSwitchRow(row: row) { value in model.send(type: "toggle", id: id, value: value) }
        case "input":
            LumenScreenInputRow(row: row) { value in model.send(type: "input", id: id, value: value) }
        case "button":
            Button {
                model.send(type: "tap", id: id)
            } label: {
                Text(row["title"] as? String ?? "")
                    .foregroundColor((row["style"] as? String == "destructive") ? .red : .accentColor)
            }
        case "selector":
            LumenScreenSelectorRow(row: row) { value in model.send(type: "toggle", id: id, value: value) }
        case "grid":
            LumenScreenGridRow(row: row, model: model)
        case "chips":
            LumenScreenChipsRow(row: row) { value in model.send(type: "select", id: id, value: value) }
        case "image":
            if let path = row["image"] as? String {
                LumenMemeThumbnail(url: model.imageURL(path) ?? URL(fileURLWithPath: path), isVideo: false)
                    .frame(height: CGFloat(row["height"] as? Int ?? 200))
                    .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 10)).listRowInsets(EdgeInsets())
            }
        default:
            LumenScreenTextRow(row: row) { model.send(type: "tap", id: id) }
        }
    }
}

// MARK: Rows

@available(iOS 15.0, *)
private struct LumenScreenTextRow: View {
    let row: [String: Any]
    let onTap: () -> Void

    var body: some View {
        let accessory = row["accessory"] as? String
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let icon = row["icon"] as? String {
                    Image(systemName: icon).frame(width: 24).foregroundColor(.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row["title"] as? String ?? "")
                        .foregroundColor((row["destructive"] as? Bool == true) ? .red : .primary)
                    if let subtitle = row["subtitle"] as? String, !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let value = row["value"] as? String, !value.isEmpty {
                    Text(value).foregroundColor(.secondary)
                }
                if accessory == "chevron" {
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(accessory == "none" && row["value"] == nil)
    }
}

@available(iOS 15.0, *)
private struct LumenScreenSwitchRow: View {
    let row: [String: Any]
    let onChange: (Bool) -> Void
    @State private var isOn: Bool

    init(row: [String: Any], onChange: @escaping (Bool) -> Void) {
        self.row = row
        self.onChange = onChange
        self._isOn = State(initialValue: row["value"] as? Bool ?? false)
    }

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { value in isOn = value; onChange(value) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row["title"] as? String ?? "")
                if let subtitle = row["subtitle"] as? String, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}

@available(iOS 15.0, *)
private struct LumenScreenInputRow: View {
    let row: [String: Any]
    let onChange: (String) -> Void
    @State private var text: String

    init(row: [String: Any], onChange: @escaping (String) -> Void) {
        self.row = row
        self.onChange = onChange
        self._text = State(initialValue: row["value"] as? String ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = row["title"] as? String, !title.isEmpty {
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            TextField(row["placeholder"] as? String ?? "", text: Binding(get: { text }, set: { value in
                text = value
                onChange(value)
            }))
        }
    }
}

@available(iOS 15.0, *)
private struct LumenScreenSelectorRow: View {
    let row: [String: Any]
    let onChange: (Int) -> Void
    @State private var selection: Int

    init(row: [String: Any], onChange: @escaping (Int) -> Void) {
        self.row = row
        self.onChange = onChange
        self._selection = State(initialValue: row["value"] as? Int ?? 0)
    }

    var body: some View {
        let options = row["options"] as? [String] ?? []
        Picker(row["title"] as? String ?? "", selection: Binding(get: { selection }, set: { value in
            selection = value
            onChange(value)
        })) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index]).tag(index)
            }
        }
    }
}

@available(iOS 15.0, *)
private struct LumenScreenChipsRow: View {
    let row: [String: Any]
    let onSelect: (String) -> Void

    var body: some View {
        let options = row["options"] as? [[String: Any]] ?? []
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    let active = option["selected"] as? Bool ?? false
                    Button {
                        onSelect(option["id"] as? String ?? "")
                    } label: {
                        Text(option["title"] as? String ?? "")
                            .font(.system(size: 14, weight: .medium)).lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(active ? Color.accentColor : Color(UIColor.secondarySystemFill))
                            .foregroundColor(active ? .white : .primary).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }
}

@available(iOS 15.0, *)
private struct LumenScreenGridRow: View {
    let row: [String: Any]
    @ObservedObject var model: LumenPluginScreenModel

    var body: some View {
        let items = row["items"] as? [[String: Any]] ?? []
        let columns = max(1, row["columns"] as? Int ?? 3)
        let height = CGFloat(row["itemHeight"] as? Int ?? 112)
        let grid = Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
        LazyVGrid(columns: grid, spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                gridCell(items[index], height: height)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }

    @ViewBuilder
    private func gridCell(_ item: [String: Any], height: CGFloat) -> some View {
        let selected = item["selected"] as? Bool ?? false
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let path = item["image"] as? String {
                    LumenMemeThumbnail(url: model.imageURL(path) ?? URL(fileURLWithPath: path), isVideo: item["video"] as? Bool ?? false)
                        .frame(height: height).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.secondarySystemFill)).frame(height: height)
                }
                if let badge = item["badge"] as? String, !badge.isEmpty {
                    Text(badge).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        .frame(width: 24, height: 24).background(Circle().fill(Color.accentColor)).padding(6)
                }
            }
            if let label = item["label"] as? String, !label.isEmpty {
                Text(label).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.send(type: "tap", id: item["id"] as? String)
        }
        .onLongPressGesture {
            model.send(type: "longtap", id: item["id"] as? String)
        }
    }
}

// MARK: Presentation (manager side)

@available(iOS 15.0, *)
final class LumenPluginScreenController: UIHostingController<LumenPluginScreenView> {
    let model: LumenPluginScreenModel

    init(model: LumenPluginScreenModel, close: @escaping () -> Void) {
        self.model = model
        super.init(rootView: LumenPluginScreenView(model: model, close: close))
        self.modalPresentationStyle = .pageSheet
        if let sheet = self.sheetPresentationController {
            // A "medium" detent leaves the screen behind (e.g. a profile) visible so plugin
            // changes show live while editing.
            if (model.spec["detent"] as? String) == "medium" {
                sheet.detents = [.medium(), .large()]
                sheet.largestUndimmedDetentIdentifier = .medium
            } else {
                sheet.detents = [.large()]
            }
            sheet.prefersGrabberVisible = true
        }
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension LumenPluginManager {
    func sendScreenEvent(screenId: String, pluginId: String, type: String, id: String?, value: Any?) {
        self.queue.async {
            var payload: [String: Any] = ["screenId": screenId, "plugin": pluginId, "type": type]
            if let id {
                payload["id"] = id
            }
            if let value {
                payload["value"] = value
            }
            self.hostCall("screen_event", payload)
            self.runDeferred()
        }
    }

    func presentScreen(pluginId: String, spec: [String: Any]) {
        guard let screenId = spec["screenId"] as? String else {
            return
        }
        self.activeViewPluginId = pluginId
        DispatchQueue.main.async {
            guard #available(iOS 15.0, *) else {
                return
            }
            let model = LumenPluginScreenModel(screenId: screenId, pluginId: pluginId, spec: spec, manager: self)
            let controller = LumenPluginScreenController(model: model, close: { [weak self] in
                self?.dismissScreen(id: screenId)
            })
            self.presentedScreens[screenId] = model
            self.screenControllers[screenId] = controller
            LumenPresentation.present(controller)
        }
    }

    func updateScreen(id: String, spec: [String: Any]) {
        DispatchQueue.main.async {
            guard #available(iOS 15.0, *), let model = self.presentedScreens[id] as? LumenPluginScreenModel else {
                return
            }
            model.spec = spec
            if let search = spec["searchText"] as? String, search != model.searchText {
                model.searchText = search
            }
        }
    }

    func dismissScreen(id: String) {
        DispatchQueue.main.async {
            self.screenControllers[id]?.dismiss(animated: true)
            self.screenControllers[id] = nil
            self.presentedScreens[id] = nil
        }
        self.queue.async {
            self.hostCall("screen_event", ["screenId": id, "type": "dismiss"])
        }
    }
}
