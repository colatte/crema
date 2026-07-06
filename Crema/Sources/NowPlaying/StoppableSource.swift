/// A source that can be shut down synchronously — kill its process / cancel its
/// polling — so the app can tear it down on quit (applicationWillTerminate)
/// without waiting for deinit, which does not run reliably on process exit.
protocol StoppableSource: AnyObject {
    func stop()
}
