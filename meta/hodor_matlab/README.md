# HODOR MATLAB Suite

A native MATLAB interface to the curated [HODOR dataset on PANGAEA](https://doi.org/10.1594/PANGAEA.980000), without a Python dependency. **Verified locally on MATLAB R2026b (Windows)**; automated CI targets **R2026b**. Compatibility with older releases (including R2022b) has not yet been verified. The base downloader, metadata readers, and validators use core MATLAB. Image Processing Toolbox is **not** required for these components.

This is a MATLAB companion to [hodor-python](https://github.com/gboeer/hodor_python), not a wrapper around it.

## Getting started

```matlab
addpath('path/to/HODOR/meta/hodor_matlab')
ds = hodor.HODORDataset('D:\HODOR');

% Metadata, including species counts, is lazily downloaded and cached.
counts = ds.counts;
interesting = ds.findSequences('Species','fish_cod','MinCount',10);

% One sequence = two cameras and one sonar, plus 3 timestamp sidecars.
result = ds.downloadSequence(42);
result = ds.downloadVideo([42 43]);  % Only cam1 + cam2 and timestamps.
result = ds.downloadSonar(42);       % Only sonar and timestamps.

report = ds.validateSequence(42, 'Level','standard');
report = ds.validateDataset('Level','quick'); % Local sequences only.
```

`setup` adds this folder to the MATLAB path; the `+hodor` folder must remain inside `meta/hodor_matlab`. The example `examples/quickstart.m` includes a basic metadata/filters workflow.

## API

| Method/property | Purpose |
| --- | --- |
| `ds.sequences` | Local canonical HODOR sequence index (TSV file named `sequences.csv`) |
| `ds.counts` | PANGAEA activity counts as a MATLAB `table`, compatible with `hodor-python` species names |
| `ds.findSequences(...)` | Filter by `Species`, `MinCount`, `From`, `To`, `MinDuration`, `MaxResults` (returns a table) |
| `ds.info(id)` | Sequence metadata, enriched with activity counts when available |
| `ds.downloadSequence(ids,...)` | Download video, sonar and timestamp sidecars |
| `ds.downloadVideo(ids,...)` | Download both cameras and timestamps |
| `ds.downloadSonar(ids,...)` | Download sonar and timestamps |
| `ds.validateSequence(id,...)` | Full list of selected files for one sequence; missing files reported as failures |
| `ds.validateDataset(...)` | Check local sequences by default, or use `'OnlyLocal',false` to include all expected files |
| `ds.refreshMetadata()` | Explicitly refresh metadata from the official sources |
| `ds.recordChecksums(ids,...)` | Establish or compare local SHA-256 references |
| `ds.verifyChecksums(ids,...)` | Check files against local SHA-256 references |

`ids` can be a sequence ID scalar or vector, IDs **0 through 5849**. Select individual sensors with `'Sensors', ["sonar","cam1"]`. Downloads have optional `'Force',true` and `'Validate',false` arguments. Validation supports `'Level','quick'`, `'standard'`, or `'deep'` and optional `'SaveReport',true`.

`ds.findSequences` returns a table; get an ID vector with `interesting.SeqID`.

The PANGAEA count tables are **camera-based, partially filtered MaxN counts**, not the extrapolated totals from Table 1 of the publication. This distinction is described in the repository's main README.

## Local SHA-256 integrity baselines

A local SHA-256 manifest detects later changes to files, including changes that leave their byte count unchanged. It does **not** establish that the original files matched an independently published PANGAEA checksum.

```matlab
% Optional: record checksums of newly downloaded files.
ds.downloadSequence(42,'RecordSHA256',true);

% Explicitly establish a baseline for existing local files.
r = ds.recordChecksums(42);

% Check stored baselines without modifying them or fetching PANGAEA sizes.
r = ds.verifyChecksums(42);

% Include local checksum verification in ordinary validation.
r = ds.validateSequence(42,'Level','quick','CheckSHA256',true);

% Restrict a check to particular sensors or multiple sequences.
r = ds.verifyChecksums([42 43],'Sensors',["cam1","cam2"]);
```

All three download methods accept `'RecordSHA256',true`. This opt-in hashes only newly completed transfers, never implicitly trusts files skipped by the downloader. For previously downloaded or imported data, explicitly call `recordChecksums` after checking that the files are suitable as a reference. Pass `ds.sequences.sequenceNo` to select every sequence; missing expected files are reported, not downloaded.

References are stored in `meta/checksums_sha256.tsv` in the local dataset, with portable relative paths, SHA-256, byte count, UTC timestamp and origin (`local` or `download`). Preserve an independent backup of this file. The manifest is validated before updating and newly recorded entries never replace existing references, including after forced re-downloads. A mismatch is reported even when the byte count is unchanged. Use one writer per dataset; concurrent modification of files or manifests is unsupported. If a legitimate new dataset revision requires a new baseline, archive the old manifest separately and deliberately establish a new one.

| Checksum status | Meaning |
| --- | --- |
| `RECORDED` | New local reference established explicitly or after an opted-in download |
| `MATCH` | Current bytes match an existing local reference |
| `MISMATCH` | Current bytes differ; reference preserved |
| `NO_BASELINE` | File exists, but has no stored local reference |
| `MISSING` / `EMPTY` | File absent / empty |
| `ERROR` | Hashing failed; inspect diagnostic message |

`recordChecksums` and `verifyChecksums` write separate CSV reports by default (disable with `'SaveReport',false`). Automatic download recording writes `reports/checksum_download.csv` for new transfers and warns on mismatches or hash failures; the download result still describes the transport outcome. Neither operation modifies media. `'CheckSHA256',true` on either validation API adds three checksum columns; a mismatch or hashing failure is `FAIL`, a missing reference is at least `WARN`, and a matching local reference does **not** remove other warnings, including unknown published sizes.

Hashing streams files in 1 MiB blocks using SHA-256 from MATLAB's bundled Java runtime (a JVM-enabled MATLAB session is required). Hashing can be I/O-intensive on large datasets, so normal download and quick/standard/deep validation behavior is unchanged unless the checksum options are enabled.

## Validation levels

- **quick**: existence, nonempty files, exact file-size comparison against published PANGAEA byte counts (when available). If PANGAEA size metadata is unavailable, present files are reported `WARN` rather than claimed to be verified.
- **standard**: quick checks plus timestamp validity, monotonicity, large gaps, sequence-time bounds, three decoded video samples, video/timestamp duration agreement, and common temporal overlap.
- **deep**: standard checks plus decoding **every frame**, comparison of actual frame counts to sidecar timestamp counts, mean brightness/entropy, and camera/sonar quality anomaly warnings. Deep validation may take substantial time and requires local video files.

Report statuses: `PASS`, `WARN`, and `FAIL`. Timestamp/synchronization checks **do not** assume equal sonar and camera frame rates. Visual anomalies (very dark, overbright, high entropy) are warnings, *not* proof of data corruption.

PANGAEA's text export can display rounded sizes such as `2.5 MBytes` under a `[Bytes]` column heading. These are kept as unknown expected sizes (`NaN`), so the validator reports `WARN` for present files. Only integer byte counts, including values such as `340 Bytes`, support exact size checks. Rounded values are never converted into purported exact byte counts. Sequence metadata retains `mergingFrames` as text because some entries contain semicolon-separated frame lists.

Reports are written to `HODOR/reports/validation_<level>.csv` by default for `validateDataset`; the downloader keeps its latest per-file statuses in `HODOR/reports/download_manifest.csv`. For large runs, start with quick validation.

## Storage, download handling and limitations

On the first access, the suite retrieves `meta/sequences.csv` from this repository (GitHub) and the published PANGAEA `.tsv` tables. Responses are parsed before replacing cached metadata, so an invalid refresh leaves the previous cache intact. Subsequent access uses local cache; call `refreshMetadata()` to update it. To use an entirely offline copy, initialize with `'AllowNetwork',false` and ensure the needed metadata are already cached under `meta/`.

The directory layout is the same one referenced in the repository's canonical `sequences.csv` (local `camera/` and `sonar/` folders). The downloader uses PANGAEA's **per-file** URLs, which do not require bulk-download registration. Large bulk ZIP/TAR archives are intentionally not downloaded automatically.

Downloads use temporary `.part` files, retry network errors and PANGAEA tape-retrieval responses, and request HTTP `Range` when partial data exist. If a server ignores `Range`, the incomplete download is discarded and restarted rather than appended. If the published byte size is available, completed files are checked against it before being moved to their final names. **Size equality does not provide cryptographic integrity verification.** Files with matching sizes are skipped; existing files with an unexpected size are preserved until a replacement successfully downloads.

Resumed responses are staged separately and their `Content-Range` is checked before appending; temporary server errors preserve the existing partial file. Staging needs additional disk space for the resumed response. HTTP `Content-Length`, when supplied, is also checked before promotion, even when the published size is unavailable. Transport completeness alone does not establish dataset integrity.

PANGAEA may need time to restore files from tape; failed files remain visible in the result table and may be retried by calling the method again. No background job is created. MATLAB's native `VideoReader` decoder determines which MP4 formats can be checked on each platform.

## Running tests

```matlab
addpath('path/to/HODOR/meta/hodor_matlab');
results = runtests('path/to/HODOR/meta/hodor_matlab/tests');
disp(results)
```

Automated tests use local metadata with no network; a few create tiny videos using the platform's MPEG-4 `VideoWriter` profile and skip when that profile is unavailable. Before real-download integration, inspect the selected files' sizes and use a separate test dataset folder; start with one sensor. The historical `viewSequence.m` and `analyze_complete_set.m` remain unchanged in `meta/matlabTools`.

### Opt-in live integration test

The separate [live integration runner](integration/runLiveIntegration.m) checks real PANGAEA camera media without making the offline CI dependent on PANGAEA availability. From the repository root:

```matlab
addpath('meta/hodor_matlab/integration');
preflight = runLiveIntegration(); % metadata + HEAD only; no media GET
result = runLiveIntegration('Download',true); % stereo + timestamp sidecars
% Optional complete sequence (only when all six HEAD requests succeed):
% result = runLiveIntegration('Download',true,'IncludeSonar',true);
```

Each call creates a fresh temporary QA dataset and retains evidence under its `reports/` folder. By default, it considers at most five candidates (IDs 0, 2900, then short sequences), with a 100 MiB total advertised HEAD-size budget. Use `'CandidateIDs',[0 2900]` to restrict candidates, `'ParentFolder',folder` to select an existing scratch parent, or `'Deep',true` for an additional full-frame decoding test. `'MaxBytes'` is a **preflight** limit, not a hard streaming bandwidth cap; actual file sizes are checked after transfer. The runner requests at most one candidate's media per call, does not force downloads, and uses no media retries.

- `READY`: HEAD preflight passed, with downloading disabled.
- `BLOCKED`: no candidate passed HEAD preflight or a media GET returned a transient server status.
- `FAIL`: an API, download, validation, transfer-size, or repeat-skip assertion failed.
- `PASS`: requested files downloaded; local sizes matched HEAD, quick and standard validation had no failures, videos decoded, timestamps overlapped, and the repeat call skipped all files without modifying them. Review any validation warnings separately.

Reports include `head_probes.csv`, `integration_summary.json`, download and repeat tables, transport-size comparison, and validation CSVs when the corresponding stages run. HEAD lengths are transport metadata, **not** independent published byte counts or cryptographic integrity evidence. No existing production dataset is used. The optional live runner is not part of `runtests('meta/hodor_matlab/tests')` or the automatic CI.

### GitHub Actions (R2026b)

The [MATLAB Suite CI workflow](../../.github/workflows/matlab-suite.yml) runs the offline unit suite on a GitHub-hosted **Windows** runner using MATLAB **R2026b**. It triggers on pushes to `main`, pull requests targeting `main`, and manual dispatch when available. Feature-branch updates are covered by the pull-request event, avoiding duplicate Windows MATLAB jobs. It uses the official `matlab-actions/setup-matlab@v3` and `matlab-actions/run-tests@v3` actions.

- Test discovery is limited to `meta/hodor_matlab/tests`; the MATLAB source path is `meta/hodor_matlab`.
- Failures appear in the GitHub Actions job summary; JUnit results and statement-coverage XML are uploaded as run artifacts (14-day retention).
- CI is deliberately **offline**: no PANGAEA media downloads or large-scale `deep` validation. Live camera/sonar integration must be verified separately.
- A green CI result verifies the selected tests on the runner, **not** all of HODOR or other MATLAB releases. Inspect the job summary for incomplete/skipped codec tests.

The initial local Windows R2026b QA reported 29/29 offline tests and 14/14 separate HTTP regressions. Only the committed offline MATLAB tests are run by this CI workflow; the local HTTP-mock harness is not part of the GitHub repository.

## Attribution

HODOR is distributed through [PANGAEA](https://doi.org/10.1594/PANGAEA.980000). Please cite the dataset and its [IEEE Data Descriptions paper](https://doi.org/10.1109/IEEEDATA.2025.3596913) when using it.
