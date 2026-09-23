#!/usr/bin/env node

import { fetchImageUrls } from '@marcus5914/google-photos-album-image-url-fetch';

const sharedUrl = process.argv[2];
if (!sharedUrl) {
  console.error('Usage: tools/google-photos-video-url.mjs GOOGLE_PHOTOS_SHARE_URL');
  process.exit(2);
}

try {
  const items = await fetchImageUrls(sharedUrl, {
    timeoutMs: 30_000,
    maxAttempts: 5,
  });

  if (!items) {
    console.error('Could not parse the Google Photos shared page.');
    process.exit(1);
  }

  const videos = items.filter(item => item.isVideo && item.videoUrl);

  if (videos.length === 0) {
    console.error('No downloadable video was found in this Google Photos share.');
    process.exit(1);
  }

  if (videos.length > 1) {
    console.error(
      `This Google Photos share contains ${videos.length} videos. Please share a link containing only the video you want.`
    );
    process.exit(1);
  }

  process.stdout.write(videos[0].videoUrl);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
