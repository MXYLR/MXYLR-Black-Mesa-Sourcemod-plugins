#pragma semicolon 1

#include <sourcemod>

public Plugin myinfo =
{
	name = "Scores Hold (TAB)",
	author = "MXYLR",
	description = "Server-side press/release scoreboard for clients bound to sm_scores_open / sm_scores_close",
	version = "1.1.0",
	url = ""
};

ConVar g_hEnabled;

// 当前地图是不是单人战役: -1 = 还没判定, 0 = 不是, 1 = 是。见 SH_Campaign()。
int g_iMapCampaign = -1;

public void OnPluginStart()
{
	g_hEnabled = CreateConVar("sm_scores_hold", "1",
		"1 = clients may open/close the scoreboard with sm_scores_open / sm_scores_close (0 = off)",
		FCVAR_NOTIFY);

	RegConsoleCmd("sm_scores_open", Cmd_ScoresOpen, "Hold-to-view scoreboard: press");
	RegConsoleCmd("sm_scores_close", Cmd_ScoresClose, "Hold-to-view scoreboard: release");
	RegConsoleCmd("+sm_scores", Cmd_ScoresOpen, "Hold-to-view scoreboard: press");
	RegConsoleCmd("-sm_scores", Cmd_ScoresClose, "Hold-to-view scoreboard: release");

	AddCommandListener(SH_SayHook, "say");
}

// ---------------------------------------------------------------- 战役判定
//
// 这个插件只为死亡竞赛存在: 战役里没有记分板这回事, 而同一个 SourceMod 装在
// 单人环境里也跑。判据沿用 BMAG 里已经实锤过的那条规则: 战役地图全部形如
// bm_c<数字>*(bm_c0a0a … bm_c5a1a), DM 侧地图是 dm_*/de_*/bm_bunnyrace_beta2,
// 没有任何地图以 bm_c<数字> 开头。判错时默认偏向 DM(即保留插件行为)。
bool SH_Campaign()
{
	if (g_iMapCampaign == -1)
	{
		char sMap[PLATFORM_MAX_PATH];
		GetCurrentMap(sMap, sizeof(sMap));

		g_iMapCampaign = (strncmp(sMap, "bm_c", 4) == 0
			&& sMap[4] >= '0' && sMap[4] <= '9') ? 1 : 0;

		LogMessage("[scores_hold] map \"%s\" -> %s", sMap, g_iMapCampaign
			? "singleplayer campaign: disabled"
			: "deathmatch: enabled");
	}

	return g_iMapCampaign == 1;
}

bool SH_Active()
{
	return g_hEnabled.BoolValue && !SH_Campaign();
}

public void OnMapStart()
{
	g_iMapCampaign = -1;
	SH_Campaign();
}

// 2026-11-17 的客户端更新在 +showscores 的回调里加了一道门:
//   if (!g_pGameRules || !g_pGameRules->vtable[0x88]()) return;   // 静默返回
//   viewport->ShowPanel("scores", true);
// 那个虚函数返回 false, 于是按 TAB 完全没反应。而 -showscores 没有这道门,
// 一直直接 ShowPanel("scores", false)。命令本身是纯客户端输入(TAB 不在
// CUserCmd 的 IN_* 位里), 服务端既看不见按键也拦不住它。
//
// 绕路: 让客户端把 TAB 绑到一对普通命令上, 服务端就能拿到按下/松开:
//
//   alias +bmscores "sm_scores_open"
//   alias -bmscores "sm_scores_close"
//   bind TAB +bmscores
//
// 按下发 VGUIMenu "scores" show=1, 松开发 show=0。客户端的 VGUIMenu 处理
// (clientmode_shared.cpp: __MsgFunc_VGUIMenu) 直接调 _ShowPanel(name, show),
// **不经过**上面那道 gamerules 门, 这是服务端唯一能把记分板打开的路。
// 线上格式 = string panelname + byte show + byte count + count×(key,value);
// "scores" 面板自读游戏状态, 不需要载荷(与 bms_match 的 ShowScoresPanel 同款)。
//
// 2026-11-17 实测: 这条 VGUIMenu 在新版客户端上没有任何可见效果(记分板不弹)。
// 所以再补一条 ClientCommand: 让客户端自己执行 +showscores / -showscores,
// 与按住 TAB 走的是同一条原生路径(打了 client_mod/showscores_fix 的客户端上
// 原生回调已经是通的)。两条通道都发, 谁的能生效就用谁的。
void SH_SendScoresPanel(int iClient, bool bShow)
{
	if (!IsClientInGame(iClient) || IsFakeClient(iClient))
	{
		return;
	}

	LogMessage("[scores_hold] %N -> VGUIMenu \"scores\" show=%d + ClientCommand %sshowscores",
		iClient, bShow ? 1 : 0, bShow ? "+" : "-");
	PrintToConsole(iClient, "[scores_hold] %sshowscores", bShow ? "+" : "-");

	Handle hMsg = StartMessageOne("VGUIMenu", iClient);
	if (hMsg != null)
	{
		BfWriteString(hMsg, "scores");
		BfWriteByte(hMsg, bShow ? 1 : 0);
		BfWriteByte(hMsg, 0);
		EndMessage();
	}

	char sCmd[16];
	Format(sCmd, sizeof(sCmd), "%sshowscores", bShow ? "+" : "-");
	ClientCommand(iClient, "%s", sCmd);
}

public Action Cmd_ScoresOpen(int client, int args)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}

	if (!SH_Active())
	{
		return Plugin_Handled;
	}

	PrintToChat(client, "[scores_hold] sm_scores_open 已执行 -> ShowPanel(\"scores\", 1)");
	SH_SendScoresPanel(client, true);
	return Plugin_Handled;
}

public Action Cmd_ScoresClose(int client, int args)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}

	if (!SH_Active())
	{
		return Plugin_Handled;
	}

	SH_SendScoresPanel(client, false);
	return Plugin_Handled;
}

// ---------------------------------------------------------------- 分流诊断
//
// 2026-11-17 复测: 在客户端控制台敲 sm_scores_open, 服务端日志里一点痕迹都没有,
// 说明那条路根本没执行(listen server 上客户端控制台的未知命令不一定被转发到服务端)。
// 聊天是确定会到服务器的, 所以用 !scores / !scoresall 做分流:
//   !scores    -> VGUIMenu "scores": 客户端 CViewPort::ShowPanel 走 FindPanelByName
//                 (按名字查表), 查不到就静默什么都不做
//   !scoresall -> VGUIMenu "all": 走 "all" 分支, 直接遍历面板数组逐个 SetVisible
// 结果判读: 两个都不亮 = 面板/ShowPanel 这条链整体不通; 只有 all 亮 = 名字表里
// 没有 "scores" 这一项; 只有 scores 亮 = 面板本来就是好的, 问题出在客户端补丁。
public Action SH_SayHook(int iClient, const char[] sCommand, int iArgs)
{
	if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient))
	{
		return Plugin_Continue;
	}

	char sText[64];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	TrimString(sText);

	if (StrEqual(sText, "!scores", false) || StrEqual(sText, "/scores", false))
	{
		SH_TestPanel(iClient, "scores");
		return Plugin_Handled;
	}

	if (StrEqual(sText, "!scoresall", false) || StrEqual(sText, "/scoresall", false))
	{
		SH_TestPanel(iClient, "all");
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void SH_SendPanelName(int iClient, const char[] sName, bool bShow)
{
	Handle hMsg = StartMessageOne("VGUIMenu", iClient);
	if (hMsg == null)
	{
		return;
	}

	BfWriteString(hMsg, sName);
	BfWriteByte(hMsg, bShow ? 1 : 0);
	BfWriteByte(hMsg, 0);
	EndMessage();
}

void SH_TestPanel(int iClient, const char[] sName)
{
	if (!SH_Active())
	{
		PrintToChat(iClient, "[scores_hold] 本图不启用(战役图或 sm_scores_hold 0)");
		LogMessage("[scores_hold] %N -> !%s ignored: disabled on this map", iClient, sName);
		return;
	}

	LogMessage("[scores_hold] %N -> chat !%s : VGUIMenu \"%s\" show=1", iClient, sName, sName);
	PrintToChat(iClient, "[scores_hold] 已发送 VGUIMenu \"%s\", 4 秒后关闭", sName);

	SH_SendPanelName(iClient, sName, true);

	if (StrEqual(sName, "scores", false))
	{
		ClientCommand(iClient, "+showscores");
		CreateTimer(4.0, Timer_CloseTest, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		CreateTimer(4.0, Timer_CloseAll, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_CloseTest(Handle hTimer, int iUserId)
{
	int iClient = GetClientOfUserId(iUserId);
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Stop;
	}

	SH_SendPanelName(iClient, "scores", false);
	ClientCommand(iClient, "-showscores");
	return Plugin_Stop;
}

public Action Timer_CloseAll(Handle hTimer, int iUserId)
{
	int iClient = GetClientOfUserId(iUserId);
	if (iClient < 1 || !IsClientInGame(iClient))
	{
		return Plugin_Stop;
	}

	SH_SendPanelName(iClient, "all", false);
	return Plugin_Stop;
}
