import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var sources: SourceManager
    @EnvironmentObject var playlists: PlaylistStore
    @ObservedObject private var cloud = CloudSync.shared
    /// 进页面时算一次即可 —— 统计磁盘占用要遍历目录,不适合每次刷新都做
    @State private var cacheSize = 0

    /// 点「导出」时才编码,编好放这儿交给 fileExporter 写盘。
    @State private var exportDoc: PlaylistArchiveDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    /// 导入/导出结束后给用户的一句话反馈(成功和失败共用)。
    @State private var transferMessage: String?

    // 辅助编译期环境判断
    private var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        Form {
            Section {
                Picker("默认音质", selection: $settings.preferredQuality) {
                    ForEach(Quality.allCases, id: \.self) { q in
                        Label(q.displayName, systemImage: iconForQuality(q)).tag(q)
                    }
                }
                Toggle("车机/锁屏用专辑栏显示歌词", isOn: $settings.showLyricsOnNowPlaying)
                NavigationLink {
                    EQView()
                } label: {
                    Label("均衡器", systemImage: "slider.vertical.3")
                }
            } header: {
                Text("播放")
            } footer: {
                Text("脚本会按此优先级请求音源 URL,若该音质不可用,会自动降级。开启「用专辑栏显示歌词」后,CarPlay 和锁屏原本显示专辑名的位置,会随播放进度显示当前歌词(参考 QQ / 网易云);无歌词时仍显示专辑名")
            }

            Section {
                Toggle("批量下载时升级已下载音质", isOn: $settings.batchUpgradeQuality)
                Stepper(value: $settings.downloadConcurrency, in: 1...32) {
                    HStack {
                        Text("同时下载数")
                        Spacer()
                        Text("\(settings.downloadConcurrency)")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("下载")
            } footer: {
                Text("「全部下载」时,如果歌单里有已下载但音质低于这次选的目标档的歌曲,自动重下升级。同时下载数控制并发上限(1–32,默认 10),太大可能拖慢播放和搜索")
            }

            Section {
                Toggle("脚本失败时走内置直连 (非官方)", isOn: $settings.enableDirectFallback)
                NavigationLink {
                    ScriptManagerView()
                } label: {
                    HStack {
                        Label("自定义音源", systemImage: "doc.text.magnifyingglass")
                        Spacer()
                        Text("\(sources.loadedScripts.count) 个已加载")
                            .foregroundColor(.secondary).font(.caption)
                    }
                }
            } header: {
                Text("音源")
            } footer: {
                Text("脚本失败或未配置音源时,回落到内置直连(仅支持酷我/网易云)。如果你添加的音源能正常解析,可关闭此项严格走脚本")
            }

            Section {
                ForEach(homeSourceOptions, id: \.self) { src in
                    Toggle(isOn: bindingFor(src)) {
                        HStack(spacing: 8) {
                            Circle().fill(src.tint).frame(width: 8, height: 8)
                            Text(src.displayName)
                        }
                    }
                }
            } header: {
                Text("发现页信息来源")
            } footer: {
                Text("勾选哪些平台的推荐歌单 / 排行榜出现在 iPad 首页。至少保留一个,否则会自动恢复全选")
            }

            if !sources.loadedScripts.isEmpty {
                Section("已加载的源") {
                    ForEach(sources.loadedScripts, id: \.id) { ls in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(ls.script.name).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text("v\(ls.script.version)").font(.caption).foregroundColor(.secondary)
                            }
                            if !ls.script.description.isEmpty {
                                Text(ls.script.description).font(.caption).foregroundColor(.secondary).lineLimit(2)
                            }
                            HStack(spacing: 4) {
                                ForEach(SourceID.allCases.filter { ls.capabilities.sources[$0] != nil }, id: \.self) { src in
                                    SourceChip(source: src)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Toggle("使用 iCloud 同步", isOn: $cloud.enabled)
                if let last = cloud.lastSyncedAt {
                    HStack {
                        Text("上次同步")
                        Spacer()
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(.secondary).font(.caption)
                    }
                }
            } header: {
                Text("云端")
            } footer: {
                Text("使用 iCloud Key-Value 同步歌单和设置(脚本本身不上传)")
            }

            Section {
                Button {
                    exportArchive()
                } label: {
                    Label("导出歌单到文件", systemImage: "square.and.arrow.up")
                }
                .disabled(playlists.playlists.isEmpty)
                Button {
                    showImporter = true
                } label: {
                    Label("从文件导入歌单", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("歌单迁移")
            } footer: {
                Text(transferFooter)
            }

            Section {
                Toggle("显示调试提示", isOn: $settings.showDebugNotices)
            } header: {
                Text("调试")
            } footer: {
                Text("开启后,播放时会显示「换源播放」「音质降级」「使用内置 Hi-Res 解码」等提示横幅。真正的播放错误始终显示,不受此开关影响")
            }

            Section {
                HStack {
                    Text("已用空间")
                    Spacer()
                    Text(AppCache.formatted(cacheSize))
                        .foregroundColor(.secondary).font(.caption).monospacedDigit()
                }
                Button(role: .destructive) {
                    AppCache.clear()
                    cacheSize = AppCache.diskUsage()
                } label: {
                    Label("清空缓存", systemImage: "trash")
                }
                .disabled(cacheSize == 0)
            } header: {
                Text("缓存")
            } footer: {
                Text("封面图片和接口响应的本地副本,清空后会在下次浏览时重新下载。歌单、已下载的歌曲和自定义音源不受影响")
            }

            Section("关于") {
                LabeledContent("版本", value: appVersion)
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .brandedSurface()
        .navigationTitle("设置")
        // 在 Mac Catalyst 桌面端下，inline 模式配合透明背景能展现出最完美的居中标题栏
        .navigationBarTitleDisplayMode(isMacCatalyst ? .inline : .large)
        // 之前这里用 onAppear 改全局 UINavigationBar.appearance() 来做透明栏 —— 代理
        // 只影响之后创建的导航栏,本弹窗自己的栏赶不上,滚动后照样变成深色毛玻璃,
        // 还要靠 onDisappear 恢复全局状态。换成 SwiftUI 的 per-view 修饰符,只作用
        // 于当前 NavigationStack,不污染别处。
        .sheetNavBarSurface()
        .task { cacheSize = AppCache.diskUsage() }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDoc,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                transferMessage = "导出失败:\(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importArchive(result)
        }
        .alert("歌单迁移", isPresented: transferAlertPresented) {
            Button("好") { transferMessage = nil }
        } message: {
            Text(transferMessage ?? "")
        }
    }

    // MARK: - 歌单迁移

    private var transferFooter: String {
        var text = "导出成一个 JSON 文件,在另一台设备或另一个版本的 app 里导入即可。"
            + "导入是合并式的,只会新增,不会覆盖或删掉已有歌单。"
        let localOnly = playlists.localOnlyTrackCount
        if localOnly > 0 {
            text += "本地文件夹导入的 \(localOnly) 首歌不会被导出 —— 它们指向本机文件,换个 app 就读不到了。"
        }
        return text
    }

    private var transferAlertPresented: Binding<Bool> {
        Binding(
            get: { transferMessage != nil },
            set: { if !$0 { transferMessage = nil } }
        )
    }

    private var exportFilename: String {
        let day = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "随便听歌单-\(day)"
    }

    private func exportArchive() {
        do {
            let data = try PlaylistArchive.encoder().encode(playlists.makeArchive())
            exportDoc = PlaylistArchiveDocument(data: data)
            showExporter = true
        } catch {
            transferMessage = "导出失败:\(error.localizedDescription)"
        }
    }

    private func importArchive(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            // 文件选择器给的是别处的 URL,读之前必须先要到访问权限。
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let archive = try PlaylistArchive.load(from: try Data(contentsOf: url))
            transferMessage = playlists.importArchive(archive).message
        } catch {
            transferMessage = "导入失败:\(error.localizedDescription)"
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func iconForQuality(_ q: Quality) -> String {
        switch q {
        case .k128: return "waveform"
        case .k320: return "waveform.badge.plus"
        case .flac: return "waveform.path.ecg"
        case .flac24: return "waveform.path.ecg.rectangle"
        case .hires: return "sparkles.rectangle.stack"
        // "spatial.audio" 不是合法 SF Symbol(渲染为空白),全景声系列用 person.spatialaudio。
        case .atmos: return "person.spatialaudio.fill"
        case .atmosPlus: return "person.spatialaudio.stereo.fill"
        case .master: return "crown"
        }
    }

    private var homeSourceOptions: [SourceID] { [.kw, .wy, .kg, .tx] }

    private func bindingFor(_ src: SourceID) -> Binding<Bool> {
        Binding(
            get: { settings.homeSources.contains(src) },
            set: { on in
                var s = settings.homeSources
                if on {
                    s.insert(src)
                } else {
                    s.remove(src)
                    if s.isEmpty { s = Set(homeSourceOptions) }
                }
                settings.homeSources = s
            }
        )
    }
}
