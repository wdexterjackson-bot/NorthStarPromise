# 05 — Backend: The Optional Cloud Processing Plane

**Status:** engineering-ready.
**Stack (locked in `docs/01-ARCHITECTURE.md` § 2, do not relitigate):** Python 3.12 + FastAPI · Postgres 16 +
pgvector · S3-compatible object store · Redis + Celery workers · containerized.
**Location in repo:** `Backend/`. Client counterpart: `Packages/NSPBackendClient/`.

---

## 0. Framing: what this plane is, and what it must never become

North-Star Promise is local-first. The canonical store is the user's device and their private iCloud
(`docs/02` § 4, § 6). This backend is **a transient processor plus three hosted services** — external share
links, team/enterprise administration, and integration brokering. It is not a copy of the product's data.

Three consequences follow, and every design choice below is derived from them:

1. **Detachability is a build-time fact, not a promise.** The `LocalOnly` build configuration compiles out
   `NSPBackendClient` entirely (`docs/01` § 4). `make test LOCAL_ONLY=1` runs the full suite with the backend
   unreachable. If a feature outside "cloud-quality transcription, external links, team admin, server-brokered
   connectors" fails in that configuration, the feature is misplaced, not the test.
2. **The backend can never be a prerequisite for a user recovering their own meeting.** Recovery is a
   manifest scan plus segment repair on the capturing device (`docs/02` § 4). No recovery path may call this
   API. There is no "restore from cloud" endpoint, because there is nothing to restore from — processing
   copies are purged, and under default policy the canonical audio, transcript, and notes were never here.
3. **Invariant I5 is enforced upstream of us.** Every request arrives with a `ProcessingGrant` minted by
   `NSPPolicy`. The server re-validates it; it does not mint it. A meeting with `ProcessingMode == .localOnly`
   cannot produce a grant, so it cannot produce a request. The server is the second gate, never the first.

### Why not make the backend canonical? (the defence)

The obvious cheaper architecture — upload everything, process server-side, sync down — is rejected because it
breaks the two structural differentiators in `docs/00` § 2. Wrist capture that depends on a server is not
"survives an absent phone and no network"; it is a phone-free *upload queue*. And "private by default,
verifiable by network inspection" is unfalsifiable if the server holds the corpus. The cost we accept is real:
duplicated retrieval implementations (local FTS5 + vector index *and* pgvector), reconciliation of provisional
and canonical transcripts on-device, and a harder story for cross-device semantic search. We accept it.

---

## 1. Design principles

| # | Principle | Concrete rule |
|---|---|---|
| P1 | **Ephemeral by default** | A processing copy has a hard TTL of **24 h** from upload, or **1 h** after the last artifact is retrieved, whichever is sooner. A reaper enforces it independently of job success. |
| P2 | **Zero-retention providers only** | A provider may not be selected for a job unless its contract entry asserts `zero_retention: true` and `no_training: true`. Enforced by a startup assertion over the provider registry, and by a per-job check in the model gateway. |
| P3 | **No training on customer content** | Contractual and technical. No customer bytes are written to any evaluation, fine-tuning, or prompt-cache store. Eval fixtures come from `Tools/evals`, never from production. |
| P4 | **Deletion receipts** | Every purge emits a signed, client-verifiable receipt (§ 3.5). Deletion is a state, then a job, then a receipt — mirroring `docs/02` § 1.6. |
| P5 | **Regional processing controls** | A grant carries `region` (`us`, `eu`, `apac`). Jobs execute only in that region's deployment; the gateway rejects cross-region routing with `409 region_mismatch` rather than silently relocating. |
| P6 | **Recovery independence** | No endpoint is on the meeting-recovery path. Asserted by a test that greps the client package for backend calls reachable from `RecoveryCoordinator`. |
| P7 | **Content-free control plane** | Job rows, audit events, metrics, traces, and logs carry IDs and sizes — never text. § 10. |
| P8 | **Human confirmation upstream** | Per I6, the backend executes external writes only against an already-confirmed payload with an idempotency key. It never originates a send. |

---

## 2. Service decomposition

All services are separate container images from one repo, sharing a `Backend/nsp_common` library (models,
auth, tracing, policy checks). Workers are Celery apps against Redis queues.

| Service | Responsibility | Scaling | Data it may touch |
|---|---|---|---|
| **gateway** (FastAPI) | AuthN/Z, grant validation, request signing verification, idempotency, rate limits, upload-session minting, job submission, artifact hand-back, WebSocket termination. | Stateless, HPA on RPS + p95 latency. 3+ replicas per region. | Postgres control tables; presigned URL minting. **Never** object bytes. |
| **asr-worker** | Batch ASR over a processing copy; emits token-level timings. | GPU or provider-bound; HPA on queue depth. Long tasks (minutes). | Reads one processing copy; writes artifact blob. |
| **diarization-worker** | Speaker clustering, `speakerClusterID` assignment. Never resolves `personID` (I4/§ 2 of `docs/02`). | CPU-bound, medium tasks. | Same copy + ASR artifact. |
| **summarization-worker** | Layered insights with `EvidenceSpan` candidates; runs the entailment prefilter. | LLM-provider-bound; HPA on queue depth + token budget. | Transcript artifact only — never audio. |
| **embedding-worker** | Chunk + embed transcript/insights for opted-in team indexing. Default tier: returns vectors to the client and stores nothing. | Batchy, high throughput. | Transcript artifact; `embedding` table only if tier opts in. |
| **retrieval-svc** | Ask/retrieval over pgvector **for team tier only**. Applies the access filter in the SQL that fetches candidates. | Read-heavy, replica-friendly. | `embedding`, ACL tables. |
| **sharelink-svc** | Hosted external share links: render, passcode, expiry, revocation, download policy. The only service that intentionally persists content, and only the explicitly shared subset. | Stateless + CDN in front. | `share_link`, share payload blobs. |
| **outbox-svc** | Server-brokered connector execution, idempotent, receipted, backoff. | Queue-depth scaled; per-destination concurrency caps. | `integration_receipt`, connector tokens. Payload only for the in-flight action. |
| **admin-svc** | Tenants, workspaces, members, roles, policy documents, retention defaults, region pinning, SSO/SCIM. | Low volume. | Tenant/policy tables. No meeting content. |
| **audit-svc** | Append-only audit log ingestion, hash-chaining, export. | Write-heavy, append-only. | `audit_event` (hashes, not payloads). |

---

## 3. The cloud data lifecycle

```
client                         gateway                     store / workers
  │  1. POST /v1/grants:validate  │
  ├──────────────────────────────▶│  verifies grant sig, region, tier
  │  2. POST /v1/uploads          │
  ├──────────────────────────────▶│  mints scoped presigned PUT + copyID
  │  3. PUT <presigned>           │
  ├───────────────────────────────┼──────────────▶ S3 (SSE-KMS, per-copy data key)
  │  4. POST /v1/jobs             │
  ├──────────────────────────────▶│──── enqueue ──▶ Celery
  │  5. GET /v1/jobs/{id}         │◀─── artifacts ─┤
  ├──────────────────────────────▶│
  │  6. GET /v1/artifacts/{id}    │
  ├──────────────────────────────▶│  presigned GET, single-use, 15 min
  │  7. DELETE /v1/processing-copies/{copyID}
  ├──────────────────────────────▶│──── purge ────▶ S3 delete + key destroy
  │◀───── signed DeletionReceipt ─┤
```

### 3.1 Grant

`ProcessingGrant` is minted by `NSPPolicy` (authoritative Swift declaration in `docs/06` § 2) and Ed25519-signed
by a device key registered at enrolment. The claims below are the **wire representation** of that same grant —
server-side fields are derived from it, not an independent definition. Claims:
`grantID`, `meetingID`, `workspaceID`, `tenantID`, `region`, `tier`, `scopes` (`asr`, `diarize`, `summarize`,
`embed`, `share`, `integrate`), `maxDurationSeconds`, `notAfter` (≤ 6 h), `policyID`, `deviceID`. The gateway
verifies signature, expiry, region, and that the requested job's scope ⊆ grant scopes. Grants are single-meeting
and replay-protected by `grantID` uniqueness.

### 3.2 Upload

`POST /v1/uploads` returns one presigned PUT per part, scoped to `s3://nsp-ephemeral-{region}/{tenantID}/{copyID}/`,
expiring in **30 minutes**. The client uploads segments (or a concatenated processing copy) already encrypted
under a per-copy data key wrapped by KMS. Object-level `Expiration` tag is set at creation so the bucket
lifecycle rule purges even if every service is down.

### 3.3 TTLs

| Object | TTL | Enforced by |
|---|---|---|
| Upload session (unused) | 30 min | Presign expiry + reaper |
| Processing copy | 24 h from upload, or 1 h after last artifact fetch | Reaper (`celery beat`, 5-min tick) + S3 lifecycle rule as backstop |
| Artifact blob | 24 h, or 1 h after fetch | Same |
| Job row (content-free) | 30 days | Nightly job |
| Deletion receipt | 400 days | Retention policy (evidence of deletion outlives the data) |
| Share link payload | `expiresAt` (default 14 d, max 180 d) | sharelink-svc + lifecycle |

### 3.4 If the client never comes back

This is the normal case for a phone that goes offline mid-job. The job **runs to completion**, artifacts are
written, and the TTL clock runs regardless. At expiry the reaper purges the copy and all artifacts, writes a
`DeletionReceipt` with `reason: "ttl_expired"`, and marks the job `expired`. The client, on next contact,
receives `410 Gone` from `GET /v1/artifacts/{id}` with the receipt embedded, and re-submits if it still wants
the work. **No unclaimed artifact is retained past TTL to be helpful.** The user lost nothing: the canonical
audio never left their device (I2).

### 3.5 Deletion receipt

```json
{
  "receiptID": "01924a...", "copyID": "01924a...", "meetingID": "0190f3...",
  "objectsPurged": [{"kind": "processing_copy", "sha256": "…", "bytes": 41238912},
                    {"kind": "artifact", "artifactID": "…", "sha256": "…"}],
  "keyDestroyed": true, "reason": "client_request",
  "purgedAt": "2026-08-19T15:41:02Z", "region": "eu",
  "signature": {"alg": "Ed25519", "keyID": "nsp-del-2026-08", "value": "base64…"}
}
```

The client verifies the signature against a pinned public key set and stores the receipt in its local
`audit_event` ledger. `keyDestroyed: true` means the per-copy KMS data key was scheduled for destruction, so
any residual replica is cryptographically inert.

---

## 4. The API

All paths are prefixed `/v1/`. **Versioning:** the major version is in the path and changes only for a breaking
change; additive fields never bump it. Two minor versions run concurrently for ≥ 90 days. Clients send
`NSP-Client-Version`; the gateway returns `NSP-API-Deprecation` with a sunset date when applicable.

**Idempotency:** every mutating endpoint (`POST`, `PUT`, `PATCH`, `DELETE`) **requires** `Idempotency-Key`.
The gateway stores `(tenantID, endpoint, key) → (status, response_hash, response_body)` for 24 h. A replay with
a matching request hash returns the stored response with `NSP-Idempotent-Replay: true`; a mismatched body under
the same key returns `409 idempotency_key_reuse`. Missing key → `400 idempotency_key_required`.

**Common errors:** `401 unauthenticated`, `403 grant_scope_denied`, `409 region_mismatch`, `410 expired`,
`413 payload_too_large`, `422 validation_error`, `429 rate_limited` (with `Retry-After`), `503 provider_unavailable`.

| Concern | Method + path | Request → Response | Codes |
|---|---|---|---|
| Token exchange | `POST /v1/auth/token` | `{deviceID, assertion, tenantHint?}` → `{accessToken, expiresIn, region, tier}` | 200, 401 |
| Grant validation | `POST /v1/grants:validate` | `{grant}` → `{grantID, scopes[], notAfter, accepted:true}` | 200, 403, 409 |
| Upload session | `POST /v1/uploads` | `{grantID, parts:[{sha256,bytes}], contentKind}` → `{copyID, parts:[{partNumber,url,expiresAt}], completeURL}` | 201, 403, 413 |
| Complete upload | `POST /v1/uploads/{copyID}:complete` | `{parts:[{partNumber,etag,sha256}]}` → `{copyID, verified:true, expiresAt}` | 200, 422 |
| Submit job | `POST /v1/jobs` | `{grantID, copyID, kind:"asr_batch"\|"summarize"\|"embed"\|"diarize", options{...}}` → `{jobID, state:"queued", estimatedSeconds}` | 202, 403, 422 |
| Job status | `GET /v1/jobs/{jobID}` | → `{jobID, state, progress, artifacts:[{artifactID,kind,bytes,sha256}], error?}` | 200, 404, 410 |
| Artifact | `GET /v1/artifacts/{artifactID}` | → `302` to single-use presigned GET (15 min) | 302, 403, 410 |
| Ask / retrieval | `POST /v1/ask` | `{grantID, query, workspaceIDs[], topK}` → `{answer, citations:[{meetingID,turnIDs,sampleRange,quotedText}]}` | 200, 403 |
| Delete + receipt | `DELETE /v1/processing-copies/{copyID}` | → `{receipt: DeletionReceipt}` | 200, 404 |
| Receipt fetch | `GET /v1/deletion-receipts/{receiptID}` | → `{receipt}` | 200, 404 |
| Share create | `POST /v1/share-links` | `{grantID, payload, scope, expiresAt, passcodeHash?, allowDownload}` → `{shareLinkID, url, expiresAt}` | 201, 403 |
| Share revoke | `DELETE /v1/share-links/{shareLinkID}` | → `{revokedAt}` | 200, 404 |
| Connector connect | `POST /v1/integrations/{connector}/connect` | `{workspaceID, redirectURI}` → `{authorizeURL, state}` | 201 |
| Connector execute | `POST /v1/integrations/{connector}/execute` | `{actionID, revision, destination, payload, confirmedBy}` → `{receiptID, externalID, state}` | 200, 202, 409 |
| Webhook register | `POST /v1/webhooks` | `{url, events[], secretHint}` → `{webhookID, signingKeyID}` | 201 |

Streaming ASR is not a REST endpoint; see § 5.

`POST /v1/jobs` example:

```json
{ "grantID": "01924a...", "copyID": "01924b...", "kind": "asr_batch",
  "options": { "languageHints": ["en-US","es-MX"], "glossary": ["Kubernetes","Ravindra"],
               "diarize": true, "modelPin": "asr.whisper-lg-v3@2026-05-01" } }
```

---

## 5. Streaming ASR transport (live preview only)

`WSS /v1/stream/asr?grantID=…&sessionID=…`. Live preview is a **progressive enhancement** (`CLAUDE.md` § 6);
it never produces canonical data.

**Frames.** Binary frames are audio; text frames are JSON control.

```
byte 0      : frame type (0x01 audio, 0x02 control-ack, 0x03 flush)
bytes 1-8   : startSample (int64, big-endian, device sample clock)
bytes 9-12  : sequence (uint32, monotonic, gapless)
bytes 13-   : Opus payload, 20 ms frames, 16 kHz mono
```

Server → client text frames: `{"type":"partial","seq":N,"turnID":"p-12","text":"…","startSample":…,"stability":0.4}`
and `{"type":"stable","seq":N,...}`. All emitted turns carry `revision < 0` and `isProvisional: true`, matching
`docs/02` § 2 (provisional revisions are negative).

**Backpressure.** Server advertises `{"type":"window","credits":K}`; the client may have at most `K`
unacknowledged audio frames in flight (default 50 ≈ 1 s). On credit exhaustion the client **drops preview
audio, never capture audio** — the segmenter is unaffected, because the canonical write path does not touch
this socket (I1/I2).

**Reconnection and resume.** On disconnect the client reconnects with `?sessionID=…&resumeFromSequence=N`. The
server holds a 60 s session shadow (last sequence, decoder state pointer, partial buffer) in Redis. Resume
within 60 s continues the session; beyond that, `4409 session_expired` and the client starts a fresh preview
session with a sequence reset — preview text prior to the gap is retained on-device and marked provisional.
Close codes: `4401` bad grant, `4403` scope denied, `4409` session expired, `4429` rate limited, `1011` server error.

**Reconciliation with the canonical batch pass.** The client never merges preview text into canonical
transcript. When the batch artifact arrives, `AlignmentJob` (`docs/01` § 5.3) maps provisional turns, markers,
ink strokes, and photos onto canonical sample offsets, then **replaces** the provisional turns wholesale
(revision `-n` → revision `1`). User edits made against a provisional turn are re-anchored by sample range and
surfaced as an explicit merge diff if the anchor moved by more than 500 ms. Preview output is never an
`EvidenceSpan` source.

---

## 6. Server-side data model

```sql
CREATE TABLE tenant (
  tenant_id      uuid PRIMARY KEY,
  tier           text NOT NULL CHECK (tier IN ('free','pro','team','enterprise')),
  region         text NOT NULL CHECK (region IN ('us','eu','apac')),
  retention_days int  NOT NULL DEFAULT 0,      -- 0 = ephemeral only
  created_at     timestamptz NOT NULL DEFAULT now());

CREATE TABLE workspace (
  workspace_id uuid PRIMARY KEY,
  tenant_id    uuid NOT NULL REFERENCES tenant,
  name_hash    bytea NOT NULL);                -- name itself is client-side; server stores a hash

CREATE TABLE grant (
  grant_id   uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenant,
  workspace_id uuid NOT NULL, device_id text NOT NULL,
  scopes text[] NOT NULL, region text NOT NULL,
  policy_id uuid NOT NULL, not_after timestamptz NOT NULL,
  consumed_at timestamptz);

CREATE TABLE processing_copy (
  copy_id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenant,
  grant_id uuid NOT NULL REFERENCES grant,
  object_key text NOT NULL, bytes bigint NOT NULL, sha256 bytea NOT NULL,
  kms_key_id text NOT NULL,
  state text NOT NULL CHECK (state IN ('pending','uploaded','processing','purged')),
  expires_at timestamptz NOT NULL, purged_at timestamptz);

CREATE TABLE job (
  job_id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenant,
  copy_id uuid REFERENCES processing_copy, kind text NOT NULL,
  state text NOT NULL CHECK (state IN ('queued','running','succeeded','failed','expired')),
  provider_id text, model_pin text, prompt_version text,
  audio_seconds int, input_tokens int, output_tokens int, cost_micros bigint,
  attempt int NOT NULL DEFAULT 0, correlation_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz);

CREATE TABLE artifact (
  artifact_id uuid PRIMARY KEY, job_id uuid NOT NULL REFERENCES job,
  tenant_id uuid NOT NULL, kind text NOT NULL,       -- transcript|diarization|summary|embedding
  object_key text NOT NULL, bytes bigint NOT NULL, sha256 bytea NOT NULL,
  expires_at timestamptz NOT NULL, fetched_at timestamptz);

CREATE TABLE deletion_receipt (
  receipt_id uuid PRIMARY KEY, tenant_id uuid NOT NULL,
  copy_id uuid NOT NULL, reason text NOT NULL,
  body jsonb NOT NULL, signature bytea NOT NULL, key_id text NOT NULL,
  purged_at timestamptz NOT NULL);

CREATE TABLE share_link (
  share_link_id uuid PRIMARY KEY, tenant_id uuid NOT NULL,
  payload_key text NOT NULL, scope jsonb NOT NULL,
  passcode_hash bytea, allow_download bool NOT NULL DEFAULT false,
  expires_at timestamptz NOT NULL, revoked_at timestamptz,
  view_count int NOT NULL DEFAULT 0);

CREATE TABLE integration_receipt (
  receipt_id uuid PRIMARY KEY, tenant_id uuid NOT NULL,
  idempotency_key text NOT NULL, destination text NOT NULL,
  request_hash bytea NOT NULL, external_id text, response jsonb,
  state text NOT NULL CHECK (state IN ('pending','sent','failed','conflict','superseded')),
  attempts int NOT NULL DEFAULT 0, next_retry_at timestamptz,
  UNIQUE (tenant_id, idempotency_key));

CREATE TABLE audit_event (
  event_id bigserial PRIMARY KEY, tenant_id uuid NOT NULL,
  actor text NOT NULL, action text NOT NULL, object_ref text NOT NULL,
  payload_hash bytea NOT NULL, result text NOT NULL,
  prev_hash bytea, this_hash bytea NOT NULL,        -- hash chain, tamper-evident
  at timestamptz NOT NULL DEFAULT now());

CREATE TABLE embedding (                            -- team/enterprise opt-in ONLY
  embedding_id uuid PRIMARY KEY, tenant_id uuid NOT NULL,
  workspace_id uuid NOT NULL, meeting_id uuid NOT NULL,
  turn_ids uuid[] NOT NULL, sample_start bigint, sample_end bigint,
  chunk_text text, vec vector(1024) NOT NULL,
  excluded_from_memory bool NOT NULL DEFAULT false);
CREATE INDEX ON embedding USING hnsw (vec vector_cosine_ops);
```

### What is NOT stored server-side under default policy

Canonical audio · canonical transcript · note blocks · insights · meeting titles · attendee names · calendar
data · `chunk_text` · any embedding. Processing copies and artifacts are transient blobs governed by § 3.3;
`job` rows hold **counts and IDs only**. `workspace.name_hash` exists so admin UI can match a name the client
supplies without the server learning it.

### What changes on team/enterprise opt-in

An explicit, admin-set, per-workspace `retention_days > 0` plus per-meeting user consent enables: persistent
`embedding` rows (with `chunk_text` for citation rendering), server-side Ask via `retrieval-svc`, and share
links whose payload outlives the processing copy. The opt-in is recorded as a policy document in `admin-svc`
and referenced by `policyID` on every grant, so an artifact can always answer "under which policy was this
retained?". Downgrading the setting schedules a purge job that emits deletion receipts per meeting.

---

## 7. Multi-tenancy and isolation

**Decision: Postgres row-level security with a single schema.** Not schema-per-tenant.

Justification: the server holds little per-tenant data and a lot of shared operational machinery. Schema-per-tenant
multiplies migration surface by tenant count (a 5,000-tenant migration is an outage class of its own), fragments
the connection pool, and makes the pgvector HNSW index unusable at sensible sizes. RLS gives one migration path,
one index, and a *database-enforced* boundary that survives an ORM mistake — the failure mode we actually fear.
Enterprise customers requiring physical separation get a dedicated regional deployment, which is a stronger
guarantee than a schema anyway.

```sql
ALTER TABLE embedding ENABLE ROW LEVEL SECURITY;
ALTER TABLE embedding FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON embedding
  USING (tenant_id = current_setting('nsp.tenant_id')::uuid);
```

The application role is never a superuser and never `BYPASSRLS`. `nsp.tenant_id` is set per-transaction from
the verified token by a FastAPI dependency; a request that reaches a repository without it raises before any SQL.

**Authorization before retrieval, never after generation.** This mirrors the client rule in `docs/02` § 5 and
the anti-pattern in `CLAUDE.md` § 8. The ACL predicate lives in the candidate-fetch SQL:

```sql
SELECT e.meeting_id, e.turn_ids, e.chunk_text
FROM embedding e
JOIN workspace_member m ON m.workspace_id = e.workspace_id
WHERE m.user_id = current_setting('nsp.user_id')::uuid
  AND e.excluded_from_memory = false
ORDER BY e.vec <=> $1 LIMIT $2;
```

Filtering generated text afterwards is prohibited — it leaks through paraphrase and it is untestable.

**Tenant-boundary tests.** `Backend/tests/isolation/` seeds two tenants with deliberately colliding content,
then for **every** table and **every** read path runs the query as tenant A and asserts zero tenant-B rows,
including: raw repository calls, `/v1/ask`, artifact fetch by guessed ID, share-link resolution, and a
`SET nsp.tenant_id` omission (must raise, not return everything). A new table without an RLS policy fails a
schema-conformance test in CI.

---

## 8. Model gateway

`Backend/nsp_common/gateway/` fronts every ASR and LLM provider behind two protocols:

```python
class ASRProvider(Protocol):
    id: str; zero_retention: bool; no_training: bool; regions: set[str]
    async def transcribe(self, copy: ProcessingCopyRef, opts: ASROptions) -> TranscriptArtifact: ...

class LLMProvider(Protocol):
    id: str; zero_retention: bool; no_training: bool; regions: set[str]
    async def complete(self, prompt: PinnedPrompt, ctx: UntrustedContext) -> Completion: ...
```

`UntrustedContext` is a distinct type from `PinnedPrompt` and cannot be concatenated into it — this is how
**I7** is enforced at the type level. Meeting content is passed as clearly delimited, non-privileged data;
model output never triggers a tool call (external writes go through § 9's confirmed outbox only).

**Selection** is a deterministic function of `(language, region, tier, jobKind)` resolved against a registry
file, then filtered by `zero_retention ∧ no_training ∧ region ∈ provider.regions`. An empty candidate set is a
`503 no_compliant_provider`, never a silent fallback to a non-compliant provider.

**Fallback and retry:** 3 attempts with exponential backoff + jitter (2 s, 8 s, 30 s) on 5xx/timeouts; on the
second failure, fall to the next compliant provider in the tier's ordered list and record `provider_id` per
attempt. 4xx from a provider is terminal. Circuit breaker opens per provider at 50 % error rate over 60 s.

**Cost accounting:** every job row records `audio_seconds`, `input_tokens`, `output_tokens`, `cost_micros`,
priced from a versioned rate card. Rolled up to cost-per-processed-hour per tenant and per provider — the
guardrail metric named in `docs/00` § 6.

**Pinning:** `model_pin` (`"asr.whisper-lg-v3@2026-05-01"`) and `prompt_version` are recorded on the job and
copied into every artifact's `Provenance` (`docs/02` § 2, Insight). Prompts are files in
`Backend/prompts/<name>/<version>.md`, content-hashed at build time; a prompt change is a new version, never an
edit. This makes artifacts reproducible and makes rollback a config change, not a redeploy of model code.

---

## 9. Integration plane

**On-device connectors** (Reminders, Calendar) never touch this backend — `NSPActions` writes them via EventKit.
**Server-brokered connectors:** Slack, Microsoft Teams, Notion, Google Drive, SharePoint, Asana, Linear, Jira,
Monday, Salesforce, HubSpot.

**OAuth broker.** `admin-svc` runs the authorization-code + PKCE flow per workspace, stores refresh tokens
encrypted with a per-tenant KMS key, and rotates access tokens. Tokens are never returned to the client; the
client holds only a `connectionID`.

```python
class Connector(Protocol):
    id: str
    def capabilities(self) -> set[Capability]      # create_task, post_message, create_page, upload_file …
    async def preview(self, payload: ActionPayload) -> RenderedPayload   # exact bytes shown to the human
    async def execute(self, payload: ActionPayload, key: str) -> ExecutionReceipt
    async def reconcile(self, receipt: ExecutionReceipt) -> ReceiptState
```

**Idempotent outbox.** Idempotency key = `actionID + destination + revision` — identical to the client rule in
`docs/01` § 5.4, so a client retry and a server retry collapse to the same row. `UNIQUE (tenant_id,
idempotency_key)` on `integration_receipt` makes dedupe a database property. Where the destination supports its
own idempotency header, the same key is forwarded; where it does not, `reconcile()` searches by external
marker before creating.

**Retry** is 6 attempts, exponential backoff with jitter, capped at 6 h, honouring `Retry-After`. **Conflict
states:** `conflict` when the external object changed since the confirmed revision (e.g. the Jira issue was
edited); the item stops, surfaces on-device, and requires re-confirmation — never an auto-overwrite (I6).
`superseded` when a newer revision was confirmed while an older attempt was in flight.

**Signed webhooks.** Outbound events (`job.succeeded`, `job.failed`, `copy.purged`, `share.viewed`,
`integration.receipt`) are signed `HMAC-SHA256(secret, timestamp + "." + body)` in `NSP-Signature`, with a 5-minute
timestamp window and replay cache. Webhook bodies carry **IDs only, never content**.

---

## 10. Security

- **TLS 1.3 only**, HSTS, modern cipher suites. Certificate pinning in `NSPBackendClient` against the
  regional endpoint's key set, with a documented rotation overlap.
- **Request signing:** in addition to the bearer token, mutating requests carry `NSP-Signature` over
  `(method, path, timestamp, sha256(body))` using the device key. Defeats a stolen bearer token in isolation.
- **Secrets** live in the cloud KMS/secret manager, injected as short-lived env at container start. No secret in
  an image, repo, or log. Provider API keys rotate every 90 days.
- **Encryption at rest:** Postgres volume encryption + S3 SSE-KMS. Every processing copy gets its **own** data
  key; purge destroys the key, so deletion is cryptographic, not just an unlink (§ 3.5).
- **No audio or transcript in logs.** A logging filter rejects any log record whose payload exceeds 512 bytes of
  free text or matches known content field names, and CI runs a log-shape test that submits a fixture meeting
  and asserts the captured log stream contains none of the fixture's distinctive strings.
- **PII in traces:** spans carry `tenantID`, `jobID`, `correlationID`, durations, byte counts, token counts.
  Never text, never titles, never attendee names, never file names derived from titles.
- **No meeting content ever reaches analytics.** Analytics is a separate first-party, content-free pipeline
  (`docs/01` § 2). The producer library physically cannot accept a free-text field; its event schema is a closed
  enum of typed dimensions. This is the server-side mirror of **I5** — and note that under `.localOnly` no
  request exists at all, so this rule governs the *cloud-allowed* case only.

---

## 11. Observability and SLOs

| SLO | Target | Alert |
|---|---|---|
| Stop → draft summary, 60-min English meeting | **< 45 s median**, < 120 s p95 | p95 breach 10 min |
| Streaming ASR first partial | < 2 s p95 | p95 breach 5 min |
| Gateway availability | 99.9 % monthly | Error budget burn > 2× |
| Job success rate | ≥ 99.0 % excluding client-caused 4xx | < 98 % over 30 min |
| Purge SLA | 100 % of copies purged by TTL + 5 min | **Any** miss pages — this is a promise, not a target |
| Cost per processed hour | tracked, budget-alerted per tenant tier | > 130 % of 7-day trailing |

Queue-depth alerting: warn at depth > 2× the 15-minute rolling throughput, page at depth implying > 10 min wait.
Autoscale on the same signal so alerts are usually informational.

**Correlation IDs.** The client mints `correlationID = UUIDv7` per job and sends it in `NSP-Correlation-Id`. It
appears on the job row, every worker span, and every log line — and it is **derived from nothing**: not the
meetingID, not a hash of it. A support engineer with a correlationID can see timing, provider, retries, and cost,
and can see no content whatsoever. The client stores the mapping locally so the user can produce it.

**Error budgets:** 99.9 % availability = 43 min/month. Budget exhausted ⇒ feature work stops, reliability work
starts, and the streaming preview path is the first thing shed under load (it is an enhancement; batch is not).

---

## 12. Deployment

- **Environments:** `dev` (ephemeral, per-PR), `staging` (fake providers + one real provider, synthetic tenants),
  `prod-us` / `prod-eu` / `prod-apac`. Each production region is an independent stack — separate Postgres,
  separate buckets, separate KMS keys, **no cross-region replication of content-bearing stores**. Data residency
  is achieved by not having the data elsewhere, not by policy.
- **Containers:** one image per service, distroless base, non-root, read-only root filesystem, pinned digests.
- **Migrations:** Alembic, numbered and append-only, forward-compatible in two steps (expand → deploy → contract).
  A migration that would break the previous image fails a CI check.
- **Release:** rolling for workers (drain: finish the in-flight task, up to 15 min); **blue/green for the
  gateway** with a 10 % canary on error rate + p95 for 10 minutes before full cut. Automatic rollback on canary
  breach. Prompt and model pins roll back independently via config.
- **Local development:** `docker-compose.yml` brings up gateway, one worker of each kind, Postgres 16 + pgvector,
  Redis, and MinIO. Providers default to `FakeASRProvider` / `FakeLLMProvider`, which return deterministic
  fixtures from `Backend/tests/fixtures/` — so the whole plane runs offline with no API key and no cost.
- **`make backend-test`** runs, in order: `ruff` + `mypy --strict`; unit tests; the isolation suite (§ 7);
  the log-shape and analytics-shape tests (§ 10); and the **contract tests** (§ 13) against the compose stack
  with fake providers. It requires no cloud credentials, so it runs in CI on every PR and on a laptop.

---

## 13. Contract testing with `NSPBackendClient`

**One rule: the client's mock and the server's contract tests derive from the same OpenAPI document.**

`Backend/openapi/nsp-v1.yaml` is generated from the FastAPI app and committed. From it:

1. `Tools/generate-client-contract.py` emits Swift `Codable` request/response types and a `MockNSPBackend` into
   `Packages/NSPTestSupport/Generated/`. Hand-editing generated files is a CI failure.
2. `schemathesis` property-tests the live server against the same document in `make backend-test`, fuzzing
   every endpoint for schema conformance, status-code correctness, and idempotency behaviour (submit twice with
   one key → identical response; submit twice with a mutated body → `409`).
3. Shared **golden fixtures** in `Backend/tests/fixtures/contract/*.json` are consumed by both sides: the Swift
   suite decodes them into client types; the Python suite validates them against the response models. A field
   added on one side without the other fails both.
4. CI gate: regenerating the OpenAPI document must produce no diff. A server change that alters the wire format
   without regenerating — and therefore without updating the Swift client and mock — cannot merge.

Because the client's mock is generated, `make test LOCAL_ONLY=1` and `make test` exercise the *same shapes* the
server promises, while never requiring the server to exist. That is the whole point of this document.
