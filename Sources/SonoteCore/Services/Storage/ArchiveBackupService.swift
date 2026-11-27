import Foundation

public struct ArchiveRestoreSummary: Equatable, Sendable {
    public var meetingsImported: Int
    public var voiceprintsImported: Int
    public var audioFilesRestored: Int
    public var settingsRestored: Bool

    public init(
        meetingsImported: Int = 0,
        voiceprintsImported: Int = 0,
        audioFilesRestored: Int = 0,
        settingsRestored: Bool = false
    ) {
        self.meetingsImported = meetingsImported
        self.voiceprintsImported = voiceprintsImported
        self.audioFilesRestored = audioFilesRestored
        self.settingsRestored = settingsRestored
    }
}

public enum ArchiveBackupError: LocalizedError {
    case zipFailed(String)
    case unzipFailed(String)
    case invalidArchive

    public var errorDescription: String? {
        switch self {
        case .zipFailed(let msg): return "打包备份归档失败：\(msg)"
        case .unzipFailed(let msg): return "解压备份归档失败：\(msg)"
        case .invalidArchive: return "所选文件不是有效的 Sonote 备份包（缺少 meetings 或 voiceprints 数据）。"
        }
    }
}

/// Portable full-library backup & migration archive service (ZIP via macOS `/usr/bin/ditto`).
/// Exports meetings, local ECAPA voiceprints, daily token ledger, sanitized settings (zero API keys!),
/// and optionally recorded `.m4a` audio backups, and safely merges on restore.
public enum ArchiveBackupService {

    public static func exportArchive(
        to destinationURL: URL,
        includeAudioFiles: Bool = false,
        store: MeetingStore = .shared,
        voiceprintStore: VoiceprintStore = .shared
    ) throws {
        let fm = FileManager.default
        let stagingRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SonoteExport-\(UUID().uuidString)", isDirectory: true)
        let payloadDir = stagingRoot.appendingPathComponent("SonoteBackup", isDirectory: true)
        defer { try? fm.removeItem(at: stagingRoot) }

        try fm.createDirectory(at: payloadDir, withIntermediateDirectories: true)

        // 1. Copy meetings directory
        if fm.fileExists(atPath: store.meetingsDirectory.path) {
            try fm.copyItem(at: store.meetingsDirectory, to: payloadDir.appendingPathComponent("meetings"))
        }

        // 2. Copy voiceprints.json
        if fm.fileExists(atPath: voiceprintStore.fileURL.path) {
            try fm.copyItem(at: voiceprintStore.fileURL, to: payloadDir.appendingPathComponent("voiceprints.json"))
        }

        // 3. Copy sanitized settings.json (already stripped of Keychain secrets)
        if fm.fileExists(atPath: store.settingsURL.path) {
            try fm.copyItem(at: store.settingsURL, to: payloadDir.appendingPathComponent("settings.json"))
        }

        // 4. Copy token_ledger.json
        if fm.fileExists(atPath: store.tokenLedgerURL.path) {
            try fm.copyItem(at: store.tokenLedgerURL, to: payloadDir.appendingPathComponent("token_ledger.json"))
        }

        // 5. Optionally copy audio backups
        if includeAudioFiles && fm.fileExists(atPath: store.audioDirectory.path) {
            try fm.copyItem(at: store.audioDirectory, to: payloadDir.appendingPathComponent("audio"))
        }

        try? fm.removeItem(at: destinationURL)
        try runDitto(arguments: ["-c", "-k", "--keepParent", payloadDir.path, destinationURL.path], isZip: true)
    }

    public static func importArchive(
        from archiveURL: URL,
        restoreSettings: Bool = true,
        store: MeetingStore = .shared,
        voiceprintStore: VoiceprintStore = .shared
    ) throws -> ArchiveRestoreSummary {
        let fm = FileManager.default
        let stagingRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SonoteImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: stagingRoot) }
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        try runDitto(arguments: ["-x", "-k", archiveURL.path, stagingRoot.path], isZip: false)

        // Locate backup payload root (supports `SonoteBackup/`, legacy `TTMinutesBackup/`, or archive root)
        let sonoteSub = stagingRoot.appendingPathComponent("SonoteBackup", isDirectory: true)
        let legacySub = stagingRoot.appendingPathComponent("TTMinutesBackup", isDirectory: true)
        let rootDir: URL
        if fm.fileExists(atPath: sonoteSub.path) {
            rootDir = sonoteSub
        } else if fm.fileExists(atPath: legacySub.path) {
            rootDir = legacySub
        } else {
            rootDir = stagingRoot
        }

        let meetingsSrc = rootDir.appendingPathComponent("meetings", isDirectory: true)
        let voiceprintsSrc = rootDir.appendingPathComponent("voiceprints.json")
        let settingsSrc = rootDir.appendingPathComponent("settings.json")
        let ledgerSrc = rootDir.appendingPathComponent("token_ledger.json")
        let audioSrc = rootDir.appendingPathComponent("audio", isDirectory: true)

        let hasAnyValidData = fm.fileExists(atPath: meetingsSrc.path)
            || fm.fileExists(atPath: voiceprintsSrc.path)
            || fm.fileExists(atPath: settingsSrc.path)
        guard hasAnyValidData else {
            throw ArchiveBackupError.invalidArchive
        }

        var summary = ArchiveRestoreSummary()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Merge audio files first so restored meetings point to valid paths
        if fm.fileExists(atPath: audioSrc.path),
           let audioURLs = try? fm.contentsOfDirectory(at: audioSrc, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            try? fm.createDirectory(at: store.audioDirectory, withIntermediateDirectories: true)
            for file in audioURLs {
                let dest = store.audioDirectory.appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    if (try? fm.copyItem(at: file, to: dest)) != nil {
                        summary.audioFilesRestored += 1
                    }
                }
            }
        }

        // 2. Merge meetings (preserve existing meetings, rewrite migrated audio path to local audioDirectory)
        if fm.fileExists(atPath: meetingsSrc.path),
           let meetingURLs = try? fm.contentsOfDirectory(at: meetingsSrc, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let existingIDs = Set(store.loadMeetings().map(\.id))
            for url in meetingURLs where url.pathExtension.lowercased() == "json" {
                guard let data = try? Data(contentsOf: url),
                      var session = try? decoder.decode(MeetingSession.self, from: data) else { continue }
                if let oldAudio = session.audioFilePath {
                    let filename = URL(fileURLWithPath: oldAudio).lastPathComponent
                    let localAudio = store.audioDirectory.appendingPathComponent(filename)
                    session.audioFilePath = fm.fileExists(atPath: localAudio.path) ? localAudio.path : nil
                }
                if !existingIDs.contains(session.id) {
                    store.saveMeeting(session)
                    summary.meetingsImported += 1
                }
            }
        }

        // 3. Merge voiceprints (upsert by name)
        if fm.fileExists(atPath: voiceprintsSrc.path),
           let data = try? Data(contentsOf: voiceprintsSrc),
           let importedVPs = try? decoder.decode([VoiceprintProfile].self, from: data) {
            let existingNames = Set(voiceprintStore.loadProfiles().map { $0.name.lowercased() })
            for vp in importedVPs where !existingNames.contains(vp.name.lowercased()) {
                _ = voiceprintStore.upsertProfile(name: vp.name, role: vp.role, embedding: vp.embedding, isSelf: vp.isSelf)
                summary.voiceprintsImported += 1
            }
        }

        // 4. Merge daily token ledger
        if fm.fileExists(atPath: ledgerSrc.path),
           let data = try? Data(contentsOf: ledgerSrc),
           let importedLedger = try? decoder.decode([String: TokenUsage].self, from: data) {
            var current = store.loadTokenLedger()
            for (day, usage) in importedLedger where current[day] == nil {
                current[day] = usage
            }
            store.saveTokenLedger(current)
        }

        // 5. Optionally merge non-secret settings (templates, glossary, preferences; preserve local Keychain API keys!)
        if restoreSettings,
           fm.fileExists(atPath: settingsSrc.path),
           let data = try? Data(contentsOf: settingsSrc),
           var imported = try? decoder.decode(AppSettings.self, from: data) {
            let current = store.loadSettings()
            imported.apiKey = current.apiKey
            imported.deepSeekAPIKey = current.deepSeekAPIKey
            imported.qwenAPIKey = current.qwenAPIKey
            imported.domesticAPIKey = current.domesticAPIKey
            imported.claudeAPIKey = current.claudeAPIKey
            imported.geminiAPIKey = current.geminiAPIKey
            imported.webhookSecret = current.webhookSecret
            store.saveSettings(imported)
            summary.settingsRestored = true
        }

        return summary
    }

    private static func runDitto(arguments: [String], isZip: Bool) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = arguments
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "exit \(proc.terminationStatus)"
            throw isZip ? ArchiveBackupError.zipFailed(errText) : ArchiveBackupError.unzipFailed(errText)
        }
    }
}
