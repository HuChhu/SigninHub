import Foundation
import BackgroundTasks

/// 后台签到调度。
///
/// ⚠️ 这一段是 iOS 平台的真限制，不是偷懒：
/// Android 用 AlarmManager.setExactAndAllowWhileIdle 能做到秒级准点；
/// iOS 只有 BGAppRefreshTask，**执行时机由系统决定**，常见表现是
/// 「昨天没跑」「隔两天跑一次」，App 被用户划掉后更是完全不跑。
/// 所以这里不做「每天 08:00 必达」的承诺，只做「系统给机会就跑一轮」。
///
/// 真正稳的安排是把 backend/ 挂在一台常开设备上，iOS App 只当控制台。
/// 设置页里写明这一点，不骗用户。
enum BGSign {
    static let taskID = "app.signhub.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            scheduleNext()
            let work = Task {
                let ok = await runOnce()
                refresh.setTaskCompleted(success: ok)
            }
            refresh.expirationHandler = { work.cancel() }
        }
    }

    /// 安排下一次。earliestBeginDate 只是「最早」，系统可能更晚。
    static func scheduleNext() {
        let req = BGAppRefreshTaskRequest(identifier: taskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 6)
        try? BGTaskScheduler.shared.submit(req)
    }

    /// 打本机控制台的 /api/checkin/all。后端在本机，失败率极低。
    static func runOnce() async -> Bool {
        guard let token = KeychainBox.read(account: "api_token"), !token.isEmpty,
              let url = URL(string: "http://127.0.0.1:8787/api/checkin/all") else {
            return false
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "X-API-Token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        req.timeoutInterval = 60
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }
}

