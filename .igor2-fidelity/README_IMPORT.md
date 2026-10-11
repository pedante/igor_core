# Igor 2 fidelity evidence archive

Imported and verified locally on 2026-10-12 against `igor2` at
`a65f43e2583305550259183b3105a2190158812a`.

The source RFC v2, comparison report and reviewed candidate retain their supplied
bytes. The nested extraction directory was flattened. The candidate has a `.txt`
suffix because it is an immutable historical document whose relative links were
written for `docs/igor2/`, not live documentation in this archive. Only its filename
in `SHA256SUMS` changed; all three supplied content hashes remain unchanged.

Run `sha256sum -c SHA256SUMS` from this directory. The manifest covers:

- [Original 170-line RFC v2](source/igor2_collection_operator_rfc_v2.md).
- [Source-fidelity comparison](evidence/igor2_collection_rfc_v2_fidelity_review.md).
- [Reviewed 523-line candidate](reviewed_candidate/COLLECTION_OPERATOR_RFC.reviewed.md.txt).

The committed RFC at the inspected baseline differs from the reviewed candidate
only in three fidelity/gate evidence hunks: the opening source-comparison record,
the pre-acceptance readiness paragraph, and the DISCOVERY exit assessment. The
Step 18/20 contract, grammar, numerical limits and acceptance requirements are
unchanged. Byte-for-byte identity of the full current document is unnecessary.
D078/D079 supersede obsolete compatibility and master-reconciliation requirements.

See the [canonical closure record](../docs/igor2/COLLECTION_OPERATOR_RFC.md#fidelity-evidence-2026-10-12)
and [current status](../docs/igor2/STATUS.md) for scoped validation and readiness.
These source artifacts establish fidelity, not runtime or hardware proof.
