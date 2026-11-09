import Foundation
import UIKit

// MARK: Lumen: storage of the iOS Meme Library. It reads and writes exactly what the
// Android plugin (meme_library.plugin by @gehirnfull) does — memes_db.json next to the
// plugin, media in the meme folder (default /storage/emulated/0/Pictures/ExteraMemes, which
// Lumen maps into Documents) — so memes and ZIP exports move between the two freely.

struct LumenMeme: Codable, Identifiable, Equatable {
    var filename: String
    var filepath: String
    var tags: String
    var category: String
    var timestamp: Double
    var favorite: Bool
    /// Where the meme was saved from (Lumen-only), so it can be resent by reference instead
    /// of re-uploaded: the Android-style dialog id and the cloud message id. 0 = unknown.
    var sourceDialogId: Int64
    var sourceMessageId: Int32

    var id: String { return self.filepath }

    enum CodingKeys: String, CodingKey {
        case filename, filepath, tags, category, timestamp, favorite
        case sourceDialogId = "lumen_source_dialog", sourceMessageId = "lumen_source_message"
    }

    init(filename: String, filepath: String, tags: String, category: String, timestamp: Double, favorite: Bool, sourceDialogId: Int64 = 0, sourceMessageId: Int32 = 0) {
        self.filename = filename
        self.filepath = filepath
        self.tags = tags
        self.category = category
        self.timestamp = timestamp
        self.favorite = favorite
        self.sourceDialogId = sourceDialogId
        self.sourceMessageId = sourceMessageId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.filename = (try? c.decode(String.self, forKey: .filename)) ?? ""
        self.filepath = (try? c.decode(String.self, forKey: .filepath)) ?? ""
        self.tags = (try? c.decode(String.self, forKey: .tags)) ?? ""
        self.category = (try? c.decode(String.self, forKey: .category)) ?? ""
        self.timestamp = (try? c.decode(Double.self, forKey: .timestamp)) ?? 0
        self.favorite = (try? c.decode(Bool.self, forKey: .favorite)) ?? false
        self.sourceDialogId = (try? c.decode(Int64.self, forKey: .sourceDialogId)) ?? 0
        self.sourceMessageId = (try? c.decode(Int32.self, forKey: .sourceMessageId)) ?? 0
    }

    var isVideo: Bool {
        return LumenMemeStore.videoExtensions.contains((self.filename as NSString).pathExtension.lowercased())
    }
}

final class LumenMemeStore: ObservableObject {
    static let pluginId = "meme_library"
    static let maxCategories = 30
    static let maxCategoryLength = 10
    static let photoExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "gif"]
    static let videoExtensions: Set<String> = ["mp4", "avi", "mov", "webm", "mkv", "3gp", "m4v"]
    private static let defaultMemeDir = "/storage/emulated/0/Pictures/ExteraMemes"

    @Published private(set) var memes: [LumenMeme] = []
    @Published private(set) var categories: [String] = []

    private weak var manager: LumenPluginManager?

    init(manager: LumenPluginManager) {
        self.manager = manager
        self.reload()
    }

    // MARK: Paths

    /// The plugin keeps its database next to its .plugin file.
    private var appDirectory: URL {
        return self.manager?.directory ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private var databaseURL: URL {
        return self.appDirectory.appendingPathComponent("memes_db.json")
    }

    private var settingsURL: URL {
        return self.appDirectory.appendingPathComponent("plugin_settings.json")
    }

    /// The folder memes are copied into: the plugin's "meme_save_dir" setting, mapped.
    var memeDirectory: URL {
        let configured = (self.manager?.settingValue(pluginId: LumenMemeStore.pluginId, key: "meme_save_dir") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let raw = configured.isEmpty ? LumenMemeStore.defaultMemeDir : configured
        let url = self.manager?.mapPath(raw, pluginId: LumenMemeStore.pluginId) ?? self.appDirectory.appendingPathComponent("memes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Stored paths may be Android-style; this is where the file really is.
    func fileURL(for meme: LumenMeme) -> URL {
        if let mapped = self.manager?.mapPath(meme.filepath, pluginId: LumenMemeStore.pluginId), FileManager.default.fileExists(atPath: mapped.path) {
            return mapped
        }
        return self.memeDirectory.appendingPathComponent(meme.filename)
    }

    /// Android-style path stored in the database, so the Android plugin finds the file too.
    private func storedPath(forFileName name: String) -> String {
        let configured = (self.manager?.settingValue(pluginId: LumenMemeStore.pluginId, key: "meme_save_dir") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let base = configured.isEmpty ? LumenMemeStore.defaultMemeDir : configured
        return (base as NSString).appendingPathComponent(name)
    }

    // MARK: Database

    func reload() {
        var memes: [LumenMeme] = []
        var categories: [String] = []
        if let data = try? Data(contentsOf: self.databaseURL) {
            let decoder = JSONDecoder()
            if let object = try? JSONSerialization.jsonObject(with: data), object is [Any] {
                // Legacy shape: a plain list of memes.
                memes = (try? decoder.decode([LumenMeme].self, from: data)) ?? []
            } else if let db = try? decoder.decode(Database.self, from: data) {
                memes = db.memes ?? []
                categories = db.categories ?? []
            }
        }
        let apply = {
            self.memes = memes
            self.categories = categories
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private struct Database: Codable {
        var memes: [LumenMeme]?
        var categories: [String]?
    }

    private func save(memes: [LumenMeme], categories: [String]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(Database(memes: memes, categories: categories)) {
            try? FileManager.default.createDirectory(at: self.appDirectory, withIntermediateDirectories: true)
            try? data.write(to: self.databaseURL, options: .atomic)
        }
        self.memes = memes
        self.categories = categories
    }

    // MARK: Onboarding

    var tutorialDone: Bool {
        get {
            guard let data = try? Data(contentsOf: self.settingsURL), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return object["tutorial_done"] as? Bool ?? false
        }
        set {
            var object: [String: Any] = [:]
            if let data = try? Data(contentsOf: self.settingsURL), let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                object = existing
            }
            object["tutorial_done"] = newValue
            object["onboarding_done"] = newValue
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) {
                try? data.write(to: self.settingsURL, options: .atomic)
            }
        }
    }

    // MARK: Editing

    enum SaveError: Error {
        case categoryLimit
        case fileMissing
        case copyFailed
    }

    /// Copies `source` into the meme folder and records it.
    func add(source: URL, category rawCategory: String, description: String, sourceDialogId: Int64 = 0, sourceMessageId: Int32 = 0) throws {
        let category = String(rawCategory.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LumenMemeStore.maxCategoryLength))
        var categories = self.categories
        if !category.isEmpty && !categories.contains(category) {
            if categories.count >= LumenMemeStore.maxCategories {
                throw SaveError.categoryLimit
            }
            categories.append(category)
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw SaveError.fileMissing
        }
        var ext = source.pathExtension.lowercased()
        if ext.isEmpty {
            ext = "jpg"
        }
        let now = Date().timeIntervalSince1970
        var name = "meme_\(Int(now)).\(ext)"
        var target = self.memeDirectory.appendingPathComponent(name)
        var counter = 1
        while FileManager.default.fileExists(atPath: target.path) {
            name = "meme_\(Int(now))_\(counter).\(ext)"
            target = self.memeDirectory.appendingPathComponent(name)
            counter += 1
        }
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            throw SaveError.copyFailed
        }
        var memes = self.memes
        memes.append(LumenMeme(filename: name, filepath: self.storedPath(forFileName: name), tags: description.trimmingCharacters(in: .whitespacesAndNewlines), category: category, timestamp: now, favorite: false, sourceDialogId: sourceDialogId, sourceMessageId: sourceMessageId))
        self.save(memes: memes, categories: categories)
    }

    func update(_ meme: LumenMeme, category rawCategory: String, description: String) throws {
        let category = String(rawCategory.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LumenMemeStore.maxCategoryLength))
        var categories = self.categories
        if !category.isEmpty && !categories.contains(category) {
            if categories.count >= LumenMemeStore.maxCategories {
                throw SaveError.categoryLimit
            }
            categories.append(category)
        }
        var memes = self.memes
        if let index = memes.firstIndex(where: { $0.filepath == meme.filepath }) {
            memes[index].category = category
            memes[index].tags = description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.save(memes: memes, categories: categories)
    }

    func toggleFavorite(_ meme: LumenMeme) {
        var memes = self.memes
        if let index = memes.firstIndex(where: { $0.filepath == meme.filepath }) {
            memes[index].favorite.toggle()
        }
        self.save(memes: memes, categories: self.categories)
    }

    func delete(_ meme: LumenMeme) {
        try? FileManager.default.removeItem(at: self.fileURL(for: meme))
        self.save(memes: self.memes.filter { $0.filepath != meme.filepath }, categories: self.categories)
    }

    func addCategory(_ raw: String) throws {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LumenMemeStore.maxCategoryLength))
        guard !name.isEmpty, !self.categories.contains(name) else {
            return
        }
        if self.categories.count >= LumenMemeStore.maxCategories {
            throw SaveError.categoryLimit
        }
        self.save(memes: self.memes, categories: self.categories + [name])
    }

    func renameCategory(_ old: String, to raw: String) {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LumenMemeStore.maxCategoryLength))
        guard !name.isEmpty, name != old else {
            return
        }
        var categories = self.categories.map { $0 == old ? name : $0 }
        var seen = Set<String>()
        categories = categories.filter { seen.insert($0).inserted }
        let memes = self.memes.map { meme -> LumenMeme in
            var meme = meme
            if meme.category == old {
                meme.category = name
            }
            return meme
        }
        self.save(memes: memes, categories: categories)
    }

    func deleteCategory(_ name: String) {
        let memes = self.memes.map { meme -> LumenMeme in
            var meme = meme
            if meme.category == name {
                meme.category = ""
            }
            return meme
        }
        self.save(memes: memes, categories: self.categories.filter { $0 != name })
    }

    func clear() {
        for meme in self.memes {
            try? FileManager.default.removeItem(at: self.fileURL(for: meme))
        }
        self.save(memes: [], categories: [])
    }

    // MARK: Search

    /// Every word of the query must appear in the description, as in the Android plugin.
    static func matches(_ meme: LumenMeme, query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        if words.isEmpty {
            return true
        }
        let haystack = (meme.tags + " " + meme.category).lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }

    // MARK: Export / import

    /// Writes meme_library_<date>.zip (memes_db.json + media/<file>), the Android format.
    func exportZip() -> URL? {
        guard !self.memes.isEmpty else {
            return nil
        }
        let writer = LumenZipWriter()
        var normalized: [LumenMeme] = []
        for meme in self.memes {
            var copy = meme
            copy.filepath = "media/" + meme.filename
            normalized.append(copy)
            if let data = try? Data(contentsOf: self.fileURL(for: meme)) {
                writer.add(name: "media/" + meme.filename, data: data)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let db = try? encoder.encode(Database(memes: normalized, categories: self.categories)) {
            writer.add(name: "memes_db.json", data: db)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let folder = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("Download", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("meme_library_\(formatter.string(from: Date())).zip")
        do {
            try writer.finish().write(to: target)
            return target
        } catch {
            return nil
        }
    }

    /// Merges an exported library; clashing file names get a numeric suffix.
    func importZip(_ url: URL) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let reader = try LumenZipReader(data: Data(contentsOf: url))
        guard let dbData = try reader.read(name: "memes_db.json") else {
            throw LumenZipError.corrupt
        }
        var imported: [LumenMeme] = []
        var importedCategories: [String] = []
        if let object = try? JSONSerialization.jsonObject(with: dbData), object is [Any] {
            imported = (try? JSONDecoder().decode([LumenMeme].self, from: dbData)) ?? []
        } else if let db = try? JSONDecoder().decode(Database.self, from: dbData) {
            imported = db.memes ?? []
            importedCategories = db.categories ?? []
        }
        var memes = self.memes
        var categories = self.categories
        var existing = Set(memes.map { $0.filename })
        var added = 0
        for meme in imported {
            let source = ((meme.filepath.isEmpty ? meme.filename : meme.filepath) as NSString).lastPathComponent
            let data = (try? reader.read(name: "media/" + source)) ?? (try? reader.read(name: source)) ?? nil
            guard let data else {
                continue
            }
            let base = (source as NSString).deletingPathExtension
            let ext = (source as NSString).pathExtension
            var name = source
            var counter = 1
            while existing.contains(name) || FileManager.default.fileExists(atPath: self.memeDirectory.appendingPathComponent(name).path) {
                name = "\(base)_\(counter)" + (ext.isEmpty ? "" : ".\(ext)")
                counter += 1
            }
            do {
                try data.write(to: self.memeDirectory.appendingPathComponent(name))
            } catch {
                continue
            }
            existing.insert(name)
            var copy = meme
            copy.filename = name
            copy.filepath = self.storedPath(forFileName: name)
            // The source message id belongs to another account/library; drop it so the meme
            // uploads normally here instead of pointing at an unrelated message.
            copy.sourceDialogId = 0
            copy.sourceMessageId = 0
            memes.append(copy)
            added += 1
        }
        for category in importedCategories where !category.isEmpty && !categories.contains(category) && categories.count < LumenMemeStore.maxCategories {
            categories.append(category)
        }
        self.save(memes: memes, categories: categories)
        return added
    }
}
