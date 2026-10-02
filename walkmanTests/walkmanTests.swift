//
//  walkmanTests.swift
//  walkmanTests
//
//  Created by allen wang on 2026/5/6.
//

import Testing
import Foundation
@testable import walkman

struct walkmanTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

/// 归档格式的编解码必须对称 —— 日期用的是 ISO8601 而不是 Codable 默认策略,
/// 编一边解另一边就会静默丢数据(歌单时间戳变 2001 年),而这类错误要等用户
/// 真的导出再导入才暴露。
struct PlaylistArchiveTests {

    private func sampleTrack(_ id: String) -> Track {
        Track(id: id, name: "晴天", singer: "周杰伦", albumName: "叶惠美",
              source: .kw, songmid: id, duration: 269, qualities: [.k320, .flac])
    }

    @Test func roundTripPreservesPlaylistsAndTracks() throws {
        let track = sampleTrack("kw_123")
        let playlist = PlaylistMeta(name: "我喜欢的", trackIDs: [track.id])
        let archive = PlaylistArchive(
            format: PlaylistArchive.format,
            version: PlaylistArchive.currentVersion,
            exportedAt: Date(),
            appVersion: "1.2.3 (6)",
            playlists: [playlist],
            tracks: [track.id: track]
        )

        let data = try PlaylistArchive.encoder().encode(archive)
        let decoded = try PlaylistArchive.load(from: data)

        #expect(decoded.playlists.count == 1)
        #expect(decoded.playlists[0].id == playlist.id)
        #expect(decoded.playlists[0].name == "我喜欢的")
        #expect(decoded.playlists[0].trackIDs == [track.id])
        // ISO8601 只到秒,比对时按秒容差 —— 只要没退回 2001 基准就说明策略是配对的
        #expect(abs(decoded.playlists[0].createdAt.timeIntervalSince(playlist.createdAt)) < 1)
        #expect(decoded.tracks[track.id]?.name == "晴天")
        #expect(decoded.tracks[track.id]?.qualities == [.k320, .flac])
    }

    @Test func rejectsForeignJSON() throws {
        // 用户很可能随手选中导出的脚本或别的 json,得报「这不是歌单文件」而不是解码错
        let data = try #require(#"{"hello":"world"}"#.data(using: .utf8))
        #expect(throws: PlaylistArchiveError.self) {
            try PlaylistArchive.load(from: data)
        }
    }

    @Test func rejectsNewerFormatVersion() throws {
        let json = """
        {"format":"\(PlaylistArchive.format)","version":\(PlaylistArchive.currentVersion + 1),
         "exportedAt":"2026-08-22T10:00:00Z","appVersion":"9.9.9 (99)",
         "playlists":[],"tracks":{}}
        """
        let data = try #require(json.data(using: .utf8))
        #expect(throws: PlaylistArchiveError.self) {
            try PlaylistArchive.load(from: data)
        }
    }
}
