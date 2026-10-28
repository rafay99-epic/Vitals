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
    }

    @Test func keepsWhatExplainsTheBug() {
        let message = "SMC key FNum read failed (kIOReturnNotPrivileged)"
        #expect(Scrub.text(message, identities: owner) == message)
    }
}
