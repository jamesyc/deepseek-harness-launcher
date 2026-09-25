# Developer ID signing and notarization in GitHub Actions

The local `tcapsulesmb-notary` profile is a Keychain item on your Mac. GitHub runners start with a fresh Keychain, so the profile name alone cannot authenticate CI. The release job recreates a temporary `ci-notary` profile from GitHub environment secrets.

## One-time setup

1. In GitHub, create an environment named `release` under **Settings → Environments**. Restrict it to version tags and consider requiring a reviewer. Signing secrets are used only by the tag release job, never by pull-request tests.
2. In Keychain Access, find **Developer ID Application: Yushen Chang (M22Z394H44)**, expand it to confirm that its private key is present, and export that identity as a password-protected `.p12`. A certificate without its private key cannot sign on CI. Do not add the `.p12` to the repository.
3. Set these environment secrets:

   | Secret | Value |
   | --- | --- |
   | `MACOS_CERTIFICATE_P12_BASE64` | The complete `.p12` file, base64 encoded as one line. |
   | `MACOS_CERTIFICATE_PASSWORD` | The password chosen when exporting the `.p12`. |

   From the repository checkout, for example:

   ```sh
   base64 -i /path/to/DeveloperID.p12 | tr -d '\n' | gh secret set --env release MACOS_CERTIFICATE_P12_BASE64
   gh secret set --env release MACOS_CERTIFICATE_PASSWORD
   ```

4. Configure **one** notarization credential method in the same environment:

   - **App Store Connect API key:** set `APPLE_NOTARY_API_KEY_P8_BASE64` (base64 of the `.p8` key), `APPLE_NOTARY_API_KEY_ID`, and, for a Team API key, `APPLE_NOTARY_API_ISSUER_ID`. For an Individual API key, omit the issuer ID. The `.p8` is a private key; never commit it.
   - **Apple ID:** set `APPLE_NOTARY_APPLE_ID` and `APPLE_NOTARY_APP_PASSWORD` (an Apple app-specific password, not your normal Apple ID password). The workflow uses team ID `M22Z394H44`.

   API key example:

   ```sh
   base64 -i /path/to/AuthKey.p8 | tr -d '\n' | gh secret set --env release APPLE_NOTARY_API_KEY_P8_BASE64
   gh secret set --env release APPLE_NOTARY_API_KEY_ID
   gh secret set --env release APPLE_NOTARY_API_ISSUER_ID
   ```

The workflow fails before packaging if the certificate or chosen notary credentials are missing. The runner imports the identity into a temporary Keychain, validates the expected signing identity, and recreates `ci-notary` there. After Apple accepts the submission, it staples the ticket, checks Gatekeeper, rebuilds the final zip, and writes a checksum. A failed notarization cannot publish a release.

## Local equivalent

Your current Keychain identity and `tcapsulesmb-notary` profile can be used directly:

```sh
CODESIGN_IDENTITY='Developer ID Application: Yushen Chang (M22Z394H44)' \
NOTARY_PROFILE=tcapsulesmb-notary \
./tests/test_package.sh 0.1.0
```

This submits the archive to Apple, waits for acceptance, staples and validates the app, then verifies the final zip. Without `NOTARY_PROFILE`, the package script only signs; without `CODESIGN_IDENTITY`, it uses ad hoc signing for local and pull-request tests.

## Release

After merging the desired commit to `main`, push a numeric version tag such as `v0.1.0`. The tag job signs and notarizes from that exact commit and attaches `DeepSeek-Harness-Launcher-macOS.zip` and its `.sha256` file to the GitHub release.

References: [Apple notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Apple notarytool workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).
