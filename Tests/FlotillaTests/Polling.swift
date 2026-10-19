// MARK: - Polling

/// 测试里等一个条件成立：最多等若干轮，每轮至少 20 ms，期间让出主线程
///
/// 按轮数而不按时钟等：kqueue 的事件、计时到期、QuickLook 的结果回到主线程时，排在其它测试已经排着的任务之后，
/// 整套测试一起跑时会晚到几秒到几十秒；每一轮也排在它之后，轮数够了它一定已经跑过
enum Polling {
    /// 等到条件成立，最多等 rounds 轮、每轮至少 20 ms
    /// - Parameters:
    ///   - rounds: 最多等几轮；默认 100 轮，总共至少 2 s
    ///   - condition: 要等的条件，每轮开始时在主线程上检查
    /// - Returns: 等到了为 true，轮数用完为 false
    @MainActor
    @discardableResult
    static func wait(rounds: Int = 100, until condition: () -> Bool) async -> Bool {
        for _ in 0 ..< rounds {
            guard !condition() else { return true }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return condition()
    }
}
