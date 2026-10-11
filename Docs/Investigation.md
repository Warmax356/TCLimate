# Protocol and validation notes

TCLimate uses unofficial international TCL Home cloud APIs. This document records the implemented protocol and its validation limits. Original packages, captures, decompiled code, and detailed local investigation logs are excluded from the repository.

## Account and device access

The implementation is informed by [nemesa/ha-tcl-home-unofficial-integration](https://github.com/nemesa/ha-tcl-home-unofficial-integration/tree/fdba4d7a0b8213f4f68a74b4ce0f932343802b6b), MIT licensed. Attribution is retained in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

1. Sign in at the selected regional `account/login` endpoint using the TCL email and an MD5-encoded TCL password. MD5 is required by this API; transport uses HTTPS. Direct Google OAuth is not implemented.
2. Discover account-specific cloud URLs through `prod-center.aws.tcljd.com/v3/global/cloud_url_get`.
3. Exchange the SSO session at the discovered cloud's `v3/auth/refresh_tokens` endpoint for SaaS and Cognito tokens.
4. Exchange the Cognito token for temporary AWS credentials using `GetCredentialsForIdentity`.
5. List linked devices through `v3/user/get_things`, signed with MD5 of timestamp, nonce, and SaaS token.
6. Read reported state through AWS IoT `GetThingShadow` at `data-ats.iot.<region>.amazonaws.com`, signed with AWS Signature Version 4.
7. Publish desired property changes to `$aws/things/{deviceId}/shadow/update`, then reread reported state to check confirmation.

Client/app IDs and API hosts in the source identify the public protocol. They are not account credentials. Account passwords, SSO/SaaS tokens, AWS keys, device IDs, and product keys are obtained at runtime; none are embedded in the repository. API version headers are retained for compatibility with verified requests.

Discovered service URLs must use HTTPS and a TCL domain. Automatic HTTP redirects are rejected so credentials and signatures remain scoped to the original endpoint. Server error bodies are not surfaced in the UI or logs.

## AC controls

Recognized split ACs use `powerSwitch`, `targetTemperature`, and `currentTemperature`. The current conservative target range is 16–30°C. Unknown models or unreadable reported state disable controls.

Mode, fan, Eco, sleep, display, beep, and airflow mappings come from the reference integration and reported device properties. The client supports standard and seven-speed fan protocols. Additional controls appear only when the corresponding state is reported. Mode changes clear reported Eco, Turbo, and Sleep flags; fan changes clear Eco. Commands preserve the selected temperature unless explicitly changed.

## Electricity reporting

The older React Native `/v3/ac/{deviceId}/power/consumption/info` endpoint returned `10003`. Inspection of the Android Flutter module identified a separate electricity API; a successful request capture established the current contract:

- `GET /v1/ac/statistics/electricity/summary?timeType=2` on the discovered regional device host.
- Device selection through `deviceId` and `productKey` headers.
- SaaS/SSO authentication and timestamp, nonce, and MD5 signature headers.
- Daily rows in `data.ecoDetails[].dataList[]`, using `time` and `totalElectricity`.

The parser displays the most recent seven local calendar days. Missing, invalid, negative, and nonfinite readings are excluded; an actual zero remains zero. A seven-day total is available only with all seven readings. Energy is fetched on demand and remains in memory. No estimated cost or persistent energy history is implemented.

## Artwork

The app uses native vector AC glyphs and a programmatically drawn snowflake icon. It does not bundle or download TCL product artwork. Previously inspected thumbnails and original app packages remain local research material and are excluded from Git.

## Validation

Live validation with a Pakistan account and two Split AC-1 units established authentication, discovery, reported state reads, power changes, temperature changes, and daily electricity readings, including zero usage. Commands were followed by reported-state checks, and both units were restored to their original settings.

This confirms cloud-reported behavior, not independent physical observation of airflow or compressor operation. Additional controls have offline encoding tests but have not been physically exercised. Other models and account regions remain unverified.

Offline tests cover signing vectors, account URL validation, parsing, command guards, both fan protocols, airflow encodings, and electricity data handling. Local packaging uses a persistent signing certificate to preserve Keychain access across updates. Local development builds are not notarized. The separate [release process](Releasing.md) requires Developer ID signing, notarization, stapling, and Gatekeeper validation before publishing a binary.

## Credential handling

The optional saved email/password is stored in macOS Keychain, using the service `io.loopbreak.TCLimate`. Sign out removes that item. Session tokens and temporary AWS credentials remain in memory. Diagnostic launch modes used during development have been removed from the distributed executable.

Do not publish raw captures, authentication responses, device identifiers, or signing keys in issues or pull requests.
