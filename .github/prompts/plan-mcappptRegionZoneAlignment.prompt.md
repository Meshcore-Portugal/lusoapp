## Plan: MCAPPPT Region-Zone Alignment

Implement a region-backed internal ZoneContext API in MCAPPPT that matches MeshCore firmware behavior (zone == region/default flood scope), reuses MeshCoreOne architecture patterns, and adds capability-gated support for firmware v10+ (with v11+ features enabled when available).

**Steps**
1. Phase 1 - Firmware contract mapping and terminology lock (blocks all): finalize MCAPPPT naming where user-facing text can say Zone but protocol/model layer maps to Region and Default Flood Scope. Confirm wire contract from firmware companion radio implementation: CMD_SEND_ANON_REQ (0x39), CMD_SET_DEFAULT_FLOOD_SCOPE (0x3F), CMD_GET_DEFAULT_FLOOD_SCOPE (0x40), RESP_CODE_DEFAULT_FLOOD_SCOPE (0x1C), PUSH_CODE_BINARY_RESPONSE (0x8C).
2. Phase 2 - Protocol layer additions in MCAPPPT (depends on 1): extend command constants and companion encoder/decoder to support default flood scope set/get and anonymous region requests. Add strict payload parsing and UTF-8 safety rules aligned with firmware limits (30-byte max display name, 31-byte field with null-termination behavior mirrored at app side).
3. Phase 3 - Domain models and internal ZoneContext API (depends on 2): add internal models for KnownRegion, DefaultFloodScope, RegionDiscoveryResult, and ZoneContextSnapshot. Keep SelfInfo/DeviceInfo minimally extended to avoid protocol breakage, and create a dedicated ZoneContext provider/service boundary instead of overloading existing providers.
4. Phase 4 - Service and state wiring (depends on 3): add RadioService methods for getDefaultFloodScope, setDefaultFloodScope, and requestRegionsByAnonReq. Update connection bootstrap flow to feature-detect firmware capabilities and populate zone/region context during initial sync without delaying critical connect UX.
5. Phase 5 - Persistence and resolver pipeline (depends on 3, parallel with 4 after interfaces are set): persist known regions and default scope in radio-scoped storage keys, then add a transport-code region resolver for inbound packet attribution (using the same SHA-256 hashtag normalization and transport-code calculation semantics used by MeshCoreOne and firmware).
6. Phase 6 - UI integration (depends on 4 and 5): add region management and default scope controls to MCAPPPT radio/channel settings using existing app patterns; expose discovery results and manual add/remove with validation and safe fallback when firmware capability is absent.
7. Phase 7 - Compatibility gates and fallbacks (depends on 4 and 6): implement capability checks for v10+ baseline, with v11+ required for persisted default scope and v13+ optional path for ad-hoc repeater requests. Ensure unsupported commands degrade gracefully with clear UX and no hard errors during connect.
8. Phase 8 - Tests and verification (depends on 2-7): add protocol, provider, service, and UI tests focused on binary framing, scope-key derivation, fallback behavior, persistence isolation by radio ID, and connection switching.

**Parallelism and dependency notes**
1. Phase 5 can start once Phase 3 model contracts are finalized, in parallel with Phase 4 service wiring.
2. Phase 6 can begin with mocked providers before Phase 5 completes, but final wiring depends on both 4 and 5.
3. Phase 8 should be staged: protocol tests as soon as Phase 2 lands, then provider/service tests after 4/5, and widget tests after 6.

**Relevant files**
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MeshCore/examples/companion_radio/MyMesh.cpp — canonical command/response behavior for anon request and default flood scope.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MeshCore/docs/cli_commands.md — region semantics and operational behavior.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/protocol/commands.dart — add missing command/response constants.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/protocol/companion_encoder.dart — encode set/get default flood scope and anon request payloads.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/protocol/companion_decoder.dart — decode RESP_CODE_DEFAULT_FLOOD_SCOPE and binary region responses.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/protocol/companion_responses.dart — new typed response models for region/scope data.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/protocol/models.dart — add zone/region context models and validation helpers.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/services/radio_service.dart — request/get/set methods and response stream integration.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/providers/radio_providers.dart — ZoneContext provider surface and state holders.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/providers/parts/connection_notifier.dart — initial sync orchestration and capability-gated flow.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/services/storage_service.dart — radio-scoped persistence for known regions/default scope.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/ui/screens/radio_settings_screen.dart — default scope UI.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MCAPPPT/lib/ui/screens/channels_list_screen.dart — optional zone-awareness display hooks.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MeshCoreOne/MeshCore/Sources/MeshCore/Session/MeshCoreSession+Regions.swift — reference region request flow.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MeshCoreOne/MeshCore/Sources/MeshCore/Protocol/TransportCodeRegionResolver.swift — reference resolver algorithm.
- c:/Users/GonZo/Documents/_GZ/HAMRADIO/MeshCore/MeshCoreOne/MC1Services/Sources/MC1Services/Services/SettingsService.swift — reference verified set/get default scope flow.

**Verification**
1. Protocol unit tests: assert exact bytes for setDefaultFloodScope clear/set, getDefaultFloodScope, and anon regions request payloads; assert parser accepts empty or full default scope response and rejects malformed sizes.
2. Decoder/response tests: validate PUSH_CODE_BINARY_RESPONSE region parsing strips timestamp and returns normalized list (excluding wildcard where intended).
3. Service tests: verify RadioService request/response matching, timeout handling, and unsupported-command fallback behavior.
4. Provider tests: verify connection_notifier populates ZoneContext only when supported and never blocks mandatory connect flow.
5. Persistence tests: verify known regions and default scope are isolated by currentRadioId and survive reconnect/app restart.
6. Resolver tests: verify normalized region hashing (# prefix, trim, private-region exclusion) and deterministic transport-code matching.
7. Widget tests: verify region management/default-scope controls render and disable correctly by firmware capability.
8. Manual verification on hardware: firmware v10, v11, and v13 devices; confirm UX for unsupported, supported, and ad-hoc discovery paths.

**Decisions**
- Included: Protocol support for get/set default flood scope, region discovery anon request, known-regions persistence/resolution, and UI changes.
- Included: Compatibility baseline v10+ with graceful fallback.
- Included: Internal API centered on ZoneContext abstraction backed by firmware Region semantics.
- Excluded for first delivery: multi-zone concurrent session execution and broad data-model partitioning by zone beyond scoped metadata/persistence.

**Further Considerations**
1. Naming strategy: Option A keep internal naming as region and map UI labels to zone; Option B dual naming ZoneContext with explicit firmwareRegion fields. Recommendation: Option B for clearer long-term abstraction.
2. Scope verification strictness: Option A fire-and-forget writes; Option B MeshCoreOne-style write-then-read verification. Recommendation: Option B to avoid hidden mismatch and improve reliability.
3. Discovery UX: Option A auto-add discovered regions directly; Option B show selectable results before add. Recommendation: Option B to reduce accidental list pollution.