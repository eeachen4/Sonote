import SwiftUI
import AVFoundation
import Speech
import SonoteCore

// MARK: - Page 2: Audio Capture, MLX ASR, Denoising, Glossary, Diarization & Permissions

extension SettingsView {

    var audioTranscriptionPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card 1: Profile & Capture Basics
            SettingsCard(title: L("采集与存储", "Capture & Storage")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        fieldLabel(L("本机发言人名称", "Your Speaker Name"), hint: L("留空默认显示「我」", "Defaults to 'Me' when empty"))
                        Spacer()
                        CleanInputBox(placeholder: L("例如：林致远 / Alex", "e.g. Alex"), text: $appState.settings.localUserName)
                            .frame(width: 210)
                    }

                    Divider().overlay(AppTheme.divider)

                    HStack {
                        fieldLabel(L("采集通道", "Audio Input Mode"), hint: L("支持系统远端声音与麦克风双轨分离", "Separate system remote audio and local microphone tracks"))
                        Spacer()
                        Menu {
                            ForEach(AudioCaptureMode.allCases) { mode in
                                Button(mode.displayName) { appState.settings.audioCaptureMode = mode }
                            }
                        } label: {
                            cleanMenuLabel(appState.settings.audioCaptureMode.displayName)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: L("保存会议音频备份 (.m4a)", "Save Audio Backup (.m4a)"),
                        subtitle: L("支持会后音文同步倍速回听与声纹认人", "Enables synced playback and post-meeting voiceprint recognition"),
                        isOn: $appState.settings.saveAudioBackup
                    )

                    Divider().overlay(AppTheme.divider)

                    HStack(spacing: 8) {
                        fieldLabel(
                            L("本地录音存储空间", "Local Audio Storage"),
                            hint: appState.audioStorageStats.fileCount == 0
                                ? L("暂无音频备份文件", "No audio backup files")
                                : (theme.isEnglish
                                    ? "\(appState.audioStorageStats.fileCount) files · \(appState.audioStorageStats.formattedSize)"
                                    : "共 \(appState.audioStorageStats.fileCount) 个文件 · 占用 \(appState.audioStorageStats.formattedSize)")
                        )
                        Spacer()
                        CleanSmallButton(L("打开目录", "Reveal")) {
                            appState.revealAudioDirectoryInFinder()
                        }
                        Menu {
                            Button(L("清理 30 天前音频（保留文字纪要）", "Prune Audio Older Than 30 Days")) { appState.pruneAudioBackups(olderThanDays: 30) }
                            Button(L("清理 7 天前音频（保留文字纪要）", "Prune Audio Older Than 7 Days")) { appState.pruneAudioBackups(olderThanDays: 7) }
                            Divider()
                            Button(L("清理全部已完成会议音频", "Clear All Completed Audio"), role: .destructive) { appState.pruneAudioBackups(olderThanDays: 0) }
                        } label: {
                            cleanMenuLabel(L("清理音频", "Clean Up"))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(appState.audioStorageStats.fileCount == 0)
                    }
                }
            }

            // Card 2: Speech-to-Text Engine & Audio Enhancement
            SettingsCard(title: L("语音转写与降噪引擎", "Speech-to-Text & Denoising")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel(L("转写引擎", "ASR Engine"))
                        Spacer()
                        Menu {
                            ForEach(TranscriptionEngine.allCases) { engine in
                                Button(engine.displayName) { appState.settings.transcriptionEngine = engine }
                            }
                        } label: {
                            cleanMenuLabel(shortEngineName(appState.settings.transcriptionEngine))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider().overlay(AppTheme.divider)

                    HStack {
                        fieldLabel(L("会议语言", "Meeting Language"), hint: L("中英混说建议保持自动检测", "Keep Auto for bilingual Chinese/English meetings"))
                        Spacer()
                        Menu {
                            ForEach(TranscriptionLanguage.allCases) { lang in
                                Button(lang.displayName) { appState.settings.transcriptionLanguage = lang }
                            }
                        } label: {
                            cleanMenuLabel(appState.settings.transcriptionLanguage.displayName)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    if appState.settings.transcriptionEngine == .mlxQwen3ASR {
                        Divider().overlay(AppTheme.divider)

                        HStack {
                            fieldLabel(L("Qwen3-ASR 模型", "Qwen3-ASR Model"), hint: mlxCacheSummary)
                            Spacer()
                            Menu {
                                ForEach(MLXQwen3ModelPreset.all) { preset in
                                    Button("\(preset.label) · \(preset.footprintHint)") {
                                        appState.settings.mlxQwen3ModelID = preset.repoID
                                    }
                                }
                            } label: {
                                cleanMenuLabel(selectedMLXPresetShortLabel)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        HStack(spacing: 8) {
                            CleanPrimaryButton(
                                title: appState.mlxModelState.isBusy ? L("加载中...", "Loading...") : L("预下载 / 加载模型", "Preload Model"),
                                icon: "arrow.down.circle",
                                disabled: appState.mlxModelState.isBusy
                            ) {
                                Task { await appState.preloadMLXQwen3Model() }
                            }
                            if appState.mlxModelState.isReady {
                                CleanSmallButton(L("释放内存", "Unload")) {
                                    Task { await appState.unloadMLXQwen3Model() }
                                }
                            }
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showAdvancedMLX.toggle()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(L("镜像源与高级选项", "Mirror & Advanced"))
                                    Image(systemName: showAdvancedMLX ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9))
                                }
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if case .downloading(let progress, _) = appState.mlxModelState, progress > 0 {
                            ProgressView(value: progress).tint(AppTheme.brandPrimary)
                        }

                        if showAdvancedMLX {
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("自定义 HuggingFace Repo / 本地目录", "Custom HuggingFace Repo / Local Path"))
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                    CleanInputBox(placeholder: "mlx-community/Qwen3-ASR-1.7B-8bit", text: $appState.settings.mlxQwen3ModelID)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("HuggingFace 镜像源", "HuggingFace Mirror"))
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                    HStack(spacing: 6) {
                                        CleanInputBox(placeholder: "https://huggingface.co", text: $appState.settings.mlxHuggingFaceHost)
                                        CleanChipButton(L("官方源", "Official"), selected: appState.settings.mlxHuggingFaceHost.contains("huggingface.co")) {
                                            appState.settings.mlxHuggingFaceHost = "https://huggingface.co"
                                        }
                                        CleanChipButton(L("国内镜像", "CN Mirror"), selected: appState.settings.mlxHuggingFaceHost.contains("hf-mirror")) {
                                            appState.settings.mlxHuggingFaceHost = "https://hf-mirror.com"
                                        }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("补充语境提示（可选）", "Extra Context Hint (Optional)"))
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                    CleanInputBox(placeholder: "PR, API, Swift, MLX, GraphQL", text: $appState.settings.asrContextHint)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.softCardBg))
                        }

                        Divider().overlay(AppTheme.divider)

                        SettingsToggleRow(
                            title: L("Silero 逐帧流式人声检测", "Streaming Silero Neural VAD"),
                            subtitle: L("过滤敲键盘、风扇底噪并精准断句", "Filters keyboard & ambient noise for clean endpointing"),
                            isOn: $appState.settings.enableNeuralVAD
                        )

                        Divider().overlay(AppTheme.divider)

                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(L("嘈杂环境人声降噪 (DeepFilterNet3)", "Noisy-Environment Denoiser (DeepFilterNet3)"))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    if appState.settings.enableSpeechEnhancement {
                                        let cached = SpeechEnhancementService.isModelCachedLocally(modelID: appState.settings.speechEnhancementModelID)
                                        if cached {
                                            Text(L("已缓存", "Cached"))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(AppTheme.successGreen)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(Capsule().fill(AppTheme.successGreen.opacity(0.12)))
                                        } else {
                                            CleanSmallButton(appState.isPreloadingDenoiser ? L("下载中...", "Downloading...") : L("预下载", "Preload")) {
                                                Task { await appState.preloadSpeechEnhancementModel() }
                                            }
                                            .disabled(appState.isPreloadingDenoiser)
                                        }
                                    }
                                }
                                Text(L("在咖啡馆、开放办公区或外放开会时抑制背景噪声", "Suppresses background noise in open offices or cafés"))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $appState.settings.enableSpeechEnhancement)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(AppTheme.brandPrimary)
                        }

                        Divider().overlay(AppTheme.divider)

                        SettingsToggleRow(
                            title: L("外放开会双轨回声去重", "Speaker-to-Mic Echo Deduplication"),
                            subtitle: L("防止扬声器串入麦克风导致重复记录", "Prevents duplicate lines when using external speakers"),
                            isOn: $appState.settings.enableEchoDeduplication
                        )

                        Divider().overlay(AppTheme.divider)

                        SettingsToggleRow(
                            title: L("会后自动释放 MLX 显存与内存", "Auto-Unload MLX Weights After Meeting"),
                            subtitle: L("非录制时段待机零模型内存占用", "Frees GPU/unified memory while idle"),
                            isOn: $appState.settings.mlxAutoUnloadAfterMeeting
                        )
                    } else if appState.settings.transcriptionEngine == .openAITranscribe {
                        Divider().overlay(AppTheme.divider)
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel(L("OpenAI 转写模型", "OpenAI Transcribe Model"))
                            CleanInputBox(placeholder: "gpt-4o-mini-transcribe / whisper-1", text: $appState.settings.openAITranscribeModel)
                        }
                    }
                }
            }

            // Card 3: Team Glossary Dictionary
            SettingsCard(
                title: L("团队术语词典", "Team Glossary"),
                subtitle: L("自动合并声纹库姓名与日程参会人，提升中英专有名词转写准确度", "Merged with voiceprints and Calendar attendees to boost domain terminology accuracy")
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        CleanInputBox(placeholder: L("输入术语（支持逗号批量，如：MLX, PR, GraphQL, Kubernetes）", "Add terms (comma-separated, e.g. MLX, GraphQL, Kubernetes)"), text: $newGlossaryTerm) {
                            addGlossaryTerm()
                        }
                        CleanSmallButton(L("加入词典", "Add")) { addGlossaryTerm() }
                            .disabled(newGlossaryTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !appState.settings.glossaryTerms.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(appState.settings.glossaryTerms, id: \.self) { term in
                                    HStack(spacing: 4) {
                                        Text(term)
                                            .font(.system(size: 11.5, weight: .medium))
                                        Button {
                                            appState.settings.glossaryTerms.removeAll { $0 == term }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8.5, weight: .bold))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .foregroundStyle(AppTheme.brandPrimary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(AppTheme.brandSoftFill))
                                }
                            }
                        }
                    }
                }
            }

            // Card 4: Speaker Diarization Strategy
            SettingsCard(title: L("多说话人分离策略", "Speaker Diarization")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel(L("分离算法", "Algorithm"))
                        Spacer()
                        Menu {
                            ForEach(DiarizationStrategy.allCases) { s in
                                Button(s.displayName) { appState.settings.diarizationStrategy = s }
                            }
                        } label: {
                            cleanMenuLabel(appState.settings.diarizationStrategy == .sortformerFourSpeaker ? L("Sortformer (≤4 人)", "Sortformer (≤4 spk)") : L("ECAPA 聚类 (5~12 人)", "ECAPA Clustering (5–12)"))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: L("会中实时多说话人分离", "Live Multi-Speaker Diarization"),
                        subtitle: L("录制过程中实时匹配远端说话人声纹", "Identify remote speakers in real time during calls"),
                        isOn: $appState.settings.enableLiveSpeakerDiarization
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: L("导入音视频时自动区分说话人", "Auto-Diarize Imported Media"),
                        subtitle: L("离线转写完成后自动分轨并匹配声纹库", "Automatically label speakers on imported recordings"),
                        isOn: $appState.settings.enableSpeakerDiarization
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: L("自动匹配本地声纹库", "Auto-Match Local Voiceprints"),
                        subtitle: L("跨会议自动把「发言人 1 / 2」标为真实姓名", "Replace generic speaker labels with enrolled names across meetings"),
                        isOn: $appState.settings.autoIdentifyVoiceprints
                    )
                }
            }

            // Card 5: macOS Permissions
            SettingsCard(title: L("系统隐私权限", "macOS Privacy Permissions")) {
                VStack(spacing: 11) {
                    cleanPermissionRow(
                        title: L("仅系统音频录制", "System Audio Recording"),
                        detail: L("采集会议远端声音（无需完整录屏权限）", "Captures remote call audio without Screen Recording permission"),
                        status: nil,
                        buttonTitle: L("系统设置", "Open Settings")
                    ) {
                        appState.openPrivacySettings("Privacy_AudioCapture")
                    }

                    Divider().overlay(AppTheme.divider)

                    cleanPermissionRow(
                        title: L("麦克风", "Microphone"),
                        detail: L("采集本机发言，实现双轨逐字稿与声纹建档", "Captures your voice for dual-track transcripts & voiceprints"),
                        status: micStatus == .authorized,
                        buttonTitle: micStatus == .authorized ? L("系统设置", "Settings") : L("授权", "Authorize")
                    ) {
                        if micStatus == .notDetermined {
                            Task {
                                _ = await MicrophoneCapture.requestPermission()
                                refreshPermissions()
                            }
                        } else {
                            appState.openPrivacySettings("Privacy_Microphone")
                        }
                    }

                    Divider().overlay(AppTheme.divider)

                    cleanPermissionRow(
                        title: L("语音识别", "Speech Recognition"),
                        detail: L("Apple 本机识别回退链路所需权限", "Required only if using Apple Speech fallback"),
                        status: speechStatus == .authorized,
                        buttonTitle: speechStatus == .authorized ? L("系统设置", "Settings") : L("授权", "Authorize")
                    ) {
                        if speechStatus == .notDetermined {
                            Task {
                                _ = await LegacySpeechTranscriber.requestSpeechAuthorization()
                                refreshPermissions()
                            }
                        } else {
                            appState.openPrivacySettings("Privacy_SpeechRecognition")
                        }
                    }
                }
            }
        }
    }
}
