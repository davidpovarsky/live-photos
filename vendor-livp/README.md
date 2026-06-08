# Local Template Assets

Place neutral Live Photo template assets here if you want to use the default paths:

```text
vendor-livp/IMB_ZyUbrU.HEIC.heic
vendor-livp/IMB_ZyUbrU.HEIC.mov
```

These media files are ignored by git. Only add template media to a public repository if you own the rights and have verified redistribution is allowed.

You can also keep templates elsewhere and run:

```bash
LIVEPHOTO_TEMPLATE_PHOTO=/path/to/template.heic \
LIVEPHOTO_TEMPLATE_VIDEO=/path/to/template.mov \
../scripts/make-livp.sh input.mp4 output.livp
```

See `docs/template-assets.md` for details.
