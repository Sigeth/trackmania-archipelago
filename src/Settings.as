// All user-configurable options. Openplanet persists these automatically to
// OpenplanetTurbo/Plugins/Archipelago/... via the [Setting] metadata.

[Setting category="Connection" name="Server host"]
string S_Host = "archipelago.gg";

[Setting category="Connection" name="Server port" min=1 max=65535]
int S_Port = 38281;

[Setting category="Connection" name="Use TLS (wss://)"]
bool S_UseTls = true;

[Setting category="Connection" name="Slot name"]
string S_SlotName = "";

[Setting category="Connection" name="Password" password]
string S_Password = "";

[Setting category="Connection" name="Auto-connect on plugin load"]
bool S_AutoConnect = false;

[Setting category="Behaviour" name="Report goal complete automatically"]
bool S_AutoGoal = true;

[Setting category="Behaviour" name="Show the lock overlay on the campaign map screen"]
bool S_CampaignOverlay = true;

// Campaign grid rectangle on screen, as fractions of the window. The ManiaLink
// tile coordinates are mapped linearly into this rectangle. Tune with the
// sliders in the Archipelago window's Debug section, then these persist.
[Setting hidden] float S_GridL = 0.275;
[Setting hidden] float S_GridT = 0.235;
[Setting hidden] float S_GridR = 0.877;
[Setting hidden] float S_GridB = 0.858;
[Setting hidden] bool S_GridDebug = false;

// Track-picker screen: the 10 thumbnails (5 x 2), as window fractions.
[Setting hidden] float S_TpL = 0.123;
[Setting hidden] float S_TpT = 0.358;
[Setting hidden] float S_TpR = 0.880;
[Setting hidden] float S_TpB = 0.863;

[Setting category="Behaviour" name="Send the player back to the menu when they enter a locked track"]
bool S_BlockLockedTracks = true;

[Setting category="Behaviour" name="Show in-game notifications when this slot receives an item or checks a location"]
bool S_Notifications = true;

[Setting category="Behaviour" name="Show a medal celebration when you finish a campaign track"]
bool S_MedalSplash = true;

[Setting category="Behaviour" name="Play the medal voice lines (on a received medal item, and on a Gold/Author finish)"]
bool S_MedalSound = true;

[Setting category="Behaviour" name="Medal voice line volume" min=0 max=1]
float S_MedalSoundVolume = 0.6f;

[Setting category="Debug" name="Verbose protocol logging"]
bool S_Trace = false;

// The medal tiers Turbo exposes per official-campaign track.
enum Medal {
    Bronze = 1,
    Silver = 2,
    Gold   = 3,
    Author = 4,
}

string ServerUrl() {
    string scheme = S_UseTls ? "wss" : "ws";
    return scheme + "://" + S_Host + ":" + tostring(S_Port);
}
