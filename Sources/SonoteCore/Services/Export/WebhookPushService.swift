import Foundation
import CryptoKit

public enum WebhookPushError: LocalizedError {
    case missingURL
    case invalidURL(String)
    case httpError(Int, String)
    case remoteRejected(String)

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            return SonoteLocale.t("尚未配置 Webhook 地址。请在「设置 → 协作与备份」中填写飞书、钉钉或自定义 Webhook URL。", "Webhook URL is not configured. Set it in Settings -> Sync & Backup.")
        case .invalidURL(let url):
            return SonoteLocale.t("无效的 Webhook 地址：\(url)", "Invalid Webhook URL: \(url)")
        case .httpError(let code, let body):
            return SonoteLocale.t("Webhook 推送失败 (HTTP \(code))：\(body)", "Webhook push failed (HTTP \(code)): \(body)")
        case .remoteRejected(let msg):
            return SonoteLocale.t("远端返回错误：\(msg)", "Remote rejected webhook: \(msg)")
        }
    }
}

/// Pushes structured meeting minutes directly to Feishu (Interactive Card), DingTalk (Markdown),
/// or Custom JSON Webhooks (Notion / n8n / Zapier), with official HMAC-SHA256 signing support.
public final class WebhookPushService: @unchecked Sendable {
    public static let shared = WebhookPushService()
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func push(
        meeting: MeetingSession,
        provider: WebhookProvider,
        webhookURL: String,
        secret: String = "",
        timestamp: Date = Date()
    ) async throws {
        let trimmedURL = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { throw WebhookPushError.missingURL }

        let targetURLString: String
        let payload: [String: Any]

        switch provider {
        case .feishu:
            targetURLString = trimmedURL
            payload = Self.buildFeishuPayload(for: meeting, secret: secret, timestamp: timestamp)
        case .dingtalk:
            targetURLString = Self.buildDingTalkSignedURL(baseURL: trimmedURL, secret: secret, timestamp: timestamp)
            payload = Self.buildDingTalkPayload(for: meeting)
        case .customJSON:
            targetURLString = trimmedURL
            payload = Self.buildCustomJSONPayload(for: meeting)
        }

        guard let url = URL(string: targetURLString) else {
            throw WebhookPushError.invalidURL(targetURLString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebhookPushError.httpError(0, "无响应")
        }
        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        guard (200...299).contains(http.statusCode) else {
            throw WebhookPushError.httpError(http.statusCode, String(bodyStr.prefix(240)))
        }

        // Check Feishu (`code != 0`) or DingTalk (`errcode != 0`) logical rejection codes
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let code = json["code"] as? Int, code != 0 {
                let msg = (json["msg"] as? String) ?? "code \(code)"
                throw WebhookPushError.remoteRejected(msg)
            }
            if let errcode = json["errcode"] as? Int, errcode != 0 {
                let errmsg = (json["errmsg"] as? String) ?? "errcode \(errcode)"
                throw WebhookPushError.remoteRejected(errmsg)
            }
        }
    }

    // MARK: - Payload Builders & Official HMAC-SHA256 Signing

    public static func feishuSign(timestampSeconds: Int64, secret: String) -> String {
        let stringToSign = "\(timestampSeconds)\n\(secret)"
        let key = SymmetricKey(data: Data(stringToSign.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(), using: key)
        return Data(mac).base64EncodedString()
    }

    public static func dingTalkSign(timestampMillis: Int64, secret: String) -> String {
        let stringToSign = "\(timestampMillis)\n\(secret)"
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        let base64 = Data(mac).base64EncodedString()
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return base64.addingPercentEncoding(withAllowedCharacters: allowed) ?? base64
    }

    public static func buildDingTalkSignedURL(baseURL: String, secret: String, timestamp: Date = Date()) -> String {
        let cleanSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSecret.isEmpty else { return baseURL }
        let millis = Int64(timestamp.timeIntervalSince1970 * 1000)
        let sign = dingTalkSign(timestampMillis: millis, secret: cleanSecret)
        let sep = baseURL.contains("?") ? "&" : "?"
        return "\(baseURL)\(sep)timestamp=\(millis)&sign=\(sign)"
    }

    public static func buildFeishuPayload(
        for meeting: MeetingSession,
        secret: String = "",
        timestamp: Date = Date()
    ) -> [String: Any] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var mdParts: [String] = []
        let tagText = meeting.tags.isEmpty ? "" : " · " + meeting.tags.map { "#\($0)" }.joined(separator: " ")
        mdParts.append("🕒 \(df.string(from: meeting.startedAt)) · \(meeting.sourceAppName) · \(meeting.chineseDurationText)\(tagText)")

        if !meeting.minutes.overview.isEmpty {
            mdParts.append("**一、会议摘要**\n\(meeting.minutes.overview)")
        }
        if !meeting.minutes.topics.isEmpty {
            let topicText = meeting.minutes.topics.map { topic in
                let pts = topic.points.map { "• \($0)" }.joined(separator: "\n")
                return "**\(topic.title)**\n\(pts)"
            }.joined(separator: "\n\n")
            mdParts.append("**二、核心要点**\n\(topicText)")
        }
        if !meeting.minutes.decisions.isEmpty {
            let dec = meeting.minutes.decisions.map { "✅ \($0)" }.joined(separator: "\n")
            mdParts.append("**三、会议决议**\n\(dec)")
        }
        if !meeting.minutes.actionItems.isEmpty {
            let todos = meeting.minutes.actionItems.map { item in
                let mark = item.isCompleted ? "☑" : "☐"
                let meta = [item.owner, item.dueDate].filter { !$0.isEmpty && $0 != "待定" }.joined(separator: " / ")
                return meta.isEmpty ? "\(mark) \(item.task)" : "\(mark) \(item.task)（\(meta)）"
            }.joined(separator: "\n")
            mdParts.append("**四、待办事项**\n\(todos)")
        }
        if !meeting.minutes.openQuestions.isEmpty {
            let qs = meeting.minutes.openQuestions.map { "❓ \($0)" }.joined(separator: "\n")
            mdParts.append("**五、待确认风险**\n\(qs)")
        }

        let cardBody = mdParts.joined(separator: "\n\n")
        var payload: [String: Any] = [
            "msg_type": "interactive",
            "card": [
                "config": ["wide_screen_mode": true],
                "header": [
                    "template": "blue",
                    "title": [
                        "tag": "plain_text",
                        "content": "📝 会议纪要｜\(meeting.title)"
                    ]
                ],
                "elements": [
                    [
                        "tag": "markdown",
                        "content": cardBody
                    ]
                ]
            ]
        ]

        let cleanSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSecret.isEmpty {
            let ts = Int64(timestamp.timeIntervalSince1970)
            payload["timestamp"] = "\(ts)"
            payload["sign"] = feishuSign(timestampSeconds: ts, secret: cleanSecret)
        }
        return payload
    }

    public static func buildDingTalkPayload(for meeting: MeetingSession) -> [String: Any] {
        let md = MeetingStore.exportMarkdown(for: meeting, includeTranscript: false)
        return [
            "msgtype": "markdown",
            "markdown": [
                "title": "会议纪要：\(meeting.title)",
                "text": md
            ]
        ]
    }

    public static func buildCustomJSONPayload(for meeting: MeetingSession) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        return [
            "event": "sonote.meeting.exported",
            "id": meeting.id.uuidString,
            "title": meeting.title,
            "sourceApp": meeting.sourceAppName,
            "startedAt": iso.string(from: meeting.startedAt),
            "durationSeconds": Int(meeting.duration),
            "tags": meeting.tags,
            "overview": meeting.minutes.overview,
            "topics": meeting.minutes.topics.map { ["title": $0.title, "points": $0.points] },
            "decisions": meeting.minutes.decisions,
            "actionItems": meeting.minutes.actionItems.map {
                ["task": $0.task, "owner": $0.owner, "dueDate": $0.dueDate, "isCompleted": $0.isCompleted]
            },
            "openQuestions": meeting.minutes.openQuestions,
            "markdown": MeetingStore.exportMarkdown(for: meeting, includeTranscript: false)
        ]
    }
}
