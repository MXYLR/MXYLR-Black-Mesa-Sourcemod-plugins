#pragma semicolon 1

#include <sourcemod>
#include <clientprefs>

public Plugin myinfo =
{
	name = "Show Health",
	author = "Unknown",
	description = "Shows your health on the screen",
	version = "1.0.2",
	url = "https://forums.alliedmods.net/"
};

#define AREA_HINT 1
#define AREA_CENTER 2

ConVar g_hVersion;
ConVar g_hEnabled;
ConVar g_hOnHitOnly;
ConVar g_hTextArea;

Handle g_hCookieShowHealth;

float g_fLastHurt[MAXPLAYERS + 1];

// 单人战役判据 (与 advertisements / fast_spawn / bms_match 同一条规则:
// 地图名 bm_c<数字>*). 战役里这块面板只是每秒糊一脸 "Show Health: N",
// 状态页也不在战役里画, 所以整块静默。
// -1 = 本图还没判过, 0 = 死斗, 1 = 战役.
int g_iMapCampaign = -1;

bool IsCampaignMap()
{
	if (g_iMapCampaign == -1)
	{
		char sMap[PLATFORM_MAX_PATH];
		GetCurrentMap(sMap, sizeof(sMap));
		g_iMapCampaign = (strncmp(sMap, "bm_c", 4) == 0
			&& sMap[4] >= '0' && sMap[4] <= '9') ? 1 : 0;
	}

	return g_iMapCampaign == 1;
}

public void OnPluginStart()
{
	g_hVersion = CreateConVar("sm_show_health_version", "1.0.2", "Show Health Version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_hEnabled = CreateConVar("sm_show_health", "1", "Enabled/Disabled show health functionality, 0 = off/1 = on", FCVAR_NOTIFY);
	g_hOnHitOnly = CreateConVar("sm_show_health_on_hit_only", "0", "Defines the weather when to show a health text:\n0 = always show your health on a screen\n1 = show your health only when somebody hit you", FCVAR_NOTIFY);
	g_hTextArea = CreateConVar("sm_show_health_text_area", "1", "Defines the area for health text:\n 1 = in the hint text area\n 2 = in the center of the screen", FCVAR_NOTIFY);

	g_hCookieShowHealth = RegClientCookie("cookie_show_health", "Cookie Show Health", CookieAccess_Protected);

	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_death", Event_PlayerDeath);

	AutoExecConfig(true, "showhealth");

	SetCookieMenuItem(CookieMenuHandler_ShowHealth, 0, "Show Health");
}

public void OnClientPutInServer(int client)
{
	g_fLastHurt[client] = 0.0;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (client && IsClientInGame(client))
	{
		g_fLastHurt[client] = GetGameTime();
	}

	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (client && IsClientInGame(client))
	{
		g_fLastHurt[client] = 0.0;
	}

	return Plugin_Continue;
}

public void CookieMenuHandler_ShowHealth(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if (action == CookieMenuAction_DisplayOption)
	{
		char cookieValue[8];
		GetClientCookie(client, g_hCookieShowHealth, cookieValue, sizeof(cookieValue));

		if (StrEqual(cookieValue, "off"))
		{
			Format(buffer, maxlen, "Show Health: Off");
		}
		else
		{
			Format(buffer, maxlen, "Show Health: On");
		}
	}
	else if (action == CookieMenuAction_SelectOption)
	{
		char cookieValue[8];
		GetClientCookie(client, g_hCookieShowHealth, cookieValue, sizeof(cookieValue));

		if (StrEqual(cookieValue, "off"))
		{
			SetClientCookie(client, g_hCookieShowHealth, "on");
		}
		else
		{
			SetClientCookie(client, g_hCookieShowHealth, "off");
		}

		ShowCookieMenu(client);
	}
}

bool IsShowHealthEnabledForClient(int client)
{
	char cookieValue[8];
	GetClientCookie(client, g_hCookieShowHealth, cookieValue, sizeof(cookieValue));

	if (StrEqual(cookieValue, "off"))
	{
		return false;
	}

	return true;
}

public void OnMapStart()
{
	g_iMapCampaign = -1;
	CreateTimer(1.0, Timer_ShowHealth, _, TIMER_REPEAT);
}

public Action Timer_ShowHealth(Handle timer)
{
	if (!g_hEnabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if (IsCampaignMap())
	{
		return Plugin_Continue;
	}

	// bms_match's status page (bms_status_page = 2) owns the hint panel and
	// draws "Show Health: N" itself as the first line; both writers would
	// overwrite each other every second. The beacon cvar is maintained by
	// bms_match's 1 Hz status timer (it reads 0 on campaign maps / after a
	// match, so health comes back on its own there).
	static ConVar hStatusActive;

	if (hStatusActive == null)
	{
		hStatusActive = FindConVar("bms_status_active");
	}

	if (hStatusActive != null && hStatusActive.BoolValue)
	{
		return Plugin_Continue;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsPlayerAlive(client))
		{
			continue;
		}

		if (!IsShowHealthEnabledForClient(client))
		{
			continue;
		}

		if (g_hOnHitOnly.BoolValue && GetGameTime() - g_fLastHurt[client] > 5.0)
		{
			continue;
		}

		char buffer[64];
		Format(buffer, sizeof(buffer), "Show Health: %i", GetClientHealth(client));

		switch (g_hTextArea.IntValue)
		{
			case AREA_CENTER:
			{
				PrintCenterText(client, "%s", buffer);
			}
			default:
			{
				PrintHintText(client, "%s", buffer);
			}
		}
	}

	return Plugin_Continue;
}
