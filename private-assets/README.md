# Private template asset

The GitHub Action expects one encrypted file here:

`intolive-template.zip.enc`

It is deliberately encrypted before being committed because this fork is public.
The decryption passphrase is stored only as the repository Actions secret:

`LIVEPHOTO_TEMPLATE_KEY`

The decrypted ZIP must contain the paired HEIC/JPEG + MOV template exported from
a Live Photo that is known to work as an iPhone lock-screen wallpaper.

Do not commit the unencrypted HEIC/MOV files to this public repository.
