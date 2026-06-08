# Open-Source Checklist

Use this checklist before making the repository public.

## Must Do

- Choose a license and add `LICENSE`.
- Remove private `.livp`, `.heic`, `.mov`, `.mp4`, and extracted template assets.
- Keep `vendor-livp/README.md`, but do not commit template media files unless redistribution is allowed.
- Run `git status --short` and inspect every tracked media file.
- Run `swift build`.
- Run the basic packager command from `README.md`.
- If you have legal template assets locally, run `scripts/make-livp.sh` once and test the output on an iPhone.

## Good To Do

- Add screenshots or a short screen recording showing the expected user flow.
- Add a GitHub Actions workflow for `swift build` and Node syntax checks.
- Add tests for `tools/set-livp-zip-comment.js`.
- Document which iOS versions and devices you personally verified.
- Add a short disclaimer that users must provide their own legal template assets.

## Do Not Promise

- Do not promise all iOS versions accept generated `.livp` files.
- Do not promise arbitrary video length or frame rate works.
- Do not promise Photos preview support equals lock-screen wallpaper support.
- Do not redistribute third-party template metadata or media without permission.
