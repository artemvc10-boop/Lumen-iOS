import Foundation
import UIKit
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import SGSimpleSettings

// MARK: Lumen: the iOS Meme Library screen — search, categories, a grid of memes, multi-select
// and send to the current chat, editing, favourites and a first-run tutorial.

@available(iOS 15.0, *)
struct LumenMemeLibraryView: View {
    @ObservedObject var store: LumenMemeStore
    let dialogId: Int64
    let accountPeerId: Int64
    var replyToMessageId: Int32 = 0
    let close: () -> Void

    @State private var query = ""
    @State private var category: String?
    @State private var favoritesOnly = false
    @State private var selected: [String] = []
    @State private var editing: LumenMeme?
    @State private var pickedImage: LumenPickedFile?
    @State private var showPicker = false
    @State private var showTutorial = false
    @State private var newCategory = ""
    @State private var showNewCategory = false
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var deleting: LumenMeme?

    private var filtered: [LumenMeme] {
        return self.store.memes
            .filter { !self.favoritesOnly || $0.favorite }
            .filter { self.category == nil || $0.category == self.category }
            .filter { LumenMemeStore.matches($0, query: self.query) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 8)]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                self.chips
                if self.filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Text(self.emptyText).foregroundColor(.secondary)
                        if self.store.memes.isEmpty {
                            Button("Добавить из галереи") { self.showPicker = true }
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: self.columns, spacing: 8) {
                            ForEach(self.filtered) { meme in
                                self.cell(meme)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 90)
                    }
                }
            }
            .searchable(text: self.$query, prompt: "Поиск по описанию…")
            .navigationTitle(self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Закрыть") { self.close() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { self.showPicker = true } label: { Image(systemName: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !self.selected.isEmpty {
                    Button(action: self.sendSelected) {
                        Text(self.dialogId != 0 ? "Отправить (\(self.selected.count))" : "Поделиться (\(self.selected.count))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: self.$showPicker) {
            LumenSinglePhotoPicker { url in
                self.showPicker = false
                if let url {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.pickedImage = LumenPickedFile(url: url)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: self.$pickedImage) { picked in
            LumenMemeFormView(title: "Сохранить в мемы", imageURL: picked.url, categories: self.store.categories, category: self.category ?? "", description: "") { category, description in
                self.save(source: picked.url, category: category, description: description)
            }
        }
        .sheet(item: self.$editing) { meme in
            LumenMemeFormView(title: "Изменить", imageURL: self.store.fileURL(for: meme), categories: self.store.categories, category: meme.category, description: meme.tags) { category, description in
                do {
                    try self.store.update(meme, category: category, description: description)
                    LumenToast.show("Сохранено", kind: .success)
                } catch {
                    LumenToast.show("Лимит категорий (\(LumenMemeStore.maxCategories)) достигнут", kind: .error)
                }
            }
        }
        .fullScreenCover(isPresented: self.$showTutorial) {
            LumenMemeTutorialView {
                self.store.tutorialDone = true
                self.showTutorial = false
            }
        }
        .alert("Новая категория", isPresented: self.$showNewCategory) {
            TextField("Название (до \(LumenMemeStore.maxCategoryLength) симв.)", text: self.$newCategory)
            Button("Создать") {
                do {
                    try self.store.addCategory(self.newCategory)
                } catch {
                    LumenToast.show("Лимит (\(LumenMemeStore.maxCategories)) достигнут", kind: .error)
                }
                self.newCategory = ""
            }
            Button("Отмена", role: .cancel) { self.newCategory = "" }
        }
        .alert("Переименовать «\(self.renaming ?? "")»", isPresented: Binding(get: { self.renaming != nil }, set: { if !$0 { self.renaming = nil } })) {
            TextField("Новое название", text: self.$renameText)
            Button("Сохранить") {
                if let old = self.renaming {
                    self.store.renameCategory(old, to: self.renameText)
                    if self.category == old {
                        self.category = String(self.renameText.prefix(LumenMemeStore.maxCategoryLength))
                    }
                }
                self.renaming = nil
            }
            Button("Отмена", role: .cancel) { self.renaming = nil }
        }
        .confirmationDialog("Удалить мем?", isPresented: Binding(get: { self.deleting != nil }, set: { if !$0 { self.deleting = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let meme = self.deleting {
                    self.selected.removeAll { $0 == meme.filepath }
                    self.store.delete(meme)
                    LumenToast.show("Мем удалён", kind: .success)
                }
                self.deleting = nil
            }
        } message: {
            Text("Файл будет удалён навсегда.")
        }
        .onAppear {
            self.store.reload()
            if !self.store.tutorialDone {
                self.showTutorial = true
            }
        }
    }

    private var title: String {
        if self.favoritesOnly {
            return "Избранные мемы"
        }
        if let category = self.category {
            return "\(category) (\(self.filtered.count))"
        }
        return "Библиотека мемов"
    }

    private var emptyText: String {
        if self.store.memes.isEmpty {
            return "В библиотеке ещё ничего нет :("
        }
        if self.favoritesOnly {
            return "В избранных пока пусто"
        }
        return "Ничего не найдено"
    }

    // MARK: Chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                self.chip("Все", active: self.category == nil && !self.favoritesOnly) {
                    self.category = nil
                    self.favoritesOnly = false
                }
                self.chip("★", active: self.favoritesOnly) {
                    self.favoritesOnly.toggle()
                }
                ForEach(self.store.categories, id: \.self) { name in
                    let count = self.store.memes.filter { $0.category == name }.count
                    self.chip("\(name) \(count)", active: self.category == name && !self.favoritesOnly) {
                        self.favoritesOnly = false
                        self.category = self.category == name ? nil : name
                    }
                    .contextMenu {
                        Button {
                            self.renameText = name
                            self.renaming = name
                        } label: { Label("Переименовать", systemImage: "pencil") }
                        Button(role: .destructive) {
                            if self.category == name {
                                self.category = nil
                            }
                            self.store.deleteCategory(name)
                            LumenToast.show("Категория удалена", kind: .success)
                        } label: { Label("Удалить категорию", systemImage: "trash") }
                    }
                }
                self.chip("+", active: false) {
                    self.showNewCategory = true
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(active ? Color.accentColor : Color(UIColor.secondarySystemFill))
                .foregroundColor(active ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Cells

    private func cell(_ meme: LumenMeme) -> some View {
        let isSelected = self.selected.contains(meme.filepath)
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                LumenMemeThumbnail(url: self.store.fileURL(for: meme), isVideo: meme.isVideo)
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                if isSelected, let index = self.selected.firstIndex(of: meme.filepath) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accentColor))
                        .padding(6)
                } else if meme.favorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.yellow)
                        .padding(6)
                        .shadow(radius: 2)
                }
            }
            if !meme.tags.isEmpty {
                Text(meme.tags)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let index = self.selected.firstIndex(of: meme.filepath) {
                self.selected.remove(at: index)
            } else {
                self.selected.append(meme.filepath)
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .contextMenu {
            if self.dialogId != 0 {
                Button {
                    self.send([meme])
                } label: { Label("Отправить", systemImage: "paperplane") }
            }
            Button {
                self.store.toggleFavorite(meme)
                LumenToast.show(meme.favorite ? "Убрано из избранного" : "Добавлено в избранное ⭐", kind: .success)
            } label: {
                Label(meme.favorite ? "Убрать из избранного" : "В избранное", systemImage: meme.favorite ? "star.slash" : "star")
            }
            Button {
                self.editing = meme
            } label: { Label("Изменить", systemImage: "pencil") }
            Button {
                LumenPresentation.share(fileURL: self.store.fileURL(for: meme))
            } label: { Label("Поделиться", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) {
                self.deleting = meme
            } label: { Label("Удалить", systemImage: "trash") }
        }
    }

    // MARK: Actions

    private func save(source: URL, category: String, description: String) {
        do {
            try self.store.add(source: source, category: category, description: description)
            LumenToast.show("Мем сохранён!", kind: .success)
        } catch LumenMemeStore.SaveError.categoryLimit {
            LumenToast.show("Лимит категорий (\(LumenMemeStore.maxCategories)) достигнут", kind: .error)
        } catch {
            LumenToast.show("Не удалось сохранить мем", kind: .error)
        }
    }

    private func sendSelected() {
        let memes = self.selected.compactMap { path in self.store.memes.first { $0.filepath == path } }
        if self.dialogId == 0 {
            if let first = memes.first {
                LumenPresentation.share(fileURL: self.store.fileURL(for: first))
            }
            return
        }
        self.send(memes)
    }

    private func send(_ memes: [LumenMeme]) {
        var sent = 0
        for meme in memes {
            let url = self.store.fileURL(for: meme)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            let ext = url.pathExtension.lowercased()
            let kind: String
            if meme.isVideo {
                kind = "video"
            } else if ext == "gif" || ext == "webp" {
                kind = "document"
            } else {
                kind = "photo"
            }
            // Resend by reference when the meme was saved from a message (instant, no re-upload);
            // reply to the composed message when one is set.
            if LumenHooks.sendMeme != nil {
                LumenHooks.sendMeme?(self.accountPeerId, self.dialogId, self.replyToMessageId, meme.sourceDialogId, meme.sourceMessageId, meme.mediaBlob, url.path, kind, "")
            } else {
                LumenHooks.sendFile?(self.accountPeerId, self.dialogId, url.path, kind, "")
            }
            sent += 1
        }
        self.selected = []
        if sent > 0 {
            LumenToast.show("Отправлено: \(sent)", kind: .success)
            self.close()
        } else {
            LumenToast.show("Файлы не найдены", kind: .error)
        }
    }
}

// MARK: Thumbnail

@available(iOS 15.0, *)
struct LumenMemeThumbnail: View {
    let url: URL
    let isVideo: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image = self.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(UIColor.secondarySystemFill))
            }
            if self.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .shadow(radius: 3)
            }
        }
        .onAppear(perform: self.load)
    }

    private func load() {
        if self.image != nil {
            return
        }
        let url = self.url
        DispatchQueue.global(qos: .userInitiated).async {
            let image = LumenImageCache.image(at: url)
            DispatchQueue.main.async {
                self.image = image
            }
        }
    }
}

struct LumenPickedFile: Identifiable {
    let url: URL
    var id: String { return self.url.path }
}

// MARK: Save / edit form

@available(iOS 15.0, *)
struct LumenMemeFormView: View {
    let title: String
    let imageURL: URL
    let categories: [String]
    @State var category: String
    @State var description: String
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(title: String, imageURL: URL, categories: [String], category: String, description: String, onSave: @escaping (String, String) -> Void) {
        self.title = title
        self.imageURL = imageURL
        self.categories = categories
        self._category = State(initialValue: category)
        self._description = State(initialValue: description)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    LumenMemeThumbnail(url: self.imageURL, isVideo: LumenMemeStore.videoExtensions.contains(self.imageURL.pathExtension.lowercased()))
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                }
                Section(header: Text("Категория"), footer: Text("Необязательно, до \(LumenMemeStore.maxCategoryLength) символов")) {
                    TextField("Категория", text: self.$category)
                        .onChange(of: self.category) { value in
                            if value.count > LumenMemeStore.maxCategoryLength {
                                self.category = String(value.prefix(LumenMemeStore.maxCategoryLength))
                            }
                        }
                    if !self.categories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(self.categories, id: \.self) { name in
                                    Button {
                                        self.category = name
                                    } label: {
                                        Text(name)
                                            .font(.system(size: 13, weight: .medium))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(self.category == name ? Color.accentColor : Color(UIColor.secondarySystemFill))
                                            .foregroundColor(self.category == name ? .white : .primary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Section(header: Text("Описание"), footer: Text("Описывайте буквально: что написано на меме, что на нём видно и когда вы будете его искать. Например: «кот сидит на полке он снова в наличии».")) {
                    TextField("кот плачет под дождём", text: self.$description)
                }
            }
            .navigationTitle(self.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { self.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        self.onSave(self.category, self.description)
                        self.dismiss()
                    }
                    .font(.headline)
                }
            }
        }
    }
}

// MARK: Tutorial

@available(iOS 15.0, *)
struct LumenMemeTutorialView: View {
    let finish: () -> Void
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        ("photo.on.rectangle.angled", "Встречайте Библиотеку мемов!", "Отдельное хранилище медиа с удобным доступом из чата и встроенным поиском по описанию."),
        ("square.and.arrow.down", "Сохраняйте любимые мемы", "Зажмите фото в любом чате → «Сохранить в мемы», или нажмите «+» в библиотеке, чтобы добавить из галереи."),
        ("paperplane", "Делитесь с друзьями", "Зажмите сообщение в чате → «Библиотека мемов», отметьте мемы и нажмите «Отправить». Зажмите мем, чтобы изменить его, а ★ откроет избранное."),
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: self.$page) {
                ForEach(self.pages.indices, id: \.self) { index in
                    VStack(spacing: 18) {
                        Image(systemName: self.pages[index].0)
                            .font(.system(size: 72))
                            .foregroundColor(.accentColor)
                        Text(self.pages[index].1)
                            .font(.title2).bold()
                            .multilineTextAlignment(.center)
                        Text(self.pages[index].2)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            Button {
                if self.page < self.pages.count - 1 {
                    withAnimation { self.page += 1 }
                } else {
                    self.finish()
                }
            } label: {
                Text(self.page == 0 ? "Начнём!" : (self.page < self.pages.count - 1 ? "Далее" : "Понятно, в библиотеку!"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: Photo picker

@available(iOS 15.0, *)
struct LumenSinglePhotoPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(completion: self.completion)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (URL?) -> Void

        init(completion: @escaping (URL?) -> Void) {
            self.completion = completion
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                self.completion(nil)
                return
            }
            let types = [UTType.movie, UTType.gif, UTType.png, UTType.jpeg, UTType.image]
            guard let type = types.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
                self.completion(nil)
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                var kept: URL?
                if let url {
                    var ext = url.pathExtension.lowercased()
                    if ext.isEmpty {
                        ext = type.preferredFilenameExtension ?? "jpg"
                    }
                    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lumen-media", isDirectory: true)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    var target = folder.appendingPathComponent("picked_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)")
                    try? FileManager.default.copyItem(at: url, to: target)
                    // HEIC becomes JPEG so Android and older clients can read it.
                    if ext == "heic", let image = UIImage(contentsOfFile: target.path), let data = image.jpegData(compressionQuality: 0.92) {
                        let jpeg = target.deletingPathExtension().appendingPathExtension("jpg")
                        try? data.write(to: jpeg)
                        try? FileManager.default.removeItem(at: target)
                        target = jpeg
                    }
                    if FileManager.default.fileExists(atPath: target.path) {
                        kept = target
                    }
                }
                DispatchQueue.main.async {
                    self.completion(kept)
                }
            }
        }
    }
}
