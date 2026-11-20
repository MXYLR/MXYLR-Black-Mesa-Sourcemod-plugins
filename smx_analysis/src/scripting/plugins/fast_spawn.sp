#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
	name = "fastspawn for players",
	author = "Alienmario",
	description = "Enables player respawn [sm_fastspawn_time] seconds after death",
	version = "1.0.0",
	url = "https://forums.alliedmods.net/"
};

ConVar g_hEnabled;
ConVar g_hRespawnTime;
ConVar g_hBatch;

float g_fDeathTime[MAXPLAYERS + 1];
int g_iBatchTick = -1;
int g_iBatchCount;

// 当前地图是不是单人战役: -1 = 还没判定, 0 = 不是, 1 = 是。见 FS_Campaign()。
// Whether the current map is a singleplayer campaign: -1 = not yet determined, 0 = no, 1 = yes. See FS_Campaign().
int g_iMapCampaign = -1;

public void OnPluginStart()
{
	g_hEnabled = CreateConVar("sm_fastspawn", "1", "Enables player respawn [sm_fastspawn_time] seconds after death", FCVAR_NOTIFY);
	g_hRespawnTime = CreateConVar("sm_fastspawn_time", "0.0", "Sets how long to wait until player can respawn (0 = instant)", FCVAR_NOTIFY);
	g_hBatch = CreateConVar("sm_fastspawn_batch", "4", "Max players respawned per game tick (stagger burst respawns; lower = smoother but slower)", FCVAR_NOTIFY);

	HookEvent("player_death", Event_Death);
	HookEvent("player_spawn", Event_PlayerSpawn);

	AutoExecConfig(true, "fastspawn");
	LoadTranslations("fast_spawn.phrases");
	// NOTE: the console command is "fastspawn" (not sm_fastspawn) - the engine
	// refuses to link a cfg-set ConVar whose name is also a ConCommand
	// ("unable to link sm_fastspawn and sm_fastspawn because one or more is a
	// ConCommand"), which made server.cfg settings for the cvar unreliable.
	RegConsoleCmd("fastspawn", Cmd_FastSpawn, "Query or toggle fast spawn (admins)");
	RegConsoleCmd("sm_fs", Cmd_FastSpawn, "Query or toggle fast spawn (admins)");
}

public void OnConfigsExecuted()
{
	// 强制零秒重生:任何 cfg 的执行顺序/内容都无法把它改回非零。
	// Force zero-second respawn: no cfg execution order/content can set it back to non-zero.
	g_hRespawnTime.SetFloat(0.0);
}

// --------------------------------------------------------------- 单人战役判定
// --------------------------------------------------------------- Singleplayer campaign detection
//
// 这套插件原本只为死亡竞赛写, 但同一个 SourceMod 装在两个环境里跑
// This plugin was originally written only for deathmatch, but the same SourceMod installation runs in two environments
// (单人战役 listen server + 死亡服), 而 fast_spawn 的每条行为都只在 DM 下成立:
// (singleplayer campaign listen server + deathmatch server), and every fast_spawn behavior only makes sense under DM:
//
//   * 单人战役里死亡 = 读档, 不是重生。零秒重生会把玩家从刚读的档里拽出来,
//   * In singleplayer campaign, death = load save, not respawn. Instant respawn yanks the player out of the just-loaded save,
//     把武器掉到地上更会直接毁掉手上的装备。
//     and dropping weapons to the ground outright destroys the equipment in hand.
//   * FS_OnTakeDamageAlivePost 的「致死时把武器掉到地上」只在 DM 下成立;
//   * FS_OnTakeDamageAlivePost's "drop weapons to the ground on lethal hit" only makes sense under DM;
//     在战役里动了玩家手里的东西, 读档回来的装备就没了。(历史上这条曾在
//     touching what the player holds in campaign means the equipment is gone after loading a save. (Historically this was once done in
//     OnTakeDamage 里按原始伤害预测致死, 因回调按 SDKHook() 注册顺序=插件加载
//     OnTakeDamage by predicting lethality from raw damage, because callbacks run in SDKHook() registration order = plugin load
//     顺序执行, BMAG 字母序在 tau_mp 之前 → 看到的是未经 tau_mp 跌落伤害封顶的
//     order; BMAG sorts alphabetically before tau_mp → it saw raw damage before tau_mp's fall-damage cap was applied;
//     原始伤害; 现在改成扣血之后按实时血量判定, 不再有这类顺序问题。)
//     now it checks live health after damage is applied, so this ordering issue no longer exists.)
//
// 判据: 战役地图全部形如 bm_c<数字>*(bm_c0a0a … bm_c5a1a); DM 侧地图是
// Criterion: all campaign maps look like bm_c<digit>* (bm_c0a0a … bm_c5a1a); DM-side maps are
// dm_*/de_*/bm_bunnyrace_beta2, **没有任何地图以 bm_c<数字> 开头**, 所以前缀
// dm_*/de_*/bm_bunnyrace_beta2, **no map starts with bm_c<digit>**, so the prefix
// 匹配安全。判定写错时默认偏向 DM(即保留本插件原有行为)。
// match is safe. If the detection is wrong it defaults toward DM (i.e. keeps the plugin's original behavior).
bool FS_Campaign()
{
	if (g_iMapCampaign == -1)
	{
		char sMap[PLATFORM_MAX_PATH];
		GetCurrentMap(sMap, sizeof(sMap));

		g_iMapCampaign = (strncmp(sMap, "bm_c", 4) == 0
			&& sMap[4] >= '0' && sMap[4] <= '9') ? 1 : 0;

		LogMessage("[fast_spawn] map \"%s\" -> %s", sMap, g_iMapCampaign
			? "singleplayer campaign: fast spawn disabled"
			: "deathmatch: fast spawn enabled");
	}

	return g_iMapCampaign == 1;
}

// 所有 fast_spawn 行为的统一闸门: cvar 开着 **且** 不在战役地图里。
// Unified gate for all fast_spawn behavior: cvar enabled **and** not on a campaign map.
bool FS_Active()
{
	return g_hEnabled.BoolValue && !FS_Campaign();
}

public Action Cmd_FastSpawn(int client, int args)
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}

	char sArg[16];
	if (args >= 1)
	{
		GetCmdArg(1, sArg, sizeof(sArg));
	}

	// bare command: report current state to anyone
	if (!strlen(sArg))
	{
		if (g_hEnabled.BoolValue)
		{
			PrintToChat(client, "%t", "fs_status_on", g_hRespawnTime.FloatValue);
		}
		else
		{
			PrintToChat(client, "%t", "fs_status_off");
		}
		PrintToChat(client, "%t", "fs_usage");
		return Plugin_Handled;
	}

	if (!CheckCommandAccess(client, "fastspawn", ADMFLAG_GENERIC, true))
	{
		PrintToChat(client, "%t", "fs_no_admin");
		return Plugin_Handled;
	}

	bool bNew;
	if (StrEqual(sArg, "on", false) || StrEqual(sArg, "1", false) || StrEqual(sArg, "enable", false))
	{
		bNew = true;
	}
	else if (StrEqual(sArg, "off", false) || StrEqual(sArg, "0", false) || StrEqual(sArg, "disable", false))
	{
		bNew = false;
	}
	else if (StrEqual(sArg, "toggle", false))
	{
		bNew = !g_hEnabled.BoolValue;
	}
	else
	{
		PrintToChat(client, "%t", "fs_usage");
		return Plugin_Handled;
	}

	if (bNew == g_hEnabled.BoolValue)
	{
		if (g_hEnabled.BoolValue)
		{
			PrintToChat(client, "%t", "fs_status_on", g_hRespawnTime.FloatValue);
		}
		else
		{
			PrintToChat(client, "%t", "fs_status_off");
		}
		return Plugin_Handled;
	}

	g_hEnabled.SetInt(bNew ? 1 : 0);

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));
	PrintToChatAll("%t", bNew ? "fs_changed_on" : "fs_changed_off", sName);

	return Plugin_Handled;
}

public void OnClientPutInServer(int client)
{
	g_fDeathTime[client] = 0.0;
	if (!SDKHookEx(client, SDKHook_OnTakeDamageAlivePost, FS_OnTakeDamageAlivePost))
	{
		// 钩不上 = 死亡时只掉当前手持武器(原生行为), 留个明确信号。
		// Hook failure = only the currently held weapon drops on death (native behavior); leave a clear signal.
		LogError("[fast_spawn] SDKHook_OnTakeDamageAlivePost failed on client %d", client);
	}
}

public void OnClientDisconnect(int client)
{
	g_fDeathTime[client] = 0.0;
}

public Action Event_Death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (client && IsClientInGame(client))
	{
		g_fDeathTime[client] = GetGameTime();
	}

	return Plugin_Continue;
}

// 重生刷默认装备时武器有几率掉地上的根因: GiveDefaultItems 在 player_spawn 之后
// Root cause of weapons sometimes dropping to the ground when the default loadout is given on respawn: GiveDefaultItems runs after player_spawn
// (CHL2MP_Player::Spawn 里 BaseClass::Spawn() 返回后才调)刷武器, 走
// (called in CHL2MP_Player::Spawn only after BaseClass::Spawn() returns) to give weapons, via
// GiveNamedItem → DispatchSpawn → 武器 Spawn(FallInit) → Touch(this) →
// GiveNamedItem → DispatchSpawn → weapon Spawn(FallInit) → Touch(this) →
// DefaultTouch → CHL2MP_Player::BumpWeapon。BumpWeapon 里有一道视线门:
// DefaultTouch → CHL2MP_Player::BumpWeapon. Inside BumpWeapon there is a line-of-sight gate:
//   if (!pWeapon->FVisible(this, MASK_SOLID) && !(GetFlags() & FL_NOTARGET))
//       return false;
// 当玩家被 spawn_distribute 传到静止 bot 身上(其位置占用判定刻意排除 bot, 见
// When a player is teleported by spawn_distribute onto a stationary bot (its position occupancy check deliberately excludes bots, see
// spawn_distribute.sp), 武器出生在 bot 的 bbox 里 → FVisible 从武器中心到玩家
// spawn_distribute.sp), the weapon spawns inside the bot's bbox → FVisible's trace from the weapon center to the player's
// 眼睛的 trace 被 bot 挡住(startsolid)→ 返回 false → BumpWeapon 拒绝装备 →
// eyes is blocked by the bot (startsolid) → returns false → BumpWeapon refuses to equip →
// FallInit 的 FallThink 把武器掉到地上(有几率, 取决于是否恰好叠到 bot)。
// FallInit's FallThink drops the weapon to the ground (probabilistically, depending on whether it happens to overlap the bot).
// 其余门(IsAllowedToPickupWeapons/pOwner/Weapon_CanUse/CanHavePlayerItem)经
// All other gates (IsAllowedToPickupWeapons/pOwner/Weapon_CanUse/CanHavePlayerItem) were
// 源码核对全部恒真, FVisible 是唯一会间歇失败的门。
// verified against the source to always be true; FVisible is the only gate that fails intermittently.
// 修法: player_spawn 先于 GiveDefaultItems, 在这里给玩家挂 FL_NOTARGET, 使上面的
// Fix: player_spawn fires before GiveDefaultItems, so set FL_NOTARGET on the player here, making the above gate's
// 门第二项 !(FL_NOTARGET) 为 false → 整条门为 false → 绕过 FVisible 直接装备;
// second term !(FL_NOTARGET) false → the whole gate is false → bypass FVisible and equip directly;
// 下一帧 RequestFrame 再清掉。FL_NOTARGET 只影响这一帧的视线/AI 判定, HL2MP
// RequestFrame clears it on the next frame. FL_NOTARGET only affects line-of-sight/AI checks for this one frame, HL2MP
// 无 NPC 敌人(全是玩家), 无副作用。仅在 FS_Active() 为真时生效(与致死时掉武器的
// has no NPC enemies (all players), so no side effects. Only applies when FS_Active() is true (consistent with the on-lethal-hit weapon drop
// FS_OnTakeDamageAlivePost 一致; 比赛期 bms_match 置 sm_fastspawn=0, 单人战役由
// in FS_OnTakeDamageAlivePost; during a match bms_match sets sm_fastspawn=0, and the singleplayer campaign is
// FS_Campaign() 关掉, 两种情况都不干预)。
// turned off by FS_Campaign(), so neither case is affected).
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!FS_Active())
	{
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	SetEntityFlags(client, GetEntityFlags(client) | FL_NOTARGET);
	RequestFrame(FS_ClearNoTarget, GetClientUserId(client));

	return Plugin_Continue;
}

void FS_ClearNoTarget(any iUserID)
{
	int client = GetClientOfUserId(view_as<int>(iUserID));
	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	SetEntityFlags(client, GetEntityFlags(client) & ~FL_NOTARGET);
}

// 玩家被打死时, 手里的武器掉到地上(可以被别人捡), 而不是跟着尸体消失。
// When a player is killed, the weapons in hand drop to the ground (others can pick them up) instead of vanishing with the corpse.
//
// 原生只掉"当前手持"那一把: CBaseCombatCharacter::Event_Killed 调
// Natively only the "currently held" one drops: CBaseCombatCharacter::Event_Killed calls
// Weapon_Drop(m_hActiveWeapon)(DEADPLAYER_WEAPONS = GR_PLR_DROP_GUN_ACTIVE),
// 其余槽位本来由 PlayerDeathThink 里的 RemoveAllItems 清掉 —— 但 fast_spawn 的
// the other slots are normally cleared by RemoveAllItems in PlayerDeathThink —— but fast_spawn's
// 零秒重生在 PlayerDeathThink 之前就 Spawn() 了(SetThink(NULL) 把它取消), 于是
// instant respawn calls Spawn() before PlayerDeathThink (SetThink(NULL) cancels it), so
// 非主动武器会被带过死亡、重生后还留在身上。所以在致死落定、Event_Killed 之前,
// non-active weapons are carried through death and remain on the player after respawn. So once the lethal hit is settled and before Event_Killed,
// 把 6 个槽位全部主动 Drop 出去: 武器落地, 玩家重生时是干净的默认装备。
// actively Drop all 6 slots: the weapons land on the ground, and the player respawns with a clean default loadout.
//
// 判定点必须是 OnTakeDamageAlive 的 **Post**, 不能是 OnTakeDamage(槽 68):
// The check point must be OnTakeDamageAlive's **Post**, not OnTakeDamage (slot 68):
//   0x104780D0 CBasePlayer::OnTakeDamage 先扣护甲(m_ArmorValue 在 player+0xDA4,
//   0x104780D0 CBasePlayer::OnTakeDamage first applies armor (m_ArmorValue at player+0xDA4,
//   最多吃掉 80% 伤害), 再调 CBaseEntity::OnTakeDamage(0x100FAC20), 后者才派发
//   absorbing at most 80% of damage), then calls CBaseEntity::OnTakeDamage (0x100FAC20), which dispatches
//   slot 0x490(OnTakeDamageAlive → 扣血) → 检查 health<=0 → slot 0x120(Event_Killed)。
//   slot 0x490 (OnTakeDamageAlive → apply damage) → check health<=0 → slot 0x120 (Event_Killed).
// 所以槽 68 钩子看到的是**护甲吸收前**的原始伤害。DM 每张图都摆了 item_battery
// So a slot 68 hook sees **pre-armor-absorption** raw damage. Every DM map places item_battery
// (拾取加护甲), 玩家只要捡过电池, 一次 raw damage >= health 的打击被护甲吃掉
// (pickup grants armor), so if a player ever picked up a battery, a hit with raw damage >= health has part
// 一部分后玩家仍然活着 —— 槽 68 上按原始伤害判死会误判。Post 钩子在扣血之后、
// absorbed by armor and the player is still alive —— judging death by raw damage on slot 68 would misjudge. The Post hook, after damage is applied and
// Event_Killed 之前, 直接读当前血量判死活, 不再预测伤害。
// before Event_Killed, reads current health directly to judge alive/dead, no longer predicting damage.
// 只在 FS_Active() 为真时生效 —— 比赛期 bms_match 把 sm_fastspawn 置 0(保留
// Only applies when FS_Active() is true —— during a match bms_match sets sm_fastspawn to 0 (keeping
// 原生掉落), 单人战役由 FS_Campaign() 关掉(战役里死亡=读档, 别动玩家手里的东西)。
// native drops); the singleplayer campaign is turned off by FS_Campaign() (in campaign death = load save, don't touch what the player holds).
public void FS_OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom)
{
	if (!FS_Active())
	{
		return;
	}

	if (victim < 1 || victim > MaxClients || !IsClientInGame(victim))
	{
		return;
	}

	if (GetClientHealth(victim) > 0)
	{
		return;
	}

	// bot 不铺满一地武器: 只留原生掉落(Event_Killed 掉"当前手持"那一把), 其余
	// Bots don't litter the ground with weapons: keep only the native drop (Event_Killed drops the "currently held" one); the other
	// 槽位在这里直接删掉 —— 不能留着。0 秒重生在 PlayerDeathThink 之前就 Spawn()
	// slots are deleted here directly —— they cannot be kept. Instant respawn calls Spawn() before PlayerDeathThink,
	// 了, 旧武器不会像原生那样被 RemoveAllItems 清掉; 而重生时 GiveDefaultItems
	// so old weapons are not cleared by RemoveAllItems as in native; and on respawn GiveDefaultItems
	// 对已经拥有的武器走 dedup 不再补发(见 BumpWeapon/Weapon_OwnsThisType), 偏偏
	// dedups already-owned weapons and does not re-give them (see BumpWeapon/Weapon_OwnsThisType), yet
	// m_hActiveWeapon 已被死亡清空 → bot 两手空空, 地上那把旧枪又因为"同型武器
	// m_hActiveWeapon was already cleared by death → the bot has empty hands, and the old gun on the ground can't be picked up because "a weapon of the same type
	// 还在背包里"捡不起来。删掉非手持武器后重生就是一套干净的默认装备。
	// is still in the inventory". After deleting non-held weapons, respawn gives a clean default loadout.
	if (IsFakeClient(victim))
	{
		FS_RemoveNonActiveWeapons(victim);
		return;
	}

	FS_DropWeapons(victim);
}

void FS_RemoveNonActiveWeapons(int client)
{
	int iActive = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	for (int slot = 0; slot <= 5; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);

		if (weapon == -1 || weapon == iActive)
		{
			continue;
		}

		char sClass[64];
		GetEntityClassname(weapon, sClass, sizeof(sClass));

		if (FS_IsCarriedItem(sClass))
		{
			continue;
		}

		RemovePlayerItem(client, weapon);
		RemoveEntity(weapon);
	}
}

// 手雷/蚁狮/遥控炸弹/绊雷是捡来的消耗品, 不是可以扔地上再捡回来的枪:
// Grenades/snarks/satchels/trip mines are picked-up consumables, not guns that can be dropped on the ground and picked back up:
// Drop() 对它们不产生可拾取的世界实体, FS_DropWeapons 会落到 RemoveEntity
// Drop() does not produce a pickable world entity for them, so FS_DropWeapons falls into the RemoveEntity
// 分支, 等于死亡时被静默删掉。DM 地图上的补给是 item_weapon_frag 这类一次性
// branch, i.e. they get silently deleted on death. Supplies on DM maps are one-shot
// 拾取物, 删了就再也拿不到(slot5 再也切不出手雷), 所以这些留在身上, 枪照常掉。
// pickups like item_weapon_frag; once deleted they can never be obtained again (slot5 can never switch to a grenade again), so these stay on the player; guns still drop as usual.
bool FS_IsCarriedItem(const char[] sClass)
{
	return StrEqual(sClass, "weapon_frag") || StrEqual(sClass, "weapon_snark")
		|| StrEqual(sClass, "weapon_satchel") || StrEqual(sClass, "weapon_tripmine");
}

void FS_DropWeapons(int client)
{
	for (int slot = 0; slot <= 5; slot++)
	{
		int weapon;
		while ((weapon = GetPlayerWeaponSlot(client, slot)) != -1)
		{
			char sClass[64];
			GetEntityClassname(weapon, sClass, sizeof(sClass));

			if (FS_IsCarriedItem(sClass))
			{
				break;
			}

			SDKHooks_DropWeapon(client, weapon);

			// 掉不下来的(伪武器/没有 owner 的)直接移除, 别在这里打转。
			// Ones that can't drop (pseudo-weapons / no owner) are removed directly; don't loop here.
			if (GetPlayerWeaponSlot(client, slot) == weapon)
			{
				RemovePlayerItem(client, weapon);
				RemoveEntity(weapon);
			}
		}
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!FS_Active())
	{
		return Plugin_Continue;
	}

	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	if (!FS_IsRespawnEligible(client))
	{
		return Plugin_Continue;
	}

	if (g_fDeathTime[client] > 0.0 && GetGameTime() - g_fDeathTime[client] >= g_hRespawnTime.FloatValue)
	{
		// Stagger burst respawns: at most sm_fastspawn_batch players respawn per
		// game tick. A kill burst (many deaths in one tick) would otherwise fire
		// N DispatchSpawn calls in a single tick and spike the server. Deferred
		// players keep their death time and retry on the next tick.
		int iTick = GetGameTickCount();
		int iBatch = g_hBatch.IntValue;

		if (iBatch <= 0)
		{
			iBatch = 1;
		}

		if (iTick != g_iBatchTick)
		{
			g_iBatchTick = iTick;
			g_iBatchCount = 0;
		}

		if (g_iBatchCount >= iBatch)
		{
			return Plugin_Continue;
		}

		g_iBatchCount++;
		g_fDeathTime[client] = 0.0;
		// Defer the real DispatchSpawn to a frame boundary. Calling Spawn()
		// re-entrantly from OnPlayerRunCmd (i.e. inside PhysicsSimulate /
		// PlayerRunCommand) makes the death->alive transition land in the same
		// client update as the death, so the client interpolates back to the
		// death origin instead of snapping to the spawn point ("respawn in
		// place"), and the whole loadout give runs mid-movement (lag / weapon
		// spawn spam). RequestFrame runs at the start of the next frame,
		// outside the movement loop.
		RequestFrame(FS_RespawnFrame, GetClientUserId(client));
	}

	return Plugin_Continue;
}

// Deferred respawn target for human players (see OnPlayerRunCmd). Runs at a
// frame boundary, outside PlayerRunCommand/PhysicsSimulate, so Spawn() is not
// re-entrant. Re-validate eligibility: the player may have died again,
// disconnected, or been respawned by another plugin in the meantime.
void FS_RespawnFrame(any iUserID)
{
	int client = GetClientOfUserId(view_as<int>(iUserID));

	if (client < 1 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	if (!FS_IsRespawnEligible(client))
	{
		return;
	}

	DispatchSpawn(client);
}

public void OnMapStart()
{
	// 换图后判据要重算(缓存跨图会错判)
	// The criterion must be recomputed after a map change (a cache carried across maps would misjudge)
	g_iMapCampaign = -1;

	// Server-side bots never fire OnPlayerRunCmd (they call PlayerRunCommand
	// directly, bypassing the engine's RunPlayerMove - cf. hl2mp_bot_temp.cpp),
	// so poll them on a timer for instant respawns as well.
	CreateTimer(0.1, Timer_RespawnBots, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RespawnBots(Handle timer)
{
	if (!FS_Active())
	{
		return Plugin_Continue;
	}

	// Batch-cap bot respawns the same way human respawns are capped, so a burst
	// of bot deaths can't all DispatchSpawn in the same timer tick either.
	int iBatch = g_hBatch.IntValue;

	if (iBatch <= 0)
	{
		iBatch = 1;
	}

	int iSpawned = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (iSpawned >= iBatch)
		{
			break;
		}

		if (!IsClientInGame(i) || !IsFakeClient(i) || !FS_IsRespawnEligible(i))
		{
			continue;
		}

		if (g_fDeathTime[i] > 0.0 && GetGameTime() - g_fDeathTime[i] >= g_hRespawnTime.FloatValue)
		{
			g_fDeathTime[i] = 0.0;
			DispatchSpawn(i);
			iSpawned++;
		}
	}

	return Plugin_Continue;
}

// Dead players keep their team in BM DM (hl2mp semantics: participants are
// team 0 in FFA, voluntary/forced spectators are moved to team 1 by
// ChangeTeam and never die). The original check (GetClientTeam <= 1, CS
// semantics where team 0 = unassigned/spectator) blocked every dead
// participant on team 0 - instant respawn never fired for anyone.
bool FS_IsRespawnEligible(int client)
{
	if (IsPlayerAlive(client))
	{
		return false;
	}

	if (GetClientTeam(client) == 1)
	{
		return false;
	}

	// 主动观战(FIXED=3/IN_EYE=4/CHASE=5/POI=6/ROAMING=7)不允许被零秒重生
	// Active spectating (FIXED=3/IN_EYE=4/CHASE=5/POI=6/ROAMING=7) must not be
	// 拉回比赛;死亡镜头(DEATHCAM=1/FREEZECAM=2)是临死瞬间的过渡状态,
	// pulled back into the match by instant respawn; the death camera (DEATHCAM=1/FREEZECAM=2) is the transitional state at the moment of death,
	// 仍走零秒重生。
	// and still goes through instant respawn.
	if (GetEntProp(client, Prop_Send, "m_iObserverMode") >= 3)
	{
		return false;
	}

	return true;
}
