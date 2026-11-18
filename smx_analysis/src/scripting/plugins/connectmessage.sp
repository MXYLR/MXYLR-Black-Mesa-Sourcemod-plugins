#pragma semicolon 1

#include <sourcemod>
#include <geoip>

public Plugin myinfo =
{
	name = "Connect MSG",
	author = "Unknown",
	description = "Provides Info of the player when he joins",
	version = "1.0",
	url = "https://forums.alliedmods.net/"
};

ConVar g_hConnectMsg;
ConVar g_hDisconnectMsg;

char g_sCountry[MAXPLAYERS + 1][46];

// 单人战役判据 (与 fast_spawn / bms_match 同一条规则: 地图名 bm_c<数字>*).
// [CONNECT]/[DISCONNECT] 是死斗服的进服提示, 单人战役不该出现在聊天框里。
// -1 = 本图还没判过, 0 = 死斗, 1 = 战役.
int g_iMapCampaign = -1;

bool IsCampaignMap()
{
	if (g_iMapCampaign == -1) {
		char sMap[PLATFORM_MAX_PATH];
		GetCurrentMap(sMap, sizeof(sMap));
		g_iMapCampaign = (strncmp(sMap, "bm_c", 4) == 0
			&& sMap[4] >= '0' && sMap[4] <= '9') ? 1 : 0;
	}
	return g_iMapCampaign == 1;
}

public void OnMapStart()
{
	g_iMapCampaign = -1;
}

public void OnPluginStart()
{
	g_hConnectMsg = CreateConVar("sm_connectmsg", "1", "Shows a connect message in the chat once a player joins.", FCVAR_NOTIFY);
	g_hDisconnectMsg = CreateConVar("sm_disconnectmsg", "1", "Shows a disconnect message in the chat once a player leaves.", FCVAR_NOTIFY);
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	char ip[32];
	GetClientIP(client, ip, sizeof(ip));

	char ccode[3];

	if (GeoipCode2(ip, ccode))
	{
		Format(g_sCountry[client], sizeof(g_sCountry[]), "%s", ccode);
	}
	else
	{
		Format(g_sCountry[client], sizeof(g_sCountry[]), "Unknown Country");
	}
}

public void OnClientDisconnect(int client)
{
	if (!g_hDisconnectMsg.BoolValue || client < 1 || client > MaxClients)
	{
		return;
	}

	if (!IsClientInGame(client))
	{
		return;
	}

	if (IsCampaignMap())
	{
		return;
	}

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));

	char auth[32];
	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true);

	PrintToChatAll("[DISCONNECT] %s (%s) has left the server from [%s]", name, auth, g_sCountry[client]);
}

public void OnClientPostAdminCheck(int client)
{
	if (!g_hConnectMsg.BoolValue || client < 1 || client > MaxClients)
	{
		return;
	}

	if (IsCampaignMap())
	{
		return;
	}

	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));

	char auth[32];
	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true);

	PrintToChatAll("[CONNECT] %s (%s) has joined the server from [%s]", name, auth, g_sCountry[client]);
}
