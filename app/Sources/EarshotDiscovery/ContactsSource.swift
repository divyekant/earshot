import Contacts
import EarshotCore
import Foundation

/// Optional names from the Contacts app. It is off until the owner switches it on and macOS gives access.
/// It reads names and nicknames only: no phone numbers, no addresses. The data stays on the Mac.
public enum ContactsSource {
    /// True if macOS gives earshot access to Contacts. This call shows no prompt.
    public static var authorized: Bool { CNContactStore.authorizationStatus(for: .contacts) == .authorized }

    /// Asks macOS for access. macOS shows its prompt once. The app bundle needs NSContactsUsageDescription (T7).
    public static func requestAccess() async -> Bool {
        do { return try await CNContactStore().requestAccess(for: .contacts) } catch { return false }
    }

    /// The names of all cards, for one app. Returns an empty list without access.
    public static func names(appID: String, limit: Int = 5000) -> [NameEntry] {
        guard authorized else { return [] }
        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
                                       CNContactOrganizationNameKey].map { $0 as CNKeyDescriptor }
        let request = CNContactFetchRequest(keysToFetch: keys)
        var out: [NameEntry] = []
        try? CNContactStore().enumerateContacts(with: request) { contact, stop in
            if let entry = NameMerge.contactEntry(appID: appID, given: contact.givenName, family: contact.familyName,
                                                  nickname: contact.nickname, organization: contact.organizationName) {
                out.append(entry)
            }
            if out.count >= limit { stop.pointee = true }
        }
        return NameMerge.merge([out])
    }
}
