import Testing
@testable import Vitals

struct ScrubTests {
    private let owner = [("/Users/abdul", "~"), ("Abdul's MacBook Pro", "<mac>"), ("Abdul Rafay", "<user>"), ("abdul", "<user>")]

    @Test func dropsTheOwnerPathsLinksAndAddresses() {
        #expect(Scrub.text("can't read /Users/abdul/Library/Caches/com.foo", identities: owner) == "can't read <path>")
        #expect(Scrub.text("Abdul's MacBook Pro went to sleep", identities: owner) == "<mac> went to sleep")
        #expect(Scrub.text("GET https://mac.tail1234.ts.net:7443/api failed", identities: owner) == "GET <url> failed")
        #expect(Scrub.text("no route to 192.168.1.44:47810", identities: owner) == "no route to <ip>")
        #expect(Scrub.text("couldn't open Invoice.pdf", identities: owner) == "couldn't open <file>")
        #expect(Scrub.text("signed in as abdul@rafay99.com", identities: []) == "signed in as <email>")
        #expect(Scrub.text("The file “Abdul Secret Project” couldn’t be opened", identities: []) == "The file “<name>” couldn’t be opened")
        #expect(Scrub.text("no answer from Abduls-MacBook-Pro.local:47810", identities: []) == "no answer from <host>:47810")
        #expect(Scrub.text("route fe80::1c2b:3a4d%en0 failed", identities: []) == "route <ip> failed")
        #expect(Scrub.text("dial 2001:db8:85a3:0:0:8a2e:370:7334", identities: []) == "dial <ip>")
    }

    @Test func homeKeepsPathsReadable() {
        #expect(Scrub.home("/Users/abdul/Downloads/Vitals.app/Contents/MacOS/Vitals", identities: owner) == "~/Downloads/Vitals.app/Contents/MacOS/Vitals")
    }

    @Test func keepsWhatExplainsTheBug() {
        let message = "SMC key FNum read failed (kIOReturnNotPrivileged) at 11:10:46 in std::exception"
        #expect(Scrub.text(message, identities: owner) == message)
        #expect(Scrub.text("client.app.fg", identities: []) == "client.app.fg")
        #expect(Scrub.text("vitals-macos@0.145-dev", identities: []) == "vitals-macos@0.145-dev")
    }
}
