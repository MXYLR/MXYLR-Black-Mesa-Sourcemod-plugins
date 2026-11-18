// bms_match - Black Mesa match plugin (module 39)
// Port of the hl2dm "xms" match plugin for Black Mesa, merged into merged.smx.
// All symbols get the mod_bms_match_ prefix. Source is pure ASCII: all player
// facing text lives in translations/bms_match.phrases.txt.

#define BMS_MAX_MODE 16
#define BMS_MAX_MAP_LENGTH 128
// Max length of the player name embedded in a SourceTV demo filename
// (matches the Source engine's in-game name cap; long names get truncated).
#define BMS_DEMO_NAME_MAX 32
// Post-restart correction budget: the engine refresh lands at an unknown
// moment (when the opening wait ends), so the correction timer re-arms
// until the round timer converges or this many ticks have passed.
#define BMS_POSTFIX_MAX_TICKS 20
// How many 1s ticks the post-restart correction re-asserts the absolute
// deadline after go-live, to outlast the engine's ASYNCHRONOUS warmup->
// Round.Enter reset that re-arms DoneTime (see BmsT_PostRestartFix).
#define BMS_POSTFIX_SETTLE_TICKS 5
#define BMS_VOTE_OPTIONS 5
#define BMS_DELAY_ACTION 4
// The HUD countdown is rendered from the NETWORKED gamerules field
// m_StateRound[0] (DoneTime), which the engine anchors at Round.Enter —
// mp_warmup_time (1s) after Bms_EngineReset's SetState(0), i.e.
// BMS_DELAY_ACTION-1 seconds BEFORE go-live. Anchoring the deadline there
// leaves the HUD short by that gap (60s shows as 57). Add the gap back so the
// HUD shows the full match length at go-live. The offset MUST land on the
// networked DoneTime (m_StateRound), not the server-only mp_round_time entity's
// m_iRoundTime field — that field has no INSENDTABLE flag and the client never
// renders it (see Bms_AdjustRoundTimer).
#define BMS_HUD_OFFSET (BMS_DELAY_ACTION - 1)
// Celebration window after a finished match: the score panel stays up for
// this long, then the round restarts in place on the CURRENT map (no map
// change - see BmsT_PostMatchRestart).
#define BMS_POSTMATCH_DELAY 10.0

#define BMS_TEAM_SPECTATORS 1
#define BMS_TEAM_COMBINE 2
#define BMS_TEAM_REBELS 3

#define BMS_CONFIG_PATH "configs/bms_match.cfg"

enum BmsGameState
{
	BmsState_Paused = -1,
	BmsState_Default = 0,
	BmsState_Overtime,
	BmsState_MatchWait,
	BmsState_Match,
	BmsState_MatchEx,
	BmsState_Over,
	BmsState_Changing
}

enum BmsVoteType
{
	BmsVote_Run = 0,
	BmsVote_RunNext,
	BmsVote_RunAuto,
	BmsVote_RunRandom,
	BmsVote_Match,
	BmsVote_Shuffle,
	BmsVote_Invert
}

enum struct BmsConVars
{
	ConVar mp_timelimit;
	ConVar mp_teamplay;
	ConVar mp_chattime;
	ConVar mp_forcerespawn;
	ConVar mp_restartgame;
	ConVar mp_fraglimit;
	ConVar sv_pausable;
	ConVar sm_nextmap;
	ConVar specDetails;
	ConVar tv_enable;
	ConVar mp_warmup_time;
	ConVar mp_round_intermission_time;
	ConVar mapvote_endvote;
}

enum struct BmsCore
{
	KeyValues kConfig;
	char sGamemodes[256];
	char sDefaultMode[BMS_MAX_MODE];
	char sRetainModes[64];
	char sStripPrefix[64];
	char sEmptyMapcycle[PLATFORM_MAX_PATH];
}

enum struct BmsRound
{
	BmsGameState iState;
	char sMode[BMS_MAX_MODE];
	char sNextMode[BMS_MAX_MODE];
	char sMap[BMS_MAX_MAP_LENGTH];
	char sNextMap[BMS_MAX_MAP_LENGTH];
	char sUID[96];
	// Match initiator's name (whoever ran !start / !starttest / the winning
	// vote); embedded in the SourceTV demo filename as 日期-地图-玩家名.
	char sInitiator[MAX_NAME_LENGTH];
	float fStartTime;
	float fEndTime;
	bool bTeamplay;
	bool bOvertime;
	Handle hOvertime;
	StringMap mTeams;
	int iTimerBackup;
	int iPublicTimelimit;
	// Public gamerules state captured in Bms_OnMatchPre (engine initial
	// state): post-match / cancel restore it so the engine returns to its
	// public-play behaviour (no forced round, no HUD countdown, no map
	// change) without a level reload.
	bool bStateBackedUp;
	int iStateBackup;
	float fDoneTimeBackup;
	float fWarmupBackup;
	int iPublicRoundIntermission;
}

enum struct BmsVoting
{
	int iStatus;
	BmsVoteType iType;
	int iElapsed;
	int iLead;
	int iMinPlayers;
	int iMaxTime;
	int iCooldown;
	bool bAutomatic;
	// Client index of the player who called the vote; used to name the demo
	// after the match initiator when a match starts via a passed vote.
	int iCaller;
}

enum struct BmsClient
{
	bool bReady;
	int iVote;
	float fVoteTick;
}

enum struct BmsSpecialClient
{
	int iAllowed;
	int iPauser;
}

enum struct BmsSourceTV
{
	bool bEnable;
	char sDemoDir[64];
	char sDownloadBase[192];
	char sDemoName[PLATFORM_MAX_PATH];
	bool bRecording;
}

BmsConVars gBmsCvar;
BmsCore gBmsCore;
BmsRound gBmsRound;
BmsVoting gBmsVoting;
BmsClient gBmsClient[MAXPLAYERS + 1];
BmsSpecialClient gBmsSpecial;
BmsSourceTV gBmsTV;

char gsBmsMotion[BMS_VOTE_OPTIONS][192];
Handle gBmsVoteHud;
// SDKCall to CGameRules::SetState(int). Resolved by the CGameRules_SetState
// signature in gamedata/bms_match.games.txt, NOT by a fixed vtable slot: the
// 2026-11-17 server.dll update inserted four virtuals into the CGameRules
// family, moving SetState from slot 160 (0x1035e510) to slot 164 (0x1035f5f0).
// The signature matches both builds (64-byte prologue, only the [eax+0x2?c]
// vtable call displacement wildcarded), so the same .smx runs on either.
// Entering PREGAME (0) with a short mp_warmup_time
// lets the engine's per-frame State_Transition fire the Round transition
// (SetState(2) -> Round.Enter -> CleanUpMap full map reparse) at its own safe
// frame point. Calling SetState(2) directly would crash (Round.Enter's first
// action is the reparse, illegal mid-command-callback).
Handle gBmsCall_SetState = INVALID_HANDLE;
float gBmsWarmupTimeBackup = -1.0;
// Set when Bms_EngineReset is asked to restore public play (cancel/post-match):
// the next engine "round_start" (fired by Round.Enter, i.e. AFTER the reparse
// has safely completed) performs the post-reset finish (future DoneTime +
// respawn). Cleared in Bms_Event_RoundStart so it never leaks to a normal round.
bool gBmsEngineResetPending = false;
int gBmsRunTimer;
int gBmsStartTimer;
int gBmsMapChanges;
int gBmsPostFixTicks;
// !starttest: 1-minute test match (SourceTV demo check). Overrides the mode's
// MatchTimelimit, suppresses overtime, and is cleared when the match ends.
bool gBmsTestMatch;
// Set true for the duration of a plugin-fired victory/draw voice event so
// Bms_Event_TeamSound lets it through while still blocking the spurious
// 0-0 draw that Bms_EngineReset's forced round emits. Cleared immediately
// after FireEvent (the Pre hook runs synchronously inside FireEvent).
bool gBmsVoiceAnnounce;

// IN-GAME WEB PANEL (socket-hosted HTTP control page). Globals live here so they
// are declared before Bms_OnClientDisconnect (which clears a client's token).
ConVar gBmsWebEnabled;
ConVar gBmsWebPort;
ConVar gBmsWebHost;
Socket gBmsWebListen;
char gBmsWebToken[MAXPLAYERS + 1][40];
char gBmsWebHtml[16384];
char gBmsWebReply[MAXPLAYERS + 1][1024];
bool gBmsWebCapturing[MAXPLAYERS + 1];

// 状态页(bms_status_page)。2026-11-17 客户端更新后引擎不再画 HUD 顶部的
// 倒计时/状态文本, 于是本模块每秒重画一次。通道见 bms_status_channel:
// 0 = 默认, hint 面板(位置由客户端 hudlayout.res 固定)。面板自身有底框动画,
//     每收到一条消息就从头重播一次缩放, 1 Hz 重发看起来就是一直在闪 ——
//     用户实机对比后要的就是这个多行的样子(bms_status_keyhint 1)。
// 1 = HudMsg(无底框、静音、每秒刷新也不闪, 但只有 6 个槽位),
// 2 = 同样走 HudMsg, 只是把 K/D/ping + 前五名也压进那 6 行。
//
// hint 面板有两块, 由 bms_status_keyhint 选:
// 1(默认) = KeyHintText / CHudHintKeyDisplay —— 多行正常(靠子面板 GetTall
//   排版, 字体 HudHintTextSmall/Large/Glyph 都在), 但 hudanimations.txt 的
//   KeyHintMessageShow 第一步就是 HintSize "0" 再 2 秒涨回 "1", 同一份动画还在
//   0s/1.5s/3.0s 闪三次底框颜色, 12 秒后 Alpha 归零 —— 所以必须 1 Hz 重发,
//   代价就是看得见的闪。
// 0 = HintText / CHudHintDisplay —— 就是原来 Show Health 用的那块细长条。
//   天生静音不闪, 但客户端 clientscheme.res 里没有 "HudHintText" 字体 →
//   GetFontTall 拿到 0, 多行会全叠在同一个 y 上, **只能单行**。用户对比后
//   认为单行不如多行那条, 所以默认不选它(见 Bms_BuildStatusPage 的 bOneLine)。
//
// VGUI panel 通道已经废掉: SendPanelToClient 每发一次就是开一块 VGUI 菜单,
// 它会占住客户端的菜单槽 —— 实机表现是**整个游戏里所有切枪键失效**(slot1..
// slot5、绑定的 G 全都没反应), 1 Hz 重发等于一直占着。所以通道 2 改成
// HudMsg + 紧凑排版(见 Bms_BuildStatusPage 里的 bCompact)。
// 面板通道的音效由 bms_status_hintsound 关掉(默认关)。
// bms_status_active 给 showhealth / SpecDetails 模块当信标, 它们看到 1 就
// 不再自己往屏幕上写(否则同一份信息在屏幕上摆两处)。
// 观战时本页画的是被观察者(m_hObserverTarget)的 HP/护甲/武器, 名字与 K/D
// 并进第一行, 所以 SpecDetails 那块 VGUI 面板已经没有存在的必要。
ConVar gBmsStatusPage;
ConVar gBmsStatusActive;
// 0 = hint 面板(底框, 每条消息重播一次缩放动画, 看起来就是闪), 1 = HudMsg,
// 2 = HudMsg + 记分块(紧凑排版, 6 行塞满)。
ConVar gBmsStatusChannel;
// 仅 hint 面板通道有效: 1 = KeyHintText(CHudHintKeyDisplay, 多行到处都正常,
// 每条消息在客户端播一声「啵」), 0 = HintText(CHudHintDisplay, 音效名
// "Hud.Hint" 在 BM 里不存在所以天生静音, 但原版客户端缺 HudHintText 字体,
// 多行会叠在一起)。
ConVar gBmsStatusKeyHint;
// 面板音效开关: 0 = 关掉(服务端 sv_hudhint_sound 0 + 让客户端执行
// cl_hudhint_sound 0), 1 = 交还给玩家设置。见 Bms_ApplyHintSound() 与
// Bms_MuteHintSound()。
ConVar gBmsStatusHintSound;
// HudMsg 第二组颜色的实验开关(bms_status_shadow), 见 CreateConVar 处的说明。
ConVar gBmsStatusShadow;
// 文字的右边界(屏幕宽的比例)。HudMessage 面板本身是 700x480 HUD 单位、
// 左上角贴 (0,0), 超过面板右边就被裁掉, 而那条边随画面比例变
// (16:9 ≈ 0.820, 16:10 ≈ 0.911, 21:9 ≈ 0.625), 所以留成 cvar 好现场调。
ConVar gBmsStatusRight;
// 比分板(自己的 K/D/延迟 + 前五名), 只在通道 2 里画(那边为它做紧凑排版)。
ConVar gBmsStatusStats;
// 让位窗口: 投票/菜单弹出来的这段时间, 状态页整块停发, 否则每秒一发的
// 面板会把正在投票的页面顶掉。值 = 绝对服务器时间(GetGameTime), 谁要弹
// 菜单谁就往后推(见文件末尾的 Bms_StatusYield 说明)。
ConVar gBmsStatusYield;
// bms_match 自己弹给某个玩家的菜单: 只停这个人的状态页, 不动别人。
float gBmsStatusYieldClient[MAXPLAYERS + 1];
// 上一次真正发给该客户端的整段文本(hint 面板通道的内容去重: 客户端每收到
// 一条 KeyHintText 都会把子面板全拆了重建, 整块框闪一下)。
char gBmsStatusLastBody[MAXPLAYERS + 1][1024];
// 上一次真正发出去的服务器时间。HintMessageShow 动画 12 秒后自动把面板
// 藏起来, 所以文本没变也要隔一阵子补发一次(见 Bms_SendStatusPage)。
float gBmsStatusLastHint[MAXPLAYERS + 1];
// 已经给该客户端发过 cl_hudhint_sound 0(见 Bms_MuteHintSound)。
bool gBmsHintSoundMuted[MAXPLAYERS + 1];
// HudMsg 通道上一次占用的行数(槽位数), 用来把多出来的旧行清空。
int gBmsStatusHudLines[MAXPLAYERS + 1];

bool Bms_IsGameMatch()
{
	return (gBmsRound.iState == BmsState_Match || gBmsRound.iState == BmsState_MatchEx || gBmsRound.iState == BmsState_MatchWait || gBmsRound.iState == BmsState_Paused);
}

bool Bms_IsGameOver()
{
	return (gBmsRound.iState == BmsState_Over || gBmsRound.iState == BmsState_Changing);
}

// Reply to a player-facing command in chat, not the console.  Commands
// re-dispatched through FakeClientCommandEx (web panel buttons, radio menu,
// chat aliases) carry a console reply source, so the stock reply native would
// push the answer into the console where nobody looks.  Route every in-game
// reply through the Safe* chat path (per-client translation + CP936 tail
// guard) and fall back to the server console only for client==0.
void Bms_Reply(int iClient, const char[] format, any ...)
{
	char buffer[512];
	SetGlobalTransTarget(iClient);
	VFormat(buffer, sizeof(buffer), format, 3);
	if (iClient > 0 && IsClientInGame(iClient))
	{
		mod_textmsg_fix_SafePrintToChat(iClient, "%s", buffer);
		if (gBmsWebCapturing[iClient])
		{
			Bms_WebCaptureAppend(iClient, buffer);
		}
	}
	else
	{
		PrintToServer("%s", buffer);
	}
}

// Broadcast a message to all players' chat via the Safe* path, and tee the
// formatted text into any active web-panel capture so a panel button click can
// echo the same line back onto the page.  Identical translation behaviour to
// the raw SafePrintToChatAll (single VFormat, server-language %t).
void Bms_SayAll(const char[] format, any ...)
{
	char buffer[512];
	VFormat(buffer, sizeof(buffer), format, 2);
	mod_textmsg_fix_SafePrintToChatAll("%s", buffer);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (gBmsWebCapturing[i])
		{
			Bms_WebCaptureAppend(i, buffer);
		}
	}
}

// Accumulate one reply line into a client's web-panel capture buffer, joining
// multiple lines with a newline and truncating safely at the buffer edge.
void Bms_WebCaptureAppend(int iClient, const char[] text)
{
	if (iClient < 1 || iClient > MaxClients)
	{
		return;
	}
	int iLen = strlen(gBmsWebReply[iClient]);
	int iAdd = strlen(text);
	if (iLen + iAdd + 2 >= sizeof(gBmsWebReply[]))
	{
		return;
	}
	if (iLen > 0)
	{
		gBmsWebReply[iClient][iLen++] = '\n';
	}
	strcopy(gBmsWebReply[iClient][iLen], sizeof(gBmsWebReply[]) - iLen, text);
}

bool Bms_IsClientAdmin(int iClient)
{
	return CheckCommandAccess(iClient, "bms_admin_override", ADMFLAG_GENERIC);
}

bool Bms_IsPlaying(int iClient)
{
	return IsClientInGame(iClient) && !IsClientObserver(iClient);
}

bool Bms_TeamplayAvailable()
{
	// HL2DM-style teamplay requires teams 2/3. Black Mesa DM only registers
	// team 0 (FFA players, shown as "unassigned") and team 1 (spectators).
	return GetTeamCount() > 3;
}

// 当前地图是不是单人战役: -1 = 还没判定, 0 = 不是, 1 = 是。
int gBmsCampaign = -1;

// 单人剧情模式不需要比赛 —— 引擎那边注册的是战役自己的队伍(而且索引 0 是非法
// 的), 逐队 GetTeamName 会抛 "Team index 0 is invalid" 刷满 errors 日志; 比赛
// 状态机/投票在战役里也没有任何意义。所以整张地图上把比赛系统置为静默。
//
// 判据: 战役地图全部形如 bm_c<数字>*(bm_c0a0a … bm_c5a1a); DM 侧地图是
// dm_*/de_*/bm_bunnyrace_beta2, 没有任何地图以 bm_c<数字> 开头 → 前缀匹配安全,
// 判定写错时偏向 DM(即保留原有的比赛行为)。缓存由 Bms_LoadConfig() 每张图重置。
bool Bms_IsCampaignMap()
{
	if (gBmsCampaign == -1)
	{
		char sMap[PLATFORM_MAX_PATH];
		GetCurrentMap(sMap, sizeof(sMap));

		gBmsCampaign = (strncmp(sMap, "bm_c", 4) == 0
			&& sMap[4] >= '0' && sMap[4] <= '9') ? 1 : 0;
	}

	return gBmsCampaign == 1;
}

int Bms_GetRandomInt(int iMin, int iMax)
{
	return GetURandomInt() % (iMax - iMin + 1) + iMin;
}

void Bms_StrToLower(char[] s)
{
	for (int i = 0; i < strlen(s); i++)
	{
		s[i] = CharToLower(s[i]);
	}
}

bool Bms_IsNumeric(const char[] s)
{
	if (!strlen(s))
	{
		return false;
	}
	for (int i = 0; i < strlen(s); i++)
	{
		if (s[i] < '0' || s[i] > '9')
		{
			return false;
		}
	}
	return true;
}

int Bms_PlayerCount(bool bInGameOnly = true, bool bIncludeBots = false, bool bIncludeSpecs = true)
{
	int iCount;
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (bInGameOnly && !IsClientInGame(iClient))
		{
			continue;
		}
		if (!bInGameOnly && !IsClientConnected(iClient))
		{
			continue;
		}
		if (IsFakeClient(iClient) && !bIncludeBots)
		{
			continue;
		}
		if (!bIncludeSpecs && IsClientObserver(iClient))
		{
			continue;
		}
		iCount++;
	}
	return iCount;
}

int Bms_ArgToTarget(int iClient, const char[] sArg)
{
	if (Bms_IsNumeric(sArg))
	{
		int iUserId = StringToInt(sArg);
		int iTarget = GetClientOfUserId(iUserId);
		if (iTarget && IsClientInGame(iTarget))
		{
			return iTarget;
		}
		return 0;
	}
	int iFound;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			continue;
		}
		char sName[MAX_NAME_LENGTH];
		GetClientName(i, sName, sizeof(sName));
		if (StrContains(sName, sArg, false) != -1)
		{
			iFound = i;
			if (i != iClient)
			{
				break;
			}
		}
	}
	return iFound;
}

bool Bms_IsItemInList(const char[] item, const char[] list)
{
	char sList[512];
	strcopy(sList, sizeof(sList), list);
	char sParts[16][64];
	int iCount = ExplodeString(sList, ",", sParts, 16, 64);
	for (int i = 0; i < iCount; i++)
	{
		TrimString(sParts[i]);
		if (StrEqual(sParts[i], item, false))
		{
			return true;
		}
	}
	return false;
}

void Bms_GetTeamName(int iTeam, char[] out, int len)
{
	GetTeamName(iTeam, out, len);
}

float Bms_GetTimeRemaining(bool bChatTime)
{
	int iLimit;
	bool bMatch = Bms_IsGameMatch();
	if (bMatch)
	{
		// Match clock: the mode/test-match length, NOT the mp_timelimit
		// convar - server_match.cfg re-stomps that one on the frame after
		// Bms_OnMatchPre sets it (a 1-minute test match would read 15 here
		// and arm the end check ~15 minutes late).
		iLimit = Bms_GetMatchTimelimit();
	}
	else if (gBmsCvar.mp_timelimit != null)
	{
		iLimit = gBmsCvar.mp_timelimit.IntValue;
	}
	else
	{
		iLimit = 0;
	}
	if (iLimit <= 0)
	{
		return 999999.0;
	}
	float fTime = iLimit * 60.0 - (GetGameTime() - gBmsRound.fStartTime);
	// The HUD countdown is anchored BMS_HUD_OFFSET seconds before go-live, so
	// Bms_AdjustRoundTimer bumps the networked DoneTime by that gap to show the
	// full match length. The end-check timer (Bms_CreateOverTimer -> this) must
	// fire on the SAME bumped deadline, or the match ends ~3s early with the
	// HUD still showing 3-4s. Match the bumped deadline here too (the public
	// mp_timelimit branch is unaffected - it has no go-live gap to absorb).
	if (bMatch)
	{
		fTime += float(BMS_HUD_OFFSET);
	}
	if (bChatTime && gBmsCvar.mp_chattime != null)
	{
		fTime += gBmsCvar.mp_chattime.FloatValue;
	}
	return fTime;
}

int Bms_GetTopPlayer()
{
	int iTop;
	int iTopFrags = -1;
	int iTopDeaths;
	bool bDraw;
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsClientObserver(iClient) || IsFakeClient(iClient))
		{
			continue;
		}
		int iFrags = GetClientFrags(iClient);
		int iDeaths = GetClientDeaths(iClient);
		if (iFrags > iTopFrags || (iFrags == iTopFrags && iDeaths < iTopDeaths))
		{
			iTop = iClient;
			iTopFrags = iFrags;
			iTopDeaths = iDeaths;
			bDraw = false;
		}
		else if (iFrags == iTopFrags && iDeaths == iTopDeaths && iTop)
		{
			bDraw = true;
		}
	}
	return bDraw ? 0 : iTop;
}

/**************************************************************
 * CONFIG
 *************************************************************/
bool Bms_GetConfigString(char[] out, int len, const char[] key, const char[] s1 = "", const char[] s2 = "")
{
	if (gBmsCore.kConfig == null)
	{
		return false;
	}
	gBmsCore.kConfig.Rewind();
	if (strlen(s1) && !gBmsCore.kConfig.JumpToKey(s1))
	{
		return false;
	}
	if (strlen(s2) && !gBmsCore.kConfig.JumpToKey(s2))
	{
		return false;
	}
	if (!gBmsCore.kConfig.GetString(key, out, len))
	{
		return false;
	}
	return strlen(out) > 0;
}

int Bms_GetConfigInt(const char[] key, const char[] s1 = "", const char[] s2 = "", int iDefault = -1)
{
	char sValue[32];
	if (Bms_GetConfigString(sValue, sizeof(sValue), key, s1, s2))
	{
		return StringToInt(sValue);
	}
	return iDefault;
}

bool Bms_GetConfigKeys(char[] out, int len, const char[] s1, const char[] s2 = "")
{
	if (gBmsCore.kConfig == null)
	{
		return false;
	}
	gBmsCore.kConfig.Rewind();
	if (strlen(s1) && !gBmsCore.kConfig.JumpToKey(s1))
	{
		return false;
	}
	if (strlen(s2) && !gBmsCore.kConfig.JumpToKey(s2))
	{
		return false;
	}
	out[0] = '\0';
	if (gBmsCore.kConfig.GotoFirstSubKey(false))
	{
		do
		{
			gBmsCore.kConfig.GetSectionName(out[strlen(out)], len);
			out[strlen(out)] = ',';
		}
		while (gBmsCore.kConfig.GotoNextKey(false));
		out[strlen(out) - 1] = '\0';
		return true;
	}
	return false;
}

void Bms_LoadConfig()
{
	if (gBmsCore.kConfig != null)
	{
		delete gBmsCore.kConfig;
	}
	gBmsCore.kConfig = new KeyValues("bms_match");
	char cfgPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, cfgPath, sizeof(cfgPath), BMS_CONFIG_PATH);
	if (!gBmsCore.kConfig.ImportFromFile(cfgPath))
	{
		LogError("[bms_match] Could not load config file: %s", cfgPath);
		return;
	}
	Bms_GetConfigKeys(gBmsCore.sGamemodes, sizeof(gBmsCore.sGamemodes), "Gamemodes");
	if (!strlen(gBmsCore.sGamemodes))
	{
		LogError("[bms_match] No gamemodes defined in config!");
	}
	Bms_GetConfigString(gBmsCore.sDefaultMode, sizeof(gBmsCore.sDefaultMode), "DefaultMode");
	if (!strlen(gBmsCore.sDefaultMode))
	{
		strcopy(gBmsCore.sDefaultMode, sizeof(gBmsCore.sDefaultMode), "ffa");
	}
	Bms_GetConfigString(gBmsCore.sRetainModes, sizeof(gBmsCore.sRetainModes), "RetainModes");
	Bms_GetConfigString(gBmsCore.sStripPrefix, sizeof(gBmsCore.sStripPrefix), "StripPrefix", "Maps");
	Bms_GetConfigString(gBmsCore.sEmptyMapcycle, sizeof(gBmsCore.sEmptyMapcycle), "EmptyMapcycle");
	gBmsTV.bEnable = (Bms_GetConfigInt("Enable", "SourceTV", "", 1) != 0);
	Bms_GetConfigString(gBmsTV.sDemoDir, sizeof(gBmsTV.sDemoDir), "DemoDir", "SourceTV");
	Bms_GetConfigString(gBmsTV.sDownloadBase, sizeof(gBmsTV.sDownloadBase), "DownloadBase", "SourceTV");
	if (!strlen(gBmsRound.sMode))
	{
		strcopy(gBmsRound.sMode, sizeof(gBmsRound.sMode), gBmsCore.sDefaultMode);
	}
	int iMin = Bms_GetConfigInt("VoteMinPlayers", "", "", 3);
	gBmsVoting.iMinPlayers = (iMin < 0 ? 3 : iMin);
	int iMax = Bms_GetConfigInt("VoteMaxTime", "", "", 25);
	gBmsVoting.iMaxTime = (iMax < 0 ? 25 : iMax);
	int iCd = Bms_GetConfigInt("VoteCooldown", "", "", 30);
	gBmsVoting.iCooldown = (iCd < 0 ? 30 : iCd);
	gBmsVoting.bAutomatic = (Bms_GetConfigInt("AutoVoting", "", "", 1) == 1);
	gBmsRound.bTeamplay = (gBmsCvar.mp_teamplay != null && gBmsCvar.mp_teamplay.BoolValue && Bms_TeamplayAvailable());
	gBmsRound.bOvertime = (Bms_GetConfigInt("Overtime", "Gamemodes", gBmsRound.sMode, 0) == 1);

	// 换图后战役判据要重算(缓存跨图会错判)
	gBmsCampaign = -1;

	if (Bms_IsCampaignMap())
	{
		// 单人战役: 别去枚举队伍(BM 的战役 gamerules 只注册了它自己的队伍,
		// 而索引 0 是"非法"的 → GetTeamName 每次都抛异常刷 errors 日志),
		// 也别让比赛系统接管这张图 —— 单人剧情模式不需要比赛。
		gBmsRound.bTeamplay = false;
		LogMessage("[bms_match] singleplayer campaign: match system idle");
	}
	else
	{
		for (int iTeam = 0; iTeam < GetTeamCount(); iTeam++)
		{
			char sName[32];
			GetTeamName(iTeam, sName, sizeof(sName));
			LogMessage("[bms_match] team %d = %s", iTeam, sName);
		}
		LogMessage("[bms_match] teams=%d teamplay=%d mode=%s", GetTeamCount(), gBmsRound.bTeamplay, gBmsRound.sMode);
	}
}

/**************************************************************
 * GAMEMODE / MAPPOOL
 *************************************************************/
void Bms_SetGamemode(const char[] mode)
{
	strcopy(gBmsRound.sNextMode, sizeof(gBmsRound.sNextMode), mode);
	strcopy(gBmsRound.sMode, sizeof(gBmsRound.sMode), mode);
	char sCommand[256];
	if (Bms_GetConfigString(sCommand, sizeof(sCommand), "Command", "Gamemodes", gBmsRound.sMode))
	{
		ServerCommand(sCommand);
	}
}

bool Bms_GetModeMapcycle(char[] out, int len, const char[] mode)
{
	return Bms_GetConfigString(out, len, "Mapcycle", "Gamemodes", mode);
}

bool Bms_GetModeDefaultmap(char[] out, int len, const char[] mode)
{
	return Bms_GetConfigString(out, len, "Defaultmap", "Gamemodes", mode);
}

bool Bms_IsModeMatchable(const char[] mode)
{
	if (Bms_GetConfigInt("Matchable", "Gamemodes", mode, 0) != 1)
	{
		return false;
	}
	// A mode whose Command enables teamplay cannot run on BM DM (no teams 2/3).
	char sCommand[256];
	if (Bms_GetConfigString(sCommand, sizeof(sCommand), "Command", "Gamemodes", mode)
		&& StrContains(sCommand, "mp_teamplay 1") != -1 && !Bms_TeamplayAvailable())
	{
		return false;
	}
	return true;
}

void Bms_SetMapcycle()
{
	char sMapcycle[PLATFORM_MAX_PATH];
	if (!Bms_GetModeMapcycle(sMapcycle, sizeof(sMapcycle), gBmsRound.sMode) || !strlen(sMapcycle))
	{
		strcopy(sMapcycle, sizeof(sMapcycle), "mapcycle_default.txt");
	}
	ServerCommand("mapcyclefile %s", sMapcycle);
}

// Append every map found in the server's maps/ folder that is missing from
// one mapcycle file. Existing lines and comments are preserved; new maps are
// appended sorted. Returns the number of maps appended.
int Bms_SyncMapcycleFile(const char[] sPath)
{
	ArrayList aMaps = new ArrayList(BMS_MAX_MAP_LENGTH);
	Bms_GetMapsArray(aMaps, "all");
	if (!aMaps.Length)
	{
		delete aMaps;
		return 0;
	}
	aMaps.Sort(Sort_Ascending, Sort_String);
	StringMap hExisting = new StringMap();
	if (FileExists(sPath, true))
	{
		File hFile = OpenFile(sPath, "r");
		if (hFile != null)
		{
			char sLine[256];
			while (!hFile.EndOfFile() && hFile.ReadLine(sLine, sizeof(sLine)))
			{
				TrimString(sLine);
				if (!strlen(sLine) || sLine[0] == ';' || sLine[0] == '/')
				{
					continue;
				}
				int iBsp = StrContains(sLine, ".bsp");
				if (iBsp != -1)
				{
					sLine[iBsp] = '\0';
				}
				TrimString(sLine);
				if (strlen(sLine))
				{
					char sLower[256];
					strcopy(sLower, sizeof(sLower), sLine);
					Bms_StrToLower(sLower);
					hExisting.SetValue(sLower, 1);
				}
			}
			delete hFile;
		}
	}
	int iAdded = 0;
	File hOut = OpenFile(sPath, "at");
	if (hOut != null)
	{
		for (int i = 0; i < aMaps.Length; i++)
		{
			char sMap[BMS_MAX_MAP_LENGTH];
			char sLower[BMS_MAX_MAP_LENGTH];
			int iDummy;
			aMaps.GetString(i, sMap, sizeof(sMap));
			strcopy(sLower, sizeof(sLower), sMap);
			Bms_StrToLower(sLower);
			if (!hExisting.GetValue(sLower, iDummy))
			{
				hOut.WriteLine(sMap);
				hExisting.SetValue(sLower, 1);
				iAdded++;
			}
		}
		delete hOut;
	}
	delete aMaps;
	delete hExisting;
	if (iAdded > 0)
	{
		LogMessage("[bms_match] mapcycle sync: %d map(s) appended to %s", iAdded, sPath);
	}
	return iAdded;
}

// Auto-detect the server's maps/ folder and make sure every map appears in
// the relevant mapcycle lists: engine mapcycle.txt, cfg/mapcycle.txt, and one
// list per configured gamemode.
void Bms_SyncMapcycles()
{
	int iTotal = Bms_SyncMapcycleFile("mapcycle.txt");
	iTotal += Bms_SyncMapcycleFile("cfg/mapcycle.txt");
	char sModes[256];
	strcopy(sModes, sizeof(sModes), gBmsCore.sGamemodes);
	int iPos = 0;
	while (iPos < strlen(sModes))
	{
		int iNext = FindCharInString(sModes[iPos], ',');
		char sMode[BMS_MAX_MODE];
		if (iNext == -1)
		{
			strcopy(sMode, sizeof(sMode), sModes[iPos]);
			iPos = strlen(sModes);
		}
		else
		{
			sModes[iPos + iNext] = '\0';
			strcopy(sMode, sizeof(sMode), sModes[iPos]);
			iPos += iNext + 1;
		}
		char sMapcycle[PLATFORM_MAX_PATH];
		if (Bms_GetModeMapcycle(sMapcycle, sizeof(sMapcycle), sMode) && strlen(sMapcycle))
		{
			char sPath[PLATFORM_MAX_PATH];
			Format(sPath, sizeof(sPath), "cfg/%s", sMapcycle);
			iTotal += Bms_SyncMapcycleFile(sPath);
		}
	}
	if (iTotal > 0)
	{
		LogMessage("[bms_match] mapcycle sync done: %d map(s) appended in total", iTotal);
	}
}

bool Bms_GetModeForMap(char[] out, int len, const char[] map)
{
	if (Bms_GetConfigString(out, len, map, "Maps", "DefaultModes"))
	{
		return true;
	}
	char sPrefix[16];
	int iPos = SplitString(map, "_", sPrefix, sizeof(sPrefix));
	if (iPos > 0)
	{
		Format(sPrefix, sizeof(sPrefix), "%s_*", sPrefix);
		if (Bms_GetConfigString(out, len, sPrefix, "Maps", "DefaultModes"))
		{
			return true;
		}
	}
	if (strlen(gBmsCore.sRetainModes))
	{
		if (strlen(gBmsRound.sMode) && Bms_IsItemInList(gBmsRound.sMode, gBmsCore.sRetainModes))
		{
			strcopy(out, len, gBmsRound.sMode);
			return true;
		}
		char sFirst[16];
		if (SplitString(gBmsCore.sRetainModes, ",", sFirst, sizeof(sFirst)) > 0)
		{
			strcopy(out, len, sFirst);
			return true;
		}
	}
	return false;
}

bool Bms_GetRandomMode(char[] out, int len, bool bExcludeCurrent)
{
	char sModes[16][BMS_MAX_MODE];
	int iCount = ExplodeString(gBmsCore.sGamemodes, ",", sModes, 16, BMS_MAX_MODE);
	if (!iCount || (iCount == 1 && bExcludeCurrent))
	{
		return false;
	}
	for (int i = 0; i < 8; i++)
	{
		int iRan = Bms_GetRandomInt(0, iCount - 1);
		if (!bExcludeCurrent || !StrEqual(sModes[iRan], gBmsRound.sMode))
		{
			strcopy(out, len, sModes[iRan]);
			return true;
		}
	}
	return false;
}

bool Bms_GetMapByAbbrev(char[] out, int len, const char[] abbrev)
{
	return Bms_GetConfigString(out, len, abbrev, "Maps", "Abbreviations");
}

void Bms_DeprefixMap(const char[] sIn, char[] out, int len)
{
	char sPrefix[16];
	int iPos = SplitString(sIn, "_", sPrefix, sizeof(sPrefix));
	Format(sPrefix, sizeof(sPrefix), "%s_", sPrefix);
	if (iPos > 0 && Bms_IsItemInList(sPrefix, gBmsCore.sStripPrefix))
	{
		strcopy(out, len, sIn[iPos]);
	}
	else
	{
		strcopy(out, len, sIn);
	}
}

int Bms_GetMapsArray(ArrayList aMaps, const char[] sMapcycle, const char[] sMustContain = "")
{
	aMaps.Clear();
	if (!strlen(sMapcycle) || StrEqual(sMapcycle, "all"))
	{
		DirectoryListing hDir = OpenDirectory("maps");
		if (hDir != INVALID_HANDLE)
		{
			char sName[256];
			FileType iType;
			while (hDir.GetNext(sName, sizeof(sName), iType))
			{
				int iBsp = StrContains(sName, ".bsp");
				if (iBsp == -1 || iType != FileType_File)
				{
					continue;
				}
				if (sName[iBsp + 4] != '\0')
				{
					continue;
				}
				sName[iBsp] = '\0';
				if (strlen(sMustContain) && StrContains(sName, sMustContain, false) == -1)
				{
					continue;
				}
				aMaps.PushString(sName);
			}
			hDir.Close();
		}
	}
	else
	{
		char sPath[PLATFORM_MAX_PATH];
		Format(sPath, sizeof(sPath), "cfg/%s", sMapcycle);
		if (!FileExists(sPath, true))
		{
			LogError("[bms_match] Mapcycle file not found: %s", sPath);
			return 0;
		}
		File hFile = OpenFile(sPath, "r");
		char sLine[256];
		while (!hFile.EndOfFile() && hFile.ReadLine(sLine, sizeof(sLine)))
		{
			TrimString(sLine);
			if (!strlen(sLine) || sLine[0] == ';' || sLine[0] == '/')
			{
				continue;
			}
			if (!IsMapValid(sLine))
			{
				LogError("[bms_match] \"%s\" map not found", sLine);
				continue;
			}
			if (strlen(sMustContain) && StrContains(sLine, sMustContain, false) == -1)
			{
				continue;
			}
			aMaps.PushString(sLine);
		}
		hFile.Close();
	}
	return aMaps.Length;
}

int Bms_SearchMap(char[] out, int len, const char[] sQuery)
{
	if (IsMapValid(sQuery))
	{
		strcopy(out, len, sQuery);
		return 1;
	}
	char sAbbrev[BMS_MAX_MAP_LENGTH];
	if (Bms_GetMapByAbbrev(sAbbrev, sizeof(sAbbrev), sQuery) && IsMapValid(sAbbrev))
	{
		strcopy(out, len, sAbbrev);
		return 1;
	}
	ArrayList aMaps = new ArrayList(BMS_MAX_MAP_LENGTH);
	Bms_GetMapsArray(aMaps, "", sQuery);
	int iCount = aMaps.Length;
	if (iCount == 1)
	{
		aMaps.GetString(0, out, len);
	}
	delete aMaps;
	return iCount;
}

/**************************************************************
 * STATE MACHINE
 *************************************************************/
// Replace characters that are illegal in a Windows filename (< > : " / \ | ? *
// and control chars 0x00-0x1F) with '_', then strip trailing dots/spaces
// (Windows ignores them). High bytes (UTF-8 CJK) pass through untouched - the
// check compares the byte as UNSIGNED so multibyte name bytes are never eaten.
void Bms_SanitizeFileName(const char[] sIn, char[] sOut, int iMax)
{
	int iLen = strlen(sIn);
	int iW = 0;
	for (int i = 0; i < iLen && iW < iMax - 1; i++)
	{
		int c = sIn[i] & 0xFF;
		if (c < 0x20 || c == '<' || c == '>' || c == ':' || c == '"' || c == '/' || c == '\\' || c == '|' || c == '?' || c == '*')
		{
			c = '_';
		}
		sOut[iW++] = c;
	}
	sOut[iW] = '\0';
	while (iW > 0 && (sOut[iW - 1] == '.' || sOut[iW - 1] == ' '))
	{
		sOut[--iW] = '\0';
	}
	if (iW == 0)
	{
		strcopy(sOut, iMax, "player");
	}
}

void Bms_GenerateGameID()
{
	char sPlayer[BMS_DEMO_NAME_MAX + 1];
	Bms_SanitizeFileName(gBmsRound.sInitiator, sPlayer, sizeof(sPlayer));
	FormatTime(gBmsRound.sUID, sizeof(gBmsRound.sUID), "%y%m%d%H%M%S");
	if (strlen(sPlayer))
	{
		Format(gBmsRound.sUID, sizeof(gBmsRound.sUID), "%s-%s-%s", gBmsRound.sUID, gBmsRound.sMap, sPlayer);
	}
	else
	{
		Format(gBmsRound.sUID, sizeof(gBmsRound.sUID), "%s-%s", gBmsRound.sUID, gBmsRound.sMap);
	}
}

void Bms_GameRestart(int iSeconds)
{
	// BM's server.dll has NO consumer for the mp_restartgame /
	// mp_restartgame_immediate cvars (verified by disassembly: the ConVar
	// objects have zero value-read references - only registration + static
	// destructor thunks; the CHL2MPRules::CheckRestartGame polling loop from
	// the 2018 hl2mp source was removed in BM, and the engine only WRITES
	// these cvars in its edicts-emergency monitor). Issuing them never
	// restarts anything: no respawn, no score wipe, and the game stays in
	// the warmup state whose gate swallows AddRoundTime (observed: 20
	// correction ticks with current=0 after both cvar variants).
	//
	// The working channel is BM's data-driven gamerules state machine
	// (CBM_MP_GameRules + CBM_GameRulesStateWarmup|Round|Intermission,
	// SourceCoop-verified API on this exact build):
	//   m_nCurrentStateId = 2 (STATE_ROUND)  - opens the AddRoundTime gate
	//   m_StateRound[0] (DoneTime, float) = now + iSeconds - feeds the HUD
	//     countdown and the engine's natural round end
	//   m_StateWarmup[0] (DoneTime) = past - closes any lingering warmup
	GameRules_SetProp("m_nCurrentStateId", 2);
	GameRules_SetPropFloat("m_StateWarmup", GetGameTime() - 1.0, 0);
	if (iSeconds <= 0)
	{
		iSeconds = (gBmsCvar.mp_timelimit != null) ? gBmsCvar.mp_timelimit.IntValue * 60 : 600;
	}
	GameRules_SetPropFloat("m_StateRound", GetGameTime() + float(iSeconds), 0);
	LogMessage("[bms_match] restart: gamerules forced to STATE_ROUND (round done in %d s)", iSeconds);
	mod_textmsg_fix_SafePrintCenterTextAll("");
}

// Manual match refresh: BM's engine has no working restart channel (see
// Bms_GameRestart), so the plugin performs the refresh itself - strip
// weapons and force a clean respawn for every participant, mirroring what
// an engine round restart would do. Must run AFTER the state is set to
// Match (the MatchWait spawn hook freezes players; the respawn here
// releases them with a fresh loadout). DispatchSpawn calls the player's
// Spawn() directly - exactly what the engine's own round restart does in
// hl2mp (leak: respawn(pPlayer) after RemoveAllItems), alive or dead.
void Bms_RefreshPlayers()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		{
			continue;
		}
		if (GetClientTeam(iClient) == BMS_TEAM_SPECTATORS)
		{
			continue;
		}
		Bms_StripWeapons(iClient);
		Bms_ResetAmmo(iClient);
		SetEntityMoveType(iClient, MOVETYPE_WALK);
		DispatchSpawn(iClient);
		// BM DM's Long Jump Module survives respawns: the pickup only sets a
		// networked flag on the player (m_bHasJumpModule, the 2018 build
		// called it m_bHasLongJump) and Spawn() never clears it. Reset both
		// the flag and its mana so a match starts from a clean slate.
		if (HasEntProp(iClient, Prop_Send, "m_bHasJumpModule"))
		{
			SetEntProp(iClient, Prop_Send, "m_bHasJumpModule", 0);
		}
		if (HasEntProp(iClient, Prop_Send, "m_flLongJumpMana"))
		{
			SetEntPropFloat(iClient, Prop_Send, "m_flLongJumpMana", 0.0);
		}
		// The LJM keeps a cooldown / "break" timestamp (CBlackMesaJumpData:
		// m_flNextLongJump, m_flLastLongJumpBreakTime). A stale future value
		// from a previous life makes the jump activation fail with
		// "LongJUMP FAILED - Time Expired" (server.dll debug string) even
		// after the module is re-acquired. Clear both so the jump is ready
		// immediately after the refresh, matching the m_flLongJumpMana reset.
		if (HasEntProp(iClient, Prop_Send, "m_flNextLongJump"))
		{
			SetEntPropFloat(iClient, Prop_Send, "m_flNextLongJump", 0.0);
		}
		if (HasEntProp(iClient, Prop_Send, "m_flLastLongJumpBreakTime"))
		{
			SetEntPropFloat(iClient, Prop_Send, "m_flLastLongJumpBreakTime", 0.0);
		}
		// BM's internal "suit charged" byte lives at player+0x94d (owned by
		// the sub-object at +0x8bc; not networked, not in the datamaps).
		// The suit charger's Use() hard-fails while it is 0. The match-start
		// respawn above (Spawn() block init) resets it to 0, and the only
		// live setter in server.dll is the Long Jump Module's charge-complete
		// path (vtable-dispatched) - so a player who picked up the LJM at
		// match start would have to sit through its whole charge-up before
		// +use could interact with a suit charger. Force it charged here:
		// the engine's own setter is idempotent (cmp/je) and the only clear
		// function has zero callers anywhere in the binary (verified by
		// exhaustive disassembly), so nothing can overwrite this in play.
		SetEntData(iClient, 0x94d, 1, 1, true);
	}
	Bms_ResetScores();
	LogMessage("[bms_match] players respawned (manual refresh)");
}

/**************************************************************
 * ROUND TIMER (BM: the mp_round_time entity drives the map
 * countdown; runtime mp_timelimit changes are NOT applied by
 * the engine - adjust the entity directly, same mechanism as
 * the is_bms_fix_timelimit plugin)
 *************************************************************/
int Bms_FindOrCreateRoundTimer()
{
	int iEnt = FindEntityByClassname(-1, "mp_round_time");
	if (iEnt == -1)
	{
		iEnt = CreateEntityByName("mp_round_time");
		if (iEnt == -1)
		{
			return -1;
		}
		DispatchSpawn(iEnt);
	}
	return iEnt;
}

void Bms_AddRoundTime(int iSeconds)
{
	if (iSeconds == 0)
	{
		return;
	}
	int iEnt = Bms_FindOrCreateRoundTimer();
	if (iEnt == -1)
	{
		LogMessage("[bms_match] RoundTimer: cannot find/create mp_round_time");
		return;
	}
	SetVariantInt(iSeconds < 0 ? -iSeconds : iSeconds);
	AcceptEntityInput(iEnt, iSeconds > 0 ? "AddRoundTime" : "RemoveRoundTime");
}

// Returns true when the round timer has converged on the target (either it
// was already there or the input stuck). During the warmup the engine's
// state gate (==2, round in progress) swallows AddRoundTime/RemoveRoundTime;
// the gamerules state channel below plus the direct field write make the
// correction land regardless of the gate.
//
// bAbsolute: when true (during a match), the gamerules deadline is pinned to
// fStartTime + iTargetSeconds (an absolute instant) instead of
// curtime + iTargetSeconds. The HUD countdown and the engine's natural round
// end both read m_StateRound[0] (DoneTime); writing it relative-to-curtime
// makes each re-arm (BmsT_Start at +4s, BmsT_PostRestartFix at +6s) push the
// deadline later than fStartTime, so the HUD showed ~7s remaining when the
// fStartTime-driven end timer (BmsT_CheckOvertime) actually fired.
bool Bms_AdjustRoundTimer(int iTargetSeconds, bool bAbsolute = false)
{
	if (iTargetSeconds <= 0)
	{
		return true;
	}
	// The HUD countdown and the engine's natural round end both read the
	// networked gamerules field m_StateRound[0] (m_flStateDoneTime at
	// gamerules+0x6c). Writing it directly is authoritative. The legacy
	// mp_round_time AddRoundTime/RemoveRoundTime inputs route to the SAME
	// field via the round timer's AddTime/RemoveTime, so applying BOTH
	// double-counts the delta: a stale m_iRoundTime (60) made Bms_EndMatch's
	// RemoveRoundTime(49) lapse DoneTime by ~38s and force a CHANGE LEVEL.
	// Drop the input; keep the vestigial entity field in sync only.
	float fDeadline = bAbsolute
		? (gBmsRound.fStartTime + float(iTargetSeconds) + float(BMS_HUD_OFFSET))
		: (GetGameTime() + float(iTargetSeconds));
	GameRules_SetPropFloat("m_StateRound", fDeadline, 0);
	LogMessage("[bms_match] RoundTimer: done_time=%.1f now=%.1f target=%d abs=%d",
		fDeadline, GetGameTime(), iTargetSeconds, bAbsolute);
	int iEnt = Bms_FindOrCreateRoundTimer();
	if (iEnt == -1)
	{
		return false;
	}
	if (!HasEntProp(iEnt, Prop_Data, "m_iRoundTime"))
	{
		return false;
	}
	// The client HUD renders the NETWORKED gamerules field m_StateRound[0]
	// (DoneTime), not the mp_round_time entity's m_iRoundTime (server-only
	// SAVE|KEY datamap flags, no INSENDTABLE). The countdown is anchored at
	// Round.Enter, which fires BMS_HUD_OFFSET seconds before go-live; that gap
	// is why the HUD opened 3s short (57 instead of 60). Bump the networked
	// DoneTime above by BMS_HUD_OFFSET so the HUD opens at iTargetSeconds. The
	// engine's natural round end also reads DoneTime, but BmsT_CheckOvertime
	// fires first at fStartTime + target and wins, so no double end.
	// m_iRoundTime is vestigial: keep it in sync with the un-offset target only.
	int iHudSeconds = iTargetSeconds;
	SetEntProp(iEnt, Prop_Data, "m_iRoundTime", iHudSeconds);
	return (GetEntProp(iEnt, Prop_Data, "m_iRoundTime") == iHudSeconds);
}

void Bms_ResetScores()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		{
			continue;
		}
		SetEntProp(iClient, Prop_Data, "m_iFrags", 0);
		SetEntProp(iClient, Prop_Data, "m_iDeaths", 0);
	}
	LogMessage("[bms_match] scores reset");
}

public Action BmsT_AdjustRoundTimer(Handle hTimer, int iTarget)
{
	if (gBmsRound.iState != BmsState_MatchWait && gBmsRound.iState != BmsState_Match)
	{
		return Plugin_Stop;
	}
	// Re-arm after server_match.cfg's one-frame mp_timelimit stomp (15) landed
	// right after Bms_OnMatchPre; this +1.5s timer is the post-restart fix-up.
	Bms_ArmMatchRoundConVars();
	Bms_AdjustRoundTimer(iTarget, true);
	return Plugin_Stop;
}

void Bms_CreateOverTimer(float fDelay = 0.0)
{
	if (gBmsRound.hOvertime != INVALID_HANDLE)
	{
		KillTimer(gBmsRound.hOvertime);
		gBmsRound.hOvertime = INVALID_HANDLE;
	}
	// Fire one second before the engine's natural round end so
	// Bms_EndMatch's AdjustRoundTimer(60) push-out lands well ahead of the
	// intermission (a 0.1s lead raced with the DoneTime expiry in practice).
	float fTime = Bms_GetTimeRemaining(false) - 1.0 + fDelay;
	if (fTime < 0.5)
	{
		fTime = 0.5;
	}
	gBmsRound.hOvertime = CreateTimer(fTime, BmsT_CheckOvertime, _, TIMER_FLAG_NO_MAPCHANGE);
}

/**************************************************************
 * SOURCETV RECORDING
 *************************************************************/
void Bms_TV_Start()
{
	if (!gBmsTV.bEnable || gBmsTV.bRecording)
	{
		return;
	}
	if (gBmsCvar.tv_enable == null)
	{
		LogMessage("[bms_match] SourceTV not supported on this engine (tv_enable missing), recording disabled");
		gBmsTV.bEnable = false;
		return;
	}
	// BM can only record when tv_enable is already 1 when the map loads
	// (resident setting in server.cfg): toggling it mid-game does not
	// bring up the SourceTV client. Just verify and warn.
	if (!gBmsCvar.tv_enable.BoolValue)
	{
		LogMessage("[bms_match] SourceTV: tv_enable is 0 - recording will not work; add \"tv_enable 1\" to server.cfg");
	}
	if (strlen(gBmsTV.sDemoDir))
	{
		if (!DirExists(gBmsTV.sDemoDir))
		{
			CreateDirectory(gBmsTV.sDemoDir, FPERM_U_READ | FPERM_U_WRITE | FPERM_U_EXEC);
		}
		FormatEx(gBmsTV.sDemoName, sizeof(gBmsTV.sDemoName), "%s/%s.dem", gBmsTV.sDemoDir, gBmsRound.sUID);
	}
	else
	{
		FormatEx(gBmsTV.sDemoName, sizeof(gBmsTV.sDemoName), "%s.dem", gBmsRound.sUID);
	}
	ServerCommand("tv_record \"%s\"", gBmsTV.sDemoName);
	gBmsTV.bRecording = true;
	Bms_SayAll("%t", "bms_demo_recording");
	LogMessage("[bms_match] SourceTV recording started: %s", gBmsTV.sDemoName);
}

void Bms_TV_Stop(bool bAnnounce)
{
	if (!gBmsTV.bRecording)
	{
		return;
	}
	ServerCommand("tv_stoprecord");
	gBmsTV.bRecording = false;
	LogMessage("[bms_match] SourceTV recording stopped: %s", gBmsTV.sDemoName);
	if (bAnnounce)
	{
		char sUrl[256];
		if (strlen(gBmsTV.sDownloadBase))
		{
			FormatEx(sUrl, sizeof(sUrl), "%s%s", gBmsTV.sDownloadBase, gBmsTV.sDemoName);
		}
		else
		{
			FormatEx(sUrl, sizeof(sUrl), "%s", gBmsTV.sDemoName);
		}
		Bms_SayAll("%t", "bms_demo_recorded", sUrl);
	}
}

/**************************************************************
 * IN-GAME VGUI PAGE (xms-style fullscreen panels)
 *************************************************************/
// BM client keeps the HL2MP viewport panels. Wire format of the VGUIMenu
// usermessage (verified against the official SDK 2013 source - BM is a
// fork of it - and the 2018 engine source, both identical):
//   string panelname + byte show + byte count + count x (string key, string value)
// The client turns the pairs into a KeyValues table and calls
// viewport->SetData(keys) before showing the panel. A plain text payload
// would have its first byte read as "count" and the panel would show
// nothing - the keys below are mandatory.
// "info" = CHL2MPTextWindow (CTextWindow): fullscreen page with a title
// label and a multiline text box. SetData keys: "type" (0 = plain text),
// "title", "msg", "msg_fallback", "cmd", "unload". type=0 renders msg
// verbatim (vgui TextEntry, no vsnprintf in the path, CP936-safe). The
// panel captures the mouse (OK button closes it until the next per-second
// push). "scores" needs no payload: native round-end scoreboard.
// All text still passes the SafeTail sanitizer as cheap insurance.

void Bms_VGUIPage_Send(int iClient, const char[] sTitle, const char[] sText)
{
	if (!IsClientInGame(iClient) || IsFakeClient(iClient))
	{
		return;
	}
	Handle hMsg = StartMessageOne("VGUIMenu", iClient);
	if (hMsg == null)
	{
		return;
	}
	char sSafeTitle[256];
	char sSafeText[1024];
	strcopy(sSafeTitle, sizeof(sSafeTitle), sTitle);
	strcopy(sSafeText, sizeof(sSafeText), sText);
	mod_textmsg_fix_TextMsgFix_SafeTail(sSafeTitle, sizeof(sSafeTitle));
	mod_textmsg_fix_TextMsgFix_SafeTail(sSafeText, sizeof(sSafeText));
	BfWriteString(hMsg, "info");
	BfWriteByte(hMsg, 1);
	BfWriteByte(hMsg, 3); // three KeyValues pairs follow
	BfWriteString(hMsg, "type");
	BfWriteString(hMsg, "0");
	BfWriteString(hMsg, "title");
	BfWriteString(hMsg, sSafeTitle);
	BfWriteString(hMsg, "msg");
	BfWriteString(hMsg, sSafeText);
	EndMessage();
}

// 只有我们真的用 VGUIMenu 开过 "scores" 面板才需要去关它。客户端自己的记分板
// (TAB / +showscores) 也是同一个原生面板, 每张图 OnMapStart 无条件 HideAll 会
// 对它发一次 show=0 —— 2026-11-17 用户报 +showscores 失效, 先从消除这个无谓的
// 干扰入手(命令本身是纯客户端输入, 服务端拦不住)。
bool gBmsScoresShown;

void Bms_VGUIPage_Hide(int iClient)
{
	if (!IsClientInGame(iClient) || IsFakeClient(iClient))
	{
		return;
	}
	Handle hMsg = StartMessageOne("VGUIMenu", iClient);
	if (hMsg == null)
	{
		return;
	}
	BfWriteString(hMsg, "info");
	BfWriteByte(hMsg, 0);
	BfWriteByte(hMsg, 0);
	EndMessage();
	if (!gBmsScoresShown)
	{
		// 没开过就绝对不要发 "scores" —— 每张图 OnMapStart 都会 HideAll,
		// 对客户端自己的记分板面板(TAB / +showscores)发一次 show=0 没道理。
		return;
	}
	// The native scoreboard is a distinct panel addressed by NAME - the
	// client VGUIMenu handler looks the panel up via FindPanelByName and
	// calls ShowPanel(viewport, bShow) on it (2018 leak
	// clientmode_shared.cpp: __MsgFunc_VGUIMenu), so hiding the "info" page
	// never closes the "scores" panel. Send a second menu message for it.
	Handle hScores = StartMessageOne("VGUIMenu", iClient);
	if (hScores == null)
	{
		return;
	}
	BfWriteString(hScores, "scores");
	BfWriteByte(hScores, 0);
	BfWriteByte(hScores, 0);
	EndMessage();
}

void Bms_VGUIPage_HideAll()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		Bms_VGUIPage_Hide(iClient);
	}
	gBmsScoresShown = false;
}

void Bms_VGUIPage_ShowScoresPanel()
{
	// Native round-end scoreboard page (HL2DM sends VGUIMenu "scores"
	// show=1 when a round ends). No payload: the panel reads the scores
	// from the game state itself.
	gBmsScoresShown = true;

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		{
			continue;
		}
		Handle hMsg = StartMessageOne("VGUIMenu", iClient);
		if (hMsg == null)
		{
			continue;
		}
		BfWriteString(hMsg, "scores");
		BfWriteByte(hMsg, 1);
		BfWriteByte(hMsg, 0);
		EndMessage();
	}
}

/**************************************************************
 * STATUS HUD (countdown / state / map / players)
 *************************************************************/
// 更新之后 HUD 顶上的倒计时和「正在等待玩家加入」一类的引擎文本都没了
// (公服本来就不画 —— Bms_RestoreGamerules 移掉了 mp_round_time; 比赛期的
// 倒计时靠 gamerules DoneTime 画, 新版客户端也不画了)。
// 先试过塞进 VGUI "info" 文本页, 实测新版客户端把它渲染成一行没有换行的黄字
// 且压在屏幕左侧; 也试过 ShowSyncHudText, 位置能对上但没有底框。最终走
// PrintHintText: 和 showhealth 的 "Show Health: N" 同一块带底框的面板,
// 每秒刷新一次, 行内换行用 \n。
//
// bms_status_page: 0 = 关, 1 = 只发给未存活的人(死亡/观战), 2 = 所有人。
// 只有 2 会占用整个 hint 面板, 此时 "Show Health: N" 由本模块一起画,
// 并通过 bms_status_active 让 showhealth 闭嘴。
void Bms_StatusStateKey(BmsGameState iState, char[] sKey, int iLen)
{
	if (iState == BmsState_Paused)         { strcopy(sKey, iLen, "bms_state_paused"); }
	else if (iState == BmsState_Overtime)  { strcopy(sKey, iLen, "bms_state_overtime"); }
	else if (iState == BmsState_MatchWait) { strcopy(sKey, iLen, "bms_state_matchwait"); }
	else if (iState == BmsState_Match)     { strcopy(sKey, iLen, "bms_state_match"); }
	else if (iState == BmsState_MatchEx)   { strcopy(sKey, iLen, "bms_state_matchex"); }
	else if (iState == BmsState_Over)      { strcopy(sKey, iLen, "bms_state_over"); }
	else if (iState == BmsState_Changing)  { strcopy(sKey, iLen, "bms_state_changing"); }
	else                                   { strcopy(sKey, iLen, "bms_state_default"); }
}

void Bms_StatusFmtTime(float fSeconds, char[] sOut, int iLen)
{
	// Bms_GetTimeRemaining 在没有时间上限(mp_timelimit<=0 且非比赛)时返回 999999。
	if (fSeconds >= 999999.0)
	{
		strcopy(sOut, iLen, "--:--");
		return;
	}
	int iSec = RoundToFloor(fSeconds);
	if (iSec < 0)
	{
		iSec = 0;
	}
	if (iSec >= 3600)
	{
		Format(sOut, iLen, "%d:%02d:%02d", iSec / 3600, (iSec % 3600) / 60, iSec % 60);
	}
	else
	{
		Format(sOut, iLen, "%02d:%02d", iSec / 60, iSec % 60);
	}
}

// 这一页要画谁的 HP/护甲/武器: 观战(以及死亡等待重生)时是被观察者。
int Bms_StatusSubject(int iClient)
{
	if (!IsClientObserver(iClient))
	{
		return iClient;
	}

	int iTarget = GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget");

	if (iTarget < 1 || iTarget > MaxClients || !IsClientInGame(iTarget) || IsClientObserver(iTarget))
	{
		return iClient;
	}

	return iTarget;
}

void Bms_BuildStatusPage(int iClient, char[] sBody, int iLen)
{
	char sKey[32];
	Bms_StatusStateKey(gBmsRound.iState, sKey, sizeof(sKey));

	// 空闲且人不够开局 = 旧版本顶部那行「正在等待玩家加入」; 人够了就是死斗。
	if (gBmsRound.iState == BmsState_Default)
	{
		strcopy(sKey, sizeof(sKey), Bms_PlayerCount() < 2 ? "bms_state_waiting" : "bms_state_ffa");
	}

	char sState[64];
	Format(sState, sizeof(sState), "%T", sKey, iClient);

	char sMap[64];
	strcopy(sMap, sizeof(sMap), strlen(gBmsRound.sMap) ? gBmsRound.sMap : "--");

	// HudMsg 通道最多 6 个槽位 = 6 行。普通排版:
	//   HP+护甲 / 状态+人数 / 倒计时 / 地图 / 武器+弹药 / !help
	// 通道 2 还要塞下记分块(自己 K/D/ping + 前五名两行), 于是压成:
	//   HP+护甲 / 地图|状态|倒计时 / 武器 / 自己 K/D/ping / 前五名×2
	// 也就是把前三行并成一行、让掉 !help。
	// 通道 0 + bms_status_keyhint 0 的 HintText 只吃单行(见下面的 bOneLine),
	// 排版是: HP: N | 护甲: N | 剩余 T | 状态 N人 | 武器
	// 地图与 !help 提示在这条通道上放不下, 留给记分板。默认走 KeyHintText
	// 多行, 这段只在把 hint 面板切到 HintText 时才生效。
	//
	// 观战时换成被观察者的数据, 第一行多出「观察 名字 K/D」, 就把 !help 那行
	// 让掉(观战者要看的是那个人, 不是指令提示), 普通排版仍然正好 6 行。
	//
	// HP 与护甲**常驻**(不再看 showhealth 的开关/on_hit_only/玩家 cookie),
	// 数字统一带冒号; 两者并成一行, 把第二行让给状态、第三行让给倒计时。
	sBody[0] = '\0';

	char sPart[192];
	int iSubject = Bms_StatusSubject(iClient);
	bool bWatching = (iSubject != iClient);
	bool bCompact = Bms_StatusUseCompact();
	// 单行: hint 面板的 HintText(CHudHintDisplay) —— 就是 showhealth 那块
	// 细长条。它是**按行高排版**的, 而原版客户端的 clientscheme.res 里没有
	// "HudHintText" 字体(只有 HudHintTextLarge/Small), GetFontTall 拿到 0,
	// 多行会全部叠在同一个 y 上。所以这条通道只能发一行; 单行的宽度由文字
	// 自己撑出来(底框被 clamp 在 hudlayout 的 wide), 正是玩家看到的长条。
	bool bOneLine = Bms_StatusUsesHint() && !Bms_StatusUseKeyHint();

	if (bWatching)
	{
		char sName[64];
		char sWatch[128];
		GetClientName(iSubject, sName, sizeof(sName));
		Format(sWatch, sizeof(sWatch), "%T K %i / D %i", "bms_page_status_watching", iClient,
			sName, GetClientFrags(iSubject), GetClientDeaths(iSubject));

		// 紧凑排版里没有单独一行放被观察者的 ping, 并进这一行。
		if ((bCompact || bOneLine) && Bms_StatusShowStats())
		{
			Format(sPart, sizeof(sPart), "%s / %ims", sWatch, Bms_ClientPing(iSubject));
		}
		else
		{
			strcopy(sPart, sizeof(sPart), sWatch);
		}

		strcopy(sBody, iLen, sPart);
		StrCat(sBody, iLen, bOneLine ? " | " : "\n");
	}

	Format(sPart, sizeof(sPart), "HP: %i", IsPlayerAlive(iSubject) ? GetClientHealth(iSubject) : 0);
	StrCat(sBody, iLen, sPart);

	// 走 FindSendPropInfo 而不是 GetEntProp: 万一这个网络属性不存在,
	// GetEntProp 会每秒刷一条 "property not found" 日志。
	static int iArmorOffs = -2;

	if (iArmorOffs == -2)
	{
		char sNetClass[64];
		GetEntityNetClass(iSubject, sNetClass, sizeof(sNetClass));
		iArmorOffs = FindSendPropInfo(sNetClass, "m_ArmorValue");

		if (iArmorOffs <= 0)
		{
			LogMessage("[bms_match] status page: m_ArmorValue missing on %s", sNetClass);
			iArmorOffs = -1;
		}
	}

	int iArmor = (iArmorOffs > 0) ? GetEntData(iSubject, iArmorOffs) : 0;

	if (iArmor < 0)
	{
		iArmor = 0;
	}

	Format(sPart, sizeof(sPart), " | %T", "bms_page_status_armor", iClient, iArmor);
	StrCat(sBody, iLen, sPart);

	// 倒计时: 热身期间引擎的倒计时是 gamerules 的 m_StateWarmup[0](绝对
	// DoneTime, 与 GetGameTime 同一时钟); 11-17 更新后客户端不再画顶部
	// 倒计时, 这一行就是在补它。热身结束后回到原来的 mp_timelimit 估算
	// (比赛走 Bms_GetMatchTimelimit)。
	char sLeft[32];
	char sLeftKey[32];
	float fWarmupDone = GameRules_GetPropFloat("m_StateWarmup", 0);
	float fLeft;

	if (fWarmupDone > GetGameTime())
	{
		strcopy(sLeftKey, sizeof(sLeftKey), "bms_page_status_warmup");
		fLeft = fWarmupDone - GetGameTime();
	}
	else
	{
		strcopy(sLeftKey, sizeof(sLeftKey), "bms_page_status_left");
		fLeft = Bms_GetTimeRemaining(false);
	}

	// KeyHintText 通道每发一条客户端就播一声「啵」(Player.HudHint =
	// hev_vox/blip.wav, 只被客户端自己的 cl_hudhint_sound 挡, 那个 cvar 在
	// 服务端没注册, 服务端碰不到) —— 走这条通道时才降频: 倒计时按分钟取整,
	// 只有最后两分钟才逐秒走, 配合 Bms_SendStatusPage 的内容去重, 最坏情况
	// 一分钟响一次。HintText / HudMsg 都是静音的, 保持逐秒。
	if (Bms_StatusUsesHint() && Bms_StatusUseKeyHint() && fLeft > 120.0 && fLeft < 999999.0)
	{
		fLeft = float(RoundToFloor(fLeft / 60.0) * 60);
	}

	Bms_StatusFmtTime(fLeft, sLeft, sizeof(sLeft));

	char sCount[64];
	Format(sCount, sizeof(sCount), "%T", sLeftKey, iClient, sLeft);

	char sStateLine[96];
	Format(sStateLine, sizeof(sStateLine), "%s %d人", sState, Bms_PlayerCount());

	char sMapLine[96];
	Format(sMapLine, sizeof(sMapLine), "%T", "bms_page_status_map", iClient, sMap);

	if (bOneLine)
	{
		// 单行: 只留 HP/护甲 + 倒计时 + 状态 + 武器。地图和 !help 提示这条
		// 通道放不下 —— 文字是以面板中心为准居中的, 太长会顶出屏幕右边。
		Format(sPart, sizeof(sPart), " | %s | %s", sCount, sStateLine);
		StrCat(sBody, iLen, sPart);
	}
	else if (bCompact)
	{
		Format(sPart, sizeof(sPart), "%s | %s | %s", sMapLine, sStateLine, sCount);
		StrCat(sBody, iLen, "\n");
		StrCat(sBody, iLen, sPart);
	}
	else
	{
		StrCat(sBody, iLen, "\n");
		StrCat(sBody, iLen, sStateLine);
		StrCat(sBody, iLen, "\n");
		StrCat(sBody, iLen, sCount);
		StrCat(sBody, iLen, "\n");
		StrCat(sBody, iLen, sMapLine);
	}

	if (Bms_StatusWeaponLine(iSubject, sPart, sizeof(sPart)))
	{
		StrCat(sBody, iLen, bOneLine ? " | " : "\n");
		StrCat(sBody, iLen, sPart);
	}

	// 记分块: 通道 2 用三列紧凑排版; hint 面板一行一个(那块面板的宽度
	// 被 clamp 在 hudlayout 的 wide 上, 三列会被裁)。HudMsg 通道 1 六个
	// 槽位本来就满了, 不加。
	if (Bms_StatusShowStats() && (bCompact || (Bms_StatusUsesHint() && !bOneLine)))
	{
		Bms_AppendScoreBlock(iClient, iSubject, bWatching, sBody, iLen, bCompact);
	}

	if (!bWatching && !bCompact && !bOneLine)
	{
		Format(sPart, sizeof(sPart), "%T", "bms_page_status_hint", iClient);
		StrCat(sBody, iLen, "\n");
		StrCat(sBody, iLen, sPart);
	}
}

bool Bms_StatusShowStats()
{
	return gBmsStatusStats != null && gBmsStatusStats.BoolValue;
}

int Bms_ClientPing(int iClient)
{
	// GetClientLatency 对 bot 直接抛 "Client N is a bot", 每秒写一行错误日志。
	if (!IsClientConnected(iClient) || IsFakeClient(iClient))
	{
		return 0;
	}

	int iPing = RoundToNearest(GetClientLatency(iClient, NetFlow_Outgoing) * 1000.0);

	return (iPing < 0) ? 0 : iPing;
}

// UTF-8 首字节 -> 该字符占几个字节。玩家名是 UTF-8, 按字节硬截会切出半个
// 汉字, 在面板上就是乱码。
int Bms_Utf8CharLen(int c)
{
	if ((c & 0x80) == 0)
	{
		return 1;
	}

	if ((c & 0xE0) == 0xC0)
	{
		return 2;
	}

	if ((c & 0xF0) == 0xE0)
	{
		return 3;
	}

	return 4;
}

void Bms_TrimName(const char[] sName, char[] sOut, int iLen, int iMaxBytes)
{
	int iCut = 0;

	while (sName[iCut])
	{
		int iCharLen = Bms_Utf8CharLen(sName[iCut]);

		if (iCut + iCharLen > iMaxBytes)
		{
			break;
		}

		iCut += iCharLen;
	}

	int iCopy = (iCut < iLen - 1) ? iCut : iLen - 1;

	for (int i = 0; i < iCopy; i++)
	{
		sOut[i] = sName[i];
	}

	sOut[iCopy] = '\0';
}

bool Bms_ScoreBeats(int iA, int iB)
{
	int iFragsA = GetClientFrags(iA);
	int iFragsB = GetClientFrags(iB);

	if (iFragsA != iFragsB)
	{
		return iFragsA > iFragsB;
	}

	return GetClientDeaths(iA) < GetClientDeaths(iB);
}

// 比分板: 自己(观战时是被观察者)的 击杀/死亡/延迟, 再往下是前五名。
// HudMsg 通道一共六个槽位, 放不下这六行, 只有 hint 面板和通道 2 画。
// bTight = 通道 2 的三列排版(一行三个人); hint 面板宽度被 clamp 在
// hudlayout 的 wide 上, 一行三个人会被裁掉半截, 所以那边一行只放一个人。
void Bms_AppendScoreBlock(int iClient, int iSubject, bool bWatching, char[] sBody, int iLen, bool bTight)
{
	char sPart[192];

	// 自己(或被观察者)的 K/D/ping。观战时 K/D 和 ping 都已经并进第一行,
	// 不再重复, 剩下 6 行预算全给前五名。
	if (!bWatching)
	{
		Format(sPart, sizeof(sPart), "%T", "bms_page_status_stats", iClient,
			GetClientFrags(iSubject), GetClientDeaths(iSubject), Bms_ClientPing(iSubject));
		StrCat(sBody, iLen, "\n");
		StrCat(sBody, iLen, sPart);
	}

	// 插入排序, 人最多 MaxClients 个, 不值得再引一个排序库。
	int iOrder[MAXPLAYERS];
	int iCount = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsClientObserver(i))
		{
			continue;
		}

		int iPos = iCount;

		while (iPos > 0 && Bms_ScoreBeats(i, iOrder[iPos - 1]))
		{
			iOrder[iPos] = iOrder[iPos - 1];
			iPos--;
		}

		iOrder[iPos] = i;
		iCount++;
	}

	// 一行 3 个, 5 个人占两行(第二行只有 2 个)。名字截到 12 字、不带 ping,
	// 否则带中文名的一行会越过屏幕右边界被裁掉。
	char sRow[2][192];
	sRow[0][0] = '\0';
	sRow[1][0] = '\0';

	for (int iRank = 0; iRank < iCount && iRank < 5; iRank++)
	{
		int iPlayer = iOrder[iRank];
		char sName[MAX_NAME_LENGTH];
		char sShort[32];
		char sEntry[64];

		GetClientName(iPlayer, sName, sizeof(sName));
		Bms_TrimName(sName, sShort, sizeof(sShort), 12);
		Format(sEntry, sizeof(sEntry), "%d. %s %d/%d", iRank + 1, sShort,
			GetClientFrags(iPlayer), GetClientDeaths(iPlayer));

		if (!bTight)
		{
			StrCat(sBody, iLen, "\n");
			StrCat(sBody, iLen, sEntry);
			continue;
		}

		int iRow = iRank / 3;

		if (sRow[iRow][0])
		{
			StrCat(sRow[iRow], sizeof(sRow[]), " | ");
		}

		StrCat(sRow[iRow], sizeof(sRow[]), sEntry);
	}

	if (bTight)
	{
		for (int iRow = 0; iRow < 2 && sRow[iRow][0]; iRow++)
		{
			StrCat(sBody, iLen, "\n");
			StrCat(sBody, iLen, sRow[iRow]);
		}
	}
}

// 当前武器 + 弹药。classname 去掉 "weapon_" 前缀直接当名字用
// (crowbar / smg1 / ar2 / tau / rpg ...), 不改写成本地化名词。
// 弹匣读 m_iClip1, 近战/工具是 -1, 只显示名字。
//
// 备弹分两条路: BM 的 HL1 系武器(glock/mp5/357/crossbow/shotgun/tau/rpg/
// satchel/snark/tripmine/frag)把备弹存在玩家自己的具名字段里 —— server.dll
// 的 datamap 建表处(0x107f530c 起)是 FIELD_INTEGER m_iAmmoGlock@0x4e4 /
// m_iAmmoMp5@0x4e8 / m_iAmmo357@0x4ec / m_iAmmoBolt@0x4f0 /
// m_iAmmoBuckshot@0x4f4 / m_iAmmoEnergy@0x4f8 / m_iAmmoMp5Grenade@0x4fc /
// m_iAmmoRPG@0x500 / m_iAmmoFrag@0x504 / m_iAmmoSatchel@0x510 /
// m_iAmmoTripmine@0x50c / m_iAmmoSnark@0x508, 而且这几条在 client.dll 里
// 一个字符串都没有 = 不走网络、只有服务端能读(Prop_Data)。
// 高斯枪(weapon_tau)读的就是 m_iAmmoEnergy; 之前按 m_iAmmo[类型] 读拿到
// 的是 HL2 那个 SendPropArray3 里的空槽, 所以显示不对。
// HL2 系武器(ar2/smg1/pistol/...)才走 m_iAmmo + m_iPrimaryAmmoType。
bool Bms_StatusWeaponLine(int iClient, char[] sOut, int iLen)
{
	int iWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");

	if (iWeapon <= 0 || !IsValidEntity(iWeapon))
	{
		return false;
	}

	char sClass[64];

	if (!GetEntityClassname(iWeapon, sClass, sizeof(sClass)) || !sClass[0])
	{
		return false;
	}

	char sName[64];

	if (StrContains(sClass, "weapon_", false) == 0)
	{
		strcopy(sName, sizeof(sName), sClass[7]);
	}
	else
	{
		strcopy(sName, sizeof(sName), sClass);
	}

	int iClip = GetEntProp(iWeapon, Prop_Send, "m_iClip1");
	int iReserve = Bms_WeaponAmmoCount(iClient, iWeapon, "m_iPrimaryAmmoType");

	char sWeapon[64];
	Format(sWeapon, sizeof(sWeapon), "%T", "bms_page_status_weapon", iClient, sName);

	// 近战/工具本来就没有弹药, m_iClip1 = -1。之前这里只看 iClip < 0, 而下面
	// 的兜底把 iReserve 补成 0 之后又去读 HL2 的 m_iAmmo[类型], 撬棍就凭空
	// 多出一个数字。这一类武器直接只显示名字。
	if (Bms_WeaponHasNoAmmo(sClass))
	{
		Format(sOut, iLen, "%s", sWeapon);
		return true;
	}

	// BM 把"没用到的弹药槽"写成 255(ammodump 实测 mp5 的 m_iClip2 = 255),
	// 而不是 HL2 的 -1。tau/rpg 这类没有弹匣的武器 m_iClip1 就是 255, 以前
	// 当成真弹量显示成 "tau 255/45"。哪一边是 255 就只显示另一边, 两边都是
	// 就只留名字。
	bool bClipNone = (iClip < 0 || iClip == 255);
	bool bReserveNone = (iReserve < 0 || iReserve == 255);

	// mp5 的第二攻击是榴弹, 弹药存在另一个字段 m_iAmmoMp5Grenade 里,
	// 玩家看不到, 跟在主弹药后面一起显示。
	char sGrenade[48];
	sGrenade[0] = '\0';

	if (Bms_WeaponUsesMp5Grenade(sClass))
	{
		int iNade = Bms_WeaponAmmoCount(iClient, iWeapon, "m_iSecondaryAmmoType");

		// BM 的 mp5 榴弹用 HL2 的 SMG1_Grenade 槽(弹药类型 3); 武器的
		// m_iSecondaryAmmoType 读出来是 255(无), 所以固定回落到 3。
		if (iNade < 0)
		{
			iNade = Bms_PlayerAmmo(iClient, 3);
		}

		if (iNade > 0)
		{
			Format(sGrenade, sizeof(sGrenade), " %T", "bms_page_status_grenade", iClient, iNade);
		}
	}

	if (bClipNone)
	{
		if (bReserveNone)
		{
			Format(sOut, iLen, "%s%s", sWeapon, sGrenade);
		}
		else
		{
			Format(sOut, iLen, "%s %d%s", sWeapon, iReserve, sGrenade);
		}

		return true;
	}

	if (bReserveNone)
	{
		Format(sOut, iLen, "%s %d%s", sWeapon, iClip, sGrenade);
		return true;
	}

	Format(sOut, iLen, "%s %d/%d%s", sWeapon, iClip, iReserve, sGrenade);
	return true;
}

// 没有弹药的武器(近战/工具/生物手雷): 面板只写名字。
bool Bms_WeaponHasNoAmmo(const char[] sClass)
{
	return StrEqual(sClass, "weapon_crowbar")
		|| StrEqual(sClass, "weapon_stunstick")
		|| StrEqual(sClass, "weapon_physcannon")
		|| StrEqual(sClass, "weapon_bugbait");
}

// 第二攻击打榴弹的枪。BM 的冲锋枪 classname 是 weapon_mp5(见 bms/cfg/config.cfg
// 的 bind 行), smg1/grenadelauncher 一并算上, 免得换个名字又漏。
bool Bms_WeaponUsesMp5Grenade(const char[] sClass)
{
	return StrEqual(sClass, "weapon_mp5")
		|| StrEqual(sClass, "weapon_smg1")
		|| StrEqual(sClass, "weapon_grenadelauncher");
}

// 玩家身上的 m_iAmmo 是 SendPropArray3(32 槽), 按武器自己声明的弹药类型索引。
// BM 那些具名字段(m_iAmmoGlock/m_iAmmoMp5Grenade/...)在运行时一个都查不到 ——
// 2026-11-18 的 ammodump 打印 12 个全是 "no datamap field found", 所以只能走数组。
int Bms_PlayerAmmo(int iClient, int iType)
{
	if (iType < 0 || iType >= 32)
	{
		return -1;
	}

	static int iOffs = -2;

	if (iOffs == -2)
	{
		char sNetClass[64];
		GetEntityNetClass(iClient, sNetClass, sizeof(sNetClass));
		iOffs = FindSendPropInfo(sNetClass, "m_iAmmo");
	}

	if (iOffs <= 0)
	{
		return -1;
	}

	return GetEntData(iClient, iOffs + iType * 4, 4);
}

// 读武器声明的弹药类型(m_iPrimaryAmmoType / m_iSecondaryAmmoType),
// 再取玩家 m_iAmmo 里对应的数量。类型无效时返回 -1。
int Bms_WeaponAmmoCount(int iClient, int iWeapon, const char[] sTypeProp)
{
	int iOffs = FindDataMapInfo(iWeapon, sTypeProp);

	if (iOffs <= 0)
	{
		iOffs = FindSendPropInfo("CBaseCombatWeapon", sTypeProp);
	}

	if (iOffs <= 0)
	{
		return -1;
	}

	return Bms_PlayerAmmo(iClient, GetEntData(iWeapon, iOffs, 4));
}

void Bms_SendStatusPage(int iClient)
{
	char sBody[1024];
	Bms_BuildStatusPage(iClient, sBody, sizeof(sBody));

	// speclist 模块在同一条通道上, 现在让位给状态页, 观战名单由这里补
	// 成最后一行(否则会少掉「谁在看我」这个信息)。
	if (!IsClientObserver(iClient))
	{
		char sSpecs[256];
		mod_speclist_BuildSpecList(iClient, sSpecs, sizeof(sSpecs));

		if (sSpecs[0])
		{
			// 单行通道(HintText)拼在同一行里, 换行在那块面板上等于不换。
			StrCat(sBody, sizeof(sBody), (Bms_StatusUsesHint() && !Bms_StatusUseKeyHint()) ? " | Spectators: " : "\nSpectators: ");
			StrCat(sBody, sizeof(sBody), sSpecs);
		}
	}

	// 底框的宽度是客户端按「最长的那一行」算出来的(CHudHintKeyDisplay 的
	// 绘制函数里 boxW = min(面板宽, 最长行宽 + 2*text_xgap)), 所以数字一变
	// (HP 100→99)、换个武器、观战名单出现或消失, 框就跟着伸缩。这里垫一条
	// 纯空格行: 空格同样计入文字宽度, 45 个远超过 hudlayout 的 wide 100,
	// 于是「最长行」永远是这一行, 底框被 clamp 成固定长度。这一行本身什么都
	// 画不出来, 只是把框撑住不动。
	// 只在 KeyHintText 那条上垫 —— HintText(CHudHintDisplay) 只吃得下单行,
	// HudMsg 是另一套排版, 都不需要也不会受它影响。
	if (Bms_StatusUsesHint() && Bms_StatusUseKeyHint())
	{
		StrCat(sBody, sizeof(sBody), "\n");

		for (int i = 0; i < 45; i++)
		{
			StrCat(sBody, sizeof(sBody), " ");
		}
	}

	// 通道 2 和通道 1 走同一条 HudMsg, 区别只在排版(以及 2 多一段记分块)。
	if (Bms_StatusUseHudMsg() || Bms_StatusUseCompact())
	{
		Bms_SendStatusHudMsg(iClient, sBody);
		return;
	}

	// 中文尾巴按 textmsg_fix 的规矩补一个空格, 否则 CP936 下客户端
	// _vsnprintf 会 fail-fast(BMAG 与 tau_mp 都是这么发的)。
	char sHint[1024];
	strcopy(sHint, sizeof(sHint), sBody);
	StrCat(sHint, sizeof(sHint), " ");

	// 内容一个字节都没变就别发了 —— 客户端会把子面板整批拆了重建,
	// 屏幕上的框跟着闪。但 hudanimations.txt 里 HintMessageShow 12 秒后
	// 自己 Hide, 所以文本静止(暂停、时间不走)时也要 10 秒补一发, 否则框没了。
	if (StrEqual(gBmsStatusLastBody[iClient], sHint)
		&& GetGameTime() - gBmsStatusLastHint[iClient] < 10.0)
	{
		return;
	}

	strcopy(gBmsStatusLastBody[iClient], 1024, sHint);
	gBmsStatusLastHint[iClient] = GetGameTime();
	Bms_SendHintPanel(iClient, sHint);
}

// HudMsg 的几何(屏幕比例)和行距。HudMsg 是**从 x 往右画**, 所以要让整块
// 文字贴住屏幕右侧, 每行得按自己的字数倒推 x(见 Bms_StatusLineWidth)。
// y 从 0.50 起往下排 6 行, 落在原来那块面板的位置(右侧中部)。
//
// 右边界不能取满: HudMsg 画在 HudMessage 面板里(hudlayout.res 里
// wide 700 / tall 480 / 无 xpos, 即贴 (0,0)), 超过面板右边直接被裁 ——
// 之前用 0.978 时整页右边全被切掉就是这个原因。
// 面板右边 = 700/(480*画面比例): 16:10 ≈ 0.911, 16:9 ≈ 0.820, 21:9 ≈ 0.625。
// 服务端问不到客户端的画面比例(SM 没有这种 native), 所以只能取一个值;
// 默认按 16:10 贴边, 16:9 的客户端请 sm_cvar bms_status_right 0.81。
#define BMS_HUDMSG_LINES   6
#define BMS_HUDMSG_RIGHT   0.89
#define BMS_HUDMSG_Y       0.50
#define BMS_HUDMSG_STEP    0.028
// 实测字宽(屏幕宽的比例): 半角 ≈ 0.0079, 全角 ≈ 2 倍。1920x1200 下按这组
// 值倒推, 六行右端对齐在 ±2px 内(0.0107 那版偏宽, 整块比目标左移了 50 多 px)。
#define BMS_HUDMSG_CHARW   0.0079

float Bms_StatusRightEdge()
{
	float fRight = (gBmsStatusRight != null) ? gBmsStatusRight.FloatValue : BMS_HUDMSG_RIGHT;

	if (fRight < 0.30)
	{
		fRight = 0.30;
	}
	else if (fRight > 1.0)
	{
		fRight = 1.0;
	}

	return fRight;
}

int Bms_StatusChannel()
{
	if (gBmsStatusChannel == null)
	{
		return 1;
	}

	int iChannel = gBmsStatusChannel.IntValue;

	return (iChannel < 0 || iChannel > 2) ? 1 : iChannel;
}

bool Bms_StatusUsesHint()
{
	return Bms_StatusChannel() == 0;
}

bool Bms_StatusUseHudMsg()
{
	return Bms_StatusChannel() == 1;
}

bool Bms_StatusUseCompact()
{
	return Bms_StatusChannel() == 2;
}

// 让位窗口取「全局窗口」和「这个人的窗口」里更晚的那个:
//   全局 —— 投票是发给所有人的, 弹菜单的那一刻把 bms_status_yield 推到
//           GetGameTime()+时长, 投票期间全服的状态页都停;
//   个人 —— bms_match 自己弹的菜单(!help 之类)只停那个人的。
float Bms_StatusYieldUntil(int iClient)
{
	float fUntil = gBmsStatusYieldClient[iClient];

	if (gBmsStatusYield != null)
	{
		float fGlobal = gBmsStatusYield.FloatValue;

		if (fGlobal > fUntil)
		{
			fUntil = fGlobal;
		}
	}

	return fUntil;
}

// 一行一个槽位。CHudMessage 的 HudMsg 线上格式, 由 server.dll 自己的发送
// 函数(0x102b5780) 与 client.dll 的解析(0x101741a0) 双向对上:
//   byte channel, float x, float y, byte×8(两组 RGBA), byte effect,
//   float fadeIn, float fadeOut, float hold, float fxTime, string text
// x/y 是屏幕比例, text 是纯文本(不是 #token —— 引擎自己也是直接传
// "A.I. Disabled...\n" 这种字面量)。channel 在客户端取模 6, 正好有六个
// 内建槽位(__NETMESSAGE__1..6), 拿来一行一个槽位。
void Bms_SendHudMsg(int iClient, int iChannel, float fX, float fY, const char[] sText)
{
	Handle hMsg = StartMessageOne("HudMsg", iClient);

	if (hMsg == null)
	{
		return;
	}

	BfWriteByte(hMsg, iChannel % BMS_HUDMSG_LINES);
	BfWriteFloat(hMsg, fX);
	BfWriteFloat(hMsg, fY);

	// 两组颜色各 RGBA。原版 HL2 只有一组, BM 扩成两组; 客户端把 8 个字节
	// 分别存进槽位对象的 +4..+0xb, 但画的时候用不用第二组还没实测。默认
	// 两组同色(引擎自己的调用点 0x1006f1da 也是两组写同一个值), 取 hint
	// 面板的 TextColor "255 170 0 220"; bms_status_shadow 1 时第二组换成
	// 不透明黑, 当作描边试一下。
	bool bShadow = (gBmsStatusShadow != null && gBmsStatusShadow.BoolValue);

	for (int i = 0; i < 2; i++)
	{
		if (i == 1 && bShadow)
		{
			BfWriteByte(hMsg, 0);
			BfWriteByte(hMsg, 0);
			BfWriteByte(hMsg, 0);
			BfWriteByte(hMsg, 255);
			continue;
		}

		BfWriteByte(hMsg, 255);
		BfWriteByte(hMsg, 170);
		BfWriteByte(hMsg, 0);
		BfWriteByte(hMsg, 220);
	}

	BfWriteByte(hMsg, 0);        // effect: 0 = 无
	BfWriteFloat(hMsg, 0.0);     // fadeIn
	BfWriteFloat(hMsg, 0.2);     // fadeOut
	BfWriteFloat(hMsg, 1.6);     // hold(每秒重发一次, 覆盖住就不会闪)
	BfWriteFloat(hMsg, 0.0);     // fxTime
	BfWriteString(hMsg, sText);
	EndMessage();
}

// 估算一行的屏幕宽度(屏幕宽的比例)。半角 1 份, 全角 2 份(UTF-8 里中文
// 只有前导字节 >= 0xC0, 后续字节是 0x80..0xBF, 按这个区分)。
float Bms_StatusLineWidth(const char[] sText)
{
	float fUnits = 0.0;

	for (int i = 0; sText[i] != '\0'; i++)
	{
		int iByte = sText[i] & 0xFF;

		if (iByte < 0x80)
		{
			fUnits += 1.0;
		}
		else if (iByte >= 0xC0)
		{
			fUnits += 2.0;
		}
	}

	return fUnits * BMS_HUDMSG_CHARW;
}

// 右对齐后的 x; 行太长就退回左边界, 宁可不齐也不要跑到屏幕外。
float Bms_StatusLineX(const char[] sText)
{
	float fX = Bms_StatusRightEdge() - Bms_StatusLineWidth(sText);
	return (fX < 0.10) ? 0.10 : fX;
}

void Bms_SendStatusHudMsg(int iClient, const char[] sBody)
{
	char sLines[BMS_HUDMSG_LINES][128];
	int iLines = 0;
	int iPos = 0;
	int iLen = strlen(sBody);

	while (iPos <= iLen && iLines < BMS_HUDMSG_LINES)
	{
		if (iLines == BMS_HUDMSG_LINES - 1)
		{
			// 最后一行把剩下的全吃进来(hint 面板通道有 7 行, 观战名单会溢到这里)
			strcopy(sLines[iLines], 128, sBody[iPos]);
			ReplaceString(sLines[iLines], 128, "\n", " | ");
			iLines++;
			break;
		}

		int i = 0;

		while (iPos + i < iLen && sBody[iPos + i] != '\n' && i < 127)
		{
			sLines[iLines][i] = sBody[iPos + i];
			i++;
		}

		sLines[iLines][i] = '\0';
		iLines++;

		while (iPos + i < iLen && sBody[iPos + i] != '\n')
		{
			i++;
		}

		iPos += i + 1;
	}

	for (int i = 0; i < iLines; i++)
	{
		char sLine[136];
		// 末尾补空格: 和 hint 通道同样的 CP936 尾巴保险。
		Format(sLine, sizeof(sLine), "%s ", sLines[i]);
		Bms_SendHudMsg(iClient, i, Bms_StatusLineX(sLine), BMS_HUDMSG_Y + float(i) * BMS_HUDMSG_STEP, sLine);
	}

	// 上一帧占用的行数比这一帧多(比如观战者离开), 把多出来的槽位用空串
	// 覆盖掉, 否则它们要等 hold 到期才自己消失。
	for (int i = iLines; i < gBmsStatusHudLines[iClient]; i++)
	{
		Bms_SendHudMsg(iClient, i, Bms_StatusRightEdge(), BMS_HUDMSG_Y + float(i) * BMS_HUDMSG_STEP, "");
	}

	gBmsStatusHudLines[iClient] = iLines;
}


bool Bms_StatusUseKeyHint()
{
	return gBmsStatusKeyHint != null && gBmsStatusKeyHint.BoolValue;
}

// CHudHintDisplay::MsgFunc_HintText 把整条消息读进一个 256 字节的静态缓冲区
// (client.dll 0x10159ff0 那条路径, push 0x100), 超出的部分引擎会直接砍。
// 服务端先按整行砍好再发, 免得砍在多字节字符中间。
#define BMS_HINTTEXT_MAX 250

int Bms_HintTextFit(const char[] sText)
{
	int iLen = strlen(sText);

	if (iLen <= BMS_HINTTEXT_MAX)
	{
		return iLen;
	}

	// 优先退到上一个整行; 某一行自己就超长才退到 UTF-8 首字节。
	for (int i = BMS_HINTTEXT_MAX; i > 0; i--)
	{
		if (sText[i] == '\n')
		{
			return i;
		}
	}

	int iCut = BMS_HINTTEXT_MAX;

	while (iCut > 0 && (sText[iCut] & 0xC0) == 0x80)
	{
		iCut--;
	}

	return iCut;
}

// 两条 hint 通道在客户端是两个不同的面板类, 但 hudlayout.res 里几何完全一样
// (都是 xpos r120 / ypos r340 / wide 100 / tall 200 / PaintBackgroundType 2),
// 所以换通道不会挪位置。区别只有声音:
//
//   HintText   (CHudHintDisplay)     → EmitSound "Hud.Hint"
//   KeyHintText(CHudHintKeyDisplay)  → EmitSound "Player.HudHint"
//
// "Hud.Hint" 这个名字在 BM 的所有 soundscript 里都不存在(只有 client.dll 里
// 一个字符串字面量), 所以 HintText 天然无声; 而且它还额外被
// sv_hudhint_sound(服务端, FCVAR_REPLICATED)+ cl_hudhint_sound 双门挡着。
// "Player.HudHint" 则是 scripts/game_sounds_player.txt 里的真声音
// (wave "/hev_vox/blip.wav", volume 0.18, pitch 115), 而那条路径**只看**
// 客户端自己的 cl_hudhint_sound(FCVAR_ARCHIVE|FCVAR_CLIENTDLL, 服务端没注册
// 同名 cvar, SendConVarValue 也用不上)。
//
// 所以默认走 KeyHintText(多行, 但会闪), 声音交给 Bms_MuteHintSound() 从
// 客户端关掉。HintText 那条静音不闪、代价是只能单行(见 Bms_BuildStatusPage
// 的 bOneLine), 用户对比后不要它。
void Bms_SendHintPanel(int iClient, const char[] sText)
{
	if (Bms_StatusUseKeyHint())
	{
		Bms_SendKeyHintText(iClient, sText);
		return;
	}

	char sFit[BMS_HINTTEXT_MAX + 2];
	strcopy(sFit, sizeof(sFit), sText);
	sFit[Bms_HintTextFit(sText)] = '\0';
	// 截断可能把原来的尾巴空格砍掉了, 这里补回来(CP936 尾巴保险)。
	StrCat(sFit, sizeof(sFit), " ");
	mod_textmsg_fix_SafePrintHintText(iClient, "%s", sFit);
}

// 状态页自己是静音的, 但它和引擎自带的 hint 面板共用 sv_hudhint_sound 这个
// 服务端开关。bms_status_hintsound 0(默认)= 强制 sv_hudhint_sound 0,
// 1 = 交还给 cfg 里的值。只在内存里改, 不动任何 cfg 文件。
void Bms_ApplyHintSound()
{
	// HudMsg / VGUI panel 通道根本不碰 hint 面板, 别去改这个服务端 cvar 影响
	// 别处的 hint 文本。
	if (!Bms_StatusUsesHint())
	{
		return;
	}

	ConVar cv = FindConVar("sv_hudhint_sound");

	if (cv == null)
	{
		return;
	}

	int iWant = (gBmsStatusHintSound != null && gBmsStatusHintSound.BoolValue) ? 1 : 0;

	if (cv.IntValue != iWant)
	{
		cv.SetInt(iWant);
	}
}

// 那声「啵」本身来自客户端, 而 cl_hudhint_sound 是 FCVAR_ARCHIVE|FCVAR_CLIENTDLL
// 的纯客户端 cvar(server.dll 里连这个字符串都没有, FindConVar 拿不到, 也就用不了
// SendConVarValue)。但客户端控制台能改它, 而服务端可以让客户端执行一行命令:
// ClientCommand 走 IServerPluginHelpers, 在客户端按用户输入的命令行解析, cvar
// 赋值一样生效。ARCHIVE 标记意味着它会被客户端自己写进 config.cfg(下次进来
// 本来就是 0, 所以每个客户端只需发一次)。
void Bms_MuteHintSound(int iClient)
{
	if (!Bms_StatusUsesHint() || gBmsHintSoundMuted[iClient])
	{
		return;
	}

	gBmsHintSoundMuted[iClient] = true;

	if (gBmsStatusHintSound != null && gBmsStatusHintSound.BoolValue)
	{
		return;
	}

	ClientCommand(iClient, "cl_hudhint_sound 0");
}

// CHudHintKeyDisplay::MsgFunc_KeyHintText 的线上格式: 一个字节的字符串
// 个数, 然后逐个字符串; 客户端自己把它们用 '\n' 拼起来再按行排版。
void Bms_SendKeyHintText(int iClient, const char[] sText)
{
	Handle hMsg = StartMessageOne("KeyHintText", iClient);

	if (hMsg == null)
	{
		return;
	}

	BfWriteByte(hMsg, 1);
	BfWriteString(hMsg, sText);
	EndMessage();
}

public Action BmsT_StatusPage(Handle hTimer)
{
	bool bCampaign = Bms_IsCampaignMap();
	bool bOver = (gBmsRound.iState == BmsState_Over || gBmsRound.iState == BmsState_Changing);
	int iMode = (gBmsStatusPage != null) ? gBmsStatusPage.IntValue : 0;

	// 只有「所有人 + 非战役 + 非赛后」才由本模块独占 hint 面板; 其余情况下
	// showhealth 照常自己写 "Show Health: N"。
	bool bOwn = (iMode >= 2 && !bCampaign && !bOver);

	if (gBmsStatusActive != null)
	{
		gBmsStatusActive.SetInt(bOwn ? 1 : 0);
	}

	// 声音: 「啵」= KeyHintText 通道的 EmitSound("Player.HudHint")
	// (hev_vox/blip.wav), 那条路径只看客户端自己的 cl_hudhint_sound; 这个
	// cvar 在服务端没注册(server.dll 里零字符串), 但可以让客户端自己去执行
	// 一行控制台命令 —— 见 Bms_MuteHintSound()。
	if (bCampaign || bOver || iMode <= 0)
	{
		// 面板已经交还给别人, 清掉去重缓存: 下次接管时第一帧必须重画。
		for (int iClient = 1; iClient <= MaxClients; iClient++)
		{
			gBmsStatusLastBody[iClient][0] = '\0';
			gBmsStatusHudLines[iClient] = 0;
		}

		return Plugin_Continue;
	}

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		{
			gBmsStatusLastBody[iClient][0] = '\0';
			gBmsStatusHudLines[iClient] = 0;
			continue;
		}
		if (iMode < 2 && IsPlayerAlive(iClient))
		{
			gBmsStatusLastBody[iClient][0] = '\0';
			gBmsStatusHudLines[iClient] = 0;
			continue;
		}
		// 投票/菜单正占着屏幕: 这一秒不发, 免得状态页的文字压在投票选项上。
		// 让位窗口一过(见 bms_status_yield)下一帧自动恢复。
		if (GetGameTime() < Bms_StatusYieldUntil(iClient))
		{
			gBmsStatusLastBody[iClient][0] = '\0';
			gBmsStatusHudLines[iClient] = 0;
			continue;
		}
		Bms_MuteHintSound(iClient);
		Bms_SendStatusPage(iClient);
	}
	return Plugin_Continue;
}

// 诊断用: 把当前武器和玩家身上所有可能的弹药字段打到控制台(同时进日志)。
// 状态页的弹药行到底该读哪个字段, 只能拿真机的数字来定, 别再猜。
public Action BmsCmd_AmmoDump(int iClient, int iArgs)
{
	// 监听服务器上 ~ 控制台就是主机玩家的控制台, 命令会以 client 0 派发过来;
	// 直接往下走会在 Bms_StatusSubject 上崩 "Client index 0 is invalid"。
	// 这种情况下把主语换成第一个真人玩家(监听服务器上就是主机自己)。
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		iClient = 0;

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				iClient = i;
				break;
			}
		}

		if (iClient < 1)
		{
			PrintToServer("[ammodump] no player in game");
			return Plugin_Handled;
		}
	}

	int iSubject = Bms_StatusSubject(iClient);

	if (iSubject < 1 || !IsClientInGame(iSubject))
	{
		return Plugin_Handled;
	}

	int iWeapon = GetEntPropEnt(iSubject, Prop_Send, "m_hActiveWeapon");
	char sClass[64] = "none";
	int iClip1 = -1;
	int iClip2 = -1;
	int iType = -1;

	if (iWeapon > 0 && IsValidEntity(iWeapon))
	{
		GetEntityClassname(iWeapon, sClass, sizeof(sClass));
		iClip1 = GetEntProp(iWeapon, Prop_Send, "m_iClip1");
		iClip2 = GetEntProp(iWeapon, Prop_Send, "m_iClip2");

		int iTypeOffs = FindDataMapInfo(iWeapon, "m_iPrimaryAmmoType");

		if (iTypeOffs <= 0)
		{
			iTypeOffs = FindSendPropInfo("CBaseCombatWeapon", "m_iPrimaryAmmoType");
		}

		if (iTypeOffs > 0)
		{
			iType = GetEntData(iWeapon, iTypeOffs, 4);
		}
	}

	PrintToConsole(iClient, "[ammodump] subject=%N class=%s clip1=%d clip2=%d ptype=%d",
		iSubject, sClass, iClip1, iClip2, iType);
	LogMessage("[ammodump] %N class=%s clip1=%d clip2=%d ptype=%d",
		iSubject, sClass, iClip1, iClip2, iType);

	// 12 个具名弹药字段在 2026-11-17 的 server.dll 里是连号的 Prop_Data
	// (m_iAmmoGlock@0x4e4 ... m_iAmmoSatchel@0x510), 但 FindDataMapInfo 查不到,
	// 这里按裸偏移直接读一遍, 用来确认 tau/gluon/rpg 的真实备弹落在哪个槽。
	char sLine[384];
	sLine[0] = '\0';

	for (int i = 0; i < 12; i++)
	{
		Format(sLine, sizeof(sLine), "%s%x=%d ", sLine, 0x4e4 + i * 4, GetEntData(iSubject, 0x4e4 + i * 4, 4));
	}

	PrintToConsole(iClient, "[ammodump] raw(0x4e4..): %s", sLine);
	LogMessage("[ammodump] raw(0x4e4..): %s", sLine);

	char sFields[][] = {
		"m_iAmmoGlock", "m_iAmmoMp5", "m_iAmmo357", "m_iAmmoBolt", "m_iAmmoBuckshot",
		"m_iAmmoEnergy", "m_iAmmoMp5Grenade", "m_iAmmoRPG", "m_iAmmoFrag", "m_iAmmoSnark",
		"m_iAmmoTripmine", "m_iAmmoSatchel"
	};

	sLine[0] = '\0';

	for (int i = 0; i < sizeof(sFields); i++)
	{
		int iOffs = FindDataMapInfo(iSubject, sFields[i]);

		if (iOffs <= 0)
		{
			continue;
		}

		Format(sLine, sizeof(sLine), "%s%s=%d ", sLine, sFields[i][7], GetEntData(iSubject, iOffs, 4));
	}

	PrintToConsole(iClient, "[ammodump] named: %s", sLine[0] ? sLine : "(no datamap field found)");
	LogMessage("[ammodump] named: %s", sLine[0] ? sLine : "(no datamap field found)");

	char sNetClass[64];
	GetEntityNetClass(iSubject, sNetClass, sizeof(sNetClass));
	int iAmmoOffs = FindSendPropInfo(sNetClass, "m_iAmmo");
	sLine[0] = '\0';

	if (iAmmoOffs > 0)
	{
		for (int i = 0; i < 32; i++)
		{
			int iVal = GetEntData(iSubject, iAmmoOffs + i * 4, 4);

			if (iVal != 0)
			{
				Format(sLine, sizeof(sLine), "%s[%d]=%d ", sLine, i, iVal);
			}
		}
	}

	PrintToConsole(iClient, "[ammodump] m_iAmmo(offs=%d): %s", iAmmoOffs, sLine[0] ? sLine : "(all zero)");
	LogMessage("[ammodump] m_iAmmo(offs=%d): %s", iAmmoOffs, sLine[0] ? sLine : "(all zero)");

	sLine[0] = '\0';

	for (int slot = 0; slot <= 5; slot++)
	{
		int iSlotWeapon = GetPlayerWeaponSlot(iSubject, slot);

		if (iSlotWeapon <= 0 || !IsValidEntity(iSlotWeapon))
		{
			continue;
		}

		char sSlotClass[64];
		GetEntityClassname(iSlotWeapon, sSlotClass, sizeof(sSlotClass));
		Format(sLine, sizeof(sLine), "%sslot%d=%s(ent %d) ", sLine, slot, sSlotClass, iSlotWeapon);
	}

	PrintToConsole(iClient, "[ammodump] slots: %s", sLine[0] ? sLine : "(empty)");
	LogMessage("[ammodump] slots: %s", sLine[0] ? sLine : "(empty)");

	return Plugin_Handled;
}

public Action BmsCmd_VguiTest(int iClient, int iArgs)
{
	if (iArgs > 0)
	{
		char sArg[16];
		GetCmdArg(1, sArg, sizeof(sArg));
		if (StrEqual(sArg, "scores"))
		{
			Bms_VGUIPage_ShowScoresPanel();
			return Plugin_Handled;
		}
		if (StrEqual(sArg, "hide"))
		{
			Bms_VGUIPage_HideAll();
			return Plugin_Handled;
		}
	}
	char sTitle[64];
	Format(sTitle, sizeof(sTitle), "%T", "bms_page_title", iClient);
	char sPage[512];
	Format(sPage, sizeof(sPage), "%T\n\n1 2 3 4 5\nVGUI PAGE TEST", "bms_page_cancel_hint", iClient);
	Bms_VGUIPage_Send(iClient, sTitle, sPage);
	return Plugin_Handled;
}

// !help / !commands: a radio menu (CHudMenu) listing every player-facing
// command with a one-line description. Selecting a no-arg item runs the
// command (bare names dispatch through SM, same as the chat-alias hook);
// items that need arguments print their usage instead. The radio menu is the
// "different way" the owner asked for after finding the info panel cannot host
// multiple clickable buttons (CTextWindow has a single OK button bound to a
// fixed command enum).
public int Bms_HelpMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sCmd[32];
		menu.GetItem(param2, sCmd, sizeof(sCmd));
		if (StrEqual(sCmd, "panel"))
		{
			FakeClientCommandEx(param1, "panel");
		}
		else if (StrEqual(sCmd, "start"))
		{
			FakeClientCommandEx(param1, "start");
		}
		else if (StrEqual(sCmd, "cancel"))
		{
			FakeClientCommandEx(param1, "cancel");
		}
		else if (StrEqual(sCmd, "maplist"))
		{
			FakeClientCommandEx(param1, "maplist");
		}
		else if (StrEqual(sCmd, "runrandom"))
		{
			FakeClientCommandEx(param1, "runrandom");
		}
		else if (StrEqual(sCmd, "run"))
		{
			Bms_Reply(param1, "%t", "bms_run_usage");
		}
		else if (StrEqual(sCmd, "runnext"))
		{
			Bms_Reply(param1, "%t", "bms_runnext_usage");
		}
		else if (StrEqual(sCmd, "shuffle"))
		{
			FakeClientCommandEx(param1, "shuffle");
		}
		else if (StrEqual(sCmd, "invert"))
		{
			FakeClientCommandEx(param1, "invert");
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

void Bms_DisplayHelpMenu(int iClient)
{
	Menu menu = new Menu(Bms_HelpMenuHandler);
	char sTitle[128];
	Format(sTitle, sizeof(sTitle), "%T", "bms_help_title", iClient);
	menu.SetTitle(sTitle);
	// Menu.AddItem is (info, display, style) with no varargs, so each display
	// string is translated into a buffer before being added (same as the vote
	// menu below).
	char sDisplay[64];
	Format(sDisplay, sizeof(sDisplay), "%T", "bms_help_panel", iClient);
	menu.AddItem("panel", sDisplay);
	Format(sDisplay, sizeof(sDisplay), "%T", "bms_help_start", iClient);
	menu.AddItem("start", sDisplay);
	Format(sDisplay, sizeof(sDisplay), "%T", "bms_help_cancel", iClient);
	menu.AddItem("cancel", sDisplay);
	Format(sDisplay, sizeof(sDisplay), "%T", "bms_help_maplist", iClient);
	menu.AddItem("maplist", sDisplay);
	Format(sDisplay, sizeof(sDisplay), "%T", "bms_help_runrandom", iClient);
	menu.AddItem("runrandom", sDisplay);
	Format(sDisplay, sizeof(sDisplay), "%T", "bms_help_run", iClient);
	menu.AddItem("run", sDisplay);
	Format(sDisplay, sizeof(sDisplay), "%T", "bms_help_runnext", iClient);
	menu.AddItem("runnext", sDisplay);
	Format(sDisplay, sizeof(sDisplay), "%T", "bms_help_shuffle", iClient);
	menu.AddItem("shuffle", sDisplay);
	Format(sDisplay, sizeof(sDisplay), "%T", "bms_help_invert", iClient);
	menu.AddItem("invert", sDisplay);
	menu.ExitButton = false;
	// 菜单和状态页抢同一块 VGUI 面板: 菜单在的这 30 秒让状态页停发。
	gBmsStatusYieldClient[iClient] = GetGameTime() + 32.0;
	menu.Display(iClient, 30);
}

public Action BmsCmd_Help(int iClient, int iArgs)
{
	Bms_DisplayHelpMenu(iClient);
	return Plugin_Handled;
}

// Test matches (!starttest) run 1 minute; normal matches read the mode config.
int Bms_GetMatchTimelimit()
{
	if (gBmsTestMatch)
	{
		return 1;
	}
	return Bms_GetConfigInt("MatchTimelimit", "Gamemodes", gBmsRound.sMode, 0);
}

// Arm the two engine ConVars that gate the match round's duration so the
// plugin's DoneTime write (curtime + match_seconds) drives BOTH the HUD
// countdown and the natural round end. The Round-state Think caps DoneTime
// down to min(DoneTime, "remaining"+curtime) every frame; "remaining" reads
// either mp_timelimit (Round.Enter) or mp_round_intermission_time (Round
// vtable slot 0x18) depending on the server.dll build, so BOTH are raised
// above the match length to make that cap a no-op. server_match.cfg stomps
// mp_timelimit back to 15 one frame after Bms_OnMatchPre, so this is re-armed
// from BmsT_AdjustRoundTimer (+1.5s) after the restart settles.
//
// On this build the Round-state "remaining" reads mp_timelimit, and the
// engine's round is anchored at Bms_EngineReset's Round.Enter (~mp_warmup_time
// + reparse, ~BMS_DELAY_ACTION-1 s BEFORE go-live). Writing mp_timelimit =
// match_seconds exactly therefore caps DoneTime to round_enter + match_seconds,
// which is ~3s short of go-live + match_seconds — the HUD countdown starts at
// 57 instead of 60. The extra BMS_DELAY_ACTION*3 margin lets the plugin's
// absolute DoneTime (fStartTime + match_seconds) survive the cap. Bms_EndMatch
// resets mp_timelimit to iElapsed*60 for the post-match round, so this margin
// never leaks past the match.
void Bms_ArmMatchRoundConVars()
{
	int iSeconds = Bms_GetMatchTimelimit() * 60;
	if (iSeconds < 60)
	{
		iSeconds = 60;
	}
	if (gBmsCvar.mp_timelimit != null)
	{
		gBmsCvar.mp_timelimit.SetInt(iSeconds + BMS_DELAY_ACTION * 3);
	}
	// Raised well above the match length so the Round Think's cap-down never
	// clamps DoneTime below the plugin's target, even when a frame reads this
	// value as "remaining".
	if (gBmsCvar.mp_round_intermission_time != null)
	{
		gBmsCvar.mp_round_intermission_time.SetInt(iSeconds + 120);
	}
}

// Defense-in-depth: the engine fires broadcast_teamsound (soundid 27 = DRAW)
// when a round ends in a tie, and broadcast_playersound for FFA placement
// voices. Suppress both across the whole match
// lifecycle AND while an engine reset is armed. The forced reset that
// Bms_EngineReset runs (SetState(0) -> warmup -> Round.Enter) ends a 0-0 round
// as a draw, so the voice fires not only during the match but also from the
// Default/Over states the post-match/cancel restore runs from - Bms_IsGameMatch
// alone leaves those two gaps open. This event produces no console log, so it
// must be blocked at the event layer.
// Fire the match-end victory/draw announcer. The engine's natural round end
// (mp_timelimit lapse) is pre-empted by the plugin's own DoneTime push-out, so
// the engine never fires these voices itself — the only engine broadcast_teamsound
// 25/26/27 the plugin ever sees is the spurious 0-0 draw from Bms_EngineReset's
// forced round, which this event block exists to suppress. The plugin therefore
// fires the authoritative voice itself, mirroring the engine's score-resolution
// fn (server.dll @0x103609b0) exactly:
//   TDM: team 2 win -> (2,25)+(3,26); team 3 win -> (3,25)+(2,26); draw -> (2,27)+(3,27)
//   FFA: 1st -> (winner,30), 2nd -> (31), 3rd -> (32)   [Placement.First/Second/Third]
// soundid table (client.dll @0x1024ad80): 25=Game.Win 26=Game.Lose 27=Game.Draw
// 30=Placement.First 31=Placement.Second 32=Placement.Third.
void Bms_FireTeamSound(int iTeam, int iSoundId)
{
	Event hEvent = CreateEvent("broadcast_teamsound");
	if (hEvent == null)
	{
		return;
	}
	SetEventInt(hEvent, "teamid", iTeam);
	SetEventInt(hEvent, "soundid", iSoundId);
	gBmsVoiceAnnounce = true;
	FireEvent(hEvent);
	gBmsVoiceAnnounce = false;
}

void Bms_FirePlayerSound(int iClient, int iSoundId)
{
	Event hEvent = CreateEvent("broadcast_playersound");
	if (hEvent == null)
	{
		return;
	}
	// "playerid" is the player entity index (client index), not userid - the
	// client compares it against its local player index (client.dll @0x1024ab20).
	SetEventInt(hEvent, "playerid", iClient);
	SetEventInt(hEvent, "soundid", iSoundId);
	gBmsVoiceAnnounce = true;
	FireEvent(hEvent);
	gBmsVoiceAnnounce = false;
}

// Defense-in-depth: the engine fires broadcast_teamsound (soundid 27 = DRAW)
// when a round ends in a tie, and broadcast_playersound for FFA placement
// voices. Suppress both across the whole match
// lifecycle AND while an engine reset is armed. The forced reset that
// Bms_EngineReset runs (SetState(0) -> warmup -> Round.Enter) ends a 0-0 round
// as a draw, so the voice fires not only during the match but also from the
// Default/Over states the post-match/cancel restore runs from - Bms_IsGameMatch
// alone leaves those two gaps open. This event produces no console log, so it
// must be blocked at the event layer.
public Action Bms_Event_TeamSound(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	// Plugin-fired victory/draw voice (Bms_FireTeamSound/Bms_FirePlayerSound set
	// the flag around FireEvent; this Pre hook runs synchronously inside it).
	if (gBmsVoiceAnnounce)
	{
		return Plugin_Continue;
	}
	if (Bms_IsGameMatch() || Bms_IsGameOver() || gBmsEngineResetPending)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void Bms_OnMatchPre()
{
	char sCommand[256];
	// mapchooser's end-of-map vote is triggered SYNCHRONOUSLY by TimerSys'
	// mp_timelimit change listener (OnConVarChanged -> MapTimeLeftChanged ->
	// OnMapTimeLeftChanged -> SetupTimeleftTimer -> InitiateVote) the instant
	// mp_timelimit is rewritten below. A short match round therefore pops the
	// map-selection UI right after !starttest, BEFORE this function's later
	// statements run (11:16:07 and 20:52:21 logs both show the vote firing in
	// the same second as !starttest, ahead of the old sm_mapvote_endvote=0).
	// Disable the auto vote FIRST - before any mp_timelimit write - and cancel
	// any vote already in progress (the public round can already be inside
	// sm_mapvote_start when !starttest is typed, and its 20s timer would
	// otherwise conclude mid-match and force a map change). Restore the cvar
	// in Bms_RestorePublicCvars.
	if (gBmsCvar.mapvote_endvote != null)
	{
		gBmsCvar.mapvote_endvote.SetInt(0);
	}
	if (IsVoteInProgress())
	{
		CancelVote();
	}
	int iEnt = FindEntityByClassname(-1, "mp_round_time");
	if (iEnt != -1 && HasEntProp(iEnt, Prop_Data, "m_iRoundTime"))
	{
		gBmsRound.iTimerBackup = GetEntProp(iEnt, Prop_Data, "m_iRoundTime");
	}
	else
	{
		gBmsRound.iTimerBackup = -1;
	}
	// Capture the public gamerules state BEFORE the match rewrites it: the
	// engine's initial state is the only "public play" reference we have
	// (no reload happens on match start/end), and Bms_RestoreGamerules
	// writes it back after the match / on cancel.
	gBmsRound.bStateBackedUp = true;
	gBmsRound.iStateBackup = GameRules_GetProp("m_nCurrentStateId");
	gBmsRound.fDoneTimeBackup = GameRules_GetPropFloat("m_StateRound", 0);
	gBmsRound.fWarmupBackup = GameRules_GetPropFloat("m_StateWarmup", 0);
	// Capture the public mp_timelimit BEFORE PreMatchCommand
	// (server_match.cfg) stomps it next frame: post-match/cancel restarts
	// must not fall back to the match value - Bms_GameRestart's <=0 fallback
	// would then create a short round the engine ends with a map change.
	if (gBmsCvar.mp_timelimit != null && gBmsCvar.mp_timelimit.IntValue > 0)
	{
		gBmsRound.iPublicTimelimit = gBmsCvar.mp_timelimit.IntValue;
	}
	else
	{
		gBmsRound.iPublicTimelimit = 30;
	}
	// Back up the engine's intermission-time ConVar for restore after the
	// match (Bms_ArmMatchRoundConVars raises it above the match length, and
	// it is left untouched by server_match.cfg so the backup is authoritative).
	if (gBmsCvar.mp_round_intermission_time != null)
	{
		gBmsRound.iPublicRoundIntermission = gBmsCvar.mp_round_intermission_time.IntValue;
	}
	else
	{
		gBmsRound.iPublicRoundIntermission = 10;
	}
	if (Bms_GetConfigString(sCommand, sizeof(sCommand), "PreMatchCommand"))
	{
		ServerCommand(sCommand);
	}
	int iTime = Bms_GetMatchTimelimit();
	if (iTime > 0 && gBmsCvar.mp_timelimit != null)
	{
		// mp_timelimit is in SECONDS ("game time per map in seconds"), while
		// Bms_GetMatchTimelimit returns MINUTES. Writing the minute value
		// verbatim (e.g. 1 for a test match) leaves a 1-second mp_timelimit,
		// which the engine's reparse (Round.Enter) can then fold into a short
		// DoneTime - the same unit bug Bms_EndMatch already converts (iElapsed
		// * 60). Convert here too.
		gBmsCvar.mp_timelimit.SetInt(iTime * 60);
	}
	// Raise BOTH engine round-duration ConVars above the match length (see
	// Bms_ArmMatchRoundConVars). mp_round_intermission_time is untouched by
	// server_match.cfg, but mp_timelimit is stomped to 15 next frame, so the
	// +1.5s BmsT_AdjustRoundTimer re-arms it after the restart settles.
	Bms_ArmMatchRoundConVars();
	// BM engine does not apply runtime mp_timelimit changes to the live
	// countdown; adjust the mp_round_time entity once the restart settles.
	if (iTime > 0)
	{
		CreateTimer(1.5, BmsT_AdjustRoundTimer, iTime * 60, TIMER_FLAG_NO_MAPCHANGE);
	}
	int iEngineTimeleft;
	GetMapTimeLeft(iEngineTimeleft);
	LogMessage("[bms_match] MatchPre: mode=%s cfg_timelimit=%d cvar=%s engine_timeleft=%d timer_backup=%d state_backup=%d done_backup=%.0f",
		gBmsRound.sMode, iTime, gBmsCvar.mp_timelimit != null ? "ok" : "NULL", iEngineTimeleft, gBmsRound.iTimerBackup, gBmsRound.iStateBackup, gBmsRound.fDoneTimeBackup);
	if (gBmsCvar.mp_fraglimit != null)
	{
		gBmsCvar.mp_fraglimit.SetInt(0);
	}
	// SpecDetails pops a panel (K/D/health/weapon of the watched player) on
	// every death-cam target change; with 0s respawn the observer/alive
	// flicker re-triggers it constantly.  It is also live intel (opponent
	// health) - disable it for the whole match.
	if (gBmsCvar.specDetails != null)
	{
		gBmsCvar.specDetails.SetInt(0);
	}
	// (the end-of-map auto vote is already disabled at the very top of this
	// function, before any mp_timelimit write could trip mapchooser's listener)
	// sm_fastspawn is intentionally left alone: instant respawn (0s) is the
	// desired behaviour in matches as well as in public play (server.cfg).
	Bms_GenerateGameID();
}

void Bms_OnMatchCancelled()
{
	gBmsTestMatch = false;
	// Announce the (partial) demo like a finished match: the recording holds
	// everything up to the cancel, players should get the download link.
	Bms_TV_Stop(true);
	Bms_VGUIPage_HideAll();
	if (gBmsRound.iTimerBackup > 0)
	{
		Bms_AdjustRoundTimer(gBmsRound.iTimerBackup);
	}
	Bms_SayAll("%t", "bms_match_cancelled");
	ServerCommand("exec server");
	Bms_SetGamemode(gBmsRound.sMode);
	Bms_RestorePublicCvars();
}

void Bms_OnStatePre(BmsGameState iState)
{
	switch (iState)
	{
		case BmsState_Default:
		{
			if (Bms_IsGameMatch())
			{
				Bms_OnMatchCancelled();
			}
		}
		case BmsState_MatchWait:
		{
			Bms_OnMatchPre();
			// Record from the countdown on: a match cancelled during
			// MatchWait still yields its (short) demo, and finished-match
			// demos include the 4s countdown.
			Bms_TV_Start();
		}
		case BmsState_Match:
		{
			if (gBmsRound.iState != BmsState_Paused && gBmsRound.bOvertime)
			{
				Bms_CreateOverTimer();
			}
		}
		case BmsState_Over:
		{
			Bms_OnRoundEnd(true);
			Bms_RestorePublicCvars();
		}
	}
}

// Cvars that bms_match disables for the duration of a match (SpecDetails
// panel: spammy with 0s respawn + leaks opponent health while spectating).
void Bms_RestorePublicCvars()
{
	if (gBmsCvar.specDetails != null)
	{
		gBmsCvar.specDetails.SetInt(1);
	}
	// mapchooser's end-of-map auto vote is disabled server-wide (bms_match is
	// the single source of truth for map changes), so keep it off after a
	// match instead of restoring the cvar's compiled default of 1.
	if (gBmsCvar.mapvote_endvote != null)
	{
		gBmsCvar.mapvote_endvote.SetInt(0);
	}
	// NOTE: mp_round_intermission_time is deliberately NOT restored here.
	// Bms_ArmMatchRoundConVars raises it far above the match length so the
	// engine's Round-state Think ("remaining" = this ConVar via Round vtable
	// slot 0x18) cannot cap the plugin's DoneTime. Dropping it back to its
	// small public value the instant the match ends makes that Think cap
	// DoneTime to now+intermission_time, overriding Bms_EndMatch's
	// now+BMS_POSTMATCH_DELAY*2 push-out; the round lapses in
	// intermission_time seconds and the engine runs intermission -> CHANGE
	// LEVEL before BmsT_PostMatchRestart can restore the state (the "比赛结束
	// 还是换图了" bug). It stays raised through the post-match window and is
	// restored in Bms_Event_RoundStart once Bms_RestoreGamerules has re-armed
	// DoneTime far into the future.
}

void Bms_OnStatePost()
{
	if (gBmsRound.iState == BmsState_Changing && gBmsRound.bTeamplay)
	{
		Bms_InvertTeams(false);
	}
}

void Bms_SetState(BmsGameState iState)
{
	if (iState == gBmsRound.iState)
	{
		return;
	}
	Bms_OnStatePre(iState);
	gBmsRound.iState = iState;
	Bms_OnStatePost();
}

/**************************************************************
 * MATCH FLOW
 *************************************************************/
void Bms_Start(int iClient = 0)
{
	gBmsStartTimer = 0;
	gBmsPostFixTicks = 0;
	// Capture the match initiator for the SourceTV demo filename
	// (日期-地图-玩家名). A console/rcon start has no player -> "server".
	if (iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient))
	{
		GetClientName(iClient, gBmsRound.sInitiator, sizeof(gBmsRound.sInitiator));
	}
	else
	{
		strcopy(gBmsRound.sInitiator, sizeof(gBmsRound.sInitiator), "server");
	}
	// The match clock runs from this stamp, NOT from the round_start event:
	// the forced gamerules state transition may or may not fire that event,
	// and Bms_EndMatch / the end-check timer are armed relative to it.
	gBmsRound.fStartTime = GetGameTime();
	Bms_SetState(BmsState_MatchWait);
	// Reset the map's entity state before the countdown via the engine's own
	// warmup->round transition (Bms_EngineReset -> SetState(0) -> the engine's
	// per-frame SetState(2) -> Round.Enter -> CleanUpMap full reparse), which
	// restores broken func_breakables / spent trigger_onces that the plugin-side
	// CleanupMap cannot. The reset is ASYNCHRONOUS (~mp_warmup_time later); the
	// countdown and Bms_AdjustRoundTimer re-arm the round timer regardless, and
	// the engine's SetState(2) leaves the game in Round state (what
	// Bms_GameRestart used to force by direct field write). Players respawn with
	// a clean loadout at the end of the countdown (BmsT_Start ->
	// Bms_RefreshPlayers).
	Bms_EngineReset(false);
	CreateTimer(1.0, BmsT_Start, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// Restores the public gamerules state captured in Bms_OnMatchPre (engine
// initial state): post-match and cancel write it back so the engine returns
// to public-play behaviour without a level reload. A fresh map's gamerules
// are exactly this state, so restoring it is equivalent to a reload for the
// state machine: no forced Round, no HUD countdown from DoneTime, no natural
// map change (public play never changes maps in BM - the only CHANGE LEVELs
// in the whole console log are match-round related).
//
// NOTE on DoneTime (m_StateRound[0]): it MUST be a FUTURE instant. Two prior
// approaches both failed and are recorded so they are not repeated:
//   * writing the backed-up value verbatim (levelStart + mp_timelimit, a
//     stale absolute instant) made the HUD render a countdown from that
//     expired moment, and when it lapsed the engine fired the round-end
//     transition -> intermission -> CHANGE LEVEL;
//   * writing an ALREADY-EXPIRED value (GetGameTime()-1.0) so the Round
//     Think would "re-arm it next frame" ALSO fails: the round-end check is a
//     separate path that runs before/independent of the Think's per-frame
//     re-arm, so the transition fires on the very next frame and the map
//     still changes ~mp_chattime later (console.log: "gamerules restored"
//     then CHANGE LEVEL ~10s after). This is the "post-match map change" bug.
// The public steady state is Round + DoneTime = curtime + mp_timelimit,
// re-armed every frame by the Round Think so it never lapses (which is why
// public play never changes maps). Reconstruct that deadline here from the
// backed-up public mp_timelimit (seconds). The mp_round_time entity that
// renders the HUD countdown is removed below, so no countdown is drawn.
void Bms_RestoreGamerules()
{
	if (!gBmsRound.bStateBackedUp)
	{
		return;
	}
	GameRules_SetProp("m_nCurrentStateId", gBmsRound.iStateBackup);
	float fPublicRound = (gBmsRound.iPublicTimelimit > 0)
		? float(gBmsRound.iPublicTimelimit)
		: 1800.0;
	GameRules_SetPropFloat("m_StateRound", GetGameTime() + fPublicRound, 0);
	GameRules_SetPropFloat("m_StateWarmup", gBmsRound.fWarmupBackup, 0);
	int iEnt = FindEntityByClassname(-1, "mp_round_time");
	if (iEnt != -1)
	{
		// The timer entity the plugin created for the match HUD: remove it so
		// the HUD returns to its public-play look. RemoveEntity (direct
		// UTIL_Remove) is used instead of the Kill input - mp_round_time does
		// not reliably consume inputs, and the entity is ours to delete.
		RemoveEntity(iEnt);
	}
	LogMessage("[bms_match] gamerules restored: state=%d done=future(+%.0fs) warmup=%.0f",
		gBmsRound.iStateBackup, fPublicRound, gBmsRound.fWarmupBackup);
}

/**************************************************************
 * ENGINE RESET (plugin-side CleanUpMap)
 *************************************************************/
// BM 2026's in-place round reset (CHL2MPRules::CleanUpMap @ server.dll
// 0x1035dbd0) DOES exist, but it is NOT safely callable from a SourceMod
// command handler: the reparse tail (MapEntity_ParseAllEntities) tears down
// and re-spawns every map entity, which crashes the game when invoked
// mid-frame (observed: !starttest crashed right after SourceTV tv_record
// started, before the "engine CleanUpMap invoked" log). Until a safe engine
// entry point is found, this is the plugin-side approximation of
// CHL2MPRules::RestartRound's CleanUpMap, limited to what has a per-entity
// channel. What it CANNOT do: restore deleted map entities (broken
// func_breakables, spent trigger_onces) - those need the map reparse only the
// engine can do, and stay broken until a real map change (same as public play).
void Bms_CleanupMap()
{
	// Buttons: the press state lives in m_toggle_state. For func_button the
	// REST (usable) position is TS_AT_BOTTOM=1 (2018 hl2mp buttons.cpp:
	// ButtonBackHome lands on TS_AT_BOTTOM as "unpressed", and the +use path
	// Press(BUTTON_ACTIVATE) is blocked while the state is TS_AT_TOP). Writing
	// 1 releases a stuck-pressed button WITHOUT re-firing its outputs, so it
	// is safe on any wiring. (Writing 0 = TS_AT_TOP = pressed = the bug that
	// made every button unusable on 2026-08-25.)
	int iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "func_button")) != -1)
	{
		if (HasEntProp(iEnt, Prop_Data, "m_toggle_state"))
		{
			SetEntProp(iEnt, Prop_Data, "m_toggle_state", 1);
		}
	}
	// Doors: restore each door to its map-defined rest position. The Open and
	// Close inputs are guarded in engine code (InputOpen ignores doors
	// already at top, InputClose doors already at bottom). Restoring the
	// spawnflags rest state keeps start-open doors open instead of slamming
	// the whole map shut (SF_DOOR_START_OPEN_OBSOLETE=1, or the newer
	// "spawnposition" keyvalue FUNC_DOOR_SPAWN_OPEN=1).
	iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "func_door")) != -1)
	{
		bool bStartOpen = false;
		if (HasEntProp(iEnt, Prop_Data, "m_spawnflags"))
		{
			bStartOpen = (GetEntProp(iEnt, Prop_Data, "m_spawnflags") & 1) != 0;
		}
		if (HasEntProp(iEnt, Prop_Data, "m_eSpawnPosition")
			&& GetEntProp(iEnt, Prop_Data, "m_eSpawnPosition") == 1)
		{
			bStartOpen = true;
		}
		AcceptEntityInput(iEnt, bStartOpen ? "Open" : "Close");
	}
	// Momentary (sliding) doors have no start-open semantics - they only
	// move while triggered, so their rest position is always closed.
	iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "momentary_door")) != -1)
	{
		AcceptEntityInput(iEnt, "Close");
	}
	// Track trains (dm_crossfire's bomber): stop it and teleport it back to
	// the start of its path so a strike run cannot keep going after the
	// match. m_target holds the first path_track's name.
	iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "func_tracktrain")) != -1)
	{
		AcceptEntityInput(iEnt, "Stop");
		char sPath[128];
		if (HasEntProp(iEnt, Prop_Data, "m_target")
			&& GetEntPropString(iEnt, Prop_Data, "m_target", sPath, sizeof(sPath)) > 0)
		{
			SetVariantString(sPath);
			AcceptEntityInput(iEnt, "TeleportToPathTrack");
		}
	}
	// Delayed map events (dm_crossfire's red-button strike sequence, etc.)
	// live in the engine's global event queue (g_EventQueue), which is only
	// cleared on a level load. logic_relay's CancelPending input is the
	// per-entity channel for that queue: it cancels every event THIS relay
	// fired (server.dll CLogicRelay::InputCancelPending ->
	// g_EventQueue.CancelEvents(this)). The strike chain in dm_crossfire is
	// blast_relay (logic_relay) firing a whole batch of delayed outputs, so
	// one CancelPending per relay wipes the pending chain - the engine's own
	// "fresh map" behaviour, applied in place. logic_relay is the only class
	// with this input in server.dll (verified: CancelEvents has exactly three
	// callers - the ent_cancelpendingentfires command, one UpdateOnRemove
	// path, and this input).
	iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "logic_relay")) != -1)
	{
		AcceptEntityInput(iEnt, "CancelPending");
	}
	// Dynamic debris/props: broken-glass shards, ragdolls, thrown grenades.
	// Only kill UNNAMED ones - a named prop_physics is a map mechanic
	// (movable puzzle piece etc.) and deleting it without a reparse would
	// remove it for the rest of the level. RemoveEntity is used instead of
	// the Kill input (direct UTIL_Remove, no input table involved).
	for (int i = MaxClients + 1; i < GetMaxEntities(); i++)
	{
		if (!IsValidEntity(i))
		{
			continue;
		}
		char sClass[64];
		GetEntityClassname(i, sClass, sizeof(sClass));
		if (StrContains(sClass, "prop_physics") != 0
			&& StrContains(sClass, "prop_ragdoll") != 0
			&& StrContains(sClass, "grenade") != 0)
		{
			continue;
		}
		char sName[64];
		if (GetEntPropString(i, Prop_Data, "m_iName", sName, sizeof(sName)) > 0)
		{
			continue;
		}
		RemoveEntity(i);
	}
	LogMessage("[bms_match] map entities reset (buttons/doors/props/trains/relays)");
}

// Engine-native full map reset. Triggers the gamerules warmup -> round
// transition so the engine's own Round.Enter runs CleanUpMap (a FULL map
// reparse: restores broken func_breakables, spent trigger_onces, buttons,
// doors, props, and clears the event queue) plus strip/reset/respawn. This is
// the mechanism the user asked for (the "real warmup/round/intermission state
// machine resets entities"), and it reaches what Bms_CleanupMap cannot.
//
// SAFETY: the reparse is ONLY legal from the engine's per-frame
// State_Transition (slot 188), never from a SourcePawn command callback.
// Calling SetState(2) directly would crash — Round.Enter's first action is the
// reparse, and doing that mid-frame tears down + re-spawns every map entity
// (the two prior !starttest crashes). So we enter PREGAME (SetState(0)) with a
// short mp_warmup_time; ~that many seconds later the engine's own frame loop
// fires SetState(2) and performs the reset at its safe point. SetState(0)
// itself only fires "warmup_start" and arms the warmup timer (PREGAME.Start)
// plus score bookkeeping (Round.Exit) — no reparse, safe.
//
// The reset is ASYNCHRONOUS: SetState(0) returns immediately and the reparse
// lands ~mp_warmup_time later. Callers must not assume map entities are reset
// the moment this returns (the countdown timers already tolerate this).
//
// bRestorePublic selects the post-reset finish. false (Bms_Start): the engine's
// SetState(2) reset is enough — the countdown (BmsT_Start) re-arms the round
// timer and refreshes players itself. true (Bms_Cancel / post-match): the next
// round_start (fired by Round.Enter after the reparse) restores the public
// gamerules state + respawns everyone, so the map returns to public play with
// all entities restored.
void Bms_EngineReset(bool bRestorePublic)
{
	if (gBmsCall_SetState == INVALID_HANDLE)
	{
		// SDKCall unavailable (no gamerules): fall back to the plugin-side
		// per-entity approximation, which cannot restore breakables/triggers.
		Bms_CleanupMap();
		if (bRestorePublic)
		{
			Bms_RestoreGamerules();
			Bms_RefreshPlayers();
		}
		return;
	}
	if (gBmsCvar.mp_warmup_time != null)
	{
		if (gBmsWarmupTimeBackup < 0.0)
		{
			gBmsWarmupTimeBackup = gBmsCvar.mp_warmup_time.FloatValue;
		}
		gBmsCvar.mp_warmup_time.SetFloat(1.0);
	}
	gBmsEngineResetPending = bRestorePublic;
	SDKCall(gBmsCall_SetState, 0);
	// Restore mp_warmup_time well after the engine's SetState(2) (~1s): the
	// next map load keeps its configured warmup length.
	CreateTimer(3.0, BmsT_RestoreWarmup, _, TIMER_FLAG_NO_MAPCHANGE);
	LogMessage("[bms_match] engine reset armed: SetState(0) -> warmup -> Round.Enter (CleanUpMap reparse), restore=%d", bRestorePublic);
}

// Restores mp_warmup_time to its value before Bms_EngineReset shortened it.
// Fired after the engine's SetState(2) reset has landed (a short delay), so
// the next map load keeps its normal warmup length.
public Action BmsT_RestoreWarmup(Handle hTimer)
{
	if (gBmsWarmupTimeBackup >= 0.0 && gBmsCvar.mp_warmup_time != null)
	{
		gBmsCvar.mp_warmup_time.SetFloat(gBmsWarmupTimeBackup);
		gBmsWarmupTimeBackup = -1.0;
	}
	return Plugin_Stop;
}

public Action BmsT_Start(Handle hTimer)
{
	if (gBmsStartTimer > BMS_DELAY_ACTION)
	{
		gBmsStartTimer = 0;
		return Plugin_Stop;
	}
	if (gBmsStartTimer == BMS_DELAY_ACTION - 1)
	{
		// Re-stamp the match clock at go-live. Bms_Start stamps fStartTime
		// BMS_DELAY_ACTION seconds earlier (before the engine reset + countdown),
		// so arming DoneTime = fStartTime + timelimit there left the HUD countdown
		// ~4-5s short at go-live. The end-check timer is re-armed on the
		// Bms_SetState(BmsState_Match) below via Bms_OnStatePre -> Bms_CreateOverTimer,
		// so it reads this corrected stamp too.
		gBmsRound.fStartTime = GetGameTime();
		Bms_ResetScores();
		Bms_AdjustRoundTimer(Bms_GetMatchTimelimit() * 60, true);
		Bms_SetState(BmsState_Match);
		Bms_VGUIPage_HideAll();
		// BM's engine has no restart channel (see Bms_GameRestart), so the
		// plugin performs the refresh itself: everyone respawns with a clean
		// loadout right when the match goes live. Runs after the state switch
		// so the MatchWait spawn hook (which freezes players) no longer
		// applies to the fresh spawns. The state corrections above are
		// idempotently re-applied until the round timer converges - see
		// BmsT_PostRestartFix.
		Bms_RefreshPlayers();
		CreateTimer(1.0, BmsT_PostRestartFix, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (gBmsStartTimer == BMS_DELAY_ACTION)
	{
		mod_textmsg_fix_SafePrintCenterTextAll("");
		gBmsStartTimer = 0;
		return Plugin_Stop;
	}
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		{
			continue;
		}
		mod_textmsg_fix_SafePrintCenterText(iClient, "%T", "bms_match_starting", iClient, BMS_DELAY_ACTION - gBmsStartTimer);
	}
	gBmsStartTimer++;
	return Plugin_Continue;
}

// Repeating post-refresh correction. The gamerules state was forced to
// STATE_ROUND at !start (see Bms_GameRestart) and the round timer corrected;
// the engine's SetState(0)->warmup->Round.Enter reset is ASYNCHRONOUS and
// completes after go-live, re-arming DoneTime to curtime+mp_timelimit and
// clobbering the deadline armed in BmsT_Start (the HUD then starts at ~57s
// instead of 60s). Re-assert the absolute fStartTime+60 deadline every tick
// until the reset has settled, then do one final score wipe and stop so kills
// made after the settle window are never wiped.
public Action BmsT_PostRestartFix(Handle hTimer)
{
	if (!Bms_IsGameMatch())
	{
		return Plugin_Stop;
	}
	gBmsPostFixTicks++;
	int iTarget = Bms_GetMatchTimelimit() * 60;
	Bms_AdjustRoundTimer(iTarget, true);
	if (gBmsPostFixTicks >= BMS_POSTFIX_SETTLE_TICKS)
	{
		Bms_ResetScores();
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

void Bms_Cancel()
{
	gBmsStartTimer = BMS_DELAY_ACTION + 1;
	Bms_SetState(BmsState_Default);
	Bms_VGUIPage_HideAll();
	// Engine reset (restore public play): SetState(0) -> warmup -> Round.Enter
	// reparse restores broken breakables/spent triggers, then the round_start
	// finish (Bms_Event_RoundStart) writes the public DoneTime + respawns.
	Bms_EngineReset(true);
}

void Bms_EndMatch()
{
	int iElapsed = RoundToCeil((GetGameTime() - gBmsRound.fStartTime) / 60.0);
	if (iElapsed < 1)
	{
		iElapsed = 1;
	}
	if (gBmsCvar.mp_timelimit != null)
	{
		// mp_timelimit is in SECONDS ("game time per map in seconds"); the
		// elapsed minutes must be converted. Writing iElapsed verbatim made a
		// 1-minute test match set the deadline to 1 second, so the Round Think
		// re-armed DoneTime to curtime+1 every frame and overwrote the 60s
		// push-out below with a 1s one.
		gBmsCvar.mp_timelimit.SetInt(iElapsed * 60);
	}
	// BM engine will not re-read mp_timelimit; end the round via the gamerules
	// DoneTime field (m_StateRound[0]). Arm the countdown to 2x BMS_POSTMATCH_DELAY
	// (the BmsT_PostMatchRestart delay) so DoneTime stays comfortably ahead of the
	// restore: BmsT_PostMatchRestart fires SetState(0) at 10s and pre-empts the
	// natural round end, and the 20s DoneTime gives 10s of margin so the engine's
	// intermission->CHANGE LEVEL can never race the restore. Bms_AdjustRoundTimer
	// no longer applies the entity Add/RemoveRoundTime input, so this is a clean
	// write with no double-counted delta.
	Bms_AdjustRoundTimer(RoundToCeil(BMS_POSTMATCH_DELAY) * 2);
	Bms_SetState(BmsState_Over);
}

void Bms_StartOvertime()
{
	if (gBmsCvar.mp_timelimit != null)
	{
		gBmsCvar.mp_timelimit.IntValue += 1;
	}
	Bms_AddRoundTime(60);
	// The AddRoundTime input above is swallowed by the round-in-progress
	// state gate; push the gamerules DoneTime directly so the engine's
	// natural round end cannot fire mid-overtime (map change).
	GameRules_SetPropFloat("m_StateRound", GetGameTime() + 60.0, 0);
	if (gBmsCvar.mp_forcerespawn != null)
	{
		gBmsCvar.mp_forcerespawn.SetBool(true);
	}
	Bms_SayAll("%t", "bms_overtime_start");
	Bms_SetState(BmsState_MatchEx);
	CreateTimer(0.1, BmsT_Overtime, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action BmsT_Overtime(Handle hTimer)
{
	if (gBmsRound.iState != BmsState_MatchEx && gBmsRound.iState != BmsState_Overtime)
	{
		return Plugin_Stop;
	}
	// Hard overtime cap (5 min past the match limit): never let a perpetual
	// tie ride into the engine's natural round end - that would change the
	// map mid-overtime. Ends as a draw through the normal post-match flow.
	if (GetGameTime() - gBmsRound.fStartTime > (Bms_GetMatchTimelimit() + 5) * 60.0)
	{
		Bms_SayAll("%t", "bms_overtime_draw");
		Bms_EndMatch();
		return Plugin_Stop;
	}
	if (gBmsRound.bTeamplay)
	{
		int iResult = GetTeamScore(BMS_TEAM_COMBINE) - GetTeamScore(BMS_TEAM_REBELS);
		if (!iResult)
		{
			// Still tied: keep pushing the gamerules round-end deadline out
			// (AddRoundTime is swallowed by the state gate) so the engine
			// cannot end the round while overtime is live.
			GameRules_SetPropFloat("m_StateRound", GetGameTime() + 60.0, 0);
			return Plugin_Continue;
		}
		char sName[64];
		Bms_GetTeamName(iResult < 0 ? BMS_TEAM_REBELS : BMS_TEAM_COMBINE, sName, sizeof(sName));
		Bms_SayAll("%t", "bms_overtime_win_team", sName);
	}
	else
	{
		int iResult = Bms_GetTopPlayer();
		if (!iResult)
		{
			GameRules_SetPropFloat("m_StateRound", GetGameTime() + 60.0, 0);
			return Plugin_Continue;
		}
		char sName[MAX_NAME_LENGTH];
		GetClientName(iResult, sName, sizeof(sName));
		Bms_SayAll("%t", "bms_overtime_win_player", sName);
	}
	Bms_EndMatch();
	return Plugin_Stop;
}

public Action BmsT_CheckOvertime(Handle hTimer)
{
	gBmsRound.hOvertime = INVALID_HANDLE;
	if (gBmsRound.iState != BmsState_Match)
	{
		return Plugin_Stop;
	}
	// Test matches end as soon as the minute is up - never extend into overtime.
	if (gBmsTestMatch)
	{
		Bms_EndMatch();
		return Plugin_Stop;
	}
	if (Bms_PlayerCount(true, true, false) <= 1)
	{
		Bms_EndMatch();
		return Plugin_Stop;
	}
	if (gBmsRound.bTeamplay)
	{
		if (GetTeamScore(BMS_TEAM_COMBINE) == GetTeamScore(BMS_TEAM_REBELS)
			&& GetTeamClientCount(BMS_TEAM_COMBINE) && GetTeamClientCount(BMS_TEAM_REBELS))
		{
			Bms_StartOvertime();
		}
		else
		{
			Bms_EndMatch();
		}
	}
	else
	{
		if (!Bms_GetTopPlayer())
		{
			Bms_StartOvertime();
		}
		else
		{
			Bms_EndMatch();
		}
	}
	return Plugin_Stop;
}

void Bms_AnnounceScore()
{
	char sBody[768];
	sBody[0] = '\0';
	if (gBmsRound.bTeamplay)
	{
		int iS2 = GetTeamScore(BMS_TEAM_COMBINE);
		int iS3 = GetTeamScore(BMS_TEAM_REBELS);
		char sT2[64];
		char sT3[64];
		Bms_GetTeamName(BMS_TEAM_COMBINE, sT2, sizeof(sT2));
		Bms_GetTeamName(BMS_TEAM_REBELS, sT3, sizeof(sT3));
		Format(sBody, sizeof(sBody), "%t", "bms_match_score", sT2, iS2, iS3, sT3);
		if (iS2 > iS3)
		{
			Bms_SayAll("%t", "bms_match_score", sT2, iS2, iS3, sT3);
			Bms_SayAll("%t", "bms_match_win_team", sT2);
			Bms_FireTeamSound(BMS_TEAM_COMBINE, 25);
			Bms_FireTeamSound(BMS_TEAM_REBELS, 26);
			char sWin[128];
			Format(sWin, sizeof(sWin), "\n\n%t", "bms_match_win_team", sT2);
			StrCat(sBody, sizeof(sBody), sWin);
		}
		else if (iS3 > iS2)
		{
			Bms_SayAll("%t", "bms_match_score", sT2, iS2, iS3, sT3);
			Bms_SayAll("%t", "bms_match_win_team", sT3);
			Bms_FireTeamSound(BMS_TEAM_REBELS, 25);
			Bms_FireTeamSound(BMS_TEAM_COMBINE, 26);
			char sWin[128];
			Format(sWin, sizeof(sWin), "\n\n%t", "bms_match_win_team", sT3);
			StrCat(sBody, sizeof(sBody), sWin);
		}
		else
		{
			Bms_SayAll("%t", "bms_match_draw");
			Bms_FireTeamSound(BMS_TEAM_COMBINE, 27);
			Bms_FireTeamSound(BMS_TEAM_REBELS, 27);
			char sDraw[128];
			Format(sDraw, sizeof(sDraw), "\n\n%t", "bms_match_draw");
			StrCat(sBody, sizeof(sBody), sDraw);
		}
	}
	else
	{
		int iClients[MAXPLAYERS + 1];
		int iFrags[MAXPLAYERS + 1];
		int iCount;
		for (int iClient = 1; iClient <= MaxClients; iClient++)
		{
			if (!IsClientInGame(iClient) || IsClientObserver(iClient) || IsFakeClient(iClient))
			{
				continue;
			}
			iClients[iCount] = iClient;
			iFrags[iCount] = GetClientFrags(iClient);
			iCount++;
		}
		for (int i = 0; i < iCount - 1; i++)
		{
			for (int j = i + 1; j < iCount; j++)
			{
				if (iFrags[j] > iFrags[i])
				{
					int iTmpFrag = iFrags[i];
					int iTmpClient = iClients[i];
					iFrags[i] = iFrags[j];
					iClients[i] = iClients[j];
					iFrags[j] = iTmpFrag;
					iClients[j] = iTmpClient;
				}
			}
		}
		if (iCount)
		{
			char sName[MAX_NAME_LENGTH];
			GetClientName(iClients[0], sName, sizeof(sName));
			Bms_SayAll("%t", "bms_match_win_player", sName, iFrags[0]);
			Format(sBody, sizeof(sBody), "%t", "bms_match_win_player", sName, iFrags[0]);
			Bms_FirePlayerSound(iClients[0], 30);
		}
		else
		{
			Format(sBody, sizeof(sBody), "%t", "bms_match_draw");
		}
		for (int i = 1; i < 3 && i < iCount; i++)
		{
			char sName[MAX_NAME_LENGTH];
			GetClientName(iClients[i], sName, sizeof(sName));
			Bms_SayAll("%t", i == 1 ? "bms_match_top2" : "bms_match_top3", sName, iFrags[i]);
			Bms_FirePlayerSound(iClients[i], i == 1 ? 31 : 32);
			char sLine[256];
			Format(sLine, sizeof(sLine), "\n%t", i == 1 ? "bms_match_top2" : "bms_match_top3", sName, iFrags[i]);
			StrCat(sBody, sizeof(sBody), sLine);
		}
	}
	Bms_SendResultsPage(sBody);
}

void Bms_SendResultsPage(const char[] sBody)
{
	char sTitle[64];
	Format(sTitle, sizeof(sTitle), "%t", "bms_page_results_title");
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		{
			continue;
		}
		Bms_VGUIPage_Send(iClient, sTitle, sBody);
	}
}

void Bms_OnRoundEnd(bool bMatch)
{
	gBmsTestMatch = false;
	gBmsRound.fEndTime = GetGameTime();
	if (bMatch)
	{
		char sCommand[256];
		if (Bms_GetConfigString(sCommand, sizeof(sCommand), "PostMatchCommand"))
		{
			ServerCommand(sCommand);
		}
		Bms_VGUIPage_ShowScoresPanel();
		Bms_AnnounceScore();
		Bms_TV_Stop(true);
		// Stay on the current map after the match: show the score panel for
		// the celebration window, then restart the round in place as public
		// play (see BmsT_PostMatchRestart) instead of auto-voting/runrandom
		// into a map change.
		CreateTimer(BMS_POSTMATCH_DELAY, BmsT_PostMatchRestart, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

// Post-match: resume public play on the CURRENT map with NO level reload
// (a reload resets everything but costs every player a map load - the owner
// chose zero reloads). Bms_RestoreGamerules writes back the public state
// captured in Bms_OnMatchPre, which is byte-identical to a fresh map's
// gamerules: no forced Round, no HUD countdown (the old in-place restart
// wrote now+54000s into DoneTime, which the HUD rendered as a 899-minute
// countdown), no natural map change. The 60s round-end push-out set by
// Bms_EndMatch keeps the engine's intermission away while the score panel
// shows; the restore lands well inside that window. Note pressed buttons /
// broken props keep their state, exactly like public play (the engine has
// no CleanUpMap in BM 2026 - nothing ever resets them until a map change).
// Bms_SetState(Default) runs first so the flow starts from a public state
// (the Over state is not covered by Bms_IsGameMatch(), so the
// match-cancelled announce/TV/vgui path in Bms_OnStatePre(Default) does not
// re-fire).
public Action BmsT_PostMatchRestart(Handle hTimer)
{
	if (gBmsRound.iState != BmsState_Over)
	{
		return Plugin_Stop;
	}
	Bms_SetState(BmsState_Default);
	Bms_VGUIPage_HideAll();
	ServerCommand("exec server");
	Bms_SetGamemode(gBmsRound.sMode);
	// Engine reset (restore public play): SetState(0) -> warmup -> Round.Enter
	// reparse restores broken breakables/spent triggers, then the round_start
	// finish (Bms_Event_RoundStart) writes the public DoneTime + gives everyone
	// a clean respawn with a fresh loadout (mirroring the pre-engine-reset
	// Bms_CleanupMap + Bms_RestoreGamerules + Bms_RefreshPlayers sequence).
	Bms_EngineReset(true);
	Bms_SayAll("%t", "bms_postmatch_resume");
	return Plugin_Stop;
}

void Bms_StartRun()
{
	gBmsRunTimer = 0;
	CreateTimer(1.0, BmsT_Run, _, TIMER_REPEAT);
}

public Action BmsT_Run(Handle hTimer)
{
	if (gBmsRunTimer == 0)
	{
		// Re-read the authoritative next map from sm_nextmap (another plugin or
		// SM core may have changed it since Bms_ExecuteRun). Keep the FULL map
		// name - it is passed verbatim to `changelevel` below. Do NOT deprefix
		// it here: the prefix-less name would fail `changelevel` (e.g.
		// "crossfire" instead of "dm_crossfire") and the server would silently
		// stay on the current map.
		if (gBmsCvar.sm_nextmap != null)
		{
			char sMap[BMS_MAX_MAP_LENGTH];
			GetConVarString(gBmsCvar.sm_nextmap, sMap, sizeof(sMap));
			if (strlen(sMap))
			{
				strcopy(gBmsRound.sNextMap, sizeof(gBmsRound.sNextMap), sMap);
			}
		}
	}
	else if (gBmsRunTimer == BMS_DELAY_ACTION)
	{
		mod_textmsg_fix_SafePrintCenterTextAll("");
		ServerCommand("changelevel %s", gBmsRound.sNextMap);
		gBmsRunTimer = 0;
		return Plugin_Stop;
	}

	char sDisplay[BMS_MAX_MAP_LENGTH];
	Bms_DeprefixMap(gBmsRound.sNextMap, sDisplay, sizeof(sDisplay));
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		{
			continue;
		}
		mod_textmsg_fix_SafePrintCenterText(iClient, "%T", "bms_map_loading", iClient, sDisplay, BMS_DELAY_ACTION - gBmsRunTimer);
	}
	gBmsRunTimer++;
	return Plugin_Continue;
}

void Bms_ExecuteRun(BmsVoteType iType, int iLead)
{
	char sMotion[192];
	strcopy(sMotion, sizeof(sMotion), gsBmsMotion[iLead]);
	char sMode[BMS_MAX_MODE];
	char sMap[BMS_MAX_MAP_LENGTH];
	int iSplit = SplitString(sMotion, ":", sMode, sizeof(sMode));
	if (iSplit > 0)
	{
		sMode[iSplit - 1] = '\0';
		strcopy(sMap, sizeof(sMap), sMotion[iSplit]);
	}
	else
	{
		strcopy(sMode, sizeof(sMode), gBmsRound.sMode);
		strcopy(sMap, sizeof(sMap), sMotion);
	}
	if (!strlen(sMap) || !IsMapValid(sMap))
	{
		LogError("[bms_match] Map \"%s\" not found", sMap);
		return;
	}
	strcopy(gBmsRound.sNextMode, sizeof(gBmsRound.sNextMode), sMode);
	strcopy(gBmsRound.sNextMap, sizeof(gBmsRound.sNextMap), sMap);
	if (gBmsCvar.sm_nextmap != null)
	{
		gBmsCvar.sm_nextmap.SetString(sMap);
	}
	char sDisplay[BMS_MAX_MAP_LENGTH];
	Bms_DeprefixMap(sMap, sDisplay, sizeof(sDisplay));
	if (iType == BmsVote_RunNext)
	{
		Bms_SayAll("%t", "bms_run_next", sMode, sDisplay);
	}
	else
	{
		Bms_SayAll("%t", "bms_run_now", sMode, sDisplay);
		Bms_SetState(BmsState_Changing);
		Bms_SetGamemode(sMode);
		Bms_StartRun();
	}
}

/**************************************************************
 * TEAM MANAGEMENT
 *************************************************************/
void Bms_ForceTeamSwitch(int iClient, int iTeam)
{
	gBmsSpecial.iAllowed = iClient;
	FakeClientCommandEx(iClient, "jointeam %i", iTeam);
}

void Bms_ShuffleTeams(bool bBroadcast = true)
{
	int iCount = Bms_PlayerCount(true, true, false);
	int iClient;
	int iTeam[MAXPLAYERS + 1];
	int iTeams[2];
	do
	{
		do
		{
			iClient = Bms_GetRandomInt(1, MaxClients);
			if (!IsClientInGame(iClient) || IsClientObserver(iClient))
			{
				iTeam[iClient] = -1;
			}
			else
			{
				iTeam[iClient] = (
					iTeams[0] > iTeams[1] ? BMS_TEAM_COMBINE
					: iTeams[1] > iTeams[0] ? BMS_TEAM_REBELS
					: Bms_GetRandomInt(BMS_TEAM_COMBINE, BMS_TEAM_REBELS)
				);
				iTeams[0] += view_as<int>(iTeam[iClient] == BMS_TEAM_REBELS);
				iTeams[1] += view_as<int>(iTeam[iClient] == BMS_TEAM_COMBINE);
				iCount--;
				if (Bms_IsGameOver() && !IsFakeClient(iClient))
				{
					char sAuth[32];
					GetClientAuthId(iClient, AuthId_Steam2, sAuth, sizeof(sAuth));
					gBmsRound.mTeams.SetValue(sAuth, iTeam[iClient]);
				}
				else
				{
					if (iTeam[iClient] != GetClientTeam(iClient))
					{
						Bms_ForceTeamSwitch(iClient, iTeam[iClient]);
					}
					if (bBroadcast)
					{
						char sName[64];
						Bms_GetTeamName(iTeam[iClient], sName, sizeof(sName));
						mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_team_assigned", sName);
					}
				}
			}
		}
		while (iTeam[iClient] == 0);
	}
	while (iCount);
}

void Bms_InvertTeams(bool bBroadcast = true)
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsClientObserver(iClient))
		{
			continue;
		}
		int iTeam = GetClientTeam(iClient) == BMS_TEAM_REBELS ? BMS_TEAM_COMBINE : BMS_TEAM_REBELS;
		if (Bms_IsGameOver() && !IsFakeClient(iClient))
		{
			char sAuth[32];
			GetClientAuthId(iClient, AuthId_Steam2, sAuth, sizeof(sAuth));
			gBmsRound.mTeams.SetValue(sAuth, iTeam);
		}
		else
		{
			Bms_ForceTeamSwitch(iClient, iTeam);
			if (bBroadcast)
			{
				char sName[64];
				Bms_GetTeamName(iTeam, sName, sizeof(sName));
				mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_team_assigned", sName);
			}
		}
	}
}

int Bms_GetOptimalTeam()
{
	// Black Mesa DM FFA: every player lives on team 0 ("unassigned").
	int iTeam = 0;
	if (gBmsRound.bTeamplay)
	{
		int iCount[2];
		iCount[0] = GetTeamClientCount(BMS_TEAM_REBELS);
		iCount[1] = GetTeamClientCount(BMS_TEAM_COMBINE);
		iTeam = (
			iCount[0] > iCount[1] ? BMS_TEAM_COMBINE
			: iCount[1] > iCount[0] ? BMS_TEAM_REBELS
			: Bms_GetRandomInt(0, 1) ? BMS_TEAM_REBELS
			: BMS_TEAM_COMBINE
		);
	}
	return iTeam;
}

public Action BmsT_CheckPlayerStates(Handle hTimer)
{
	// 单人战役: 比赛状态机整张图静默(见 Bms_IsCampaignMap)。
	// 尤其要挡住下面的 BmsT_TeamAutoAssign —— 战役里把玩家"分队"毫无意义。
	if (Bms_IsCampaignMap())
	{
		return Plugin_Continue;
	}

	static int iWasTeam[MAXPLAYERS + 1] = {-1, ...};
	if (gBmsRound.iState == BmsState_Changing)
	{
		return Plugin_Continue;
	}
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		int iTeam;
		if (!IsClientInGame(iClient))
		{
			// Only a client that was previously in the match (iWasTeam set)
			// and has actually left the server counts as "disconnected".
			// Empty slots stay at -1 forever and must never trigger the
			// auto-pause; a client in the game's built-in pre-round wait
			// (not in game but still connected) must not either.
			if (iWasTeam[iClient] != -1 && !IsClientConnected(iClient)
				&& iWasTeam[iClient] != BMS_TEAM_SPECTATORS && Bms_IsGameMatch())
			{
				if (gBmsRound.iState != BmsState_Paused)
				{
					ServerCommand("pause");
					Bms_SayAll("%t", "bms_auto_pause");
					gBmsSpecial.iPauser = 0;
				}
			}
			iWasTeam[iClient] = -1;
			continue;
		}
		if (IsClientSourceTV(iClient))
		{
			continue;
		}
		iTeam = GetClientTeam(iClient);
		if (iWasTeam[iClient] == -1)
		{
			CreateTimer(1.0, BmsT_TeamAutoAssign, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}
		else if (iTeam != iWasTeam[iClient])
		{
			if (gBmsSpecial.iAllowed != iClient && Bms_IsGameMatch() && iWasTeam[iClient] != BMS_TEAM_SPECTATORS)
			{
				Bms_ForceTeamSwitch(iClient, iWasTeam[iClient]);
				continue;
			}
		}
		iWasTeam[iClient] = iTeam;
		if (gBmsClient[iClient].bReady && !Bms_IsGameOver())
		{
			char sAuth[32];
			GetClientAuthId(iClient, AuthId_Steam2, sAuth, sizeof(sAuth));
			gBmsRound.mTeams.SetValue(sAuth, iTeam);
		}
	}
	return Plugin_Continue;
}

public Action BmsT_TeamAutoAssign(Handle hTimer, int iClient)
{
	int iTeam;
	if (!IsClientInGame(iClient))
	{
		return Plugin_Stop;
	}
	else if (gBmsRound.iState == BmsState_Paused || Bms_IsGameOver())
	{
		return Plugin_Continue;
	}
	char sAuth[32];
	GetClientAuthId(iClient, AuthId_Steam2, sAuth, sizeof(sAuth));
	gBmsRound.mTeams.GetValue(sAuth, iTeam);
	if (Bms_IsGameMatch())
	{
		mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_teamchange_deny");
	}
	else if (iTeam)
	{
		if (iTeam == BMS_TEAM_SPECTATORS)
		{
			mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_auto_spectate");
		}
		else
		{
			Bms_ForceTeamSwitch(iClient, iTeam);
		}
	}
	else if (Bms_IsPlaying(iClient) && !gBmsRound.bTeamplay)
	{
		// BM DM FFA: already on the play team (team 0), nothing to switch.
	}
	else
	{
		Bms_ForceTeamSwitch(iClient, Bms_GetOptimalTeam());
	}
	gBmsClient[iClient].bReady = true;
	return Plugin_Stop;
}

/**************************************************************
 * VOTING
 *************************************************************/
int Bms_VoteTimeout(int iClient)
{
	if (Bms_PlayerCount(true, false, true) <= gBmsVoting.iMinPlayers)
	{
		return 0;
	}
	int iTime = gBmsVoting.iCooldown - RoundToNearest(GetGameTime() - gBmsClient[iClient].fVoteTick);
	return iTime > 0 ? iTime : 0;
}

void Bms_FormatOptionText(const char[] sMotion, char[] out, int len)
{
	char sMode[BMS_MAX_MODE];
	char sMap[BMS_MAX_MAP_LENGTH];
	int iSplit = SplitString(sMotion, ":", sMode, sizeof(sMode));
	if (iSplit > 0)
	{
		sMode[iSplit - 1] = '\0';
		strcopy(sMap, sizeof(sMap), sMotion[iSplit]);
		char sDisplay[BMS_MAX_MAP_LENGTH];
		Bms_DeprefixMap(sMap, sDisplay, sizeof(sDisplay));
		if (StrEqual(sMode, gBmsRound.sMode))
		{
			strcopy(out, len, sDisplay);
		}
		else
		{
			Format(out, len, "%s (%s)", sDisplay, sMode);
		}
	}
	else
	{
		char sDisplay[BMS_MAX_MAP_LENGTH];
		Bms_DeprefixMap(sMotion, sDisplay, sizeof(sDisplay));
		strcopy(out, len, sDisplay);
	}
}

public int Bms_VoteMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		gBmsClient[param1].iVote = param2;
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

void Bms_DisplayVoteMenu(int iClient)
{
	Menu menu = new Menu(Bms_VoteMenuHandler);
	char sTitle[128];
	Format(sTitle, sizeof(sTitle), "%T", "bms_vote_menu_title", iClient);
	menu.SetTitle(sTitle);
	if (strlen(gsBmsMotion[1]))
	{
		for (int i = 0; i < BMS_VOTE_OPTIONS; i++)
		{
			if (!strlen(gsBmsMotion[i]))
			{
				break;
			}
			// RadioMenu auto-prefixes "N. " to every item, so the display string
			// must not carry its own number (it would render "1. 1. <option>").
			char sOption[192];
			Bms_FormatOptionText(gsBmsMotion[i], sOption, sizeof(sOption));
			menu.AddItem("", sOption);
		}
	}
	else
	{
		menu.AddItem("", "YES");
		menu.AddItem("", "NO");
	}
	menu.ExitButton = false;
	// 同上: 投票菜单显示 30 秒, 这段时间状态页让位, 否则选票页面每秒被顶掉。
	gBmsStatusYieldClient[iClient] = GetGameTime() + 32.0;
	menu.Display(iClient, 30);
}

void Bms_CallVote(BmsVoteType iType, int iCaller)
{
	bool bMulti = strlen(gsBmsMotion[1]) > 0;
	gBmsClient[iCaller].fVoteTick = GetGameTime();
	gBmsVoting.iStatus = 1;
	gBmsVoting.iType = iType;
	gBmsVoting.iElapsed = 0;
	gBmsVoting.iLead = -1;
	gBmsVoting.iCaller = iCaller;
	if (!bMulti && iCaller > 0)
	{
		gBmsClient[iCaller].iVote = 1;
	}
	if (iCaller > 0)
	{
		char sName[MAX_NAME_LENGTH];
		GetClientName(iCaller, sName, sizeof(sName));
		Bms_SayAll("%t", "bms_vote_called_from", sName);
	}
	else
	{
		Bms_SayAll("%t", "bms_vote_called");
	}
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		{
			continue;
		}
		if ((iClient != iCaller || bMulti) && (!IsClientObserver(iClient) || iType != BmsVote_Match))
		{
			gBmsClient[iClient].iVote = -1;
			Bms_DisplayVoteMenu(iClient);
		}
	}
}

void Bms_ExecuteVote(bool bMulti)
{
	switch (gBmsVoting.iType)
	{
		case BmsVote_Shuffle:
		{
			Bms_ShuffleTeams();
		}
		case BmsVote_Invert:
		{
			Bms_InvertTeams();
		}
		case BmsVote_Match:
		{
			if (!Bms_IsGameMatch())
			{
				Bms_Start(gBmsVoting.iCaller);
			}
			else
			{
				Bms_Cancel();
			}
		}
		default:
		{
			Bms_ExecuteRun(gBmsVoting.iType, bMulti ? gBmsVoting.iLead : 0);
		}
	}
}

public Action BmsT_Voting(Handle hTimer)
{
	// 单人战役: 投票整张图静默(见 Bms_IsCampaignMap)
	if (Bms_IsCampaignMap())
	{
		return Plugin_Continue;
	}

	static bool bMultiChoice;
	static char sMotion[BMS_VOTE_OPTIONS][192];
	char sHud[1024];
	bool bContested;
	bool bDraw;
	int iVotes;
	int iAbstains;
	int iLead = -1;
	int iHighest;
	int iTally[BMS_VOTE_OPTIONS];
	if (!gBmsVoting.iStatus)
	{
		if (gBmsVoting.iElapsed)
		{
			for (int i = 0; i < BMS_VOTE_OPTIONS; i++)
			{
				sMotion[i][0] = '\0';
				gsBmsMotion[i][0] = '\0';
			}
			gBmsVoting.iElapsed = 0;
		}
		return Plugin_Continue;
	}
	if (!gBmsVoting.iElapsed)
	{
		bMultiChoice = strlen(gsBmsMotion[1]) > 0;
		for (int i = 0; i < BMS_VOTE_OPTIONS; i++)
		{
			strcopy(sMotion[i], sizeof(sMotion[]), gsBmsMotion[i]);
		}
	}
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		{
			continue;
		}
		if ((!Bms_IsGameMatch() && gBmsVoting.iType != BmsVote_Match) || !IsClientObserver(iClient))
		{
			if (gBmsClient[iClient].iVote != -1)
			{
				iTally[gBmsClient[iClient].iVote]++;
				iVotes++;
			}
			else
			{
				iAbstains++;
			}
		}
	}
	for (int i = 0; i < BMS_VOTE_OPTIONS; i++)
	{
		if (!bMultiChoice && i > 1)
		{
			break;
		}
		if (iTally[i] > iHighest)
		{
			iHighest = iTally[i];
			iLead = i;
			bDraw = false;
		}
		else if (iTally[i] == iHighest)
		{
			iLead = -1;
			bDraw = true;
		}
	}
	for (int i = 0; i < BMS_VOTE_OPTIONS; i++)
	{
		if (i != iLead)
		{
			if (iLead < 0 || iAbstains + iTally[i] + (iAbstains ? 1 : 0) > iTally[iLead])
			{
				bContested = true;
			}
		}
	}
	if ((iLead > -1 && !bContested) || gBmsVoting.iElapsed >= gBmsVoting.iMaxTime)
	{
		if (bMultiChoice)
		{
			if (bDraw)
			{
				if (!iVotes && !Bms_IsGameOver())
				{
					iLead = -1;
				}
				else
				{
					{
						int iWinner[BMS_VOTE_OPTIONS];
						int iWinCount;
						for (int i = 0; i < BMS_VOTE_OPTIONS; i++)
						{
							if (iTally[i] == iHighest && iTally[i] > 0)
							{
								iWinner[iWinCount] = i;
								iWinCount++;
							}
						}
						if (iWinCount)
						{
							iLead = iWinner[Bms_GetRandomInt(0, iWinCount - 1)];
						}
						else
						{
							iLead = -1;
						}
					}
					if (iLead > -1)
					{
						char sOption[192];
						Bms_FormatOptionText(sMotion[iLead], sOption, sizeof(sOption));
						Bms_SayAll("%t", "bms_vote_draw", iLead + 1, sOption);
					}
				}
			}
			else if (iLead > -1)
			{
				char sOption[192];
				Bms_FormatOptionText(sMotion[iLead], sOption, sizeof(sOption));
				Bms_SayAll("%t", "bms_vote_victory", iLead + 1, sOption);
			}
		}
		else if (iLead == 0)
		{
			iLead = -1;
		}
		gBmsVoting.iStatus = iLead > -1 ? 2 : -1;
	}
	if (!bMultiChoice)
	{
		Format(sHud, sizeof(sHud), "%s (%i)\nYES: %i   NO: %i", sMotion[0], gBmsVoting.iMaxTime - gBmsVoting.iElapsed, iTally[1], iTally[0]);
	}
	else
	{
		Format(sHud, sizeof(sHud), "(%i)", gBmsVoting.iMaxTime - gBmsVoting.iElapsed);
		for (int i = 0; i < BMS_VOTE_OPTIONS; i++)
		{
			if (!strlen(sMotion[i]))
			{
				break;
			}
			char sOption[192];
			Bms_FormatOptionText(sMotion[i], sOption, sizeof(sOption));
			Format(sHud, sizeof(sHud), "%s\n%i. %s - %i", sHud, i + 1, sOption, iTally[i]);
		}
	}
	switch (gBmsVoting.iStatus)
	{
		case -1:
		{
			SetHudTextParams(0.01, 0.11, 1.01, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
		}
		case 2:
		{
			SetHudTextParams(0.01, 0.11, 1.01, 0, 255, 0, 255, 0, 0.0, 0.0, 0.0);
			Bms_ExecuteVote(bMultiChoice);
		}
		default:
		{
			SetHudTextParams(0.01, 0.11, 1.01, 255, 177, 0, 255, view_as<int>(gBmsVoting.iMaxTime - gBmsVoting.iElapsed <= 5), 0.0, 0.0, 0.0);
		}
	}
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		char sHud2[1024];
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		{
			continue;
		}
		if (gBmsVoting.iType == BmsVote_RunAuto)
		{
			Format(sHud2, sizeof(sHud2), "%T - %s", "bms_autovote", iClient, sHud);
		}
		else
		{
			Format(sHud2, sizeof(sHud2), "%T - %s", "bms_vote", iClient, sHud);
		}
		if (gBmsVoting.iStatus != 1)
		{
			if (!bMultiChoice)
			{
				mod_textmsg_fix_SafePrintToChat(iClient, "%t", gBmsVoting.iStatus == -1 ? "bms_vote_fail" : "bms_vote_success");
			}
		}
		ShowSyncHudText(iClient, gBmsVoteHud, "%s", sHud2);
	}
	if (gBmsVoting.iStatus != 1)
	{
		gBmsVoting.iStatus = 0;
		Bms_VGUIPage_HideAll();
	}
	gBmsVoting.iElapsed++;
	return Plugin_Continue;
}

/**************************************************************
 * EVENTS
 *************************************************************/
void Bms_StripWeapons(int iClient)
{
	for (int i = MaxClients + 1; i < GetMaxEntities(); i++)
	{
		if (!IsValidEntity(i))
		{
			continue;
		}
		char sClass[32];
		GetEntityClassname(i, sClass, sizeof(sClass));
		if (StrContains(sClass, "weapon_") != 0)
		{
			continue;
		}
		if (GetEntPropEnt(i, Prop_Send, "m_hOwnerEntity") == iClient)
		{
			RemoveEdict(i);
		}
	}
}

// hl2mp's respawn pipeline only ever ADDS to m_iAmmo (GiveAmmo) - it never
// zeroes the array, so grenades and ammo picked up before a match survive the
// manual refresh (leak: RemoveAllItems doesn't touch ammo; only the engine's
// own ForceRespawn path runs RemoveAllAmmo). m_iAmmo is a SendPropArray3 of
// 32 4-byte counts, which SM cannot write through SetEntProp (array props are
// rejected by the FIND_PROP_SEND macro), so poke the raw send-prop memory
// directly - the same trick used for m_iRoundTime.
void Bms_ResetAmmo(int iClient)
{
	char sNetClass[64];
	GetEntityNetClass(iClient, sNetClass, sizeof(sNetClass));
	int iOffs = FindSendPropInfo(sNetClass, "m_iAmmo");
	if (iOffs <= 0)
	{
		LogMessage("[bms_match] Bms_ResetAmmo: m_iAmmo not found on netclass %s", sNetClass);
		return;
	}
	for (int i = 0; i < 32; i++)
	{
		SetEntData(iClient, iOffs + i * 4, 0, 4, true);
	}
}

public Action Bms_Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	if (iClient <= 0 || iClient > MaxClients || IsFakeClient(iClient))
	{
		return Plugin_Continue;
	}
	if (gBmsRound.iState == BmsState_MatchWait)
	{
		SetEntityMoveType(iClient, MOVETYPE_NONE);
		CreateTimer(0.1, BmsT_RemoveWeapons, iClient, TIMER_FLAG_NO_MAPCHANGE);
	}
	// Every Spawn() block-init re-zeroes BM's "suit charged" byte
	// (player+0x94d) - so death respawns re-block the suit charger for anyone
	// holding the Long Jump Module, whose charge-complete path is the only
	// live setter in server.dll (see Bms_RefreshPlayers for the full
	// reverse-engineering notes). Re-apply the forced value on EVERY spawn,
	// match or not: the post-match refresh (DispatchSpawn) also re-zeroes it,
	// which made the LJM fail again right after a match ended (console.log
	// "LongJUMP FAILED" spam). The engine setter is idempotent (cmp/je) and
	// the only clear function has zero callers, so this is safe in public
	// play too - chargers just never wait on the module again.
	SetEntData(iClient, 0x94d, 1, 1, true);
	return Plugin_Continue;
}

public Action BmsT_RemoveWeapons(Handle hTimer, int iClient)
{
	if (IsClientInGame(iClient) && IsPlayerAlive(iClient))
	{
		Bms_StripWeapons(iClient);
	}
	return Plugin_Stop;
}

public Action Bms_Event_RoundStart(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	// Public play bookkeeping only: during a match the clock runs from
	// Bms_Start's stamp, and re-stamping here (the forced gamerules
	// transition may fire this event late or not at all) would skew the
	// end-check timer.
	if (!Bms_IsGameMatch())
	{
		gBmsRound.fStartTime = GetGameTime();
	}
	else
	{
		// The engine's round-state Think (round-state vtable slot 0 = 0x10361590,
		// fired by the warmup->round transition that Bms_EngineReset arms)
		// re-arms DoneTime (m_StateRound[0]) every frame to
		// "round remaining + gpGlobals->curtime". NOTE: [0x1086b1c8+0xc] is
		// gpGlobals->curtime (the engine clock), NOT a duration - the remaining
		// value comes from the round-state's own getter (vtable slot 0x18). This
		// clobbers the match deadline armed at the end of the countdown
		// (BmsT_Start). round_start fires AFTER that write
		// (Round.Enter order: CleanUpMap -> strip/reset/respawn -> DoneTime ->
		// round_start), so re-asserting the deadline here always wins. Without
		// this the round lapses a few seconds later and the engine runs
		// intermission -> CHANGE LEVEL - the "match ends in ~10s and the map
		// changes" bug. Re-arming is idempotent and the match end is still
		// driven by fStartTime (BmsT_CheckOvertime), not by this deadline.
		Bms_AdjustRoundTimer(Bms_GetMatchTimelimit() * 60, true);
	}
	// Post-engine-reset finish (Bms_EngineReset(true), i.e. cancel/post-match):
	// this event is fired by Round.Enter AFTER the reparse has completed, so it
	// is the safe point to restore the public gamerules state (future DoneTime)
	// and respawn everyone. Doing it here (not in the command/timer callback)
	// avoids racing the engine's warmup->round transition.
	if (gBmsEngineResetPending)
	{
		gBmsEngineResetPending = false;
		Bms_RestoreGamerules();
		// Only now is it safe to drop the raised intermission-time ConVar back
		// to its public value: Bms_RestoreGamerules just re-armed DoneTime far
		// into the future, so the Round-state Think can no longer lapse the
		// round (see the note in Bms_RestorePublicCvars).
		if (gBmsCvar.mp_round_intermission_time != null)
		{
			gBmsCvar.mp_round_intermission_time.SetInt(gBmsRound.iPublicRoundIntermission);
		}
		Bms_RefreshPlayers();
	}
	return Plugin_Continue;
}

public Action Bms_ListenCmd_Team(int iClient, const char[] sCommand, int iArgs)
{
	if (iClient <= 0)
	{
		// BM 2026 会以 client==0 派发 "chooseteam"(listen server 主机上下文,
		// 实测 "Team is full" 拒绝后引擎从服务器端重发),GetClientTeam(0)
		// 会抛 "Client index 0 is invalid"。服务器端调用直接放行给引擎。
		return Plugin_Continue;
	}
	int iTeam = BMS_TEAM_SPECTATORS;
	bool bRoute = false;
	if (StrEqual(sCommand, "jointeam", false))
	{
		if (!iArgs)
		{
			return Plugin_Continue;
		}
		iTeam = GetCmdArgInt(1);
	}
	else if (StrEqual(sCommand, "chooseteam", false))
	{
		// BM 2026 引擎没有队伍选择面板(VGUI PANEL_* 全部被删),"chooseteam"
		// (默认 M 键)到引擎后什么都不做。这里把它当观战/上场切换:
		// 观战 → 参赛队 0,参赛 → 观战队 1。
		iTeam = (GetClientTeam(iClient) == BMS_TEAM_SPECTATORS) ? 0 : BMS_TEAM_SPECTATORS;
		bRoute = true;
	}
	else
	{
		// "spectate"
		bRoute = true;
	}
	if (gBmsSpecial.iAllowed == iClient)
	{
		gBmsSpecial.iAllowed = 0;
		return Plugin_Continue;
	}
	else if (GetClientTeam(iClient) == iTeam)
	{
		char sName[64];
		Bms_GetTeamName(iTeam, sName, sizeof(sName));
		mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_team_same", sName);
		return Plugin_Continue;
	}
	else if (Bms_IsGameMatch())
	{
		mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_teamchange_deny");
		return Plugin_Handled;
	}
	else if (gBmsRound.iState == BmsState_MatchEx)
	{
		mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_teamchange_deny_overtime");
		return Plugin_Handled;
	}
	if (bRoute)
	{
		// 不依赖引擎的 "spectate"/"chooseteam" ClientCommand 分支(BM 2026
		// 已不存在):统一改走 jointeam 的引擎正式通道(HandleCommand_JoinTeam
		// → ChangeTeam,含 mp_allowspectators 检查/自杀平衡/观察者状态机),
		// 与 forcespec/自动分队同一条路。iAllowed 放行本插件的监听器。
		gBmsSpecial.iAllowed = iClient;
		FakeClientCommandEx(iClient, "jointeam %d", iTeam);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action Bms_ListenCmd_Pause(int iClient, const char[] sCommand, int iArgs)
{
	if (iClient == 0)
	{
		// 服务器端派发:同步状态机,并吞掉引擎回显。listen server 上引擎每次
		// 暂停/恢复后会把同一条命令回显给客户端,主机端回显以 client==0
		// 重新派发("pause" 是 toggle,再放行一次会立刻取消暂停)。远程玩家
		// 的回显则以玩家命令到达,由下面的客户端分支处理。
		bool bPause = StrEqual(sCommand, "pause", false);
		if (StrEqual(sCommand, "setpause", false))
		{
			// "setpause" 无条件置暂停(非 toggle),由引擎内部调用;只同步状态
			if (gBmsRound.iState == BmsState_Match || gBmsRound.iState == BmsState_MatchEx)
			{
				Bms_SetState(BmsState_Paused);
			}
			return Plugin_Continue;
		}
		if (!Bms_IsGameMatch())
		{
			// 公服状态不干预:放行,由 mod_pause 自己维护 g_bPaused
			return Plugin_Continue;
		}
		if (bPause && gBmsRound.iState == BmsState_Paused)
		{
			// 已暂停时到达的 pause = 引擎回显或重复输入;放行会再次 toggle
			LogMessage("[bms_match] swallow 'pause' echo (client 0, already Paused)");
			return Plugin_Handled;
		}
		if (!bPause && gBmsRound.iState != BmsState_Paused)
		{
			// 未暂停时到达的 unpause/setpause = 引擎回显;放行会重新暂停
			LogMessage("[bms_match] swallow '%s' echo (client 0, state %d)", sCommand, gBmsRound.iState);
			return Plugin_Handled;
		}
		if (bPause && (gBmsRound.iState == BmsState_Match || gBmsRound.iState == BmsState_MatchEx))
		{
			Bms_SetState(BmsState_Paused);
		}
		else if (!bPause && gBmsRound.iState == BmsState_Paused)
		{
			Bms_SetState(BmsState_Match);
		}
		return Plugin_Continue;
	}
	if (!Bms_IsGameMatch())
	{
		return Plugin_Continue;
	}
	// 引擎的 "pause" 是 toggle(engine.dll:SetPaused(!IsPaused)),而且引擎每次
	// 暂停/恢复后会把同一条命令回显给客户端、客户端再作为玩家命令发回来,
	// 造成同一条输入被派发两次。所以这里必须按命令名判断方向(不能用
	// "当前状态" 推断),并把与状态不符的命令吞掉 —— 否则回显会再次翻转
	// 引擎状态、打印相反文本(实测:sm_pause 后跟 "比赛已继续",sm_unpause
	// 后跟 "比赛已暂停")。
	bool bPause = StrEqual(sCommand, "pause", false);
	if (StrEqual(sCommand, "setpause", false))
	{
		// "setpause" 无条件置暂停(非 toggle),引擎内部使用:只同步状态
		if (gBmsRound.iState == BmsState_Match || gBmsRound.iState == BmsState_MatchEx)
		{
			Bms_SetState(BmsState_Paused);
		}
		return Plugin_Continue;
	}
	if (bPause && gBmsRound.iState == BmsState_Paused)
	{
		// 已暂停时收到的 pause = 引擎回显或重复按键;放行会把暂停取消掉
		return Plugin_Handled;
	}
	if (!bPause && gBmsRound.iState != BmsState_Paused)
	{
		// 未暂停时收到的 unpause/setpause = 引擎回显或多余输入;吞掉
		return Plugin_Handled;
	}
	if (gBmsRound.iState == BmsState_MatchWait)
	{
		mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_deny_changing");
		return Plugin_Handled;
	}
	if (gBmsRound.iState == BmsState_MatchEx)
	{
		mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_deny_overtime_pause");
		return Plugin_Handled;
	}
	if (gBmsCvar.sv_pausable != null && !gBmsCvar.sv_pausable.BoolValue)
	{
		mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_pause_deny");
		return Plugin_Handled;
	}
	if (bPause)
	{
		// 发起暂停:仅管理员(暂停发起者必然是自己,其他人一律拒绝)
		if (iClient != gBmsSpecial.iPauser && !Bms_IsClientAdmin(iClient))
		{
			mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_pause_deny_pauser");
			return Plugin_Handled;
		}
		gBmsSpecial.iPauser = iClient;
		Bms_SayAll("%t", "bms_match_paused");
		Bms_SetState(BmsState_Paused);
	}
	else
	{
		// 恢复:发起人或管理员;自动暂停(iPauser=0)时参赛者(非观战)可恢复
		if (iClient != gBmsSpecial.iPauser && !Bms_IsClientAdmin(iClient)
			&& (gBmsSpecial.iPauser != 0 || IsClientObserver(iClient)))
		{
			mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_pause_deny_pauser");
			return Plugin_Handled;
		}
		Bms_SayAll("%t", "bms_match_resumed");
		gBmsSpecial.iPauser = 0;
		Bms_SetState(BmsState_Match);
	}
	return Plugin_Continue;
}

public Action Bms_ListenCmd_MapChange(int iClient, const char[] sCommand, int iArgs)
{
	if (iClient == 0)
	{
		Bms_SetState(BmsState_Changing);
		Bms_SetGamemode(gBmsRound.sNextMode);
		CreateTimer(10.0, BmsT_MapChangeFailsafe, gBmsMapChanges, TIMER_FLAG_NO_MAPCHANGE);
	}
	return Plugin_Continue;
}

// During the match countdown (MatchWait) every participant is frozen with
// MOVETYPE_NONE. A suicide command ("kill"/"explode") sidesteps that freeze:
// sm_fastspawn is left at 0s during matches, so death -> DispatchSpawn ->
// Spawn() lands the player back with MOVETYPE_WALK, and that respawn path
// slips past (or races) the spawn-hook re-freeze - a player types kill and
// walks around before go-live. The ending countdown (Over) has NO engine
// freeze at all (BM MP's GoToIntermission drops vanilla hl2mp's FL_FROZEN), so
// a kill there is an equally free bypass. Block both suicide commands during
// the MatchWait freeze and the Over ending window. No other death vector
// exists while frozen + weapon-stripped (BmsT_RemoveWeapons) + friendly-fire
// off, so this closes the bypass for both windows.
public Action Bms_ListenCmd_Suicide(int iClient, const char[] sCommand, int iArgs)
{
	if (iClient <= 0)
	{
		return Plugin_Continue;
	}
	if (gBmsRound.iState == BmsState_MatchWait)
	{
		mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_deny_suicide_countdown");
		return Plugin_Handled;
	}
	if (gBmsRound.iState == BmsState_Over)
	{
		mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_deny_over");
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action BmsT_MapChangeFailsafe(Handle hTimer, int iMapcount)
{
	if (gBmsMapChanges > iMapcount)
	{
		return Plugin_Stop;
	}
	char sMap[BMS_MAX_MAP_LENGTH];
	if (!Bms_GetModeDefaultmap(sMap, sizeof(sMap), gBmsRound.sMode) || !strlen(sMap) || !IsMapValid(sMap))
	{
		Bms_SetGamemode(gBmsCore.sDefaultMode);
		if (!Bms_GetModeDefaultmap(sMap, sizeof(sMap), gBmsCore.sDefaultMode) || !strlen(sMap) || !IsMapValid(sMap))
		{
			LogError("[bms_match] Mapchange failed and no fallback map found!");
			return Plugin_Stop;
		}
	}
	ServerCommand("changelevel %s", sMap);
	return Plugin_Stop;
}

public Action BmsT_RePause(Handle hTimer)
{
	static int i;
	if (gBmsSpecial.iPauser > 0 && IsClientConnected(gBmsSpecial.iPauser))
	{
		FakeClientCommand(gBmsSpecial.iPauser, "pause");
	}
	i++;
	if (i == 2)
	{
		gBmsSpecial.iPauser = 0;
		i = 0;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public void Bms_OnClientPutInServer(int iClient)
{
	if (gBmsRound.iState == BmsState_Paused)
	{
		gBmsSpecial.iPauser = iClient;
		CreateTimer(0.1, BmsT_RePause, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
	if (Bms_IsGameMatch() && !IsFakeClient(iClient))
	{
		gBmsSpecial.iAllowed = iClient;
		FakeClientCommandEx(iClient, "jointeam %i", BMS_TEAM_SPECTATORS);
	}
}

public void Bms_OnClientDisconnect(int iClient)
{
	if (!IsFakeClient(iClient))
	{
		if (Bms_PlayerCount(false) == 1 && gBmsRound.iState != BmsState_Changing)
		{
			if (Bms_IsGameMatch())
			{
				CreateTimer(1.0, BmsT_RestartMap, _, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}
	gBmsClient[iClient].bReady = false;
	gBmsClient[iClient].iVote = -1;
	gBmsWebToken[iClient][0] = '\0';
	gBmsStatusLastBody[iClient][0] = '\0';
	gBmsStatusLastHint[iClient] = 0.0;
	gBmsHintSoundMuted[iClient] = false;
	gBmsStatusHudLines[iClient] = 0;
	if (iClient == gBmsSpecial.iPauser || Bms_PlayerCount(false) == 0)
	{
		gBmsSpecial.iPauser = 0;
	}
}

public Action BmsT_RestartMap(Handle hTimer)
{
	Bms_SetGamemode(gBmsCore.sDefaultMode);
	char sMap[BMS_MAX_MAP_LENGTH];
	if (Bms_GetModeDefaultmap(sMap, sizeof(sMap), gBmsCore.sDefaultMode) && strlen(sMap) && gBmsCvar.sm_nextmap != null)
	{
		gBmsCvar.sm_nextmap.SetString(sMap);
	}
	ServerCommand("changelevel %s", sMap);
	return Plugin_Stop;
}

/**************************************************************
 * CHAT INTERCEPT
 *************************************************************/
public Action Bms_OnClientSayCommand(int iClient, const char[] sCommand, const char[] sArgs)
{
	if (iClient == 0)
	{
		// Listen server: the engine re-dispatches the host's chat as a
		// client==0 echo AFTER the client>=1 dispatch below already handled
		// it. Letting the echo through re-fires SM chat triggers (a second
		// sm_pause/sm_unpause that fights the match state) — block chat
		// commands here. Dedicated-server console says (admin console path)
		// are unaffected.
		if (!IsDedicatedServer() && (StrContains(sArgs, "!") == 0 || StrContains(sArgs, "/") == 0))
		{
			LogMessage("[bms_match] say echo blocked (client 0): %s", sArgs);
			return Plugin_Stop;
		}
		return Plugin_Continue;
	}
	bool bCommand = (StrContains(sArgs, "!") == 0 || StrContains(sArgs, "/") == 0);
	int i = view_as<int>(bCommand);
	if (Bms_IsGameMatch())
	{
		if (StrEqual(sArgs[i], "rtv", false))
		{
			mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_rtv_deny");
			return Plugin_Stop;
		}
		if (StrEqual(sArgs[i], "nominate", false))
		{
			mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_nominate_deny");
			return Plugin_Stop;
		}
	}
	if (gBmsVoting.iStatus == 1
		&& (StrEqual(sArgs[i], "yes", false) || StrEqual(sArgs[i], "no", false)
			|| StrEqual(sArgs[i], "1") || StrEqual(sArgs[i], "2") || StrEqual(sArgs[i], "3")
			|| StrEqual(sArgs[i], "4") || StrEqual(sArgs[i], "5")))
	{
		if (StrContains(sArgs, "/", false) != 0)
		{
			FakeClientCommandEx(iClient, "say /%s", sArgs[i]);
			return Plugin_Stop;
		}
	}
	if (bCommand)
	{
		if (StrEqual(sArgs[i], "stop", false))
		{
			FakeClientCommandEx(iClient, "say !cancel");
			return Plugin_Stop;
		}
		else if (StrEqual(sArgs[i], "starttest", false))
		{
			FakeClientCommandEx(iClient, "starttest");
			return Plugin_Stop;
		}
		else if (StrEqual(sArgs[i], "pause", false))
		{
			// 拦截在聊天触发(sm_pause)之前,直接驱动引擎。只发起引擎命令
			// 并打印;状态同步由 Bms_ListenCmd_Pause 的 client==0 分支在命令
			// 实际派发时完成 —— 若这里先把状态置为 Paused,监听器会把
			// ServerCommand("pause") 当成回显吞掉,引擎永远不会真正暂停。
			if (gBmsRound.iState == BmsState_Match || gBmsRound.iState == BmsState_MatchEx)
			{
				if (gBmsRound.iState == BmsState_MatchEx)
				{
					mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_deny_overtime_pause");
					return Plugin_Stop;
				}
				if (gBmsCvar.sv_pausable != null && !gBmsCvar.sv_pausable.BoolValue)
				{
					mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_pause_deny");
					return Plugin_Stop;
				}
				if (iClient != gBmsSpecial.iPauser && !Bms_IsClientAdmin(iClient))
				{
					mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_pause_deny_pauser");
					return Plugin_Stop;
				}
				ServerCommand("pause");
				Bms_SayAll("%t", "bms_match_paused");
				gBmsSpecial.iPauser = iClient;
			}
			else if (gBmsRound.iState == BmsState_Paused)
			{
				mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_deny_paused");
			}
			else
			{
				// 非比赛状态:放行给 sm_pause 聊天触发,公服暂停照常
				return Plugin_Continue;
			}
			return Plugin_Stop;
		}
		else if (StrEqual(sArgs[i], "unpause", false))
		{
			if (gBmsRound.iState == BmsState_Paused)
			{
				if (iClient == gBmsSpecial.iPauser || gBmsSpecial.iPauser == 0 || Bms_IsClientAdmin(iClient))
				{
					// 状态同步由监听器的 client==0 分支完成(同 !pause)
					ServerCommand("unpause");
					Bms_SayAll("%t", "bms_match_resumed");
					gBmsSpecial.iPauser = 0;
				}
				else
				{
					mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_pause_deny_pauser");
				}
			}
			else if (gBmsRound.iState == BmsState_Match || gBmsRound.iState == BmsState_MatchEx)
			{
				mod_textmsg_fix_SafePrintToChat(iClient, "%t", "bms_deny_match");
			}
			else
			{
				// 非比赛状态:放行给 sm_unpause 聊天触发
				return Plugin_Continue;
			}
			return Plugin_Stop;
		}
		else if (StrEqual(sArgs[i], "join", false))
		{
			FakeClientCommandEx(iClient, "jointeam %i", Bms_GetOptimalTeam());
			return Plugin_Stop;
		}
		else if (StrEqual(sArgs[i], "spec", false) || StrEqual(sArgs[i], "spectate", false))
		{
			FakeClientCommandEx(iClient, "spectate");
			return Plugin_Stop;
		}
		else if (StrContains(sArgs, "next ", false) == 1)
		{
			FakeClientCommandEx(iClient, "say !runnext %s", sArgs[5]);
			return Plugin_Stop;
		}
		else if (StrEqual(sArgs[i], "random", false))
		{
			FakeClientCommandEx(iClient, "say !runrandom");
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}

/**************************************************************
 * COMMANDS
 *************************************************************/
public Action BmsCmd_Maplist(int iClient, int iArgs)
{
	char sMode[BMS_MAX_MODE];
	if (!iArgs)
	{
		strcopy(sMode, sizeof(sMode), gBmsRound.sMode);
	}
	else
	{
		GetCmdArg(1, sMode, sizeof(sMode));
	}
	if (!StrEqual(sMode, "all", false) && !Bms_IsItemInList(sMode, gBmsCore.sGamemodes))
	{
		Bms_Reply(iClient, "%t", "bms_list_invalid", sMode);
		return Plugin_Handled;
	}
	// Auto-detect the maps/ folder and append missing maps to the mapcycles
	// before listing, so newly installed maps show up without a config edit.
	Bms_SyncMapcycles();
	ArrayList aMaps = new ArrayList(BMS_MAX_MAP_LENGTH);
	if (StrEqual(sMode, "all", false))
	{
		Bms_GetMapsArray(aMaps, "all");
	}
	else
	{
		char sMapcycle[PLATFORM_MAX_PATH];
		if (!Bms_GetModeMapcycle(sMapcycle, sizeof(sMapcycle), sMode) || !strlen(sMapcycle))
		{
			strcopy(sMapcycle, sizeof(sMapcycle), "all");
		}
		Bms_GetMapsArray(aMaps, sMapcycle);
	}
	if (!aMaps.Length)
	{
		delete aMaps;
		Bms_Reply(iClient, "%t", "bms_list_empty", sMode);
		return Plugin_Handled;
	}
	Bms_Reply(iClient, "%t", "bms_list_header", sMode);
	aMaps.Sort(Sort_Ascending, Sort_String);
	for (int i = 0; i < aMaps.Length; i++)
	{
		char sMap[BMS_MAX_MAP_LENGTH];
		char sDisplay[BMS_MAX_MAP_LENGTH];
		aMaps.GetString(i, sMap, sizeof(sMap));
		Bms_DeprefixMap(sMap, sDisplay, sizeof(sDisplay));
		Bms_Reply(iClient, " > %s", sDisplay);
	}
	Bms_Reply(iClient, "%t", "bms_list_total", aMaps.Length);
	delete aMaps;
	return Plugin_Handled;
}

public Action BmsCmd_Run(int iClient, int iArgs)
{
	BmsVoteType iVoteType;
	bool bMulti;
	char sParam[5][512];
	char sCommand[16];
	GetCmdArg(0, sCommand, sizeof(sCommand));
	GetCmdArgString(sParam[0], sizeof(sParam[]));
	Bms_StrToLower(sParam[0]);
	if (StrEqual(sCommand, "runrandom", false) || StrEqual(sParam[0], "random", false))
	{
		iVoteType = BmsVote_RunRandom;
	}
	else if (StrContains(sCommand, "runnext", false) == 0)
	{
		iVoteType = BmsVote_RunNext;
	}
	else if (StrContains(sCommand, "runauto", false) == 0)
	{
		iVoteType = BmsVote_RunAuto;
	}
	else
	{
		iVoteType = BmsVote_Run;
	}
	if (!iArgs)
	{
		if (iVoteType == BmsVote_Run)
		{
			Bms_Reply(iClient, "%t", "bms_run_usage");
			return Plugin_Handled;
		}
		if (iVoteType == BmsVote_RunNext)
		{
			Bms_Reply(iClient, "%t", "bms_runnext_usage");
			return Plugin_Handled;
		}
	}
	if (gBmsVoting.iStatus)
	{
		Bms_Reply(iClient, "%t", "bms_vote_deny");
		return Plugin_Handled;
	}
	else if (Bms_VoteTimeout(iClient) && !Bms_IsClientAdmin(iClient))
	{
		Bms_Reply(iClient, "%t", "bms_vote_timeout", Bms_VoteTimeout(iClient));
		return Plugin_Handled;
	}
	else if (gBmsRound.iState == BmsState_Paused)
	{
		Bms_Reply(iClient, "%t", "bms_deny_paused");
		return Plugin_Handled;
	}
	else if (gBmsRound.iState == BmsState_Match || gBmsRound.iState == BmsState_MatchEx)
	{
		Bms_Reply(iClient, "%t", "bms_deny_match");
		return Plugin_Handled;
	}
	else if (gBmsRound.iState == BmsState_Changing || gBmsRound.iState == BmsState_MatchWait)
	{
		Bms_Reply(iClient, "%t", "bms_deny_changing");
		return Plugin_Handled;
	}
	if (iVoteType == BmsVote_RunRandom)
	{
		bMulti = true;
		for (int i = 0; i < BMS_VOTE_OPTIONS; i++)
		{
			gsBmsMotion[i][0] = '\0';
		}
		// 4 random options in gsBmsMotion[0..3] (0-based, matching the vote menu /
		// HUD / tally which all read from index 0). The previous 1-based fill left
		// gsBmsMotion[0] empty, so the menu and HUD loop broke immediately and a
		// vote for "1" mapped to an empty slot ("bms_vote_invalid").
		for (int i = 0; i < BMS_VOTE_OPTIONS - 1; i++)
		{
			char sMode[BMS_MAX_MODE];
			if (i <= 1)
			{
				strcopy(sMode, sizeof(sMode), gBmsRound.sMode);
			}
			else if (!Bms_GetRandomMode(sMode, sizeof(sMode), true))
			{
				break;
			}
			char sMapcycle[PLATFORM_MAX_PATH];
			if (!Bms_GetModeMapcycle(sMapcycle, sizeof(sMapcycle), sMode) || !strlen(sMapcycle))
			{
				continue;
			}
			ArrayList aMaps = new ArrayList(BMS_MAX_MAP_LENGTH);
			if (Bms_GetMapsArray(aMaps, sMapcycle) > 1)
			{
				for (int y = 0; y < 8; y++)
				{
					int iRan = Bms_GetRandomInt(0, aMaps.Length - 1);
					char sMap[BMS_MAX_MAP_LENGTH];
					aMaps.GetString(iRan, sMap, sizeof(sMap));
					if (!StrEqual(sMap, gBmsRound.sMap) && !StrEqual(sMap, gBmsRound.sNextMap))
					{
						Format(gsBmsMotion[i], sizeof(gsBmsMotion[]), "%s:%s", sMode, sMap);
						break;
					}
				}
			}
			delete aMaps;
		}
	}
	else
	{
		char sArgs[512];
		strcopy(sArgs, sizeof(sArgs), sParam[0]);
		int iCount;
		int iPos;
		while (iCount < BMS_VOTE_OPTIONS && iPos < strlen(sArgs))
		{
			int iNext = FindCharInString(sArgs[iPos], ',');
			if (iNext == -1)
			{
				strcopy(sParam[iCount], sizeof(sParam[]), sArgs[iPos]);
				iCount++;
				break;
			}
			sArgs[iPos + iNext] = '\0';
			strcopy(sParam[iCount], sizeof(sParam[]), sArgs[iPos]);
			iCount++;
			iPos += iNext + 1;
		}
		bMulti = (iCount > 1);
		for (int i = 0; i < BMS_VOTE_OPTIONS; i++)
		{
			gsBmsMotion[i][0] = '\0';
		}
		for (int i = 0; i < iCount; i++)
		{
			char sMode[BMS_MAX_MODE];
			char sMap[BMS_MAX_MAP_LENGTH];
			int iSplit = SplitString(sParam[i], ":", sMode, sizeof(sMode));
			if (iSplit > 0)
			{
				sMode[iSplit - 1] = '\0';
			}
			else
			{
				strcopy(sMode, sizeof(sMode), sParam[i]);
			}
			bool bModeMatched = Bms_IsItemInList(sMode, gBmsCore.sGamemodes);
			if (!bModeMatched)
			{
				strcopy(sMap, sizeof(sMap), sMode);
				if (iSplit > 0)
				{
					strcopy(sMode, sizeof(sMode), sParam[i][iSplit]);
					if (!Bms_IsItemInList(sMode, gBmsCore.sGamemodes))
					{
						Bms_Reply(iClient, "%t", "bms_map_notfound", sMap);
						return Plugin_Handled;
					}
					bModeMatched = true;
				}
			}
			else if (iSplit > 0)
			{
				strcopy(sMap, sizeof(sMap), sParam[i][iSplit]);
			}
			else
			{
				if (StrEqual(gBmsRound.sMode, sMode) && !bMulti)
				{
					Bms_Reply(iClient, "%t", "bms_run_denymode", sMode);
					return Plugin_Handled;
				}
				if (!Bms_GetModeDefaultmap(sMap, sizeof(sMap), sMode) || !strlen(sMap) || !IsMapValid(sMap))
				{
					if (Bms_IsItemInList(gBmsRound.sMode, gBmsCore.sRetainModes) && Bms_IsItemInList(sMode, gBmsCore.sRetainModes))
					{
						strcopy(sMap, sizeof(sMap), gBmsRound.sMap);
					}
					else if (!Bms_GetModeDefaultmap(sMap, sizeof(sMap), sMode) || !strlen(sMap))
					{
						strcopy(sMap, sizeof(sMap), gBmsRound.sMap);
					}
				}
			}
			if (strlen(sMap))
			{
				int iHits = Bms_SearchMap(sMap, sizeof(sMap), sMap);
				if (!iHits)
				{
					Bms_Reply(iClient, "%t", "bms_map_notfound", sMap);
					return Plugin_Handled;
				}
				else if (iHits > 1 && !bMulti)
				{
					ArrayList aMaps = new ArrayList(BMS_MAX_MAP_LENGTH);
					Bms_GetMapsArray(aMaps, "", sMap);
					char sAll[1024];
					sAll[0] = '\0';
					for (int z = 0; z < aMaps.Length; z++)
					{
						char sFound[BMS_MAX_MAP_LENGTH];
						aMaps.GetString(z, sFound, sizeof(sFound));
						Format(sAll, sizeof(sAll), "%s%s%s", sAll, strlen(sAll) ? ", " : "", sFound);
					}
					delete aMaps;
					Bms_Reply(iClient, "%t", "bms_run_found", sAll);
					return Plugin_Handled;
				}
			}
			if (!bModeMatched)
			{
				if (!Bms_GetModeForMap(sMode, sizeof(sMode), sMap))
				{
					strcopy(sMode, sizeof(sMode), gBmsRound.sMode);
				}
			}
			if (!strlen(sMap) || !IsMapValid(sMap))
			{
				Bms_Reply(iClient, "%t", "bms_map_notfound", sMap);
				return Plugin_Handled;
			}
			Format(gsBmsMotion[i], sizeof(gsBmsMotion[]), "%s:%s", sMode, sMap);
		}
	}
	if (!bMulti && (Bms_PlayerCount(true, false, false) < gBmsVoting.iMinPlayers || gBmsVoting.iMinPlayers <= 0 || iClient == 0))
	{
		Bms_ExecuteRun(iVoteType, 0);
	}
	else
	{
		Bms_CallVote(iVoteType, iClient);
	}
	return Plugin_Handled;
}

public Action BmsCmd_Start(int iClient, int iArgs)
{
	if (iClient == 0)
	{
		Bms_Start(0);
		return Plugin_Handled;
	}

	char sAuth[32];
	GetClientAuthId(iClient, AuthId_Steam2, sAuth, sizeof(sAuth));
	LogMessage("[bms_match] !start by %N<%s> team=%d state=%d mode=%s players=%d admin=%d",
		iClient, sAuth, GetClientTeam(iClient), gBmsRound.iState, gBmsRound.sMode,
		Bms_PlayerCount(true, true, false), Bms_IsClientAdmin(iClient));

	char sReason[32];
	// 至少 2 名玩家(含 bot)才能开始比赛,对所有玩家一视同仁 —— 不再给
	// 管理员豁免(单人测试走 !starttest)。bot 是 DM 的正式参战者,bot_add
	// 在 BM 被设为作弊命令、只有管理员/服主加得出来,不会被普通玩家滥用。
	// 投票门槛(下方)仍只按真人算,3 名真人照常走投票。
	if (Bms_PlayerCount(true, true, false) <= 1)
	{
		strcopy(sReason, sizeof(sReason), "playercount");
		Bms_Reply(iClient, "%t", "bms_start_deny");
	}
	else if (gBmsVoting.iStatus)
	{
		strcopy(sReason, sizeof(sReason), "vote-active");
		Bms_Reply(iClient, "%t", "bms_vote_deny");
	}
	else if (Bms_VoteTimeout(iClient) && !Bms_IsClientAdmin(iClient))
	{
		strcopy(sReason, sizeof(sReason), "cooldown");
		Bms_Reply(iClient, "%t", "bms_vote_timeout", Bms_VoteTimeout(iClient));
	}
	else if (IsClientObserver(iClient) && !Bms_IsClientAdmin(iClient))
	{
		strcopy(sReason, sizeof(sReason), "spectator");
		Bms_Reply(iClient, "%t", "bms_deny_spectator");
	}
	else if (!Bms_IsModeMatchable(gBmsRound.sMode))
	{
		strcopy(sReason, sizeof(sReason), "mode-not-matchable");
		Bms_Reply(iClient, "%t", "bms_start_deny_mode", gBmsRound.sMode);
	}
	else if (Bms_IsGameMatch())
	{
		strcopy(sReason, sizeof(sReason), "match-running");
		Bms_Reply(iClient, "%t", "bms_deny_match");
	}
	else if (gBmsRound.iState == BmsState_Changing || gBmsRound.iState == BmsState_MatchWait)
	{
		strcopy(sReason, sizeof(sReason), "changing");
		Bms_Reply(iClient, "%t", "bms_deny_changing");
	}
	else if (gBmsRound.iState == BmsState_Over || Bms_GetTimeRemaining(false) < 1)
	{
		strcopy(sReason, sizeof(sReason), "round-over");
		Bms_Reply(iClient, "%t", "bms_start_deny_over");
	}
	else
	{
		if (Bms_PlayerCount(true, false, false) < gBmsVoting.iMinPlayers || gBmsVoting.iMinPlayers <= 0)
		{
			Bms_Start(iClient);
		}
		else
		{
			gsBmsMotion[0] = "start match";
			gsBmsMotion[1][0] = '\0';
			Bms_CallVote(BmsVote_Match, iClient);
		}
		return Plugin_Handled;
	}
	LogMessage("[bms_match] !start denied: %s", sReason);
	return Plugin_Handled;
}

// !starttest: admin-only, no vote - starts a 1-minute match immediately so the
// SourceTV demo pipeline (tv_record -> demos/<uid>.dem -> download link) can be
// verified without waiting out a full 15-minute match. Overtime is suppressed;
// the match always ends when the minute is up.
public Action BmsCmd_StartTest(int iClient, int iArgs)
{
	if (iClient == 0)
	{
		gBmsTestMatch = true;
		Bms_Start(0);
		return Plugin_Handled;
	}
	if (Bms_IsGameMatch())
	{
		Bms_Reply(iClient, "%t", "bms_deny_match");
		return Plugin_Handled;
	}
	if (gBmsRound.iState == BmsState_Changing || gBmsRound.iState == BmsState_MatchWait)
	{
		Bms_Reply(iClient, "%t", "bms_deny_changing");
		return Plugin_Handled;
	}
	if (gBmsRound.iState == BmsState_Over || Bms_GetTimeRemaining(false) < 1)
	{
		Bms_Reply(iClient, "%t", "bms_start_deny_over");
		return Plugin_Handled;
	}
	gBmsTestMatch = true;
	LogMessage("[bms_match] !starttest by %N: 1-minute test match, SourceTV demo check", iClient);
	Bms_Start(iClient);
	return Plugin_Handled;
}

public Action BmsCmd_Cancel(int iClient, int iArgs)
{
	if (iClient == 0)
	{
		Bms_Cancel();
		return Plugin_Handled;
	}
	if (gBmsVoting.iStatus)
	{
		Bms_Reply(iClient, "%t", "bms_vote_deny");
	}
	else if (Bms_VoteTimeout(iClient) && !Bms_IsClientAdmin(iClient))
	{
		Bms_Reply(iClient, "%t", "bms_vote_timeout", Bms_VoteTimeout(iClient));
	}
	else if (IsClientObserver(iClient) && !Bms_IsClientAdmin(iClient))
	{
		Bms_Reply(iClient, "%t", "bms_deny_spectator");
	}
	else if (gBmsRound.iState == BmsState_Paused)
	{
		Bms_Reply(iClient, "%t", "bms_deny_paused");
	}
	else if (gBmsRound.iState == BmsState_Default || gBmsRound.iState == BmsState_Overtime)
	{
		Bms_Reply(iClient, "%t", "bms_deny_nomatch");
	}
	else if (gBmsRound.iState == BmsState_MatchEx)
	{
		Bms_Reply(iClient, "%t", "bms_deny_overtime_cancel");
	}
	else if (gBmsRound.iState == BmsState_Changing || gBmsRound.iState == BmsState_MatchWait)
	{
		Bms_Reply(iClient, "%t", "bms_deny_changing");
	}
	else if (gBmsRound.iState == BmsState_Over || Bms_GetTimeRemaining(false) < 1)
	{
		Bms_Reply(iClient, "%t", "bms_deny_over");
	}
	else
	{
		if (Bms_PlayerCount(true, false, false) < gBmsVoting.iMinPlayers || gBmsVoting.iMinPlayers <= 0)
		{
			Bms_Cancel();
		}
		else
		{
			gsBmsMotion[0] = "cancel match";
			gsBmsMotion[1][0] = '\0';
			Bms_CallVote(BmsVote_Match, iClient);
		}
	}
	return Plugin_Handled;
}

public Action BmsCmd_Shuffle(int iClient, int iArgs)
{
	if (gBmsVoting.iStatus)
	{
		Bms_Reply(iClient, "%t", "bms_vote_deny");
	}
	else if (Bms_VoteTimeout(iClient) && !Bms_IsClientAdmin(iClient))
	{
		Bms_Reply(iClient, "%t", "bms_vote_timeout", Bms_VoteTimeout(iClient));
	}
	else if (Bms_IsGameMatch())
	{
		Bms_Reply(iClient, "%t", "bms_deny_match");
	}
	else if (!gBmsRound.bTeamplay)
	{
		Bms_Reply(iClient, "%t", "bms_deny_teamplay");
	}
	else if (gBmsRound.iState == BmsState_Changing || gBmsRound.iState == BmsState_MatchWait)
	{
		Bms_Reply(iClient, "%t", "bms_deny_changing");
	}
	else
	{
		if (Bms_PlayerCount(true, false, false) < gBmsVoting.iMinPlayers || gBmsVoting.iMinPlayers <= 0)
		{
			Bms_ShuffleTeams();
		}
		else
		{
			gsBmsMotion[0] = "shuffle teams";
			gsBmsMotion[1][0] = '\0';
			Bms_CallVote(BmsVote_Shuffle, iClient);
		}
	}
	return Plugin_Handled;
}

public Action BmsCmd_Invert(int iClient, int iArgs)
{
	if (gBmsVoting.iStatus)
	{
		Bms_Reply(iClient, "%t", "bms_vote_deny");
	}
	else if (Bms_VoteTimeout(iClient) && !Bms_IsClientAdmin(iClient))
	{
		Bms_Reply(iClient, "%t", "bms_vote_timeout", Bms_VoteTimeout(iClient));
	}
	else if (Bms_IsGameMatch())
	{
		Bms_Reply(iClient, "%t", "bms_deny_match");
	}
	else if (!gBmsRound.bTeamplay)
	{
		Bms_Reply(iClient, "%t", "bms_deny_teamplay");
	}
	else if (gBmsRound.iState == BmsState_Changing || gBmsRound.iState == BmsState_MatchWait)
	{
		Bms_Reply(iClient, "%t", "bms_deny_changing");
	}
	else
	{
		if (Bms_PlayerCount(true, false, false) < gBmsVoting.iMinPlayers || gBmsVoting.iMinPlayers <= 0)
		{
			Bms_InvertTeams();
		}
		else
		{
			gsBmsMotion[0] = "invert teams";
			gsBmsMotion[1][0] = '\0';
			Bms_CallVote(BmsVote_Invert, iClient);
		}
	}
	return Plugin_Handled;
}

public Action BmsCmd_CastVote(int iClient, int iArgs)
{
	char sVote[8];
	GetCmdArg(0, sVote, sizeof(sVote));
	bool bNumeric = Bms_IsNumeric(sVote);
	int iVote = bNumeric ? (StringToInt(sVote) - 1) : view_as<int>(StrEqual(sVote, "yes", false));
	bool bMulti = strlen(gsBmsMotion[1]) > 0;
	if (gBmsVoting.iStatus != 1)
	{
		Bms_Reply(iClient, "%t", "bms_vote_none");
	}
	else if (IsClientObserver(iClient) && gBmsVoting.iType == BmsVote_Match)
	{
		Bms_Reply(iClient, "%t", "bms_vote_deny_spec");
	}
	else if (!bMulti && bNumeric && iVote > 1)
	{
		Bms_Reply(iClient, "%t", "bms_vote_invalid");
	}
	else if (bMulti && !bNumeric)
	{
		Bms_Reply(iClient, "%t", "bms_vote_invalid");
	}
	else if (bNumeric && (iVote < 0 || iVote >= BMS_VOTE_OPTIONS))
	{
		Bms_Reply(iClient, "%t", "bms_vote_invalid");
	}
	else if (bMulti && !strlen(gsBmsMotion[iVote]))
	{
		Bms_Reply(iClient, "%t", "bms_vote_invalid");
	}
	else
	{
		gBmsClient[iClient].iVote = iVote;
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public Action BmsAdminCmd_Forcespec(int iClient, int iArgs)
{
	if (!iArgs)
	{
		Bms_Reply(iClient, "%t", "bms_forcespec_usage");
		return Plugin_Handled;
	}
	char sArg[64];
	GetCmdArg(1, sArg, sizeof(sArg));
	if (StrEqual(sArg, "@all", false))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsClientObserver(i))
			{
				continue;
			}
			ChangeClientTeam(i, BMS_TEAM_SPECTATORS);
		}
		Bms_Reply(iClient, "%t", "bms_forcespec_all");
	}
	else
	{
		int iTarget = Bms_ArgToTarget(iClient, sArg);
		if (iTarget)
		{
			char sName[MAX_NAME_LENGTH];
			GetClientName(iTarget, sName, sizeof(sName));
			ChangeClientTeam(iTarget, BMS_TEAM_SPECTATORS);
			Bms_Reply(iClient, "%t", "bms_forcespec_success", sName);
		}
		else
		{
			Bms_Reply(iClient, "%t", "bms_target_notfound");
		}
	}
	return Plugin_Handled;
}

public Action BmsAdminCmd_Allow(int iClient, int iArgs)
{
	if (!Bms_IsGameMatch())
	{
		Bms_Reply(iClient, "%t", "bms_deny_nomatch");
		return Plugin_Handled;
	}
	if (!iArgs)
	{
		Bms_Reply(iClient, "%t", "bms_allow_usage");
		return Plugin_Handled;
	}
	char sArg[64];
	GetCmdArg(1, sArg, sizeof(sArg));
	int iTarget = Bms_ArgToTarget(iClient, sArg);
	if (iTarget)
	{
		char sName[MAX_NAME_LENGTH];
		GetClientName(iTarget, sName, sizeof(sName));
		if (GetClientTeam(iTarget) == BMS_TEAM_SPECTATORS)
		{
			gBmsSpecial.iAllowed = iTarget;
			FakeClientCommand(iTarget, "jointeam %i", Bms_GetOptimalTeam());
			Bms_SayAll("%t", "bms_allow_success", sName);
		}
		else
		{
			Bms_Reply(iClient, "%t", "bms_allow_fail", sName);
		}
	}
	else
	{
		Bms_Reply(iClient, "%t", "bms_target_notfound");
	}
	return Plugin_Handled;
}

void Bms_RegisterCommands()
{
	RegConsoleCmd("maplist", BmsCmd_Maplist, "View list of available maps");
	RegConsoleCmd("list", BmsCmd_Maplist, "View list of available maps");
	RegConsoleCmd("run", BmsCmd_Run, "[Vote to] change the current map");
	RegConsoleCmd("runnow", BmsCmd_Run, "[Vote to] change the current map");
	RegConsoleCmd("runnext", BmsCmd_Run, "[Vote to] set the next map");
	RegConsoleCmd("runrandom", BmsCmd_Run, "Call a random map/mode vote");
	RegConsoleCmd("start", BmsCmd_Start, "[Vote to] start a match");
	RegAdminCmd("starttest", BmsCmd_StartTest, ADMFLAG_GENERIC, "Start a 1-minute test match (SourceTV demo check)");
	RegConsoleCmd("cancel", BmsCmd_Cancel, "[Vote to] cancel the match");
	RegConsoleCmd("shuffle", BmsCmd_Shuffle, "[Vote to] shuffle teams");
	RegConsoleCmd("invert", BmsCmd_Invert, "[Vote to] invert the teams");
	RegConsoleCmd("yes", BmsCmd_CastVote, "Vote YES");
	RegConsoleCmd("no", BmsCmd_CastVote, "Vote NO");
	for (int i = 1; i <= BMS_VOTE_OPTIONS; i++)
	{
		char sCmd[4];
		IntToString(i, sCmd, sizeof(sCmd));
		RegConsoleCmd(sCmd, BmsCmd_CastVote, "Vote for option");
	}
	RegAdminCmd("forcespec", BmsAdminCmd_Forcespec, ADMFLAG_GENERIC, "Force a player to spectate");
	RegAdminCmd("allow", BmsAdminCmd_Allow, ADMFLAG_GENERIC, "Allow a player to join the match");
	RegConsoleCmd("vguitest", BmsCmd_VguiTest, "Show a test VGUI page (scores/hide variants)");
	RegConsoleCmd("ammodump", BmsCmd_AmmoDump, "Print the active weapon's ammo fields to the console (debug)");
	RegConsoleCmd("help", BmsCmd_Help, "Show the match command menu");
	RegConsoleCmd("commands", BmsCmd_Help, "Show the match command menu");
	AddCommandListener(Bms_ListenCmd_Team, "jointeam");
	AddCommandListener(Bms_ListenCmd_Team, "spectate");
	AddCommandListener(Bms_ListenCmd_Team, "chooseteam");
	AddCommandListener(Bms_ListenCmd_Pause, "pause");
	AddCommandListener(Bms_ListenCmd_Pause, "unpause");
	AddCommandListener(Bms_ListenCmd_Pause, "setpause");
	AddCommandListener(Bms_ListenCmd_MapChange, "changelevel");
	AddCommandListener(Bms_ListenCmd_MapChange, "changelevel_next");
	AddCommandListener(Bms_ListenCmd_Suicide, "kill");
	AddCommandListener(Bms_ListenCmd_Suicide, "explode");
}

/**************************************************************
 * IN-GAME WEB PANEL (socket-hosted HTTP control page)
 *
 * A tiny HTTP server hosted inside the plugin via the SourceMod "socket"
 * extension, so the in-game HTML page (opened with !panel through
 * ShowMOTDPanel -> MOTDPANEL_TYPE_URL) can read match state and drive the
 * player-level commands through real buttons.  The page itself lives in
 * configs/bms_webpanel.html (UTF-8, editable without recompiling); this .sp
 * stays pure ASCII.  Feasibility/architecture notes: [[bms-in-game-html-panel]].
 *
 *   - Every !panel mints a per-client token; /do/<cmd> resolves the token back
 *     to a client and re-issues the command with FakeClientCommandEx, so the
 *     existing permission / team / cooldown gates apply exactly as if the
 *     player typed it.  Only the whitelist below is reachable.
 *   - Each endpoint is a small HTTP/1.1 GET with no body, so the request is
 *     assumed to arrive in a single receive callback (one TCP segment in
 *     practice).  No per-connection buffering.
 *   - Port / host changes take effect on `sm plugins reload merged` (the
 *     listener is bound at plugin load, before server.cfg re-runs per map).
 *************************************************************/

void Bms_WebPanel_GetQuery(const char[] sQuery, const char[] sKey, char[] sOut, int iMaxLen)
{
	sOut[0] = '\0';
	if (!sQuery[0])
	{
		return;
	}
	// Our URLs only ever carry a single "key=value" pair, so locate "key=" and
	// take everything after the '=' up to a '&' (or end of string).
	char sNeedle[32];
	FormatEx(sNeedle, sizeof(sNeedle), "%s=", sKey);
	int iPos = StrContains(sQuery, sNeedle);
	if (iPos == -1)
	{
		return;
	}
	char sVal[256];
	strcopy(sVal, sizeof(sVal), sQuery[iPos + strlen(sNeedle)]);
	int iAmp = FindCharInString(sVal, '&');
	if (iAmp != -1)
	{
		sVal[iAmp] = '\0';
	}
	strcopy(sOut, iMaxLen, sVal);
}

void Bms_WebPanel_StateName(int iState, char[] out, int len)
{
	if (iState == BmsState_Paused)          { strcopy(out, len, "paused"); }
	else if (iState == BmsState_Overtime)   { strcopy(out, len, "overtime"); }
	else if (iState == BmsState_MatchWait)  { strcopy(out, len, "matchwait"); }
	else if (iState == BmsState_Match)      { strcopy(out, len, "match"); }
	else if (iState == BmsState_MatchEx)    { strcopy(out, len, "matchex"); }
	else if (iState == BmsState_Over)       { strcopy(out, len, "over"); }
	else if (iState == BmsState_Changing)   { strcopy(out, len, "changing"); }
	else                                    { strcopy(out, len, "default"); }
}

void Bms_WebPanel_StateDisplay(int iState, char[] sText, int textLen, char[] sClass, int classLen)
{
	char sKey[32];
	if (iState == BmsState_Paused)         { strcopy(sKey, sizeof(sKey), "bms_state_paused");     strcopy(sClass, classLen, "s-paused"); }
	else if (iState == BmsState_Overtime)  { strcopy(sKey, sizeof(sKey), "bms_state_overtime");  strcopy(sClass, classLen, "s-overtime"); }
	else if (iState == BmsState_MatchWait) { strcopy(sKey, sizeof(sKey), "bms_state_matchwait"); strcopy(sClass, classLen, "s-matchwait"); }
	else if (iState == BmsState_Match)     { strcopy(sKey, sizeof(sKey), "bms_state_match");     strcopy(sClass, classLen, "s-match"); }
	else if (iState == BmsState_MatchEx)   { strcopy(sKey, sizeof(sKey), "bms_state_matchex");   strcopy(sClass, classLen, "s-matchex"); }
	else if (iState == BmsState_Over)      { strcopy(sKey, sizeof(sKey), "bms_state_over");      strcopy(sClass, classLen, "s-over"); }
	else if (iState == BmsState_Changing)  { strcopy(sKey, sizeof(sKey), "bms_state_changing");  strcopy(sClass, classLen, "s-changing"); }
	else                                   { strcopy(sKey, sizeof(sKey), "bms_state_default");   strcopy(sClass, classLen, "s-default"); }
	Format(sText, textLen, "%t", sKey);
}

void Bms_WebPanel_FmtTimeLeft(int iSec, char[] out, int len)
{
	if (iSec < 0)
	{
		strcopy(out, len, "-");
		return;
	}
	Format(out, len, "%d:%02d", iSec / 60, iSec % 60);
}

void Bms_WebPanel_HtmlEscape(const char[] src, char[] dst, int maxlen)
{
	dst[0] = '\0';
	int iOut = 0;
	for (int i = 0; src[i] != '\0' && iOut < maxlen - 8; i++)
	{
		char c = src[i];
		if (c == '&')            { dst[iOut++] = '&'; dst[iOut++] = 'a'; dst[iOut++] = 'm'; dst[iOut++] = 'p'; dst[iOut++] = ';'; }
		else if (c == '<')       { dst[iOut++] = '&'; dst[iOut++] = 'l'; dst[iOut++] = 't'; dst[iOut++] = ';'; }
		else if (c == '>')       { dst[iOut++] = '&'; dst[iOut++] = 'g'; dst[iOut++] = 't'; dst[iOut++] = ';'; }
		else if (c == '\n')      { dst[iOut++] = '<'; dst[iOut++] = 'b'; dst[iOut++] = 'r'; dst[iOut++] = '>'; }
		else if (c == '\r')      { /* drop */ }
		else                     { dst[iOut++] = c; }
	}
	dst[iOut] = '\0';
}

void Bms_WebPanel_Respond(Socket socket, int iStatus, const char[] sContentType, const char[] sBody)
{
	char sStatus[16];
	if (iStatus == 200)      { strcopy(sStatus, sizeof(sStatus), "OK"); }
	else if (iStatus == 400) { strcopy(sStatus, sizeof(sStatus), "Bad Request"); }
	else if (iStatus == 404) { strcopy(sStatus, sizeof(sStatus), "Not Found"); }
	else                     { strcopy(sStatus, sizeof(sStatus), "Error"); }

	char sHead[512];
	int iLen = strlen(sBody);
	FormatEx(sHead, sizeof(sHead),
		"HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",
		iStatus, sStatus, sContentType, iLen);
	socket.Send(sHead, strlen(sHead));
	if (iLen > 0)
	{
		socket.Send(sBody, iLen);
	}
}

int Bms_WebPanel_HexVal(char c)
{
	if (c >= '0' && c <= '9') { return c - '0'; }
	if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
	if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
	return -1;
}

void Bms_WebPanel_UrlDecode(const char[] src, char[] dst, int maxlen)
{
	dst[0] = '\0';
	int iOut = 0;
	for (int i = 0; src[i] != '\0' && iOut < maxlen - 1; i++)
	{
		if (src[i] == '%' && src[i + 1] != '\0' && src[i + 2] != '\0')
		{
			int iHi = Bms_WebPanel_HexVal(src[i + 1]);
			int iLo = Bms_WebPanel_HexVal(src[i + 2]);
			if (iHi >= 0 && iLo >= 0)
			{
				dst[iOut++] = (iHi << 4) | iLo;
				i += 2;
				continue;
			}
		}
		else if (src[i] == '+')
		{
			dst[iOut++] = ' ';
			continue;
		}
		dst[iOut++] = src[i];
	}
	dst[iOut] = '\0';
}

void Bms_WebPanel_SanitizeArg(const char[] src, char[] dst, int maxlen)
{
	dst[0] = '\0';
	int iOut = 0;
	for (int i = 0; src[i] != '\0' && iOut < maxlen - 1; i++)
	{
		char c = src[i];
		if (c == ';' || c == '"' || c == '\'' || c == '`' || c == '\n' || c == '\r' || c == '\t')
		{
			continue;
		}
		if (c >= 0 && c < 0x20)
		{
			continue;
		}
		dst[iOut++] = c;
	}
	dst[iOut] = '\0';
}

void Bms_WebPanel_CloseSoon(Socket socket)
{
	// The socket extension writes queued bytes asynchronously; closing the handle
	// in the same callback as Send() would discard the response (Steam MOTD shows
	// error 324 "empty response"). Delay the close so the bytes flush first.
	CreateTimer(1.0, Bms_WebPanel_Timer_Close, socket);
}

public Action Bms_WebPanel_Timer_Close(Handle timer, any data)
{
	Socket s = view_as<Socket>(data);
	delete s;
	return Plugin_Stop;
}

void Bms_WebPanel_ReadPage(char[] out, int maxlen)
{
	out[0] = '\0';
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/bms_webpanel.html");
	File hFile = OpenFile(sPath, "r");
	if (hFile == null)
	{
		return;
	}
	char sLine[2048];
	int iUsed = 0;
	while (hFile.ReadLine(sLine, sizeof(sLine)))
	{
		int iLen = strlen(sLine);
		while (iLen > 0 && (sLine[iLen - 1] == '\r' || sLine[iLen - 1] == '\n'))
		{
			sLine[--iLen] = '\0';
		}
		if (iUsed > 0 && iUsed + 1 < maxlen)
		{
			out[iUsed++] = '\n';
		}
		if (iUsed + iLen >= maxlen)
		{
			break;
		}
		strcopy(out[iUsed], maxlen - iUsed, sLine);
		iUsed += iLen;
	}
	delete hFile;
}

void Bms_WebPanel_ServePage(Socket socket, int iClient, const char[] sToken)
{
	gBmsWebHtml[0] = '\0';
	Bms_WebPanel_ReadPage(gBmsWebHtml, sizeof(gBmsWebHtml));
	if (!gBmsWebHtml[0])
	{
		Bms_WebPanel_Respond(socket, 404, "text/plain", "bms_webpanel.html not found");
		return;
	}

	// Server-side render: fill the __PLACEHOLDER__ tokens so the page works with
	// zero JavaScript.  Every page load — the initial !panel, the <meta refresh>
	// auto-reload, and the 302 bounce after a command — carries fresh state, so
	// the in-game browser never needs fetch/XHR (which it renders unreliably).
	char sHost[128];
	Bms_WebPanel_GetHost(sHost, sizeof(sHost));
	char sBase[160];
	FormatEx(sBase, sizeof(sBase), "http://%s:%d", sHost, gBmsWebPort.IntValue);

	char sStateText[32], sStateClass[32];
	Bms_WebPanel_StateDisplay(gBmsRound.iState, sStateText, sizeof(sStateText), sStateClass, sizeof(sStateClass));

	int iTimeLeft = -1;
	if (Bms_IsGameMatch())
	{
		float fLeft = Bms_GetTimeRemaining(false);
		iTimeLeft = (fLeft > 0.0) ? RoundToCeil(fLeft) : 0;
	}
	else
	{
		int iLeft = -1;
		if (GetMapTimeLeft(iLeft) && iLeft > 0)
		{
			iTimeLeft = iLeft;
		}
	}
	char sTime[16];
	Bms_WebPanel_FmtTimeLeft(iTimeLeft, sTime, sizeof(sTime));

	char sPlayers[8];
	IntToString(Bms_PlayerCount(true, true, false), sPlayers, sizeof(sPlayers));

	char sMap[64];
	strcopy(sMap, sizeof(sMap), (gBmsRound.sMap[0]) ? gBmsRound.sMap : "-");

	char sMode[32];
	strcopy(sMode, sizeof(sMode), (gBmsRound.sMode[0]) ? gBmsRound.sMode : "-");
	for (int i = 0; sMode[i] != '\0'; i++)
	{
		if (sMode[i] >= 'a' && sMode[i] <= 'z')
		{
			sMode[i] = sMode[i] - ('a' - 'A');
		}
	}

	char sScores[384];
	sScores[0] = '\0';
	if (gBmsRound.bTeamplay)
	{
		char sT2[32], sT3[32];
		Bms_GetTeamName(BMS_TEAM_COMBINE, sT2, sizeof(sT2));
		Bms_GetTeamName(BMS_TEAM_REBELS, sT3, sizeof(sT3));
		FormatEx(sScores, sizeof(sScores),
			"<div class=\"grid\"><div class=\"cell\"><div class=\"k\">%s</div><div class=\"v\">%d</div></div><div class=\"cell\"><div class=\"k\">%s</div><div class=\"v\">%d</div></div></div>",
			sT2, GetTeamScore(BMS_TEAM_COMBINE), sT3, GetTeamScore(BMS_TEAM_REBELS));
	}

	char sResult[1024];
	if (iClient > 0 && gBmsWebReply[iClient][0])
	{
		Bms_WebPanel_HtmlEscape(gBmsWebReply[iClient], sResult, sizeof(sResult));
	}
	else
	{
		Format(sResult, sizeof(sResult), "%t", "bms_panel_noresult");
	}

	char sNow[16];
	FormatTime(sNow, sizeof(sNow), "%H:%M:%S");

	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__BASE__", sBase, true);
	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__TOKEN__", sToken, true);
	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__STATECLASS__", sStateClass, true);
	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__STATETEXT__", sStateText, true);
	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__MAP__", sMap, true);
	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__MODE__", sMode, true);
	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__PLAYERS__", sPlayers, true);
	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__TIMELEFT__", sTime, true);
	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__SCORESHTML__", sScores, true);
	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__RESULT__", sResult, true);
	ReplaceString(gBmsWebHtml, sizeof(gBmsWebHtml), "__NOW__", sNow, true);

	Bms_WebPanel_Respond(socket, 200, "text/html; charset=utf-8", gBmsWebHtml);
}

void Bms_WebPanel_ServeStatus(Socket socket)
{
	char sState[16];
	Bms_WebPanel_StateName(gBmsRound.iState, sState, sizeof(sState));

	int iTimeLeft = -1;
	if (Bms_IsGameMatch())
	{
		float fLeft = Bms_GetTimeRemaining(false);
		iTimeLeft = (fLeft > 0.0) ? RoundToCeil(fLeft) : 0;
	}
	else
	{
		// Public server (no match): fall back to the engine's own map clock so
		// the panel stays meaningful between matches too.
		int iLeft = -1;
		if (GetMapTimeLeft(iLeft) && iLeft > 0)
		{
			iTimeLeft = iLeft;
		}
	}

	// GetTeamScore throws on non-existent teams (FFA maps only define team 0/1),
	// so only read the scoreboard when a teamplay round is actually running.
	int iScore2 = 0;
	int iScore3 = 0;
	if (gBmsRound.bTeamplay)
	{
		iScore2 = GetTeamScore(BMS_TEAM_COMBINE);
		iScore3 = GetTeamScore(BMS_TEAM_REBELS);
	}

	char sJson[512];
	FormatEx(sJson, sizeof(sJson),
		"{\"state\":\"%s\",\"map\":\"%s\",\"mode\":\"%s\",\"teamplay\":%d,\"players\":%d,\"timeleft\":%d,\"score2\":%d,\"score3\":%d}",
		sState,
		gBmsRound.sMap,
		gBmsRound.sMode,
		gBmsRound.bTeamplay ? 1 : 0,
		Bms_PlayerCount(true, true, false),
		iTimeLeft,
		iScore2,
		iScore3);

	Bms_WebPanel_Respond(socket, 200, "application/json; charset=utf-8", sJson);
}

int Bms_WebPanel_FindClientByToken(const char[] sToken)
{
	if (!sToken[0])
	{
		return -1;
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (gBmsWebToken[i][0] && StrEqual(gBmsWebToken[i], sToken))
		{
			return i;
		}
	}
	return -1;
}

void Bms_WebPanel_DoCommand(Socket socket, const char[] sCmd, const char[] sToken, const char[] sRawArg)
{
	int iClient = Bms_WebPanel_FindClientByToken(sToken);
	if (iClient <= 0 || !IsClientInGame(iClient) || IsFakeClient(iClient))
	{
		Bms_WebPanel_Respond(socket, 200, "text/html; charset=utf-8",
			"<html><body>Invalid token (player left?) - type !panel again.</body></html>");
		return;
	}

	// Decode + sanitise the optional argument before splicing it into a console
	// command, so a crafted URL cannot smuggle a ';' command separator or a
	// quote/control char through FakeClientCommandEx.
	char sArg[192];
	Bms_WebPanel_UrlDecode(sRawArg, sArg, sizeof(sArg));
	char sSafe[192];
	Bms_WebPanel_SanitizeArg(sArg, sSafe, sizeof(sSafe));

	// Whitelist of player-level commands the panel may trigger.  Argument
	// commands (run / runnext / vote) append the sanitised input; every command
	// maps to something the client could type themselves, so the existing
	// permission / team / cooldown gates apply exactly as typed.  The reply is
	// captured into gBmsWebReply and echoed back onto the page so the button's
	// result matches what the player sees in chat.  We then serve the freshly
	// rendered panel inline (a direct 200): top-level navigation paints in every
	// in-game browser, whereas a 302 redirect was followed at the HTTP layer but
	// never re-rendered, so a button looked like it did nothing.
	char sReal[256];
	if (StrEqual(sCmd, "start"))          { strcopy(sReal, sizeof(sReal), "start"); }
	else if (StrEqual(sCmd, "cancel"))    { strcopy(sReal, sizeof(sReal), "cancel"); }
	else if (StrEqual(sCmd, "pause"))     { strcopy(sReal, sizeof(sReal), "pause"); }
	else if (StrEqual(sCmd, "runrandom")) { strcopy(sReal, sizeof(sReal), "runrandom"); }
	else if (StrEqual(sCmd, "shuffle"))   { strcopy(sReal, sizeof(sReal), "shuffle"); }
	else if (StrEqual(sCmd, "invert"))    { strcopy(sReal, sizeof(sReal), "invert"); }
	else if (StrEqual(sCmd, "maplist"))   { strcopy(sReal, sizeof(sReal), "maplist"); }
	else if (StrEqual(sCmd, "help"))      { strcopy(sReal, sizeof(sReal), "help"); }
	else if (StrEqual(sCmd, "yes"))       { strcopy(sReal, sizeof(sReal), "yes"); }
	else if (StrEqual(sCmd, "no"))        { strcopy(sReal, sizeof(sReal), "no"); }
	else if (Bms_IsNumeric(sCmd) && StringToInt(sCmd) >= 1 && StringToInt(sCmd) <= BMS_VOTE_OPTIONS)
	{
		strcopy(sReal, sizeof(sReal), sCmd);
	}
	else if (StrEqual(sCmd, "run"))
	{
		if (sSafe[0]) { FormatEx(sReal, sizeof(sReal), "run %s", sSafe); }
		else          { strcopy(sReal, sizeof(sReal), "run"); }
	}
	else if (StrEqual(sCmd, "runnext"))
	{
		if (sSafe[0]) { FormatEx(sReal, sizeof(sReal), "runnext %s", sSafe); }
		else          { strcopy(sReal, sizeof(sReal), "runnext"); }
	}
	else
	{
		gBmsWebReply[iClient][0] = '\0';
		Bms_WebPanel_ServePage(socket, iClient, sToken);
		return;
	}

	gBmsWebReply[iClient][0] = '\0';
	gBmsWebCapturing[iClient] = true;
	// FakeClientCommandEx is DEFERRED: the command handler (and its reply via
	// Bms_Reply / Bms_SayAll) runs on the NEXT game frame, not inside this call.
	// Serving the page here therefore always renders an empty result box (the
	// reply has not been teed into gBmsWebReply yet).  Defer the serve a few
	// frames so the deferred command has run and captured its reply first.  The
	// socket handle stays alive via OnReceive's 1.0s CloseSoon, so it is carried
	// as a raw int inside the DataPack rather than an extra handle reference.
	FakeClientCommandEx(iClient, sReal);

	DataPack dp = new DataPack();
	dp.WriteCell(view_as<int>(socket));
	dp.WriteCell(iClient);
	dp.WriteString(sReal);
	dp.WriteString(sToken);
	CreateTimer(0.1, Bms_WebPanel_Timer_DoResult, dp);
}

public Action Bms_WebPanel_Timer_DoResult(Handle timer, DataPack dp)
{
	dp.Reset();
	Socket socket = view_as<Socket>(dp.ReadCell());
	int iClient = dp.ReadCell();
	char sCmd[256];
	dp.ReadString(sCmd, sizeof(sCmd));
	char sToken[40];
	dp.ReadString(sToken, sizeof(sToken));

	gBmsWebCapturing[iClient] = false;
	LogMessage("[bms_match] web panel do: cmd='%s' result='%s'", sCmd, gBmsWebReply[iClient]);

	// Serve the panel inline (no 302).  The in-game browser follows a redirect at
	// the HTTP layer but never re-renders it, whereas a direct 200 is the same
	// path the <meta refresh> already uses and that provably paints.
	Bms_WebPanel_ServePage(socket, iClient, sToken);
	delete dp;
	return Plugin_Stop;
}

void Bms_WebPanel_NewToken(int iClient)
{
	if (iClient < 1 || iClient > MaxClients)
	{
		return;
	}
	FormatEx(gBmsWebToken[iClient], sizeof(gBmsWebToken[]), "%x%x",
		GetURandomInt() & 0x7FFFFFFF, GetURandomInt() & 0x7FFFFFFF);
}

void Bms_WebPanel_GetHost(char[] out, int maxlen)
{
	char sCfg[128];
	gBmsWebHost.GetString(sCfg, sizeof(sCfg));
	TrimString(sCfg);
	if (sCfg[0])
	{
		strcopy(out, maxlen, sCfg);
		return;
	}
	// Loopback default: correct when server and client share a machine (the
	// test rig).  For remote clients set sm_bms_webpanel_host to the server's
	// public / LAN IP.
	strcopy(out, maxlen, "127.0.0.1");
}

void Bms_WebPanel_OnError(Socket socket, const int errorType, const char[] errorMsg, any data)
{
	LogMessage("[bms_match] web panel socket error %d: %s", errorType, errorMsg);
}

void Bms_WebPanel_OnDisconnect(Socket socket, any data)
{
	// nothing to do; the connection handle is closed by the receive path.
}

void Bms_WebPanel_OnReceive(Socket socket, const char[] buffer, const int size, const char[] senderIP, int senderPort, any data)
{
	if (size <= 0)
	{
		Bms_WebPanel_CloseSoon(socket);
		return;
	}
	if (strncmp(buffer, "GET", 3) != 0)
	{
		Bms_WebPanel_Respond(socket, 400, "text/plain", "Bad Request");
		Bms_WebPanel_CloseSoon(socket);
		return;
	}

	int iSp1 = FindCharInString(buffer, ' ');
	int iSp2 = (iSp1 == -1) ? -1 : FindCharInString(buffer[iSp1 + 1], ' ');
	if (iSp1 == -1 || iSp2 == -1)
	{
		Bms_WebPanel_Respond(socket, 400, "text/plain", "Bad Request");
		Bms_WebPanel_CloseSoon(socket);
		return;
	}

	char sPath[256];
	if (iSp2 >= sizeof(sPath))
	{
		iSp2 = sizeof(sPath) - 1;
	}
	strcopy(sPath, iSp2 + 1, buffer[iSp1 + 1]);

	char sQuery[256];
	sQuery[0] = '\0';
	int iQ = FindCharInString(sPath, '?');
	if (iQ != -1)
	{
		strcopy(sQuery, sizeof(sQuery), sPath[iQ + 1]);
		sPath[iQ] = '\0';
	}

	char sToken[40];
	Bms_WebPanel_GetQuery(sQuery, "token", sToken, sizeof(sToken));
	int iClient = Bms_WebPanel_FindClientByToken(sToken);

	LogMessage("[bms_match] web panel request: %s (client=%d)", sPath, iClient);

	if (StrEqual(sPath, "/") || StrEqual(sPath, "/panel"))
	{
		Bms_WebPanel_ServePage(socket, iClient, sToken);
	}
	else if (StrEqual(sPath, "/status"))
	{
		Bms_WebPanel_ServeStatus(socket);
	}
	else if (StrContains(sPath, "/do/") == 0)
	{
		char sArg[256];
		Bms_WebPanel_GetQuery(sQuery, "arg", sArg, sizeof(sArg));
		Bms_WebPanel_DoCommand(socket, sPath[4], sToken, sArg);
	}
	else
	{
		Bms_WebPanel_Respond(socket, 404, "text/plain", "Not Found");
	}

	Bms_WebPanel_CloseSoon(socket);
}

void Bms_WebPanel_OnIncoming(Socket socket, Socket newSocket, const char[] remoteIP, int remotePort, any data)
{
	newSocket.SetReceiveCallback(Bms_WebPanel_OnReceive, 0);
	newSocket.SetDisconnectCallback(Bms_WebPanel_OnDisconnect, 0);
	newSocket.SetErrorCallback(Bms_WebPanel_OnError, 0);
}

public Action BmsCmd_Panel(int iClient, int iArgs)
{
	if (iClient == 0 || !IsClientInGame(iClient) || IsFakeClient(iClient))
	{
		return Plugin_Handled;
	}

	char sTitle[64];
	Format(sTitle, sizeof(sTitle), "%T", "bms_panel_title", iClient);

	if (gBmsWebListen == null || !gBmsWebEnabled.BoolValue)
	{
		char sMsg[256];
		Format(sMsg, sizeof(sMsg), "%T", "bms_panel_unavailable", iClient);
		Bms_VGUIPage_Send(iClient, sTitle, sMsg);
		return Plugin_Handled;
	}

	Bms_WebPanel_NewToken(iClient);
	char sHost[128];
	Bms_WebPanel_GetHost(sHost, sizeof(sHost));
	int iPort = gBmsWebPort.IntValue;
	char sUrl[256];
	FormatEx(sUrl, sizeof(sUrl), "http://%s:%d/panel?token=%s", sHost, iPort, gBmsWebToken[iClient]);
	ShowMOTDPanel(iClient, sTitle, sUrl, MOTDPANEL_TYPE_URL);
	return Plugin_Handled;
}

void Bms_WebPanel_StartServer()
{
	if (gBmsWebListen != null)
	{
		return;
	}
	Socket sock = new Socket(SOCKET_TCP);
	if (sock == null)
	{
		LogError("[bms_match] web panel: failed to create socket");
		return;
	}
	sock.SetOption(SocketReuseAddr, 1);
	int iPort = gBmsWebPort.IntValue;
	if (!sock.Bind("0.0.0.0", iPort))
	{
		LogError("[bms_match] web panel: bind 0.0.0.0:%d failed", iPort);
		delete sock;
		return;
	}
	sock.SetIncomingCallback(Bms_WebPanel_OnIncoming, 0);
	sock.SetErrorCallback(Bms_WebPanel_OnError, 0);
	if (!sock.Listen())
	{
		LogError("[bms_match] web panel: listen failed on port %d", iPort);
		delete sock;
		return;
	}
	gBmsWebListen = sock;
	PrintToServer("[bms_match] web panel: listening on 0.0.0.0:%d", iPort);
}

void Bms_WebPanel_Init()
{
	gBmsWebListen = null;

	gBmsWebEnabled = CreateConVar("sm_bms_webpanel_enabled", "1", "Enable the in-game web control panel (needs the socket extension)", FCVAR_NOTIFY);
	gBmsWebPort = CreateConVar("sm_bms_webpanel_port", "28015", "HTTP port for the web control panel", FCVAR_NONE);
	gBmsWebHost = CreateConVar("sm_bms_webpanel_host", "", "Host/IP used in the panel URL (empty = 127.0.0.1)", FCVAR_NONE);

	RegConsoleCmd("panel", BmsCmd_Panel, "Open the in-game web control panel");
	RegConsoleCmd("webpanel", BmsCmd_Panel, "Open the in-game web control panel");

	if (!LibraryExists("socket"))
	{
		LogMessage("[bms_match] web panel: socket extension not loaded, panel disabled");
		return;
	}
	if (!gBmsWebEnabled.BoolValue)
	{
		return;
	}
	Bms_WebPanel_StartServer();
}

/**************************************************************
 * LIFECYCLE
 *************************************************************/
public void OnPluginStart()
{
	gBmsCvar.mp_timelimit = FindConVar("mp_timelimit");
	gBmsCvar.mp_teamplay = FindConVar("mp_teamplay");
	gBmsCvar.mp_chattime = FindConVar("mp_chattime");
	gBmsCvar.mp_forcerespawn = FindConVar("mp_forcerespawn");
	gBmsCvar.mp_restartgame = FindConVar("mp_restartgame");
	gBmsCvar.mp_fraglimit = FindConVar("mp_fraglimit");
	gBmsCvar.sv_pausable = FindConVar("sv_pausable");
	gBmsCvar.sm_nextmap = FindConVar("sm_nextmap");
	gBmsCvar.specDetails = FindConVar("sm_specDetails_enabled");
	gBmsCvar.tv_enable = FindConVar("tv_enable");
	gBmsCvar.mp_warmup_time = FindConVar("mp_warmup_time");
	gBmsCvar.mp_round_intermission_time = FindConVar("mp_round_intermission_time");
	gBmsCvar.mapvote_endvote = FindConVar("sm_mapvote_endvote");
	// 状态页(倒计时/状态/地图/人数)。0 = 关, 1 = 只发给死亡/观战的人,
	// 2 = 所有人。默认 2: 用户要求所有人常驻。
	gBmsStatusPage = CreateConVar("bms_status_page", "2", "Status page (countdown/state/map/players): 0=off, 1=dead/spectators only, 2=everyone", FCVAR_NOTIFY);
	gBmsStatusActive = CreateConVar("bms_status_active", "0", "Internal: 1 while bms_match owns the hint text (showhealth reads it)", FCVAR_DONTRECORD);
	// 0 = 走 hint 面板(HintText/KeyHintText): 有底框, 贴屏幕右侧, 但每条消息
	//     客户端都把整块动画从头重播(HintSize 0->1), 1 Hz 下就是每秒闪一下。
	// 1 = 走 HudMsg(CHudMessage): 屏幕上的纯文本, 没有底框, 但每秒刷新也不闪。
	// 2 = 同样是 HudMsg, 但改用紧凑排版, 腾出两行画「自己 K/D/ping + 前五名」。
	//     (早先这里走 SendPanelToClient 的 VGUI 面板, 结果是那块面板常驻占着
	//      客户端的菜单槽, 整个游戏里所有切枪键全部失效 —— 已废。)
	gBmsStatusChannel = CreateConVar("bms_status_channel", "0", "Status page transport: 0=hint panel (box, right-anchored, flickers), 1=HudMsg (no box, 6 lines), 2=HudMsg compact (same, plus own K/D/ping and the top-5 board)", FCVAR_NOTIFY);
	// 仅 bms_status_channel 0 时有效:
	// 0 = HintText (CHudHintDisplay) —— 原来 Show Health 用的那块**长条**,
	//     天生静音(音效名 "Hud.Hint" 在 BM 里不存在)、动画不动 HintSize 所以
	//     不闪。代价是客户端 scheme 里没有 "HudHintText" 字体, 行高算出来是 0,
	//     **只能发单行**(状态页在单行模式下把各行用 " | " 拼起来)。
	// 1 = KeyHintText (CHudHintKeyDisplay) —— 多行在任何客户端上都正常, 但每条
	//     消息播一声 hev_vox/blip.wav(服务端关不掉, 只能让客户端执行
	//     cl_hudhint_sound 0), 而且每发一条都会重播 HintSize 0->1 的缩放动画。
	gBmsStatusKeyHint = CreateConVar("bms_status_keyhint", "1", "Status page hint panel: 0=HintText (show-health long bar, silent, single line), 1=KeyHintText (narrow box, multi-line, beeps)", FCVAR_NOTIFY);
	// 0 = 由本插件关掉 hint 面板的音效: 服务端 sv_hudhint_sound 压成 0, 再让每个
	// 客户端执行一次 cl_hudhint_sound 0。1 = 全部交还给玩家自己的设置。
	// 两边都只在运行时改, 不写任何 cfg 文件(客户端的 ARCHIVE 标记会自己存盘)。
	gBmsStatusHintSound = CreateConVar("bms_status_hintsound", "0", "Status page: 0 = silence the hint panel (sv_hudhint_sound 0 + cl_hudhint_sound 0 on each client), 1 = leave the players' own settings alone", FCVAR_NOTIFY);
	// HudMsg 的第二组颜色(客户端把 8 个字节原样存进槽位对象的 +4..+0xb)。
	// 1 = 第二组写黑色, 当作描边/阴影用; **默认关**, 因为客户端是否真的画
	// 第二组还没实测 —— 如果它是在同一坐标上画的, 黑字会直接把黄字盖掉,
	// 游戏里 `sm_cvar bms_status_shadow 1` 一眼就能分辨。
	gBmsStatusShadow = CreateConVar("bms_status_shadow", "0", "Status page: 1 = colour the HudMsg second colour quad black (outline test)", FCVAR_NOTIFY);
	// 文字右边界。HudMessage 面板 = 700x480 HUD 单位、左上角 (0,0), 面板右边
	// 换算成屏幕宽比例是 700 / (480 * 宽高比): 16:9 ≈ 0.820, 16:10 ≈ 0.911,
	// 4:3 ≈ 1.09(不裁), 21:9 ≈ 0.625。服务端查不到客户端的宽高比, 所以默认
	// 按 16:10 贴边(0.89); 16:9 的客户端要用 sm_cvar bms_status_right 0.81,
	// 带鱼屏 0.60 左右。
	gBmsStatusRight = CreateConVar("bms_status_right", "0.89", "Status page: right edge of the HudMsg text block (0..1 of screen width; 16:10 max ~0.91, 16:9 max ~0.82)", FCVAR_NOTIFY);
	// 记分块只在通道 2 上画: 那边为它把「状态/倒计时/地图」压成一行、
	// 让掉 !help, 才腾得出「自己 K/D/Ping + 前五名」这几行。
	gBmsStatusStats = CreateConVar("bms_status_stats", "1", "Status page: 1 = append K/D/ping + top 5 to the compact channel (bms_status_channel 2)", FCVAR_NOTIFY);
	// 让位窗口(绝对服务器时间)。投票/菜单弹出来时把状态页挪开, 免得文字压在
	// 选项上 —— 弹菜单之前把这里的值推到 GetGameTime()+时长, 关掉之后自动恢复。
	// 投票插件都写成 FindConVar("bms_status_yield") + 写值, 不跨模块调函数。
	gBmsStatusYield = CreateConVar("bms_status_yield", "0", "Internal: absolute game time until which the status page stays off the screen (menus/votes set it)", FCVAR_DONTRECORD);
	// CGameRules::SetState(int) SDKCall. this = g_pGameRules (auto), one int
	// parameter (newState), void return. The address comes from the gamedata
	// signature so the vtable-slot shift between game builds is irrelevant;
	// Bms_EngineReset falls back to the plugin-side CleanupMap when the
	// gamedata file is missing or the signature no longer matches.
	// NOTE: LoadGameConfigFile appends ".txt" verbatim (no ".games.txt"
	// fallback), so the name must include the ".games" part.
	Handle hSetStateConf = LoadGameConfigFile("bms_match.games");
	Address pSetState = Address_Null;
	if (hSetStateConf != INVALID_HANDLE)
	{
		pSetState = GameConfGetAddress(hSetStateConf, "CGameRules_SetState");
		CloseHandle(hSetStateConf);
	}
	if (pSetState != Address_Null)
	{
		StartPrepSDKCall(SDKCall_GameRules);
		PrepSDKCall_SetAddress(pSetState);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		gBmsCall_SetState = EndPrepSDKCall();
	}
	if (gBmsCall_SetState == INVALID_HANDLE)
	{
		LogError("[bms_match] SetState SDKCall unavailable - engine reset disabled");
	}
	LoadTranslations("bms_match.phrases");
	gBmsRound.mTeams = new StringMap();
	gBmsRound.iState = BmsState_Default;
	gBmsVoteHud = CreateHudSynchronizer();
	Bms_LoadConfig();
	HookEvent("player_spawn", Bms_Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("round_start", Bms_Event_RoundStart, EventHookMode_Post);
	HookEvent("broadcast_teamsound", Bms_Event_TeamSound, EventHookMode_Pre);
	HookEvent("broadcast_playersound", Bms_Event_TeamSound, EventHookMode_Pre);
	// NOTE: broadcast_killstreak is deliberately NOT hooked - killstreak voice
	// ("double kill" etc.) is legitimate mid-match feedback and must keep playing.
	Bms_RegisterCommands();
	Bms_WebPanel_Init();
	CreateTimer(1.0, BmsT_CheckPlayerStates, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(1.0, BmsT_Voting, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(1.0, BmsT_StatusPage, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	PrintToServer("[bms_match] loaded, gamemodes: %s", gBmsCore.sGamemodes);
}

public void OnConfigsExecuted()
{
	// mapchooser's automatic end-of-map vote ("下一幅地图投选") fires ~3 min
	// before the map ends and overwrites sm_nextmap, silently undoing an
	// explicit runnext setting. Disable it server-wide: bms_match is the
	// single source of truth for map changes (runnext / run / runrandom /
	// post-match autovote). OnConfigsExecuted runs after server.cfg and the
	// auto-generated per-plugin cfgs, so this beats the cvar's compiled
	// default of 1.
	if (gBmsCvar.mapvote_endvote != null)
	{
		gBmsCvar.mapvote_endvote.SetInt(0);
	}

	// server.cfg 可能带着 sv_hudhint_sound 1(引擎默认也是 1), 每条 hint 消息
	// 客户端都会播一声。这里按 bms_status_hintsound 在内存里压成 0。
	Bms_ApplyHintSound();
}

public void OnMapStart()
{
	gBmsMapChanges++;
	gBmsRunTimer = 0;
	gBmsTV.bRecording = false;
	// tv_enable stays resident (server.cfg sets it): never toggle it here.
	Bms_VGUIPage_HideAll();
	Bms_LoadConfig();
	GetCurrentMap(gBmsRound.sMap, sizeof(gBmsRound.sMap));
	strcopy(gBmsRound.sNextMode, sizeof(gBmsRound.sNextMode), gBmsRound.sMode);
	// 必须带上 Bms_TeamplayAvailable(): server.cfg 里 mp_teamplay 可能是 1, 但
	// BM DM 的 gamerules 只注册 team 0(unassigned) 和 team 1(spectator),
	// GetTeamClientCount(REBELS=3) 会抛 "Team index 3 is invalid" —— 每客户端
	// 每秒一次的 BmsT_TeamAutoAssign 定时器因此被异常打断(永远走不到
	// Plugin_Stop), errors 日志被刷满, 选手也永远上不了场。
	gBmsRound.bTeamplay = (gBmsCvar.mp_teamplay != null && gBmsCvar.mp_teamplay.BoolValue
		&& Bms_TeamplayAvailable());
	gBmsRound.bOvertime = (Bms_GetConfigInt("Overtime", "Gamemodes", gBmsRound.sMode, 0) == 1);
	Bms_SetState(BmsState_Default);
	Bms_SetGamemode(gBmsRound.sMode);
	Bms_SetMapcycle();
	Bms_SyncMapcycles();
	gBmsRound.fStartTime = GetGameTime() - 1.0;
	gBmsVoting.iStatus = 0;
	gBmsVoting.iElapsed = 0;
	gBmsVoting.iLead = -1;
	gBmsSpecial.iAllowed = 0;
	gBmsSpecial.iPauser = 0;
	gBmsRound.iTimerBackup = -1;
	gBmsTestMatch = false;
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		gBmsClient[iClient].bReady = false;
		gBmsClient[iClient].iVote = -1;
	}
	if (gBmsCvar.sm_nextmap != null)
	{
		gBmsCvar.sm_nextmap.SetString("");
	}
	if (gBmsRound.bOvertime)
	{
		Bms_CreateOverTimer();
	}
}

public void OnMapEnd()
{
	gBmsRound.bTeamplay = (gBmsCvar.mp_teamplay != null && gBmsCvar.mp_teamplay.BoolValue
		&& Bms_TeamplayAvailable());
	if (gBmsRound.hOvertime != INVALID_HANDLE)
	{
		KillTimer(gBmsRound.hOvertime);
		gBmsRound.hOvertime = INVALID_HANDLE;
	}
	if (gBmsRound.iState == BmsState_MatchEx || gBmsRound.iState == BmsState_Overtime)
	{
		Bms_SayAll("%t", "bms_overtime_draw");
	}
}
