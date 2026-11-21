# Curriculum Domain Contract — Phase 2

**Status:** DRAFT / NOT APPROVED. Domain model only. Content ownership/licensing follows existing D-012 and Product Owner decisions; no shared-content licensing or catalog scope is silently expanded. Synthetic data only (D-014).

## 1. Canonical hierarchy

The educational curriculum hierarchy for MVP is:

`Grade → Subject → Book / Edition → Chapter → Topic → Subtopic`

- Grade is a controlled key, not a display label.
- Subject belongs to a grade and has a source/owner classification.
- Book identifies a curriculum text/resource and edition; chapter ordering is scoped to a book edition.
- Topic belongs to a chapter; subtopic belongs to a topic.
- A curriculum item may have an optional stable external/reference code, but uniqueness is scoped by owner/source and grade.
- Titles/order numbers are display metadata, not stable identity.

The current Workspace skeleton has Subject → Chapter → Topic but no Book/Edition or Subtopic. That is incomplete relative to the canonical hierarchy and must be reconciled.

## 2. Ownership and source boundaries

- Platform reference curriculum, Workspace-owned custom curriculum and any explicitly licensed content must have distinct source/ownership metadata.
- A Workspace may create a custom subject/book/topic only within its own ownership boundary.
- A Workspace cannot modify Platform-owned reference content or another Workspace's custom content.
- A Workspace customization of a reference curriculum must be an overlay/mapping owned by that Workspace; it must not mutate the shared reference source.
- D-012 and the approved content ownership/licensing rules remain controlling. This contract does not authorize Platform-owned Program Templates or shared program catalogs beyond the accepted scope.

## 3. Versioning and curriculum changes

- Published curriculum editions/versions are immutable.
- Corrections or curriculum updates create a new edition/version with source, effective period, change reason and actor.
- Topic/subtopic mapping across versions is explicit and versioned; do not assume old and new curriculum nodes are identical because their titles match.
- Student mastery/progress records retain the exact curriculum node/version they reference.
- If a node is retired or moved, historical study sessions, tests, reviews and plans remain linked to their original node; a mapping to a successor is a separate relation.
- Deletion of a referenced curriculum node is restricted; archive/deprecate and preserve references.

## 4. Mastery and educational evidence

- Mastery may be recorded at topic or subtopic level with source evidence, timestamp, confidence and assessment/rule version.
- Aggregated chapter/subject mastery is derived from versioned evidence and a deterministic aggregation rule; it is not an unexplained mutable scalar.
- Test responses, study sessions, reviews and counselor assessments can contribute evidence but retain their distinct source.
- Manual counselor override is attributable, reasoned and preserved as an override event.
- Progress from an older curriculum version must not be silently assigned to a different topic after curriculum change.

## 5. Required schema structures

The Workspace schema should include or map:
- `curriculum_books` and `curriculum_book_editions`;
- `chapters` scoped to book edition (or a documented equivalent);
- `topics` and `subtopics`;
- stable source/owner metadata distinguishing platform reference vs Workspace custom;
- explicit curriculum version/successor mapping;
- mastery evidence/history at topic/subtopic level.

All Workspace-owned curriculum rows must be isolated to the current Workspace DB. Shared reference curriculum must be read-only to Workspace runtime roles and versioned under Platform governance.

## 6. Required acceptance tests

1. Chapter cannot reference a book edition from another subject/grade.
2. Topic cannot reference a chapter from a different book/edition.
3. Subtopic cannot reference a topic outside its chapter/subject/grade chain.
4. Workspace runtime cannot mutate Platform reference curriculum.
5. Workspace A cannot read/write Workspace B custom curriculum.
6. Published edition/node cannot be silently mutated or deleted.
7. New edition preserves old references and explicit successor mapping.
8. Mastery evidence remains bound to the original curriculum version after update.
9. Duplicate stable curriculum code is rejected within its defined owner/source scope.
10. Cross-Workspace access and export do not leak custom curriculum metadata.

All tests are specifications until implemented and executed.

## 7. Open decisions

- Exact Platform reference curriculum source and licensing/attribution obligations.
- Whether books/editions are MVP-managed or imported from a controlled source.
- Whether Workspace custom curriculum can fork reference nodes or only add overlays.
- Curriculum update/mapping governance and who approves changes.
- Whether subtopic-level mastery is mandatory in MVP or optional by curriculum.

**Gate impact:** WS-DOM-05 remains open until Book/Edition/Subtopic and ownership/versioning are reconciled with the schema. Phase 2 remains NOT READY.
