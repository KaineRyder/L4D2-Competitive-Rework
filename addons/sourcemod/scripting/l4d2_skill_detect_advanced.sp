#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>

#define PLUGIN_VERSION "1.2.5-20260914"

#define MAX_EDICTS 2048

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_BOOMER 2
#define ZC_CHARGER 6
#define ZC_TANK 8

#define CONTROL_SCAN_INTERVAL 0.10
#define HITTABLE_OWNER_TIME 1.00
#define DAMAGE_DEDUPE_TIME 0.20
#define HITTABLE_DEDUPE_TIME 0.60
#define CHARGER_TEAMKILL_CHARGE_GRACE 0.35
#define CHARGER_TEAMKILL_SHOT_TIME 0.10
#define CHARGER_TEAMKILL_MAX_CHARGE_TIME 12.0
#define CHARGER_TEAMKILL_DEATH_GRACE 1.00
#define CHARGER_TEAMKILL_EVENT_DEDUPE 0.25

#define MULTI_CONTROL_MIN 2
#define MULTI_CONTROL_MAX 4

public Plugin myinfo =
{
	name = "L4D2 Skill Detect - Advanced Infected Highlights",
	author = "Zonemod",
	description = "检测并播报多特感控制、冲锋者枪杀、撞击、喷吐和 Tank 高光动作。",
	version = PLUGIN_VERSION,
	url = "https://github.com/fbef0102/L4D1_2-Plugins"
};

ConVar g_hCvarEnable;
ConVar g_hCvarMultiControl;
ConVar g_hCvarCharger;
ConVar g_hCvarChargerTeamKill;
ConVar g_hCvarBoomer;
ConVar g_hCvarTankRock;
ConVar g_hCvarTankHittable;
ConVar g_hCvarTankPunch;
ConVar g_hCvarChargerWindow;
ConVar g_hCvarBoomerWindow;
ConVar g_hCvarTankPunchWindow;

Handle g_hControlTimer;
Handle g_hChargerReset[MAXPLAYERS + 1];
Handle g_hBoomerReset[MAXPLAYERS + 1];
Handle g_hTankPunchReset[MAXPLAYERS + 1];

// 多特感控制状态：一次控制表示一个特感正在控制一名幸存者。
int g_iControlCount;
int g_iControlAnnounced;
bool g_bControlRoundEndAnnounced;
bool g_bRoundEnded;

// 冲锋者撞击状态：同一次冲锋检测窗口内，每名受害者只记录一次。
bool g_bChargerVictim[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_iChargerVictimCount[MAXPLAYERS + 1];
int g_iChargerAnnounced[MAXPLAYERS + 1];
float g_fChargerLastHit[MAXPLAYERS + 1];

// 冲锋期间冲锋者被枪械击杀时的枪械伤害状态。
int g_iChargerGunDamage[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_iChargerGunShots[MAXPLAYERS + 1][MAXPLAYERS + 1];
float g_fChargerGunLastShot[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_bChargerGunLastShotgun[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_bChargerGunTracking[MAXPLAYERS + 1];
bool g_bChargerGunLethal[MAXPLAYERS + 1];
bool g_bChargerGunLethalDuringCharge[MAXPLAYERS + 1];
int g_iChargerGunLethalAttacker[MAXPLAYERS + 1];
int g_iChargerLastGunAttacker[MAXPLAYERS + 1];
float g_fChargerLastChargingGun[MAXPLAYERS + 1];
bool g_bChargerChargeActive[MAXPLAYERS + 1];
bool g_bChargerChargeHitTarget[MAXPLAYERS + 1];
float g_fChargerChargeStart[MAXPLAYERS + 1];
float g_fChargerChargeEndGrace[MAXPLAYERS + 1];

// Boomer 喷吐状态：同一次喷吐检测窗口内，每名受害者只记录一次。
bool g_bBoomerVictim[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_iBoomerVictimCount[MAXPLAYERS + 1];
int g_iBoomerAnnounced[MAXPLAYERS + 1];
float g_fBoomerLastHit[MAXPLAYERS + 1];

// Tank 拳击状态：同一次拳击检测窗口内，每名受害者只记录一次。
bool g_bTankPunchVictim[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_iTankPunchVictimCount[MAXPLAYERS + 1];
int g_iTankPunchAnnounced[MAXPLAYERS + 1];
float g_fTankPunchLastHit[MAXPLAYERS + 1];

// 打铁伤害会保留到 player_incapacitated_start 事件，用于确认是否真的倒地。
int g_iRecentHittableTank[MAXPLAYERS + 1];
float g_fRecentHittableTime[MAXPLAYERS + 1];

// 石头命中和打铁倒地播报使用短暂的去重窗口，避免同一事件重复播报。
int g_iLastRockTank[MAXPLAYERS + 1];
float g_fLastRockAnnounce[MAXPLAYERS + 1];
int g_iLastHittableTank[MAXPLAYERS + 1];
float g_fLastHittableAnnounce[MAXPLAYERS + 1];

// 记录物理物体的实体输出，用于追踪 Tank 击中的物理物体。
bool g_bHittableHooked[MAX_EDICTS];
int g_iLastHittableTankByEntity[MAX_EDICTS];
float g_fLastHittableEntityHit[MAX_EDICTS];
int g_iLastHittableOwnerTank;
float g_fLastHittableOwnerHit;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, errMax, "此插件仅支持 Left 4 Dead 2。");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("l4d2_skill_detect_advanced.phrases");

	g_hCvarEnable = CreateConVar(
		"l4d2_skill_advanced_enable", "1",
		"启用特感高光动作播报。",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarMultiControl = CreateConVar(
		"l4d2_skill_advanced_multi_control", "1",
		"播报特感队伍达到 2/3/4 控的里程碑。",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarCharger = CreateConVar(
		"l4d2_skill_advanced_charger", "1",
		"播报一次冲锋撞到 2/3/4 名不同幸存者。",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarChargerTeamKill = CreateConVar(
		"l4d2_skill_advanced_charger_teamkill", "1",
		"播报枪械击杀冲锋中的冲锋者；集火击杀时显示协助者和伤害。",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarBoomer = CreateConVar(
		"l4d2_skill_advanced_boomer", "1",
		"播报一次喷吐命中 2/3/4 名不同幸存者。",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarTankRock = CreateConVar(
		"l4d2_skill_advanced_tank_rock", "1",
		"播报 Tank 石头命中幸存者。",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarTankHittable = CreateConVar(
		"l4d2_skill_advanced_tank_hittable", "1",
		"播报 Tank 使用打铁物体将幸存者打倒。",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarTankPunch = CreateConVar(
		"l4d2_skill_advanced_tank_punch", "1",
		"播报 Tank 一拳同时命中 2/3/4 名不同幸存者。",
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarChargerWindow = CreateConVar(
		"l4d2_skill_advanced_charger_window", "0.75",
		"最后一次冲锋撞击后，多少秒后重置多目标计数。",
		FCVAR_NOTIFY, true, 0.10, true, 3.0);
	g_hCvarBoomerWindow = CreateConVar(
		"l4d2_skill_advanced_boomer_window", "2.75",
		"最后一次喷吐命中后，多少秒后重置喷吐计数。",
		FCVAR_NOTIFY, true, 0.50, true, 6.0);
	g_hCvarTankPunchWindow = CreateConVar(
		"l4d2_skill_advanced_tank_punch_window", "0.45",
		"最后一次 Tank 拳击命中后，多少秒后重置多目标计数。",
		FCVAR_NOTIFY, true, 0.10, true, 1.5);

	AutoExecConfig(true, "l4d2_skill_detect_advanced");

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEventEx("scavenge_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEventEx("map_transition", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEventEx("mission_lost", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEventEx("finale_win", Event_RoundEnd, EventHookMode_PostNoCopy);

	HookEvent("ability_use", Event_AbilityUse, EventHookMode_Post);
	HookEventEx("charger_charge_start", Event_ChargerChargeStart, EventHookMode_Post);
	HookEventEx("charger_charge_end", Event_ChargerChargeEnd, EventHookMode_Post);
	HookEvent("charger_impact", Event_ChargerImpact, EventHookMode_Post);
	HookEventEx("charger_carry_start", Event_ChargerCarryStart, EventHookMode_Post);
	HookEvent("player_now_it", Event_PlayerNowIt, EventHookMode_Post);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_incapacitated_start", Event_PlayerIncapStart, EventHookMode_Post);
	HookEventEx("player_incapacitated", Event_PlayerIncapStart, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			OnClientPutInServer(client);
		}
	}

	g_bRoundEnded = false;
	StartControlTimer();

	CreateTimer(0.20, Timer_HookExistingHittables, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnPluginEnd()
{
	delete g_hControlTimer;
	g_hControlTimer = null;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamagePre);
			SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
		}

		delete g_hChargerReset[client];
		delete g_hBoomerReset[client];
		delete g_hTankPunchReset[client];
	}
}

public void OnMapStart()
{
	for (int entity = 0; entity < MAX_EDICTS; entity++)
	{
		g_bHittableHooked[entity] = false;
	}
	ResetHittableOwnerCache();

	g_bRoundEnded = false;
	ResetAllState();
	StartControlTimer();
	CreateTimer(0.20, Timer_HookExistingHittables, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
	g_bRoundEnded = true;
	delete g_hControlTimer;
	g_hControlTimer = null;
	ResetAllState();
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamagePre);
	SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamagePre);
	SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
	ResetClientState(client);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (entity <= MaxClients || entity >= MAX_EDICTS)
	{
		return;
	}

	if (IsHittableClass(classname))
	{
		SDKHook(entity, SDKHook_SpawnPost, OnHittableSpawned);
	}
}

public void OnEntityDestroyed(int entity)
{
	if (entity < 0 || entity >= MAX_EDICTS)
	{
		return;
	}

	g_bHittableHooked[entity] = false;
	g_iLastHittableTankByEntity[entity] = 0;
	g_fLastHittableEntityHit[entity] = 0.0;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnded = false;
	ResetAllState();
	ResetHittableOwnerCache();
	CreateTimer(0.20, Timer_HookExistingHittables, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnded = true;
	ResetAllState();
	ResetHittableOwnerCache();
}

public void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidInfected(client))
	{
		return;
	}

	char ability[64];
	event.GetString("ability", ability, sizeof(ability));

	if (StrEqual(ability, "ability_charge", false) && GetZombieClass(client) == ZC_CHARGER)
	{
		ResetChargerState(client);
		ResetChargerGunState(client);
		BeginChargerCharge(client);
	}
	else if (StrEqual(ability, "ability_vomit", false) && GetZombieClass(client) == ZC_BOOMER)
	{
		ResetBoomerState(client);
	}
}

public void Event_ChargerChargeStart(Event event, const char[] name, bool dontBroadcast)
{
	int charger = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidInfected(charger) && GetZombieClass(charger) == ZC_CHARGER)
	{
		float now = GetGameTime();
		if (!g_bChargerChargeActive[charger] ||
			g_fChargerChargeStart[charger] <= 0.0 ||
			now - g_fChargerChargeStart[charger] > CHARGER_TEAMKILL_EVENT_DEDUPE)
		{
			ResetChargerState(charger);
			ResetChargerGunState(charger);
		}
		BeginChargerCharge(charger);
	}
}

public void Event_ChargerChargeEnd(Event event, const char[] name, bool dontBroadcast)
{
	int charger = GetClientOfUserId(event.GetInt("userid"));
	EndChargerCharge(charger);
}

public void Event_ChargerImpact(Event event, const char[] name, bool dontBroadcast)
{
	int charger = GetClientOfUserId(event.GetInt("userid"));
	int victim = GetClientOfUserId(event.GetInt("victim"));
	RegisterChargerVictim(charger, victim);
	EndChargerCharge(charger, true);
}

public void Event_ChargerCarryStart(Event event, const char[] name, bool dontBroadcast)
{
	int charger = GetClientOfUserId(event.GetInt("userid"));
	int victim = GetClientOfUserId(event.GetInt("victim"));
	RegisterChargerVictim(charger, victim);
	EndChargerCharge(charger, true);
}

public void Event_PlayerNowIt(Event event, const char[] name, bool dontBroadcast)
{
	if (!event.GetBool("by_boomer") || event.GetBool("exploded"))
	{
		return;
	}

	int boomer = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	RegisterBoomerVictim(boomer, victim);
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidInfected(victim) && GetZombieClass(victim) == ZC_CHARGER)
	{
		TrackChargerGunDamage(event, victim);
		return;
	}

	if (!IsValidSurvivor(victim))
	{
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int attackerEntity = event.GetInt("attackerentid", -1);
	char weapon[64];
	event.GetString("weapon", weapon, sizeof(weapon));
	bool tankHittableFallback = IsTankHittableFallback(attacker, weapon);
	bool missingSource = attacker <= 0 && attackerEntity <= 0 && weapon[0] == '\0';
	bool explicitHittable = IsHittableEntity(attacker) ||
		IsRecentHittableEntity(attacker) ||
		IsHittableEntity(attackerEntity) ||
		IsRecentHittableEntity(attackerEntity);
	int tank = ResolveTank(attacker, attackerEntity);
	if (!IsValidTank(tank) && explicitHittable)
	{
		tank = GetLatestHittableTank();
	}
	if (!IsValidTank(tank) && tankHittableFallback)
	{
		// l4d2_hittable_control 可能会把物理物体造成的伤害改写为 Tank 作为攻击者，
		// 同时清空 inflictor/attackerentid 字段。
		tank = attacker;
	}
	bool implicitHittable = false;
	if (!IsValidTank(tank) && missingSource)
	{
		// 某些 L4D2 版本对物理物体造成的伤害不会填写 attacker/attackerentid/weapon。
		// 这种情况下，OnHitByTank 时间戳是可靠的判定依据。
		tank = GetLatestHittableTank();
		implicitHittable = IsValidTank(tank);
	}
	if (!IsValidTank(tank))
	{
		tank = GetRecentHittableTank(victim);
	}
	if (!IsValidTank(tank))
	{
		return;
	}

	if (IsRockWeapon(weapon) || IsTankRock(attackerEntity))
	{
		AnnounceTankRock(tank, victim);
	}
	else if (IsTankClawWeapon(weapon))
	{
		RegisterTankPunchVictim(tank, victim);
	}
	else if (explicitHittable || implicitHittable || tankHittableFallback ||
		IsRecentHittable(victim, tank))
	{
		// 非爪击、非石头的 Tank 伤害视为打铁候选；实际播报要等
		// player_incapacitated_start 事件确认。
		MarkRecentHittable(victim, tank);
	}
}

void TrackChargerGunDamage(Event event, int charger)
{
	if (!g_hCvarEnable.BoolValue || !g_hCvarChargerTeamKill.BoolValue ||
		!IsValidInfected(charger) || GetZombieClass(charger) != ZC_CHARGER ||
		g_bChargerChargeHitTarget[charger])
	{
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsValidSurvivor(attacker))
	{
		return;
	}

	char weapon[64];
	event.GetString("weapon", weapon, sizeof(weapon));
	int damageType = event.GetInt("type");
	if (!IsChargerFirearm(weapon, damageType))
	{
		return;
	}

	int damage = event.GetInt("dmg_health");
	if (damage <= 0)
	{
		return;
	}

	float now = GetGameTime();
	bool charging = IsChargerCharging(charger);
	if (charging && !g_bChargerChargeActive[charger])
	{
		// 某些服务器在首次伤害事件前不会触发 charger_charge_start/ability_charge，
		// 这里提供事件缺失时的备用判定。
		BeginChargerCharge(charger);
	}

	// 最后的 player_hurt 事件到来前，m_isCharging 可能已经被清零。优先使用
	// 冲锋开始/撞击事件窗口进行判断，再用网络属性兜底，并给同帧伤害留出短暂宽限时间。
	bool inChargeWindow = IsChargerChargeWindow(charger, now) || charging;
	if (!inChargeWindow && g_bChargerGunTracking[charger] &&
		g_fChargerLastChargingGun[charger] > 0.0 &&
		now - g_fChargerLastChargingGun[charger] <= CHARGER_TEAMKILL_CHARGE_GRACE)
	{
		inChargeWindow = true;
	}
	if (inChargeWindow)
	{
		g_bChargerGunTracking[charger] = true;
		g_fChargerLastChargingGun[charger] = now;
	}

	if (!inChargeWindow)
	{
		return;
	}

	g_iChargerGunDamage[charger][attacker] += damage;
	g_iChargerLastGunAttacker[charger] = attacker;

	bool shotgun = (damageType & DMG_BUCKSHOT) != 0 ||
		StrContains(weapon, "shotgun", false) >= 0;
	if (!shotgun || !g_bChargerGunLastShotgun[charger][attacker] ||
		g_fChargerGunLastShot[charger][attacker] == 0.0 ||
		now - g_fChargerGunLastShot[charger][attacker] > CHARGER_TEAMKILL_SHOT_TIME)
	{
		g_iChargerGunShots[charger][attacker]++;
	}
	g_fChargerGunLastShot[charger][attacker] = now;
	g_bChargerGunLastShotgun[charger][attacker] = shotgun;

	if (event.GetInt("health", 1) <= 0)
	{
		g_bChargerGunLethal[charger] = true;
		g_bChargerGunLethalDuringCharge[charger] = inChargeWindow;
		g_iChargerGunLethalAttacker[charger] = attacker;
	}
}

void ReportChargerGunTeamKill(int charger, int deathAttacker)
{
	if (!g_hCvarEnable.BoolValue || !g_hCvarChargerTeamKill.BoolValue ||
		!g_bChargerGunLethal[charger] || !g_bChargerGunLethalDuringCharge[charger])
	{
		return;
	}

	int attacker = g_iChargerGunLethalAttacker[charger];
	if (!IsValidSurvivor(attacker) || g_iChargerGunDamage[charger][attacker] <= 0)
	{
		attacker = deathAttacker;
	}
	if ((!IsValidSurvivor(attacker) || g_iChargerGunDamage[charger][attacker] <= 0) &&
		IsValidSurvivor(g_iChargerLastGunAttacker[charger]))
	{
		attacker = g_iChargerLastGunAttacker[charger];
	}

	if (!IsValidSurvivor(attacker) || g_iChargerGunDamage[charger][attacker] <= 0)
	{
		return;
	}

	int contributors;
	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (IsValidSurvivor(survivor) && g_iChargerGunDamage[charger][survivor] > 0)
		{
			contributors++;
		}
	}

	if (contributors <= 0)
	{
		return;
	}

	int damage = g_iChargerGunDamage[charger][attacker];
	int shots = g_iChargerGunShots[charger][attacker];
	if (shots < 1)
	{
		shots = 1;
	}

	char shotSuffix[2];
	strcopy(shotSuffix, sizeof(shotSuffix), shots == 1 ? "" : "s");

	if (contributors == 1)
	{
		CPrintToChatAll("%t", "Advanced_ChargerGunSolo", attacker, charger, damage, shots, shotSuffix);
		return;
	}

	char assists[256];
	assists[0] = '\0';
	int assistCount;
	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (survivor == attacker || !IsValidSurvivor(survivor) ||
			g_iChargerGunDamage[charger][survivor] <= 0)
		{
			continue;
		}

		int assistShots = g_iChargerGunShots[charger][survivor];
		if (assistShots < 1)
		{
			assistShots = 1;
		}

		char assist[64];
		char assistSuffix[2];
		strcopy(assistSuffix, sizeof(assistSuffix), assistShots == 1 ? "" : "s");
		FormatEx(assist, sizeof(assist), "%N (%d/%d shot%s)", survivor,
			g_iChargerGunDamage[charger][survivor], assistShots, assistSuffix);

		if (assistCount > 0)
		{
			StrCat(assists, sizeof(assists), ", ");
		}
		StrCat(assists, sizeof(assists), assist);
		assistCount++;
	}

	CPrintToChatAll("%t", "Advanced_ChargerGunTeam", attacker, charger, damage, shots, shotSuffix, assists);
}

public void Event_PlayerIncapStart(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidSurvivor(victim))
	{
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int attackerEntity = event.GetInt("attackerentid", -1);
	char weapon[64];
	event.GetString("weapon", weapon, sizeof(weapon));
	bool tankHittableFallback = IsTankHittableFallback(attacker, weapon);
	bool missingSource = attacker <= 0 && attackerEntity <= 0 && weapon[0] == '\0';
	bool explicitHittable = IsHittableEntity(attackerEntity) ||
		IsRecentHittableEntity(attackerEntity) ||
		IsHittableEntity(attacker) ||
		IsRecentHittableEntity(attacker);
	int tank = ResolveTank(attacker, attackerEntity);

	if (!IsValidTank(tank) && explicitHittable)
	{
		tank = GetLatestHittableTank();
	}
	if (!IsValidTank(tank) && tankHittableFallback)
	{
		// 兼容 l4d2_hittable_control 对攻击者字段的改写。
		tank = attacker;
	}
	bool implicitHittable = false;
	if (!IsValidTank(tank) && missingSource)
	{
		tank = GetLatestHittableTank();
		implicitHittable = IsValidTank(tank);
	}
	if (!IsValidTank(tank))
	{
		tank = GetRecentHittableTank(victim);
	}

	if (!IsValidTank(tank))
	{
		return;
	}

	if (IsRockWeapon(weapon) || IsTankRock(attackerEntity))
	{
		AnnounceTankRock(tank, victim);
	}
	else if (IsTankClawWeapon(weapon))
	{
		RegisterTankPunchVictim(tank, victim);
	}
	else if (explicitHittable || implicitHittable || tankHittableFallback ||
		IsRecentHittable(victim, tank))
	{
		AnnounceTankHittable(tank, victim);
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
	{
		if (IsValidInfected(client) && GetZombieClass(client) == ZC_CHARGER &&
			!g_bChargerGunLethal[client])
		{
			// 某些游戏版本的最后一次 player_hurt 事件不会带 health==0。
			// 当已追踪的伤害和冲锋窗口确认是冲锋击杀时，从 player_death 恢复致命枪击。
			char deathWeapon[64];
			event.GetString("weapon", deathWeapon, sizeof(deathWeapon));
			int deathType = event.GetInt("type", 0);
			int deathAttacker = GetClientOfUserId(event.GetInt("attacker"));
			if (IsValidSurvivor(deathAttacker) &&
				IsChargerFirearm(deathWeapon, deathType) &&
				HasRecentChargerGunDamage(client, GetGameTime()))
			{
				g_bChargerGunLethal[client] = true;
				g_bChargerGunLethalDuringCharge[client] = true;
				g_iChargerGunLethalAttacker[client] = deathAttacker;
			}
		}

		if (g_bChargerGunLethal[client])
		{
			int attacker = GetClientOfUserId(event.GetInt("attacker"));
			ReportChargerGunTeamKill(client, attacker);
		}

		ResetClientState(client);
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
	{
		ResetClientState(client);
	}
}

public Action OnTakeDamagePre(
	int victim,
	int &attacker,
	int &inflictor,
	float &damage,
	int &damagetype)
{
	if (damage <= 0.0 || !IsValidSurvivor(victim))
	{
		return Plugin_Continue;
	}

	// 在其它伤害钩子改写 attacker/inflictor 前，先记录原始物理实体；
	// l4d2_hittable_control 会改写物理物体造成的伤害。
	bool explicitHittable = IsHittableEntity(attacker) ||
		IsRecentHittableEntity(attacker) ||
		IsHittableEntity(inflictor) ||
		IsRecentHittableEntity(inflictor);
	int tank = ResolveTank(attacker, inflictor);
	if (!IsValidTank(tank) && explicitHittable)
	{
		tank = GetLatestHittableTank();
	}

	if (IsValidTank(tank) && explicitHittable && !IsTankRock(inflictor))
	{
		MarkRecentHittable(victim, tank);
	}

	return Plugin_Continue;
}

public void OnTakeDamagePost(
	int victim,
	int attacker,
	int inflictor,
	float damage,
	int damagetype,
	int weapon,
	const float damageForce[3],
	const float damagePosition[3])
{
	if (IsValidInfected(victim) && GetZombieClass(victim) == ZC_CHARGER &&
		!g_bChargerChargeHitTarget[victim] &&
		IsValidSurvivor(attacker) &&
		IsLikelyChargerFirearmDamage(inflictor, damagetype) &&
		IsChargerCharging(victim))
	{
		if (!g_bChargerChargeActive[victim])
		{
			BeginChargerCharge(victim);
		}
		g_bChargerGunTracking[victim] = true;
		g_fChargerLastChargingGun[victim] = GetGameTime();
		return;
	}

	if (damage <= 0.0 || !IsValidSurvivor(victim))
	{
		return;
	}

	int tank = ResolveTank(attacker, inflictor);
	bool explicitHittable = IsHittableEntity(attacker) ||
		IsRecentHittableEntity(attacker) ||
		IsHittableEntity(inflictor) ||
		IsRecentHittableEntity(inflictor);
	if (!IsValidTank(tank) && explicitHittable)
	{
		tank = GetLatestHittableTank();
	}
	bool implicitHittable = false;
	if (!IsValidTank(tank) && attacker <= 0 && inflictor <= 0)
	{
		tank = GetLatestHittableTank();
		implicitHittable = IsValidTank(tank);
	}
	if (!IsValidTank(tank))
	{
		return;
	}

	if (IsTankRock(inflictor))
	{
		AnnounceTankRock(tank, victim);
	}
	else if (explicitHittable || implicitHittable)
	{
		MarkRecentHittable(victim, tank);
	}
}

public Action Timer_CheckMultiControl(Handle timer)
{
	if (g_bRoundEnded || !g_hCvarEnable.BoolValue || !g_hCvarMultiControl.BoolValue)
	{
		ResetControlState();
		return Plugin_Continue;
	}

	int controlCount = 0;
	for (int infected = 1; infected <= MaxClients; infected++)
	{
		if (!IsValidAliveInfected(infected))
		{
			continue;
		}

		int victim = GetControlVictim(infected);
		if (IsValidSurvivor(victim))
		{
			controlCount++;
		}
	}

	if (controlCount < MULTI_CONTROL_MIN)
	{
		ResetControlState();
		return Plugin_Continue;
	}

	int previousCount = g_iControlCount;
	if (controlCount > previousCount)
	{
		int target = controlCount < MULTI_CONTROL_MAX ? controlCount : MULTI_CONTROL_MAX;
		for (int level = g_iControlAnnounced + 1; level <= target; level++)
		{
			if (level >= MULTI_CONTROL_MIN)
			{
				CPrintToChatAll("%t", "Advanced_MultiControl", level);
			}
		}
		g_iControlAnnounced = target;
	}

	g_iControlCount = controlCount;

	int aliveSurvivors = CountAliveSurvivors();
	if (!g_bControlRoundEndAnnounced && aliveSurvivors > 0 && controlCount >= aliveSurvivors)
	{
		CPrintToChatAll("%t", "Advanced_RoundEnd");
		g_bControlRoundEndAnnounced = true;
	}

	return Plugin_Continue;
}

void StartControlTimer()
{
	if (g_hControlTimer != null)
	{
		return;
	}

	g_hControlTimer = CreateTimer(
		CONTROL_SCAN_INTERVAL,
		Timer_CheckMultiControl,
		_,
		TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_HookExistingHittables(Handle timer)
{
	HookExistingHittables();
	return Plugin_Stop;
}

public Action Timer_ResetCharger(Handle timer, int userid)
{
	int charger = GetClientOfUserId(userid);
	if (charger > 0 && charger <= MaxClients)
	{
		g_hChargerReset[charger] = null;
		ResetChargerState(charger, false);
	}
	return Plugin_Stop;
}

public Action Timer_ResetBoomer(Handle timer, int userid)
{
	int boomer = GetClientOfUserId(userid);
	if (boomer > 0 && boomer <= MaxClients)
	{
		g_hBoomerReset[boomer] = null;
		ResetBoomerState(boomer, false);
	}
	return Plugin_Stop;
}

public Action Timer_ResetTankPunch(Handle timer, int userid)
{
	int tank = GetClientOfUserId(userid);
	if (tank > 0 && tank <= MaxClients)
	{
		g_hTankPunchReset[tank] = null;
		ResetTankPunchState(tank, false);
	}
	return Plugin_Stop;
}

public void OnHittableSpawned(int entity)
{
	HookHittable(entity);
}

public void OnHittableHitByTank(const char[] output, int caller, int activator, float delay)
{
	if (caller < 0 || caller >= MAX_EDICTS)
	{
		return;
	}

	int tank = activator;
	if (!IsValidTank(tank))
	{
		tank = GetLatestHittableTank();
	}
	if (!IsValidTank(tank))
	{
		tank = FindAnyTank();
	}

	if (!IsValidTank(tank))
	{
		return;
	}

	RememberHittableTank(caller, tank);
}

public void OnHittableTouchPost(int entity, int other)
{
	if (!IsValidSurvivor(other))
	{
		return;
	}

	// 物理物体命中幸存者后，player_hurt 可能已经丢失 attackerentid。
	// 保留“受害者 -> Tank”的直接关联，供随后 incap 事件使用。
	int tank = GetRecentHittableEntityTank(entity);
	if (IsValidTank(tank))
	{
		MarkRecentHittable(other, tank);
	}
}

public void OnHittableTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	if (victim < 0 || victim >= MAX_EDICTS || !IsHittableEntity(victim))
	{
		return;
	}

	// 某些地图不会稳定触发 OnHitByTank。物理伤害钩子作为第二判定来源：
	// 直接由 Tank 造成的伤害可以确定归属，连续物理碰撞则继承攻击者缓存的 Tank。
	int tank = ResolveTank(attacker, inflictor);
	if (!IsValidTank(tank) && !IsValidSurvivor(attacker))
	{
		// 在伤害回调中，可能只剩下物理物体实体本身可供识别。
		tank = GetRecentHittableEntityTank(victim);
	}
	if (IsValidTank(tank))
	{
		RememberHittableTank(victim, tank);
	}
}

void RememberHittableTank(int entity, int tank)
{
	if (entity < 0 || entity >= MAX_EDICTS || !IsValidTank(tank))
	{
		return;
	}

	float now = GetGameTime();
	g_iLastHittableTankByEntity[entity] = tank;
	g_fLastHittableEntityHit[entity] = now;
	g_iLastHittableOwnerTank = tank;
	g_fLastHittableOwnerHit = now;
}

void RegisterChargerVictim(int charger, int victim)
{
	if (!g_hCvarEnable.BoolValue || !g_hCvarCharger.BoolValue ||
		!IsValidInfected(charger) || GetZombieClass(charger) != ZC_CHARGER ||
		!IsValidSurvivor(victim))
	{
		return;
	}

	float now = GetGameTime();
	if (g_fChargerLastHit[charger] > 0.0 &&
		now - g_fChargerLastHit[charger] > g_hCvarChargerWindow.FloatValue)
	{
		ResetChargerState(charger);
	}

	g_fChargerLastHit[charger] = now;
	if (!g_bChargerVictim[charger][victim])
	{
		g_bChargerVictim[charger][victim] = true;
		g_iChargerVictimCount[charger]++;

		AnnounceChargerMilestone(charger, g_iChargerVictimCount[charger]);
	}

	delete g_hChargerReset[charger];
	g_hChargerReset[charger] = CreateTimer(
		g_hCvarChargerWindow.FloatValue,
		Timer_ResetCharger,
		GetClientUserId(charger),
		TIMER_FLAG_NO_MAPCHANGE);
}

void RegisterBoomerVictim(int boomer, int victim)
{
	if (!g_hCvarEnable.BoolValue || !g_hCvarBoomer.BoolValue ||
		!IsValidInfected(boomer) || GetZombieClass(boomer) != ZC_BOOMER ||
		!IsValidSurvivor(victim))
	{
		return;
	}

	float now = GetGameTime();
	if (g_fBoomerLastHit[boomer] > 0.0 &&
		now - g_fBoomerLastHit[boomer] > g_hCvarBoomerWindow.FloatValue)
	{
		ResetBoomerState(boomer);
	}

	g_fBoomerLastHit[boomer] = now;
	if (!g_bBoomerVictim[boomer][victim])
	{
		g_bBoomerVictim[boomer][victim] = true;
		g_iBoomerVictimCount[boomer]++;

		AnnounceBoomerMilestone(boomer, g_iBoomerVictimCount[boomer]);
	}

	delete g_hBoomerReset[boomer];
	g_hBoomerReset[boomer] = CreateTimer(
		g_hCvarBoomerWindow.FloatValue,
		Timer_ResetBoomer,
		GetClientUserId(boomer),
		TIMER_FLAG_NO_MAPCHANGE);
}

void RegisterTankPunchVictim(int tank, int victim)
{
	if (!g_hCvarEnable.BoolValue || !g_hCvarTankPunch.BoolValue ||
		!IsValidTank(tank) || !IsValidSurvivor(victim))
	{
		return;
	}

	float now = GetGameTime();
	if (g_fTankPunchLastHit[tank] > 0.0 &&
		now - g_fTankPunchLastHit[tank] > g_hCvarTankPunchWindow.FloatValue)
	{
		ResetTankPunchState(tank);
	}

	g_fTankPunchLastHit[tank] = now;
	if (!g_bTankPunchVictim[tank][victim])
	{
		g_bTankPunchVictim[tank][victim] = true;
		g_iTankPunchVictimCount[tank]++;

		AnnounceTankPunchMilestone(tank, g_iTankPunchVictimCount[tank]);
	}

	delete g_hTankPunchReset[tank];
	g_hTankPunchReset[tank] = CreateTimer(
		g_hCvarTankPunchWindow.FloatValue,
		Timer_ResetTankPunch,
		GetClientUserId(tank),
		TIMER_FLAG_NO_MAPCHANGE);
}

void AnnounceChargerMilestone(int charger, int count)
{
	if (count < MULTI_CONTROL_MIN || count > MULTI_CONTROL_MAX ||
		count <= g_iChargerAnnounced[charger])
	{
		return;
	}

	for (int level = g_iChargerAnnounced[charger] + 1; level <= count; level++)
	{
		if (level >= MULTI_CONTROL_MIN)
		{
			CPrintToChatAll("%t", "Advanced_ChargerMulti", charger, level);
		}
	}
	g_iChargerAnnounced[charger] = count;
}

void AnnounceBoomerMilestone(int boomer, int count)
{
	if (count < MULTI_CONTROL_MIN || count > MULTI_CONTROL_MAX ||
		count <= g_iBoomerAnnounced[boomer])
	{
		return;
	}

	for (int level = g_iBoomerAnnounced[boomer] + 1; level <= count; level++)
	{
		if (level >= MULTI_CONTROL_MIN)
		{
			CPrintToChatAll("%t", "Advanced_BoomerMulti", boomer, level);
		}
	}
	g_iBoomerAnnounced[boomer] = count;
}

void AnnounceTankPunchMilestone(int tank, int count)
{
	if (count < MULTI_CONTROL_MIN || count > MULTI_CONTROL_MAX ||
		count <= g_iTankPunchAnnounced[tank])
	{
		return;
	}

	for (int level = g_iTankPunchAnnounced[tank] + 1; level <= count; level++)
	{
		if (level >= MULTI_CONTROL_MIN)
		{
			CPrintToChatAll("%t", "Advanced_TankPunchMulti", tank, level);
		}
	}
	g_iTankPunchAnnounced[tank] = count;
}

void AnnounceTankRock(int tank, int victim)
{
	if (!g_hCvarEnable.BoolValue || !g_hCvarTankRock.BoolValue ||
		!IsValidTank(tank) || !IsValidSurvivor(victim))
	{
		return;
	}

	float now = GetGameTime();
	if (g_iLastRockTank[victim] == tank &&
		now - g_fLastRockAnnounce[victim] < DAMAGE_DEDUPE_TIME)
	{
		return;
	}

	g_iLastRockTank[victim] = tank;
	g_fLastRockAnnounce[victim] = now;
	CPrintToChatAll("%t", "Advanced_TankRockHit", tank, victim);
}

void AnnounceTankHittable(int tank, int victim)
{
	if (!g_hCvarEnable.BoolValue || !g_hCvarTankHittable.BoolValue ||
		!IsValidTank(tank) || !IsValidSurvivor(victim))
	{
		return;
	}

	float now = GetGameTime();
	if (g_iLastHittableTank[victim] == tank &&
		now - g_fLastHittableAnnounce[victim] < HITTABLE_DEDUPE_TIME)
	{
		return;
	}

	g_iLastHittableTank[victim] = tank;
	g_fLastHittableAnnounce[victim] = now;
	CPrintToChatAll("%t", "Advanced_TankHittableIncap", tank, victim);
}

void MarkRecentHittable(int victim, int tank)
{
	if (!IsValidSurvivor(victim) || !IsValidTank(tank))
	{
		return;
	}

	g_iRecentHittableTank[victim] = tank;
	g_fRecentHittableTime[victim] = GetGameTime();
}

int GetRecentHittableTank(int victim)
{
	if (!IsValidSurvivor(victim) || !IsRecentHittable(victim, 0))
	{
		return 0;
	}

	return g_iRecentHittableTank[victim];
}

bool IsRecentHittable(int victim, int tank)
{
	if (!IsValidSurvivor(victim) || !IsValidTank(g_iRecentHittableTank[victim]))
	{
		return false;
	}

	if (GetGameTime() - g_fRecentHittableTime[victim] > HITTABLE_OWNER_TIME)
	{
		return false;
	}

	return tank == 0 || g_iRecentHittableTank[victim] == tank;
}

bool IsRecentHittableEntity(int entity)
{
	if (entity < 0 || entity >= MAX_EDICTS ||
		!IsValidTank(g_iLastHittableTankByEntity[entity]))
	{
		return false;
	}

	return GetGameTime() - g_fLastHittableEntityHit[entity] <= HITTABLE_OWNER_TIME;
}

int GetRecentHittableEntityTank(int entity)
{
	if (entity < 0 || entity >= MAX_EDICTS ||
		GetGameTime() - g_fLastHittableEntityHit[entity] > HITTABLE_OWNER_TIME)
	{
		return 0;
	}

	int tank = g_iLastHittableTankByEntity[entity];
	return IsValidTank(tank) ? tank : 0;
}

int GetLatestHittableTank()
{
	if (IsValidTank(g_iLastHittableOwnerTank) &&
		GetGameTime() - g_fLastHittableOwnerHit <= HITTABLE_OWNER_TIME)
	{
		return g_iLastHittableOwnerTank;
	}

	return 0;
}

int ResolveTank(int attacker, int inflictor)
{
	if (IsValidTank(attacker))
	{
		return attacker;
	}

	if (IsTankRock(inflictor))
	{
		int owner = GetEntityPropEntSafe(inflictor, Prop_Data, "m_hOwnerEntity");
		if (!IsValidTank(owner))
		{
			owner = GetEntityPropEntSafe(inflictor, Prop_Data, "m_hThrower");
		}
		if (IsValidTank(owner))
		{
			return owner;
		}
	}

	int owner = GetRecentHittableEntityTank(inflictor);
	if (IsValidTank(owner))
	{
		return owner;
	}

	owner = GetRecentHittableEntityTank(attacker);
	if (IsValidTank(owner))
	{
		return owner;
	}

	return 0;
}

int GetControlVictim(int infected)
{
	int victim = -1;

	switch (GetZombieClass(infected))
	{
		case 1:
		{
			victim = GetEntityPropEntSafe(infected, Prop_Send, "m_tongueVictim");
		}
		case 3:
		{
			victim = GetEntityPropEntSafe(infected, Prop_Send, "m_pounceVictim");
		}
		case 5:
		{
			victim = GetEntityPropEntSafe(infected, Prop_Send, "m_jockeyVictim");
		}
		case ZC_CHARGER:
		{
			victim = GetEntityPropEntSafe(infected, Prop_Send, "m_carryVictim");
			if (!IsValidSurvivor(victim))
			{
				victim = GetEntityPropEntSafe(infected, Prop_Send, "m_pummelVictim");
			}
		}
	}

	return victim;
}

int CountAliveSurvivors()
{
	int count = 0;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsValidSurvivor(client) && IsPlayerAlive(client))
		{
			count++;
		}
	}
	return count;
}

void HookExistingHittables()
{
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "prop_physics*")) != -1)
	{
		HookHittable(entity);
	}

	entity = -1;
	while ((entity = FindEntityByClassname(entity, "physics_prop")) != -1)
	{
		HookHittable(entity);
	}

	entity = -1;
	while ((entity = FindEntityByClassname(entity, "prop_car_alarm")) != -1)
	{
		HookHittable(entity);
	}

	entity = -1;
	while ((entity = FindEntityByClassname(entity, "prop_alarm_car")) != -1)
	{
		HookHittable(entity);
	}
}

void HookHittable(int entity)
{
	if (entity <= MaxClients || entity >= MAX_EDICTS || !IsHittableEntity(entity) ||
		g_bHittableHooked[entity])
	{
		return;
	}

	HookSingleEntityOutput(entity, "OnHitByTank", OnHittableHitByTank);
	SDKHook(entity, SDKHook_OnTakeDamagePost, OnHittableTakeDamagePost);
	SDKHook(entity, SDKHook_TouchPost, OnHittableTouchPost);
	g_bHittableHooked[entity] = true;
}

bool IsHittableClass(const char[] classname)
{
	return StrContains(classname, "prop_physics", false) == 0 ||
		StrEqual(classname, "physics_prop", false) ||
		StrEqual(classname, "prop_car_alarm", false) ||
		StrEqual(classname, "prop_alarm_car", false);
}

bool IsHittableEntity(int entity)
{
	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return false;
	}

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	if (StrEqual(classname, "prop_car_alarm", false) ||
		StrEqual(classname, "prop_alarm_car", false))
	{
		return true;
	}

	if (StrContains(classname, "prop_physics", false) == 0 ||
		StrEqual(classname, "physics_prop", false))
	{
		// 自定义地图上 m_hasTankGlow 的初始化并不一致。这里对所有物理物体都挂钩，
		// 只有实际的 OnHitByTank 输出或 Tank 伤害路径才能创建播报候选。
		return true;
	}

	return false;
}

bool IsTankRock(int entity)
{
	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return false;
	}

	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));
	return StrEqual(classname, "tank_rock", false);
}

bool IsTankClawWeapon(const char[] weapon)
{
	return StrEqual(weapon, "tank_claw", false) ||
		StrEqual(weapon, "weapon_tank_claw", false);
}

bool IsRockWeapon(const char[] weapon)
{
	return StrEqual(weapon, "tank_rock", false);
}

bool IsTankHittableFallback(int attacker, const char[] weapon)
{
	// l4d2_hittable_control 会把幸存者受到的物理伤害的攻击者改为 Tank，
	// 也可能清空原始物理实体。此时唯一可靠的区分方式是 weapon 既不是 claw 也不是 rock。
	// 这个逻辑也刻意接受 AI Tank。
	return IsValidTank(attacker) &&
		!IsTankClawWeapon(weapon) &&
		!IsRockWeapon(weapon);
}

bool IsChargerFirearm(const char[] weapon, int damageType)
{
	if (IsTankClawWeapon(weapon) || IsRockWeapon(weapon) ||
		StrContains(weapon, "melee", false) >= 0)
	{
		return false;
	}

	// 对标准枪械来说，子弹和霰弹伤害是可靠信号。
	if ((damageType & (DMG_BULLET | DMG_BUCKSHOT)) != 0)
	{
		return true;
	}

	// 包含直接命中的榴弹发射器伤害，但不把土制炸弹、火焰或胆汁罐等
	// 一般爆炸伤害算进去。
	if (StrEqual(weapon, "grenade_launcher_projectile", false) ||
		StrEqual(weapon, "grenade_launcher", false))
	{
		return true;
	}

	return StrContains(weapon, "pistol", false) >= 0 ||
		StrContains(weapon, "smg", false) >= 0 ||
		StrContains(weapon, "shotgun", false) >= 0 ||
		StrContains(weapon, "rifle", false) >= 0 ||
		StrContains(weapon, "sniper", false) >= 0;
}

bool IsLikelyChargerFirearmDamage(int inflictor, int damageType)
{
	if ((damageType & (DMG_BULLET | DMG_BUCKSHOT)) != 0)
	{
		return true;
	}

	if (inflictor < 0 || !IsValidEntity(inflictor))
	{
		return false;
	}

	char classname[64];
	GetEntityClassname(inflictor, classname, sizeof(classname));
	return StrContains(classname, "grenade_launcher_projectile", false) >= 0;
}

bool IsChargerCharging(int charger)
{
	if (!IsValidInfected(charger) || GetZombieClass(charger) != ZC_CHARGER)
	{
		return false;
	}

	int ability = GetEntityPropEntSafe(charger, Prop_Send, "m_customAbility");
	return IsValidEntity(ability) && HasEntProp(ability, Prop_Send, "m_isCharging") &&
		GetEntProp(ability, Prop_Send, "m_isCharging") != 0;
}

void BeginChargerCharge(int charger)
{
	if (!IsValidInfected(charger) || GetZombieClass(charger) != ZC_CHARGER)
	{
		return;
	}

	float now = GetGameTime();
	if (g_bChargerChargeActive[charger] &&
		g_fChargerChargeStart[charger] > 0.0 &&
		now - g_fChargerChargeStart[charger] <= CHARGER_TEAMKILL_MAX_CHARGE_TIME)
	{
		// ability_use 和 charger_charge_start 可能描述的是同一次冲锋，
		// 不要因为第二个事件到来就清空已经记录的枪械伤害。
		return;
	}

	g_bChargerChargeHitTarget[charger] = false;
	g_bChargerChargeActive[charger] = true;
	g_fChargerChargeStart[charger] = now;
	g_fChargerChargeEndGrace[charger] = 0.0;
}

void EndChargerCharge(int charger, bool hitTarget = false)
{
	if (charger <= 0 || charger > MaxClients)
	{
		return;
	}

	if (hitTarget)
	{
		// The game can leave m_isCharging set for a few frames after impact.
		// Lock this charge out so post-impact shots are not reported as a
		// charger kill while charging. The lock is cleared by the next charge.
		ResetChargerGunState(charger);
		g_bChargerChargeHitTarget[charger] = true;
		return;
	}

	if (!g_bChargerChargeActive[charger])
	{
		return;
	}

	g_fChargerChargeEndGrace[charger] = GetGameTime() +
		CHARGER_TEAMKILL_CHARGE_GRACE;
}

bool IsChargerChargeWindow(int charger, float now)
{
	if (charger <= 0 || charger > MaxClients ||
		!g_bChargerChargeActive[charger] ||
		g_bChargerChargeHitTarget[charger] ||
		g_fChargerChargeStart[charger] <= 0.0)
	{
		return false;
	}

	if (now - g_fChargerChargeStart[charger] > CHARGER_TEAMKILL_MAX_CHARGE_TIME)
	{
		g_bChargerChargeActive[charger] = false;
		g_fChargerChargeStart[charger] = 0.0;
		g_fChargerChargeEndGrace[charger] = 0.0;
		return false;
	}

	if (g_fChargerChargeEndGrace[charger] > 0.0 &&
		now > g_fChargerChargeEndGrace[charger])
	{
		g_bChargerChargeActive[charger] = false;
		g_fChargerChargeStart[charger] = 0.0;
		g_fChargerChargeEndGrace[charger] = 0.0;
		return false;
	}

	return true;
}

bool HasChargerGunDamage(int charger)
{
	if (charger <= 0 || charger > MaxClients)
	{
		return false;
	}

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (g_iChargerGunDamage[charger][survivor] > 0)
		{
			return true;
		}
	}

	return false;
}

bool HasRecentChargerGunDamage(int charger, float now)
{
	return HasChargerGunDamage(charger) &&
		g_bChargerGunTracking[charger] &&
		g_fChargerLastChargingGun[charger] > 0.0 &&
		now - g_fChargerLastChargingGun[charger] <= CHARGER_TEAMKILL_DEATH_GRACE;
}

int GetZombieClass(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) ||
		!HasEntProp(client, Prop_Send, "m_zombieClass"))
	{
		return 0;
	}

	return GetEntProp(client, Prop_Send, "m_zombieClass");
}

int GetEntityPropEntSafe(int entity, PropType type, const char[] prop)
{
	if (entity < 0 || !IsValidEntity(entity) || !HasEntProp(entity, type, prop))
	{
		return -1;
	}

	return GetEntPropEnt(entity, type, prop);
}

bool IsValidSurvivor(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) &&
		GetClientTeam(client) == TEAM_SURVIVOR;
}

bool IsValidInfected(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) &&
		GetClientTeam(client) == TEAM_INFECTED;
}

bool IsValidAliveInfected(int client)
{
	return IsValidInfected(client) && IsPlayerAlive(client);
}

bool IsValidTank(int client)
{
	return IsValidInfected(client) && GetZombieClass(client) == ZC_TANK;
}

int FindAnyTank()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsValidTank(client))
		{
			return client;
		}
	}

	return 0;
}

void ResetControlState()
{
	g_iControlCount = 0;
	g_iControlAnnounced = 0;
	g_bControlRoundEndAnnounced = false;
}

void ResetChargerState(int client, bool cancelTimer = true)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (cancelTimer)
	{
		delete g_hChargerReset[client];
	}
	g_hChargerReset[client] = null;

	g_iChargerVictimCount[client] = 0;
	g_iChargerAnnounced[client] = 0;
	g_fChargerLastHit[client] = 0.0;
	for (int victim = 1; victim <= MaxClients; victim++)
	{
		g_bChargerVictim[client][victim] = false;
	}
}

void ResetChargerGunState(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bChargerGunTracking[client] = false;
	g_bChargerGunLethal[client] = false;
	g_bChargerGunLethalDuringCharge[client] = false;
	g_iChargerGunLethalAttacker[client] = 0;
	g_iChargerLastGunAttacker[client] = 0;
	g_fChargerLastChargingGun[client] = 0.0;
	g_bChargerChargeActive[client] = false;
	g_bChargerChargeHitTarget[client] = false;
	g_fChargerChargeStart[client] = 0.0;
	g_fChargerChargeEndGrace[client] = 0.0;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		g_iChargerGunDamage[client][survivor] = 0;
		g_iChargerGunShots[client][survivor] = 0;
		g_fChargerGunLastShot[client][survivor] = 0.0;
		g_bChargerGunLastShotgun[client][survivor] = false;
	}
}

void ResetBoomerState(int client, bool cancelTimer = true)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (cancelTimer)
	{
		delete g_hBoomerReset[client];
	}
	g_hBoomerReset[client] = null;

	g_iBoomerVictimCount[client] = 0;
	g_iBoomerAnnounced[client] = 0;
	g_fBoomerLastHit[client] = 0.0;
	for (int victim = 1; victim <= MaxClients; victim++)
	{
		g_bBoomerVictim[client][victim] = false;
	}
}

void ResetTankPunchState(int client, bool cancelTimer = true)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (cancelTimer)
	{
		delete g_hTankPunchReset[client];
	}
	g_hTankPunchReset[client] = null;

	g_iTankPunchVictimCount[client] = 0;
	g_iTankPunchAnnounced[client] = 0;
	g_fTankPunchLastHit[client] = 0.0;
	for (int victim = 1; victim <= MaxClients; victim++)
	{
		g_bTankPunchVictim[client][victim] = false;
	}
}

void ResetClientState(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ResetChargerState(client);
	ResetChargerGunState(client);
	ResetBoomerState(client);
	ResetTankPunchState(client);

	g_iRecentHittableTank[client] = 0;
	g_fRecentHittableTime[client] = 0.0;
	g_iLastRockTank[client] = 0;
	g_fLastRockAnnounce[client] = 0.0;
	g_iLastHittableTank[client] = 0;
	g_fLastHittableAnnounce[client] = 0.0;

	for (int owner = 1; owner <= MaxClients; owner++)
	{
		g_bChargerVictim[owner][client] = false;
		g_iChargerGunDamage[owner][client] = 0;
		g_iChargerGunShots[owner][client] = 0;
		g_fChargerGunLastShot[owner][client] = 0.0;
		g_bChargerGunLastShotgun[owner][client] = false;
		g_bBoomerVictim[owner][client] = false;
		g_bTankPunchVictim[owner][client] = false;
	}
}

void ResetAllState()
{
	ResetControlState();

	for (int client = 1; client <= MaxClients; client++)
	{
		ResetChargerState(client);
		ResetChargerGunState(client);
		ResetBoomerState(client);
		ResetTankPunchState(client);
		g_iRecentHittableTank[client] = 0;
		g_fRecentHittableTime[client] = 0.0;
		g_iLastRockTank[client] = 0;
		g_fLastRockAnnounce[client] = 0.0;
		g_iLastHittableTank[client] = 0;
		g_fLastHittableAnnounce[client] = 0.0;

		for (int victim = 1; victim <= MaxClients; victim++)
		{
			g_bChargerVictim[client][victim] = false;
			g_iChargerGunDamage[client][victim] = 0;
			g_iChargerGunShots[client][victim] = 0;
			g_fChargerGunLastShot[client][victim] = 0.0;
			g_bChargerGunLastShotgun[client][victim] = false;
			g_bBoomerVictim[client][victim] = false;
			g_bTankPunchVictim[client][victim] = false;
		}
	}
}

void ResetHittableOwnerCache()
{
	g_iLastHittableOwnerTank = 0;
	g_fLastHittableOwnerHit = 0.0;

	for (int entity = 0; entity < MAX_EDICTS; entity++)
	{
		g_iLastHittableTankByEntity[entity] = 0;
		g_fLastHittableEntityHit[entity] = 0.0;
	}
}
