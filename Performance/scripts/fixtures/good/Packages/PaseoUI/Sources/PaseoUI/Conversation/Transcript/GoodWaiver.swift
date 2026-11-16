// features: 
// Fixture: a waiver. The line is flagged by C08 and carries `perf-ok:` with a reason, so it is reported as a
// waiver (the report then asks the agent to escalate it) and not as a failure.
import SwiftUI

struct GoodWaiver: View {
    var body: some View {
        let formatter = DateFormatter() // perf-ok: C08 sheet body that is built once per launch // waived: C08
        Text(formatter.string(from: .now))
    }
}
