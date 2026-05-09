# LivePhotoSpike iOS App

This is a minimal iPhone-only Spike for testing whether the iOS Photos framework changes Live Photo wallpaper compatibility when saving paired resources.

## Cases

- `Control Native`: original iPhone Live Photo from `IMG_0135.HEIC` + `IMG_0135.mov`. This should save and remain Lock Screen wallpaper-capable.
- `Basic Custom`: custom video with only basic Live Photo metadata. This tests whether iOS Photos can upgrade a basic generated pair.
- `Template Custom`: custom video with copied static-template `mebx` tracks. This tests whether iOS Photos rewrites or preserves non-wallpaper-capable metadata.

## Run

1. Open `LivePhotoSpike.xcodeproj` in Xcode.
2. Select the `LivePhotoSpike` target.
3. In **Signing & Capabilities**, choose your Apple development team.
4. Connect an iPhone.
5. Run the app on the iPhone.

## Test

For each case:

1. Tap **Preview**. Confirm whether `PHLivePhoto.request` can load the pair.
2. Tap **Save**. Allow Photos permission.
3. Open the iPhone Photos app and find the saved item.
4. Confirm whether it appears as a Live Photo.
5. Try setting it as the Lock Screen wallpaper and check whether dynamic effect is available.

## Interpretation

- If `Control Native` fails, the App save path or signing/runtime setup is broken.
- If `Basic Custom` or `Template Custom` becomes wallpaper-capable after saving, iOS Photos is rewriting enough metadata for the commercial App path to work.
- If they remain non-wallpaper-capable, iOS does not generate the required `live-photo-info` metadata for arbitrary video pairs; we need a custom `mebx` generator.
