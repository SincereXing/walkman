import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 歌单归档 —— 导出成一个自包含的 JSON 文件,导入方不依赖 iCloud。
///
/// 存在的理由:iCloud KV 的存储区按 `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`
/// 隔离,换开发者账号或换 bundle id 之后,新装的 app 看不到旧 app 同步上去的任何
/// 东西,而且两边互相不可见也没法互相覆盖。文件导出是这种情况下唯一能把歌单
/// 搬过去的通道。
struct PlaylistArchive: Codable {
    static let format = "walkman.playlists"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var appVersion: String
    var playlists: [PlaylistMeta]
    /// trackID → Track。只装 `playlists` 真正引用到的曲目,不是整个曲库。
    var tracks: [String: Track]

    /// 编解码两边必须用同一套策略。日期用 ISO8601 而不是 `Codable` 默认的
    /// 「2001 年起的秒数」—— 归档是要跨版本、甚至用文本编辑器打开看的。
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// 读一个归档文件。先认 `format` 再解内容 —— 用户很可能随手选了别的 json
    /// (脚本、导出的播放记录),报「这不是歌单文件」比报一串解码错有用。
    static func load(from data: Data) throws -> PlaylistArchive {
        let archive: PlaylistArchive
        do {
            archive = try decoder().decode(PlaylistArchive.self, from: data)
        } catch {
            throw PlaylistArchiveError.notAnArchive
        }
        guard archive.format == Self.format else { throw PlaylistArchiveError.notAnArchive }
        guard archive.version <= Self.currentVersion else {
            throw PlaylistArchiveError.tooNew(archive.version)
        }
        return archive
    }
}

enum PlaylistArchiveError: LocalizedError {
    case notAnArchive
    case tooNew(Int)

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "这不是随便听导出的歌单文件"
        case .tooNew(let v):
            return "该文件由更新版本导出(格式 v\(v)),请先升级 app"
        }
    }
}

/// 一次导入的结果,用来给用户一句人话反馈。
struct PlaylistImportSummary {
    var newPlaylists = 0
    var mergedPlaylists = 0
    var addedTracks = 0

    var isEmpty: Bool { newPlaylists == 0 && mergedPlaylists == 0 && addedTracks == 0 }

    var message: String {
        if isEmpty { return "歌单已是最新,没有需要导入的内容。" }
        var parts: [String] = []
        if newPlaylists > 0 { parts.append("新增 \(newPlaylists) 个歌单") }
        if mergedPlaylists > 0 { parts.append("合并 \(mergedPlaylists) 个已有歌单") }
        if addedTracks > 0 { parts.append("共 \(addedTracks) 首歌曲") }
        return parts.joined(separator: ",") + "。"
    }
}

/// `fileExporter` 要的壳。归档在点导出时就编码好了,这里只负责把 Data 写出去。
struct PlaylistArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = d
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
