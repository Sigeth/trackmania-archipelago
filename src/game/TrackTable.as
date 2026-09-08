// Maps a Turbo official-campaign map to its AP location base name.
//
// There is no UID table. The Turbo solo campaign is 200 maps authored by
// "Nadeo" and named "001".."200"; that number alone identifies the track. This
// is how the Ultimate Medals plugin detects campaign maps
// (Text::ParseInt(challenge.MapName) + AuthorLogin == "Nadeo") -- see
// Phlarx/tm-ultimate-medals, UltimateMedals.as.
//
// Campaign layout (difficulty-major, then environment, then 1..10):
//   tier = (n-1) / 40   ->  White Green Blue Red Black
//   env  = (n-1) % 40 / 10  ->  Canyon Valley Lagoon Stadium
//   idx  = (n-1) % 10 + 1   ->  1..10
// so map 001 = "White Canyon 01", map 200 = "Black Stadium 10".
//
// Environment order within a tier (Canyon -> Valley -> Lagoon -> Stadium) matches
// the in-game unlock progression. VERIFY against the GameState trace log
// ("campaign map N -> <label>") when loading real tracks.
//
// AP location name convention (must match the .apworld):
//   "<Track Label> - <Medal>"   e.g. "White Canyon 01 - Gold"

const string CAMPAIGN_AUTHOR_LOGIN = "Nadeo";
// The VR campaign reuses the same 200 maps but authored as "nadeolabs" -- accept
// both, the way the Ultimate Medals / TurboSkillpoints plugins do.
const string CAMPAIGN_AUTHOR_LOGIN_VR = "nadeolabs";
const array<string> TIERS = { "White", "Green", "Blue", "Red", "Black" };
const array<string> ENVIRONMENTS = { "Canyon", "Valley", "Lagoon", "Stadium" };
const int TRACKS_PER_TIER = 40;
const int TRACKS_PER_ENV = 10;
const array<string> MEDAL_SUFFIX = { "", "Bronze", "Silver", "Gold", "Author" };

// "001".."200" from an official-campaign map -> 1..200; anything else -> 0.
int CampaignNumber(const string &in mapName, const string &in authorLogin) {
    if (authorLogin != CAMPAIGN_AUTHOR_LOGIN
     && authorLogin != CAMPAIGN_AUTHOR_LOGIN_VR) return 0;
    int n = 0;
    if (!Text::TryParseInt(mapName, n)) return 0;
    return (n >= 1 && n <= 200) ? n : 0;
}

// 1..200 -> "White Canyon 01"; 0 or out of range -> "".
string TrackLabel(int campaignNumber) {
    if (campaignNumber < 1 || campaignNumber > 200) return "";
    int z = campaignNumber - 1;
    string tier = TIERS[z / TRACKS_PER_TIER];
    string env = ENVIRONMENTS[(z % TRACKS_PER_TIER) / TRACKS_PER_ENV];
    int idx = z % TRACKS_PER_ENV + 1;
    return tier + " " + env + " " + (idx < 10 ? "0" : "") + idx;
}

// "White Canyon 01" -> 1..200; malformed / out of range -> 0. Inverse of
// TrackLabel(). Tolerant of extra spacing but expects the exact tier/env words.
int CampaignNumberFromLabel(const string &in label) {
    array<string>@ parts = label.Split(" ");
    if (parts.Length != 3) return 0;
    int tierIdx = TIERS.Find(parts[0]);
    int envIdx = ENVIRONMENTS.Find(parts[1]);
    int idx = 0;
    if (tierIdx < 0 || envIdx < 0 || !Text::TryParseInt(parts[2], idx)) return 0;
    if (idx < 1 || idx > TRACKS_PER_ENV) return 0;
    return tierIdx * TRACKS_PER_TIER + envIdx * TRACKS_PER_ENV + idx;
}

string TrackLocationName(const string &in trackLabel, Medal medal) {
    if (trackLabel == "" || int(medal) < 1 || int(medal) > 4) return "";
    return trackLabel + " - " + MEDAL_SUFFIX[int(medal)];
}

// ---- vanilla unlock model -------------------------------------------------
//
// The 200 campaign tracks split into 20 "blocks" of 10 (one tier/environment
// pair each), in campaign order: block index i = tierIdx*4 + envIdx, i in 0..19.
// Block i opens once the player has received block-threshold[i] medal items of
// the block's grade -- Bronze for the White/Green blocks (i < 8), Silver for
// Blue/Red (i < 16), Gold for Black. block-threshold[i] == 10*i (block 0 -> 0,
// always open); the real table is sent in slot_data. These helpers mirror the
// apworld (worlds/trackmania_turbo/__init__.py).

const int BLOCK_COUNT = 20;
const int TRACKS_PER_BLOCK = 10;
const int ENV_COUNT = 4;        // == ENVIRONMENTS.Length, as an int for arithmetic

// campaign number 1..200 -> block 0..19; out of range -> -1.
int BlockIndex(int campaignNumber) {
    if (campaignNumber < 1 || campaignNumber > 200) return -1;
    return (campaignNumber - 1) / TRACKS_PER_BLOCK;
}

// "White Valley 03" -> block 1; malformed -> -1.
int BlockIndexFromLabel(const string &in label) {
    return BlockIndex(CampaignNumberFromLabel(label));
}

// The medal grade whose received count gates this block.
Medal BlockGrade(int blockIndex) {
    if (blockIndex < 8) return Medal::Bronze;
    if (blockIndex < 16) return Medal::Silver;
    return Medal::Gold;
}

// "White Canyon", "Black Stadium", ... ; "" if out of range.
string BlockName(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= BLOCK_COUNT) return "";
    return TIERS[blockIndex / ENV_COUNT] + " " + ENVIRONMENTS[blockIndex % ENV_COUNT];
}

// "White", "Black", ... ; "" if out of range.
string TierNameForBlock(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= BLOCK_COUNT) return "";
    return TIERS[blockIndex / ENV_COUNT];
}

// Milestone location names (must match the apworld).
string BlockCompleteLocation(int blockIndex) {
    string n = BlockName(blockIndex);
    return n == "" ? "" : n + " Complete";
}
string TierCompleteLocation(int blockIndex) {
    string n = TierNameForBlock(blockIndex);
    return n == "" ? "" : n + " Complete";
}

// The k-th campaign number (k = 0..9) in a block.
int BlockTrackNumber(int blockIndex, int k) {
    if (blockIndex < 0 || blockIndex >= BLOCK_COUNT || k < 0 || k >= TRACKS_PER_BLOCK) return 0;
    return blockIndex * TRACKS_PER_BLOCK + k + 1;
}

// Tier index (0..4) owning this block.
int TierIndexForBlock(int blockIndex) {
    if (blockIndex < 0 || blockIndex >= BLOCK_COUNT) return -1;
    return blockIndex / ENV_COUNT;
}
