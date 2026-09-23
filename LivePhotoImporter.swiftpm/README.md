# Live Photo Importer for Swift Playgrounds

This small iOS/iPadOS app imports an already-generated Live Photo pair into
Photos using PhotoKit.

## Why this exists

Files/iOS may save the HEIC and MOV as two separate assets even when their Live
Photo metadata matches. PhotoKit can explicitly create one asset with:

- `.photo`
- `.pairedVideo`

in the same `PHAssetCreationRequest`.

## Use on iPad

1. Install **Swift Playgrounds** from the App Store.
2. Download `LivePhotoImporter.swiftpm.zip` from the GitHub Actions artifact.
3. In Files, unzip it.
4. Tap/open `LivePhotoImporter.swiftpm` in Swift Playgrounds.
5. Run the app.
6. Tap **בחר HEIC + MOV**.
7. Select both generated files at the same time:
   - `*.heic`
   - `*.mov`
8. Allow Photos add access.
9. Open Photos and confirm that one item with the **LIVE** badge was created.

The files must already be a valid matched Live Photo pair. The app does not
rewrite their metadata; it only imports them correctly as one PhotoKit asset.


CI note: the Swift source is type-checked against the iOS SDK before this
package is merged.
