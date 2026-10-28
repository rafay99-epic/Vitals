import Testing
@testable import Vitals

struct ErrorReportingTests {
    private func project(_ channel: Channel) -> String {
        String(ErrorReporting.dsn(for: channel).split(separator: "/").last ?? "")
    }

    @Test func onlyStableReportsToProd() {
        #expect(project(.stable) == "4512333592526848")
    }

    @Test func nightlyAndDevReportToNightly() {
        #expect(project(.nightly) == "4512333983252480")
        #expect(project(.dev) == "4512333983252480")
    }
}
