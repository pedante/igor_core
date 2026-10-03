# Provisioning and Installation

Status: **Igor 2 roadmap completion gate; runtime implementation deferred**.

This document gives the missing roadmap home to greenfield creation of external
resources. It builds on capabilities, reviewed composite capabilities,
Configuration Service, Deployment Service and Operational History. It does not
authorize provisioning work by itself.

## Product goal

Igor should eventually support both:

```text
brownfield:
  thing already exists -> recognize -> adopt selected responsibility

greenfield:
  user requests thing -> preflight -> create -> bind -> configure -> verify
```

Installing/enabling a module package is different from provisioning the
application or infrastructure that module knows how to operate.

## Required flow

A provisioning request should follow:

```text
typed user intent
  -> compatibility/preflight
  -> frozen proposed effects and providers
  -> explicit policy/approval
  -> durable attempt/identity placeholders before effects
  -> canonical capability execution
  -> bind native identities as they become known
  -> configuration through Configuration Service/capabilities
  -> independent verification
  -> deployment/relationship update
  -> explicit responsibility decision
  -> Operational History
```

Provider/module declarations may describe how to provision a domain. Core owns
admission, policy, approval, privilege, durable operation identity and
cross-authority consistency rules.

## Relationship to composite capabilities

Reviewed composite capabilities are useful for bounded synchronous composition,
for example package install -> service enable -> service start.

They are not a general workflow engine. Provisioning must not add loops,
arbitrary scripts, blind retry, generic rollback or durable resume cursors to
the composite-capability contract.

If provisioning must wait for reboot, OAuth, DNS, user action or another
external condition, use the separate Resumable Work contract.

## Deployment identity during creation

Before a changing effect, Igor needs enough durable intent to explain what it
was trying to create. Planned deployment/resource slots are not proof that a
native resource exists.

After each relevant effect, bind immutable/native identity at the earliest safe
point and independently verify it. Missing identity after a possible effect is
`unknown/unresolved`, not permission to create another copy.

Provisioned-by-Igor is origin/provenance. It does not automatically grant every
lifecycle/configuration/backup/update responsibility.

## Failure and recovery

Provisioning inherits the existing rule:

> effect uncertainty is reconciled before another changing attempt.

A failed/interrupted plan records completed/unknown effects. Igor performs
explicit READ reconciliation and then requires a newly authorized request for
remaining work where change is still needed.

Recovery is provider/domain-specific. Do not promise universal rollback for
package installation, external account creation, data migration or other
irreversible effects.

Destroy remains a separate exact-target capability and is never implied by
provisioning origin.

## User-visible preflight

Before approval, an operator should be able to inspect:

- requested outcome;
- selected providers/versions/platform mechanisms;
- resources/settings expected to be created or changed;
- approval and privilege points;
- relevant secret references without secret values;
- verification/postconditions;
- recovery limitations;
- whether external waits/reboot/user action may occur.

TUI, CLI and future APIs render the same backend proposal.

## Implementation gate

Provisioning follows the representative brownfield/application workflow rather
than preceding it. First prove that Igor can identify, adopt, configure, verify,
recover and release an application it did not create.

The first provisioning vertical slice is selected separately. Do not infer that
the Docker composite proof or the Nextcloud brownfield lab already proves
application provisioning.

Completion requires contract, regression, real vertical-slice, inspection and
recovery/reconciliation evidence under EXECUTION.md.
