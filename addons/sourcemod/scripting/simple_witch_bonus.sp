#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <l4d2_penalty_bonus>

#define TEAM_SURVIVOR 2

public Plugin myinfo =
{
	name = "Witch Score Bonus",
	author = "Tabun, Zonemod",
	description = "Adds round bonus for Witch kills and a penalty for Witch incapacitations.",
	version = "1.0.0",
	url = "https://github.com/SirPlease/L4D2-Competitive-Rework"
};

ConVar
	g_hCvarEnable,
	g_hCvarKillBonus,
	g_hCvarOneShotBonus,
	g_hCvarIncapPenalty,
	g_hCvarPrint,
	g_hCvarBonusAlways;

bool g_bPenaltyBonusAvailable;
bool g_bMissingPenaltyBonusLogged;
bool g_bIncapPenaltyGiven[MAXPLAYERS + 1];

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		SetFailState("This plugin supports Left 4 Dead 2 only.");
	}

	g_hCvarEnable = CreateConVar(
		"sm_witch_score_enable", "1",
		"Enable Witch kill bonuses and Witch incap penalties.",
		FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvarKillBonus = CreateConVar(
		"sm_simple_witch_bonus", "20",
		"Round bonus for a non-one-shot Witch kill.",
		FCVAR_NONE, true, 0.0);
	g_hCvarOneShotBonus = CreateConVar(
		"sm_witch_oneshot_bonus", "50",
		"Round bonus for a one-shot Witch kill.",
		FCVAR_NONE, true, 0.0);
	g_hCvarIncapPenalty = CreateConVar(
		"sm_witch_incap_penalty", "40",
		"Points deducted immediately when a Witch incapacitates a survivor.",
		FCVAR_NONE, true, 0.0);
	g_hCvarPrint = CreateConVar(
		"sm_witch_bonus_print", "1",
		"Print Witch score changes to chat.",
		FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCvarBonusAlways = CreateConVar(
		"sm_witch_bonus_always", "0",
		"Award the kill bonus even when the final Witch attacker is not a survivor.",
		FCVAR_NONE, true, 0.0, true, 1.0);

	HookEvent("witch_killed", Event_WitchKilled, EventHookMode_Post);
	HookEventEx("player_incapacitated_start", Event_PlayerIncapacitated, EventHookMode_Post);
	HookEventEx("player_incapacitated", Event_PlayerIncapacitated, EventHookMode_Post);
	HookEvent("revive_success", Event_ReviveSuccess, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	g_bPenaltyBonusAvailable = HasPenaltyBonus();
	ResetIncapState();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "penaltybonus"))
	{
		g_bPenaltyBonusAvailable = HasPenaltyBonus();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "penaltybonus"))
	{
		g_bPenaltyBonusAvailable = false;
	}
}

public void OnClientPutInServer(int client)
{
	if (client > 0 && client <= MaxClients)
	{
		g_bIncapPenaltyGiven[client] = false;
	}
}

public void OnClientDisconnect(int client)
{
	if (client > 0 && client <= MaxClients)
	{
		g_bIncapPenaltyGiven[client] = false;
	}
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ResetIncapState();
}

void Event_WitchKilled(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_hCvarEnable.BoolValue)
	{
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("userid"));
	if (!g_hCvarBonusAlways.BoolValue && !IsSurvivor(attacker))
	{
		return;
	}

	bool oneShot = event.GetBool("oneshot", false);
	int bonus = oneShot ? g_hCvarOneShotBonus.IntValue : g_hCvarKillBonus.IntValue;
	if (bonus <= 0)
	{
		return;
	}

	if (AddRoundScore(bonus) && g_hCvarPrint.BoolValue)
	{
		if (oneShot && IsSurvivor(attacker))
		{
			PrintToChatAll("\x04[妹子加分]\x01 %N 一枪秒妹：生还者 \x05+%d\x01 分。", attacker, bonus);
		}
		else if (oneShot)
		{
			PrintToChatAll("\x04[妹子加分]\x01 一枪秒妹：生还者 \x05+%d\x01 分。", bonus);
		}
		else
		{
			PrintToChatAll("\x04[妹子加分]\x01 集火/引秒击杀女巫：\x05+%d\x01 分。", bonus);
		}
	}
}

void Event_PlayerIncapacitated(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_hCvarEnable.BoolValue)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!IsSurvivor(victim) || g_bIncapPenaltyGiven[victim])
	{
		return;
	}

	int attackerEntity = event.GetInt("attackerentid", -1);
	if (!IsWitch(attackerEntity))
	{
		// Some event producers only expose the entity index in "attacker".
		int fallbackEntity = event.GetInt("attacker", -1);
		if (fallbackEntity > MaxClients && IsWitch(fallbackEntity))
		{
			attackerEntity = fallbackEntity;
		}
	}

	if (!IsWitch(attackerEntity))
	{
		return;
	}

	int penalty = g_hCvarIncapPenalty.IntValue;
	if (penalty <= 0)
	{
		return;
	}

	// This is deliberately done from the incap event, not player_death. The
	// penalty therefore takes effect as soon as the Witch puts the survivor down.
	if (!AddRoundScore(-penalty))
	{
		return;
	}

	// L4D2 can emit both player_incapacitated_start and player_incapacitated
	// for the same incap. Clear this flag only after a successful revive.
	g_bIncapPenaltyGiven[victim] = true;

	if (g_hCvarPrint.BoolValue)
	{
		PrintToChatAll("\x04[妹子加分]\x01 %N 被女巫放倒：\x03-%d\x01 分。", victim, penalty);
	}
}

void Event_ReviveSuccess(Event event, const char[] name, bool dontBroadcast)
{
	int survivor = GetClientOfUserId(event.GetInt("subject"));
	if (survivor > 0 && survivor <= MaxClients)
	{
		g_bIncapPenaltyGiven[survivor] = false;
	}
}

bool AddRoundScore(int amount)
{
	if (!g_bPenaltyBonusAvailable)
	{
		if (!g_bMissingPenaltyBonusLogged)
		{
			LogError("Witch score change skipped because l4d2_penalty_bonus is not loaded.");
			g_bMissingPenaltyBonusLogged = true;
		}
		return false;
	}

	PBONUS_AddRoundBonus(amount, true);
	return true;
}

bool HasPenaltyBonus()
{
	return LibraryExists("penaltybonus") &&
		GetFeatureStatus(FeatureType_Native, "PBONUS_AddRoundBonus") == FeatureStatus_Available;
}

bool IsSurvivor(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) &&
		GetClientTeam(client) == TEAM_SURVIVOR;
}

bool IsWitch(int entity)
{
	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return false;
	}

	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));
	return StrContains(classname, "witch", false) == 0;
}

void ResetIncapState()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		g_bIncapPenaltyGiven[client] = false;
	}
}
