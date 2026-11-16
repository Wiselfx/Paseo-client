// Features import only PaseoStore. They may read PaseoKit and PaseoProtocol value types
// (ConnectionState, AgentSnapshot, TimelineItem…), but never construct a connection or send a
// request: that's the store's job. See ARCHITECTURE.md.
@_exported import PaseoKit
@_exported import PaseoProtocol
