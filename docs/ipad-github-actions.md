# iPad-only GitHub Action

This fork adds a cloud workflow that converts a video into a template-backed
`.livp` using a GitHub-hosted macOS runner. No local Mac is required.

## One-time setup

1. Put the encrypted template file at:
   `private-assets/intolive-template.zip.enc`
2. In **Settings -> Secrets and variables -> Actions**, create:
   `LIVEPHOTO_TEMPLATE_KEY`

Never commit the unencrypted template files.

## Create a Live Photo

1. Upload the source video to Google Drive or Dropbox.
2. Create a share link that the GitHub runner can download.
3. Open **Actions -> Create iPhone Live Photo -> Run workflow**.
4. Paste the link into **video_url**.
5. Optionally choose an output name.
6. Run the workflow.
7. When it finishes, download the artifact. The artifact is a ZIP containing
   the generated `.livp` file.

The workflow accepts ordinary direct HTTPS links too.

## Output matching

The converter probes the private MOV template and automatically matches its:

- width and height
- duration
- frame rate
- presence/absence of an audio track

The source video is looped if necessary and center-cropped to fill the template
frame. The template's metadata tracks are then copied by the Swift packager.
