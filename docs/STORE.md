# Microsoft Store packaging

The Store build is an x64 full-trust desktop MSIX. It uses the same WPF capture application as the installer, plus a small native IExplorerCommand extension for the packaged desktop menu and a background startup launcher. Packaged apps use manifest integration rather than the installer's system-registry menu.

## Registered identity

| Field | Value |
|---|---|
| Package name | `Geeklabs.GrabPic` |
| Publisher | `CN=5B135F6F-4181-4A69-A7BE-6BAA39528EBE` |
| Publisher display name | `Owl Dev` |
| Package family | `Geeklabs.GrabPic_r9bpyvrsmjz2p` |
| Store ID | `9PJ3HBXBCTX1` |
| Version | `0.5.1.0` |

Keep the identity stable and increase the version for each new upload; the fourth component remains zero for Store submissions.

## Build

```powershell
powershell -ExecutionPolicy Bypass -File tools/Build-Store.ps1
```

The script regenerates icon assets, publishes the self-contained application, restores the pinned Windows SDK build tools, downloads a checksum-verified C++ toolchain, builds and verifies the native menu, indexes all icon scales and target sizes into a single resources.pri, and runs MakeAppx manifest validation. The result is under `submission/packages`.

The unsigned output is suitable for submission to Partner Center: Microsoft signs Store-distributed packages. For local test signing, pass `-SigningThumbprint <thumbprint>` for an existing code-signing certificate whose subject exactly matches the manifest publisher. The script never exports a private key or changes certificate trust or sideload policy.

## Upload

1. Open the existing Grabpic product in Partner Center and create a submission.
2. Upload `submission/packages/Grabpic-0.5.1.0-x64.msix` in Packages.
3. Use the listing text and metadata in `submission/listing`.
4. Upload the four PNGs in `submission/screenshots` in numeric order. They are 1366 × 900, above the Desktop minimum of 1366 × 768.
5. Use `submission/icons/Grabpic-300.png` for the 1:1 Store listing logo. Other sizes and all package-qualified assets are provided as well.
6. Link the [privacy policy](https://talhazahid.github.io/grabpic/privacy/) and [support page](https://github.com/talhazahid/grabpic/issues).
7. Complete the account-specific pricing/markets, properties, declarations, age-rating questionnaire, and certification sections in Partner Center. These cannot be generated as app files.

Microsoft must approve and publish the submission before the [Store listing](https://apps.microsoft.com/detail/9PJ3HBXBCTX1) becomes downloadable.

## Validation limits

Local checks cover package schema, identity, native COM command enumeration and icon resolution, application checks, and assets. The current development PC rejects local MSIX installation because its certificate/sideload policy does not permit it. No trust or sideload settings are changed by the build. Full packaged installation, startup-task activation, packaged shell registration, Windows App Certification Kit, and Store certification remain checks for an appropriately configured test machine or Microsoft's submission process. This is not a certification claim.

References: [Store signing](https://learn.microsoft.com/en-us/windows/msix/package/sign-msix-package-guide), [screenshots and images](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/screenshots-and-images), [MakeAppx](https://learn.microsoft.com/en-us/windows/msix/package/create-app-package-with-makeappx-tool).
