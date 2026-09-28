import Foundation
import Security
import Testing
@testable import Search

@Suite struct VaultRefusalTests {
    @Test func denyOrADialogClosedIsARefusal() {
        #expect(Vault.isRefusal(errSecAuthFailed))
        #expect(Vault.isRefusal(errSecUserCanceled))
    }

    @Test func nothingThereOrAnAnswerIsNot() {
        #expect(!Vault.isRefusal(errSecSuccess))
        #expect(!Vault.isRefusal(errSecItemNotFound))
        #expect(!Vault.isRefusal(errSecInteractionNotAllowed))
    }
}
