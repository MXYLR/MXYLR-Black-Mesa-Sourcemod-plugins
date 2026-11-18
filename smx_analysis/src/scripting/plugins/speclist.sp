#pragma semicolon 1

#include <sourcemod>

public Plugin myinfo =
{
	name = "BM Spectator list",
	author = "Alienmario",
	description = "A plugin for showing spectators",
	version = "1.0.0",
	url = "https://forums.alliedmods.net/"
};

#define UPDATE_INTERVAL 0.5

Handle g_hTimer;
int g_iTickCount;

public void OnPluginStart()
{
	g_hTimer = CreateTimer(UPDATE_INTERVAL, Timer_Update, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	g_iTickCount = 0;
}

public Action Timer_Update(Handle timer)
{
	// bms_match 把状态页挪到 KeyHintText 通道上时, 这里就不要再写同一条
	// 消息了 —— 两边都是 1Hz/2Hz 地覆盖对方, 玩家只会看到闪烁。
	// 独立编译(没有 bms_match)时两个 FindConVar 都是 null, 照常工作。
	static ConVar hKeyHint;
	static ConVar hStatusActive;
	static bool bLookedUp;

	if (!bLookedUp)
	{
		hKeyHint = FindConVar("bms_status_keyhint");
		hStatusActive = FindConVar("bms_status_active");
		bLookedUp = true;
	}

	if (hKeyHint != null && hKeyHint.BoolValue
		&& hStatusActive != null && hStatusActive.BoolValue)
	{
		return Plugin_Continue;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsClientObserver(client))
		{
			continue;
		}

		char specList[256];
		BuildSpecList(client, specList, sizeof(specList));

		if (specList[0])
		{
			Client_PrintKeyHintText(client, "Spectators: %s", specList);
		}
	}

	return Plugin_Continue;
}

void BuildSpecList(int target, char[] buffer, int maxlen)
{
	buffer[0] = '\0';

	char name[MAX_NAME_LENGTH];

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsClientObserver(client))
		{
			continue;
		}

		int obsTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

		if (obsTarget != target)
		{
			continue;
		}

		GetClientName(client, name, sizeof(name));

		if (buffer[0])
		{
			Format(buffer, maxlen, "%s, %s", buffer, name);
		}
		else
		{
			Format(buffer, maxlen, "%s", name);
		}
	}
}

void Client_PrintKeyHintText(int client, const char[] format, any ...)
{
	static UserMsg userMessageId = INVALID_MESSAGE_ID;

	if (userMessageId == INVALID_MESSAGE_ID)
	{
		userMessageId = GetUserMessageId("KeyHintText");
	}

	if (userMessageId == INVALID_MESSAGE_ID)
	{
		return;
	}

	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 3);

	Handle msg = StartMessageOne("KeyHintText", client);
	BfWriteByte(msg, 1);
	BfWriteString(msg, buffer);
	EndMessage();
}
