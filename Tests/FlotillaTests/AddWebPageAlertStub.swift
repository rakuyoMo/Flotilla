import AppKit

@testable import Flotilla

// MARK: - AddWebPageAlertStub

/// “添加网页…” 提示框的假环境：取标题、等停顿与等时限都是假的，由测试决定停顿与时限何时结束、何时交出什么标题；
/// 同时记下提示框交出的网页与补上的标题。不联网，也不真的等待，CI 上同样确定
@MainActor
final class AddWebPageAlertStub {
    /// 收到的取标题请求，按先后顺序：网址，与交出结果的回调
    private var requests: [(url: URL, completion: @MainActor (String?) -> Void)] = []

    /// 正在等的停顿，按先后顺序
    private var pauses: [@MainActor () -> Void] = []

    /// 每次获取开始等的时限，按先后顺序，与 `requests` 一一对应：提示框每开始一次获取就等一次时限
    private var timeLimits: [@MainActor () -> Void] = []

    /// 被取消的取标题请求的网址，按先后顺序
    private(set) var cancelledURLs: [URL] = []

    /// 提示框交出的、要加入的网页，按先后顺序
    private(set) var addedItems: [FolderItem] = []

    /// 提示框交给调用方补上的标题，与那一项的 id，按先后顺序
    private(set) var filledTitles: [(title: String, webPageID: UUID)] = []

    /// 请求过标题的网址，按先后顺序
    var requestedURLs: [URL] {
        requests.map(\.url)
    }

    /// 用这个假环境取标题、等停顿与时限的提示框
    func makeAlert() -> AddWebPageAlert {
        AddWebPageAlert(
            fetchTitle: { url, completion in
                self.requests.append((url, completion))

                return {
                    self.cancelledURLs.append(url)
                }
            },
            waitForPause: {
                self.pauses.append($0)
            },
            waitForTimeLimit: {
                self.timeLimits.append($0)
            }
        )
    }

    /// 以 sheet 弹出提示框，记下它交出的网页与补上的标题
    /// - Parameters:
    ///   - alert: 提示框
    ///   - window: 提示框挂在这个窗口上
    func beginSheet(of alert: AddWebPageAlert, on window: NSWindow) {
        alert.beginSheetModal(
            for: window,
            completionHandler: {
                self.addedItems.append($0)
            },
            titleHandler: {
                self.filledTitles.append(($0, $1))
            }
        )
    }

    /// 让正在等的停顿全部结束，按开始等的先后顺序
    func endPauses() {
        let endedPauses = pauses
        pauses = []

        for pause in endedPauses {
            pause()
        }
    }

    /// 让为某个网址开始的每一次获取都到时，不论它是否已有结果或已被取消
    /// - Parameter url: 网页的网址
    func endTimeLimit(of url: URL) {
        for (request, timeLimit) in zip(requests, timeLimits) where request.url == url {
            timeLimit()
        }
    }

    /// 交出某个网址的标题，与 LinkPresentation 一样经回调送达；被取消过的请求同样收到，用来检验晚到的结果被丢掉
    /// - Parameters:
    ///   - url: 网页的网址
    ///   - title: 取到的标题；为 nil 表示取不到
    func complete(_ url: URL, with title: String?) {
        for request in requests where request.url == url {
            request.completion(title)
        }
    }
}
