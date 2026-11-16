import Foundation
import PaseoProtocol
import Testing

/// `skills.selection` rides the daemon config as raw JSON; decode it leniently and hide it when
/// absent, because the skills RPCs are not implemented in this client.
@Suite struct SkillsTests {
    private func config(from json: String) throws -> DaemonConfig {
        try JSONDecoder().decode(DaemonConfig.self, from: Data(json.utf8))
    }

    @Test func selectionAllDecodes() throws {
        let config = try config(from: """
        {"skills": {"selection": {"mode": "all"}}}
        """)
        #expect(config.skillsSelection == .all)
        #expect(config.skillsSelection?.label == "All skills")
    }

    @Test func selectionCustomDecodesWithIds() throws {
        let config = try config(from: """
        {"skills": {"selection": {"mode": "custom", "skills": ["paseo", "worktrees"]}}}
        """)
        #expect(config.skillsSelection == .custom(["paseo", "worktrees"]))
        #expect(config.skillsSelection?.label == "Custom (2 selected)")
    }

    @Test func selectionCustomWithNonStringIdsDropsThem() throws {
        let config = try config(from: """
        {"skills": {"selection": {"mode": "custom", "skills": ["paseo", 42, true]}}}
        """)
        #expect(config.skillsSelection == .custom(["paseo"]))
    }

    @Test func missingSkillsFieldIsNil() throws {
        let config = try config(from: "{}")
        #expect(config.skillsSelection == nil)
    }

    @Test func missingSelectionIsNil() throws {
        let config = try config(from: #"{"skills": {}}"#)
        #expect(config.skillsSelection == nil)
    }

    @Test func unknownModeIsNil() throws {
        let config = try config(from: """
        {"skills": {"selection": {"mode": "everything"}}}
        """)
        #expect(config.skillsSelection == nil)
    }

    @Test func skillsWithNonStandardShapesDoNotCrash() throws {
        let config = try config(from: #"{"skills": ["not", "an", "object"]}"#)
        #expect(config.skillsSelection == nil)
    }
}
