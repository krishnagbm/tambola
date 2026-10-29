/**
 * scripts/sync_youtube.js
 * Automatically checks the @DabHousie YouTube channel for newly published videos
 * and updates web/js/videos-data.js without breaking existing categories.
 *
 * Usage:
 *   node scripts/sync_youtube.js
 *   or
 *   npm run sync-videos
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

const CHANNEL_URL = 'https://www.youtube.com/@DabHousie/videos';
const DATA_FILE = path.join(__dirname, '..', 'web', 'js', 'videos-data.js');

function fetchPage(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' } }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

async function run() {
  console.log(`\n🔍 Fetching latest videos from ${CHANNEL_URL}...`);
  try {
    const html = await fetchPage(CHANNEL_URL);
    const match = html.match(/var ytInitialData = ({.*?});<\/script>/) || html.match(/ytInitialData\s*=\s*({.*?});/);
    if (!match) {
      console.error('❌ Could not parse ytInitialData from YouTube. Channel may be temporarily rate-limited.');
      return;
    }

    const data = JSON.parse(match[1]);
    const tabs = data?.contents?.twoColumnBrowseResultsRenderer?.tabs || [];
    let videosTab = tabs.find(t => t.tabRenderer?.title?.toLowerCase?.().includes('video'))?.tabRenderer;
    if (!videosTab) videosTab = tabs[1]?.tabRenderer;

    const contents = videosTab?.content?.richGridRenderer?.contents || [];
    const channelVideos = [];

    for (const c of contents) {
      const lockup = c?.richItemRenderer?.content?.lockupViewModel;
      if (!lockup) continue;

      const id = lockup.contentId;
      const title = lockup.metadata?.lockupMetadataViewModel?.title?.content || 'Untitled Video';
      
      let duration = '';
      const badges = lockup.contentImage?.thumbnailViewModel?.overlays || [];
      for (const b of badges) {
        const badgeList = b?.thumbnailBottomOverlayViewModel?.badges || [];
        for (const badge of badgeList) {
          const t = badge?.thumbnailBadgeViewModel?.text;
          if (t) duration = t;
        }
      }

      channelVideos.push({ id, title, duration });
    }

    console.log(`✅ Found ${channelVideos.length} public videos on YouTube channel.`);

    // Read current videos-data.js
    let currentVideos = [];
    if (fs.existsSync(DATA_FILE)) {
      const currentContent = fs.readFileSync(DATA_FILE, 'utf8');
      const jsonMatch = currentContent.match(/window\.DABHOUSIE_VIDEOS\s*=\s*(\[[\s\S]*?\]);/);
      if (jsonMatch) {
        try {
          currentVideos = JSON.parse(jsonMatch[1]);
        } catch (e) {}
      }
    }

    const existingIds = new Set(currentVideos.map(v => v.id));
    const newVideos = channelVideos.filter(v => !existingIds.has(v.id));

    if (newVideos.length === 0) {
      console.log('✨ All YouTube channel videos are already synced in web/js/videos-data.js!\n');
      return;
    }

    console.log(`🎉 Found ${newVideos.length} NEW video(s) to add:`);
    for (const nv of newVideos) {
      console.log(`   - [${nv.id}] (${nv.duration}) ${nv.title}`);
      
      // Auto-categorize based on title keywords
      let group = 'player';
      let groupLabel = 'Player & Guest Guides';
      let badge = 'Tutorial';

      const lower = nv.title.toLowerCase();
      if (lower.includes('host') || lower.includes('organizer') || lower.includes('tv') || lower.includes('lobby')) {
        group = 'host';
        groupLabel = 'Host & Organizer Controls';
        badge = 'Host Guide';
      } else if (lower.includes('trivia') || lower.includes('recall') || lower.includes('cognitive') || lower.includes('memory')) {
        group = 'trivia';
        groupLabel = 'Recall Trivia & Skills';
        badge = 'Trivia Challenge';
      } else if (lower.includes('promo') || lower.includes('trailer') || lower.includes('teaser')) {
        group = 'promos';
        groupLabel = 'Brand Promos & Trailers';
        badge = 'Official Promo';
      }

      currentVideos.push({
        id: nv.id,
        title: nv.title,
        duration: nv.duration,
        group,
        groupLabel,
        badge,
        summary: nv.title,
        thumbnail: `https://img.youtube.com/vi/${nv.id}/hqdefault.jpg`,
        youtubeUrl: `https://www.youtube.com/watch?v=${nv.id}`
      });
    }

    const updatedFileContent = `/**\n * DabHousie Official YouTube Video Registry\n * All public videos verified on https://www.youtube.com/@DabHousie\n * Update this list or run \`npm run sync-videos\` to add new videos in the future!\n */\nwindow.DABHOUSIE_VIDEOS = ${JSON.stringify(currentVideos, null, 2)};\n`;
    fs.writeFileSync(DATA_FILE, updatedFileContent, 'utf8');
    console.log(`💾 Successfully updated ${DATA_FILE} (Total: ${currentVideos.length} videos).\n`);

  } catch (err) {
    console.error('❌ Error during sync:', err.message);
  }
}

run();
