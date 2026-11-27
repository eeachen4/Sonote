import Foundation
import SonoteCore

// MARK: - Media Import, Speaker Diarization, Voiceprint Enrollment & Templates

extension AppState {

    public func importMediaFile(url: URL) async {
        guard importProgress == nil else { return }
        let fileName = url.deletingPathExtension().lastPathComponent
        importProgress = AudioFileImportProgress(fraction: 0.02, message: L("准备导入「\(fileName)」...", "Preparing \"\(fileName)\"..."))

        let sessionID = UUID()
        let baseBackupURL = store.audioBackupURL(for: sessionID)
        var savedMediaURL: URL?

        do {
            importProgress = AudioFileImportProgress(fraction: 0.04, message: L("正在提取音频轨道...", "Extracting audio track..."))
            let preparedURL = try await AudioFileImporter.preparePlayableAudioBackup(
                from: url,
                destinationBaseURL: baseBackupURL
            )
            savedMediaURL = preparedURL

            let (segments, duration) = try await AudioFileImporter.transcribeMediaFile(
                url: preparedURL,
                settings: settings,
                extraHotwords: combinedVoiceprintHotwords,
                voiceprintProfiles: voiceprints,
                onProgress: { [weak self] prog in
                    Task { @MainActor [weak self] in
                        self?.importProgress = prog
                    }
                },
                onMLXState: { [weak self] state in
                    Task { @MainActor [weak self] in
                        self?.mlxModelState = state
                    }
                }
            )

            let session = MeetingSession(
                id: sessionID,
                title: fileName.isEmpty ? L("导入录音", "Imported Media") : fileName,
                sourceAppName: L("文件导入", "File Import"),
                startedAt: Date(),
                endedAt: Date(),
                duration: duration,
                status: segments.isEmpty ? .completed : .summarizing,
                segments: segments,
                audioFilePath: preparedURL.path,
                template: settings.defaultMinutesTemplate
            )

            meetings.insert(session, at: 0)
            selectedMeetingID = session.id
            store.saveMeeting(session)
            refreshAudioStorageStats()
            importProgress = nil

            if !segments.isEmpty {
                await refreshMinutesNow(for: session.id, isFinal: true)
                updateMeeting(id: session.id) { $0.status = .completed }
            }
        } catch {
            if let savedMediaURL {
                try? FileManager.default.removeItem(at: savedMediaURL)
            }
            importProgress = nil
            statusBannerMessage = L("导入音视频失败：\(error.localizedDescription)", "Media import failed: \(error.localizedDescription)")
        }
    }

    public var combinedVoiceprintHotwords: String {
        var terms: [String] = []
        let local = settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { terms.append(local) }
        for term in settings.glossaryTerms {
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !terms.contains(clean) {
                terms.append(clean)
            }
        }
        for vp in voiceprints {
            let clean = vp.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !terms.contains(clean) {
                terms.append(clean)
            }
        }
        return terms.prefix(40).joined(separator: ", ")
    }

    public func runSpeakerDiarization(for meetingID: UUID) async {
        guard !isDiarizing,
              let meeting = meetings.first(where: { $0.id == meetingID }),
              let audioPath = meeting.audioFilePath,
              FileManager.default.fileExists(atPath: audioPath) else {
            return
        }

        isDiarizing = true
        let useVoiceprints = settings.autoIdentifyVoiceprints && !voiceprints.isEmpty
        if settings.diarizationStrategy == .voiceprintClusteringUnlimited {
            statusBannerMessage = L("正在通过 ECAPA 声纹聚类识别多说话人（突破 4 人上限）...", "Clustering speakers with ECAPA voiceprints...")
        } else {
            statusBannerMessage = useVoiceprints
                ? L("正在通过 Sortformer + 本地声纹库识别说话人...", "Identifying speakers via Sortformer + local voiceprints...")
                : L("正在通过 Sortformer 识别多说话人...", "Separating speakers via Sortformer...")
        }
        do {
            let (samples, decodedDur) = try await AudioFileImporter.decodeToMono16kSamples(url: URL(fileURLWithPath: audioPath))
            if settings.diarizationStrategy == .voiceprintClusteringUnlimited {
                let result = await SpeakerDiarizerService.diarizeByVoiceprintClustering(
                    segments: meeting.segments,
                    fullSamples16k: samples,
                    meetingDuration: max(meeting.duration, decodedDur),
                    profiles: useVoiceprints ? voiceprints : [],
                    matchThreshold: settings.voiceprintMatchThreshold,
                    voiceprintModelID: settings.voiceprintModelID,
                    hfHost: settings.mlxHuggingFaceHost,
                    localUserName: settings.localUserName,
                    autoUnloadVoiceprintModel: settings.mlxAutoUnloadAfterMeeting
                )
                updateMeeting(id: meetingID) { $0.segments = result.segments }
                if !result.matchedVoiceprintNames.isEmpty {
                    statusBannerMessage = L(
                        "ECAPA 聚类已识别 \(result.totalRemoteSpeakersDetected) 位说话人，声纹匹配：\(result.matchedVoiceprintNames.joined(separator: "、"))",
                        "ECAPA detected \(result.totalRemoteSpeakersDetected) speakers; matched: \(result.matchedVoiceprintNames.joined(separator: ", "))"
                    )
                } else {
                    statusBannerMessage = L(
                        "ECAPA 聚类已分离 \(result.totalRemoteSpeakersDetected) 位说话人（点击说话人名可改名并建档）",
                        "ECAPA separated \(result.totalRemoteSpeakersDetected) speakers (click any label to rename & enroll)"
                    )
                }
            } else {
                let diarization = try await SpeakerDiarizerService.shared.diarize(
                    samples16k: samples,
                    modelID: settings.diarizationModelID,
                    hfHost: settings.mlxHuggingFaceHost
                )
                if useVoiceprints {
                    let result = await SpeakerDiarizerService.assignSpeakerLabelsWithVoiceprints(
                        segments: meeting.segments,
                        diarization: diarization,
                        fullSamples16k: samples,
                        profiles: voiceprints,
                        matchThreshold: settings.voiceprintMatchThreshold,
                        voiceprintModelID: settings.voiceprintModelID,
                        hfHost: settings.mlxHuggingFaceHost,
                        localUserName: settings.localUserName,
                        autoUnloadVoiceprintModel: settings.mlxAutoUnloadAfterMeeting
                    )
                    updateMeeting(id: meetingID) { $0.segments = result.segments }
                    if !result.matchedVoiceprintNames.isEmpty {
                        statusBannerMessage = L(
                            "已分离 \(result.totalRemoteSpeakersDetected) 位说话人，声纹匹配：\(result.matchedVoiceprintNames.joined(separator: "、"))",
                            "Separated \(result.totalRemoteSpeakersDetected) speakers; matched: \(result.matchedVoiceprintNames.joined(separator: ", "))"
                        )
                    } else {
                        statusBannerMessage = L("已完成多说话人分离（未命中已建档声纹，可点击说话人名改名并记住声纹）", "Diarization complete (no enrolled match; click speaker label to enroll)")
                    }
                } else {
                    let updatedSegments = SpeakerDiarizerService.assignSpeakerLabels(
                        segments: meeting.segments,
                        diarization: diarization,
                        localUserName: settings.localUserName
                    )
                    updateMeeting(id: meetingID) { $0.segments = updatedSegments }
                    statusBannerMessage = L("已完成多说话人声纹分离", "Speaker diarization complete")
                }
                if settings.mlxAutoUnloadAfterMeeting {
                    await SpeakerDiarizerService.shared.unload()
                }
            }
        } catch {
            statusBannerMessage = L("多说话人识别失败：\(error.localizedDescription)", "Speaker diarization failed: \(error.localizedDescription)")
        }
        isDiarizing = false
    }

    public func inferSpeakerNamesWithAI(for meetingID: UUID) async {
        guard !isInferringSpeakers,
              let meeting = meetings.first(where: { $0.id == meetingID }) else { return }
        isInferringSpeakers = true
        statusBannerMessage = L("正在结合会议上下文推断说话人姓名...", "Inferring speaker names from transcript context...")
        do {
            var candidates = meeting.calendarAttendees + voiceprints.map(\.name)
            let local = settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !local.isEmpty { candidates.append(local) }

            let (mapping, usage) = try await gptClient.inferSpeakerNames(
                for: meeting,
                candidateNames: candidates,
                settings: settings
            )
            if !usage.isEmpty {
                updateMeeting(id: meetingID) { $0.tokenUsage.add(usage) }
                recordDailyTokenUsage(usage)
            }
            if mapping.isEmpty {
                statusBannerMessage = L("对话中暂无足够姓名线索，可点击说话人标签手动命名", "Not enough name clues in transcript; click speaker labels to rename")
            } else {
                updateMeeting(id: meetingID) { m in
                    for (oldName, newName) in mapping {
                        m.renameSpeaker(from: oldName, to: newName, onlySegmentID: nil, updateMinutes: true)
                    }
                }
                let summary = mapping.map { "\($0.key)→\($0.value)" }.joined(separator: ", ")
                statusBannerMessage = L("AI 已推断说话人姓名：\(summary)", "AI inferred speakers: \(summary)")
            }
        } catch {
            statusBannerMessage = L("AI 推断姓名失败：\(error.localizedDescription)", "Speaker inference failed: \(error.localizedDescription)")
        }
        isInferringSpeakers = false
    }

    /// Renames a speaker in a meeting transcript (single segment or all matching segments),
    /// optionally syncing minutes text and enrolling the speaker's audio into the local ECAPA voiceprint library.
    public func renameSpeaker(
        meetingID: UUID,
        oldName: String,
        newName: String,
        onlySegmentID: UUID?,
        updateMinutes: Bool,
        enrollVoiceprint: Bool
    ) async {
        let cleanNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNew.isEmpty else { return }

        // Collect intervals BEFORE mutating if we are enrolling voiceprint
        var intervalsToEnroll: [(start: TimeInterval, end: TimeInterval)] = []
        var audioPathForEnroll: String? = nil
        if enrollVoiceprint, let meeting = meetings.first(where: { $0.id == meetingID }),
           let path = meeting.audioFilePath, FileManager.default.fileExists(atPath: path) {
            audioPathForEnroll = path
            let segs = meeting.segments
            for idx in segs.indices {
                let seg = segs[idx]
                let matchesTarget: Bool
                if let onlyID = onlySegmentID {
                    matchesTarget = seg.id == onlyID
                } else {
                    matchesTarget = seg.resolvedSpeakerName == oldName
                }
                guard matchesTarget else { continue }
                let nextStart: TimeInterval = (idx + 1 < segs.count)
                    ? segs[idx + 1].timestamp
                    : max(seg.timestamp + 6.0, meeting.duration)
                let estEnd = min(nextStart, seg.timestamp + 12.0)
                if estEnd - seg.timestamp >= 0.8 {
                    intervalsToEnroll.append((start: seg.timestamp, end: estEnd))
                }
            }
        }

        updateMeeting(id: meetingID) { m in
            m.renameSpeaker(
                from: oldName,
                to: cleanNew,
                onlySegmentID: onlySegmentID,
                updateMinutes: updateMinutes
            )
        }

        if enrollVoiceprint, let audioPath = audioPathForEnroll, !intervalsToEnroll.isEmpty {
            isEnrollingVoiceprint = true
            statusBannerMessage = L("正在提取「\(cleanNew)」声纹并写入本地声纹库...", "Enrolling voiceprint for \"\(cleanNew)\"...")
            do {
                let (fullSamples, _) = try await AudioFileImporter.decodeToMono16kSamples(url: URL(fileURLWithPath: audioPath))
                let speakerSamples = VoiceprintService.extractSpeakerSamples(
                    from: fullSamples,
                    intervals: intervalsToEnroll,
                    maxDurationSeconds: 14.0
                )
                let embedding = try await VoiceprintService.shared.extractEmbedding(
                    samples16k: speakerSamples,
                    modelID: settings.voiceprintModelID,
                    hfHost: settings.mlxHuggingFaceHost
                )
                voiceprints = voiceprintStore.upsertProfile(name: cleanNew, embedding: embedding)
                if settings.mlxAutoUnloadAfterMeeting {
                    await VoiceprintService.shared.unload()
                }
                statusBannerMessage = L("已保存「\(cleanNew)」声纹，下次会议将自动识别", "Saved voiceprint for \"\(cleanNew)\"")
            } catch {
                statusBannerMessage = L("已改名为「\(cleanNew)」，但声纹提取失败：\(error.localizedDescription)", "Renamed to \"\(cleanNew)\", voiceprint failed: \(error.localizedDescription)")
            }
            isEnrollingVoiceprint = false
        }
    }

    public func updateSegmentText(meetingID: UUID, segmentID: UUID, newText: String) {
        let cleaned = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateMeeting(id: meetingID) { m in
            if let idx = m.segments.firstIndex(where: { $0.id == segmentID }) {
                m.segments[idx].text = cleaned
            }
        }
    }

    // MARK: - Local Voiceprint Library Enrollment & Management

    public func enrollVoiceprintFromLiveMic(name: String, role: String = "", isSelf: Bool = false) async {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !isEnrollingVoiceprint else { return }

        isEnrollingVoiceprint = true
        voiceprintEnrollProgress = 0
        voiceprintEnrollLevel = 0
        voiceprintStatusMessage = L("请对着麦克风自然朗读 5 秒...", "Speak naturally into your mic for 5 seconds...")

        let recorder = VoiceprintEnrollmentRecorder()
        do {
            let samples = try await recorder.recordSample(durationSeconds: 5.0) { [weak self] prog, level in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.voiceprintEnrollProgress = prog
                    if level > 0 {
                        self.voiceprintEnrollLevel = self.voiceprintEnrollLevel * 0.4 + level * 0.6
                    }
                }
            }
            voiceprintStatusMessage = L("正在通过 ECAPA-TDNN 提取 192 维声纹特征...", "Extracting 192-dim ECAPA-TDNN voiceprint...")
            let embedding = try await VoiceprintService.shared.extractEmbedding(
                samples16k: samples,
                modelID: settings.voiceprintModelID,
                hfHost: settings.mlxHuggingFaceHost
            )
            voiceprints = voiceprintStore.upsertProfile(
                name: cleanName,
                role: role,
                embedding: embedding,
                isSelf: isSelf
            )
            if isSelf && settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.localUserName = cleanName
            }
            if settings.mlxAutoUnloadAfterMeeting {
                await VoiceprintService.shared.unload()
            }
            voiceprintStatusMessage = L("已成功录入「\(cleanName)」声纹", "Enrolled voiceprint for \"\(cleanName)\"")
        } catch {
            voiceprintStatusMessage = L("声纹录入失败：\(error.localizedDescription)", "Voiceprint enrollment failed: \(error.localizedDescription)")
        }
        voiceprintEnrollProgress = 0
        voiceprintEnrollLevel = 0
        isEnrollingVoiceprint = false
    }

    public func enrollVoiceprintFromAudioFile(url: URL, name: String, role: String = "", isSelf: Bool = false) async {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !isEnrollingVoiceprint else { return }

        isEnrollingVoiceprint = true
        voiceprintStatusMessage = L("正在从音频文件提取「\(cleanName)」声纹...", "Extracting voiceprint for \"\(cleanName)\"...")
        do {
            let (samples, _) = try await AudioFileImporter.decodeToMono16kSamples(url: url)
            let embedding = try await VoiceprintService.shared.extractEmbedding(
                samples16k: samples,
                modelID: settings.voiceprintModelID,
                hfHost: settings.mlxHuggingFaceHost
            )
            voiceprints = voiceprintStore.upsertProfile(
                name: cleanName,
                role: role,
                embedding: embedding,
                isSelf: isSelf
            )
            if isSelf && settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.localUserName = cleanName
            }
            if settings.mlxAutoUnloadAfterMeeting {
                await VoiceprintService.shared.unload()
            }
            voiceprintStatusMessage = L("已从文件成功建档「\(cleanName)」声纹", "Enrolled \"\(cleanName)\" from audio file")
        } catch {
            voiceprintStatusMessage = L("音频声纹建档失败：\(error.localizedDescription)", "Audio voiceprint failed: \(error.localizedDescription)")
        }
        isEnrollingVoiceprint = false
    }

    public func renameVoiceprint(id: UUID, newName: String, newRole: String? = nil) {
        voiceprints = voiceprintStore.renameProfile(id: id, newName: newName, newRole: newRole)
    }

    public func deleteVoiceprint(id: UUID) {
        voiceprints = voiceprintStore.deleteProfile(id: id)
    }

    public func preloadSpeechEnhancementModel() async {
        guard !isPreloadingDenoiser else { return }
        isPreloadingDenoiser = true
        statusBannerMessage = L("正在下载并加载 DeepFilterNet3 降噪模型...", "Downloading/loading DeepFilterNet3 denoiser...")
        let loaded = await SpeechEnhancementService.shared.ensureLoaded(
            modelID: settings.speechEnhancementModelID,
            hfHost: settings.mlxHuggingFaceHost
        )
        statusBannerMessage = loaded != nil
            ? L("DeepFilterNet3 降噪模型已就绪", "DeepFilterNet3 denoiser ready")
            : L("DeepFilterNet3 模型加载失败，将自动使用轻量 DSP 降噪", "DeepFilterNet3 failed; falling back to DSP denoiser")
        isPreloadingDenoiser = false
    }

    public func setTemplate(_ template: MinutesTemplate, for meetingID: UUID, regenerate: Bool = false) {
        updateMeeting(id: meetingID) {
            $0.template = template
            $0.customTemplateID = nil
        }
        if regenerate {
            Task { await refreshMinutesNow(for: meetingID, isFinal: true) }
        }
    }

    public func setCustomTemplate(_ custom: CustomMinutesTemplate, for meetingID: UUID, regenerate: Bool = false) {
        updateMeeting(id: meetingID) { $0.customTemplateID = custom.id }
        if regenerate {
            Task { await refreshMinutesNow(for: meetingID, isFinal: true) }
        }
    }

    public func addCustomTemplate(name: String, guidance: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGuidance = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanGuidance.isEmpty else { return }
        settings.customTemplates.append(CustomMinutesTemplate(name: cleanName, promptGuidance: cleanGuidance))
    }

    public func deleteCustomTemplate(id: UUID) {
        settings.customTemplates.removeAll { $0.id == id }
    }
}
