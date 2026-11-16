import Foundation
import PaseoProtocol
import Testing

@Suite struct WorkspaceTitleNullTests {
    @Test func clearingTitleEncodesExplicitNull() throws {
        let data = try JSONEncoder().encode(WorkspaceTitleSetRequest(workspaceId: "w1", title: nil))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.contains("title"))
        #expect(object["title"] is NSNull)
    }
}
