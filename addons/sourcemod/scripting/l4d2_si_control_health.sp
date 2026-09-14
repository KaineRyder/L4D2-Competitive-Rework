#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <colors>
#include <l4d2util_constants>

public Plugin myinfo =
{
	name = "L4D2 SI Control Health",
	author = "Zonemod",
	description = "Tells a controlled survivor how much health the controlling special infected has left.",
	version = "1.0.0",
	url = ""
};

// charger_impact can be followed by charger_carry_start for the same control.
// Keep a short per-pair cooldown so that control is announced only once.
float g_fLastChargerAnnounce[MAXPLAYERS + 1][MAXPLAYERS + 1];

public void OnPluginStart()
{
	LoadTranslations("l4d2_si_control_health.phrases");
	ResetChargerAnnounceTimes();

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("tongue_grab", Event_Control, EventHookMode_Post);
	HookEvent("lunge_pounce", Event_Control, EventHookMode_Post);
	HookEvent("jockey_ride", Event_Control, EventHookMode_Post);
	HookEvent("charger_impact", Event_Control, EventHookMode_Post);
	HookEvent("charger_carry_start", Event_Control, EventHookMode_Post);
	HookEvent("charger_pummel_start", Event_Control, EventHookMode_Post);
}

public void OnMapStart()
{
	ResetChargerAnnounceTimes();
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ResetChargerAnnounceTimes();
}

void Event_Control(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	int victim = GetClientOfUserId(event.GetInt("victim"));

	if (!IsValidClient(attacker) || !IsValidClient(victim))
	{
		return;
	}

	if (GetClientTeam(attacker) != L4D2Team_Infected ||
		GetClientTeam(victim) != L4D2Team_Survivor)
	{
		return;
	}

	if (!HasEntProp(attacker, Prop_Send, "m_zombieClass"))
	{
		return;
	}

	int zombieClass = GetEntProp(attacker, Prop_Send, "m_zombieClass");
	if (zombieClass < L4D2Infected_Smoker || zombieClass > L4D2Infected_Charger)
	{
		return;
	}

	if (zombieClass == L4D2Infected_Charger)
	{
		float now = GetGameTime();
		if (g_fLastChargerAnnounce[attacker][victim] >= 0.0 &&
			now - g_fLastChargerAnnounce[attacker][victim] < 0.25)
		{
			return;
		}

		g_fLastChargerAnnounce[attacker][victim] = now;
	}

	int remainingHealth = GetClientHealth(attacker);
	CPrintToChat(victim, "%t", "HealthRemaining", attacker,
		L4D2_InfectedNames[zombieClass], remainingHealth);
}

bool IsValidClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client);
}

void ResetChargerAnnounceTimes()
{
	for (int attacker = 1; attacker <= MaxClients; attacker++)
	{
		for (int victim = 1; victim <= MaxClients; victim++)
		{
			g_fLastChargerAnnounce[attacker][victim] = -1.0;
		}
	}
}
