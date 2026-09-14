#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <builtinvotes>
#include <colors>

#define FILE_PATH		"configs/l4d2_vote.txt"
#define WITCH_STATE_FILE	"data/l4d2_vote_witch_state.txt"

Handle g_hVote = INVALID_HANDLE;
Handle g_hCfgsKV = INVALID_HANDLE;
ConVar g_hWitchCanSpawn = null;

enum voteType
{
	None,
	kick,
	spec,
}
voteType g_voteType = None;

char g_sCfg[PLATFORM_MAX_PATH];
 
public Plugin myinfo =
{
	name = "l4d2_vote",
	author = "Bred",
	description = "vote for maps, hp, kick, spec",
	version = "2.2",
	url = ""
};
public void OnPluginStart()
{
	char sBuffer[128];
	GetGameFolderName(sBuffer, sizeof(sBuffer));
	if (!StrEqual(sBuffer, "left4dead2", false))
	{
		SetFailState("Only support for L4D2");
	}
	
	g_hCfgsKV = CreateKeyValues("VoteItems");
	BuildPath(Path_SM, sBuffer, sizeof(sBuffer), FILE_PATH);
	if (!FileToKeyValues(g_hCfgsKV, sBuffer))
	{
		SetFailState("Didn't find configs/l4d2_vote.txt!");
	}
	
	RegConsoleCmd("sm_vote", CommondVote);
	RegConsoleCmd("sm_votekick", Command_VoteKick);
	RegConsoleCmd("sm_votespec", Command_VoteSpec);
	RegAdminCmd("sm_hp", Command_ServerHp, ADMFLAG_ROOT);
	RegServerCmd("sm_witch_vote_state", Command_WitchVoteState);
	g_hWitchCanSpawn = FindConVar("sm_witch_can_spawn");
	
	LoadTranslations("l4d2_vote.phrases");
}

public void OnConfigsExecuted()
{
	// Confogl applies its tracked cvars during config execution. Restore the
	// vote-selected state after those defaults have been applied.
	CreateTimer(0.1, RestoreWitchState, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Command_WitchVoteState(int args)
{
	if (args != 1)
	{
		PrintToServer("[l4d2_vote] Usage: sm_witch_vote_state <0|1>");
		return Plugin_Handled;
	}

	char value[8];
	GetCmdArg(1, value, sizeof(value));
	int enabled = StringToInt(value) != 0 ? 1 : 0;
	SaveWitchState(enabled);

	if (g_hWitchCanSpawn == null)
	{
		g_hWitchCanSpawn = FindConVar("sm_witch_can_spawn");
	}
	if (g_hWitchCanSpawn != null)
	{
		SetConVarInt(g_hWitchCanSpawn, enabled);
	}
	return Plugin_Handled;
}

public Action RestoreWitchState(Handle timer)
{
	if (g_hWitchCanSpawn == null)
	{
		g_hWitchCanSpawn = FindConVar("sm_witch_can_spawn");
	}

	int enabled;
	if (g_hWitchCanSpawn != null && LoadWitchState(enabled))
	{
		SetConVarInt(g_hWitchCanSpawn, enabled);
	}
	return Plugin_Stop;
}

void SaveWitchState(int enabled)
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), WITCH_STATE_FILE);

	File file = OpenFile(path, "w");
	if (file == null)
	{
		LogError("Unable to save Witch state to %s", path);
		return;
	}
	file.WriteLine("%d", enabled != 0 ? 1 : 0);
	delete file;
}

bool LoadWitchState(int &enabled)
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), WITCH_STATE_FILE);

	File file = OpenFile(path, "r");
	if (file == null)
	{
		return false;
	}

	char value[8];
	bool read = file.ReadLine(value, sizeof(value));
	delete file;
	if (!read)
	{
		return false;
	}

	TrimString(value);
	enabled = StringToInt(value) != 0 ? 1 : 0;
	return true;
}

stock void CheatCommand(int Client, const char[] command, const char[] arguments)
{
	int admindata = GetUserFlagBits(Client);
	SetUserFlagBits(Client, ADMFLAG_ROOT);
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	FakeClientCommand(Client, "%s %s", command, arguments);
	SetCommandFlags(command, flags);
	SetUserFlagBits(Client, admindata);
}

public Action Command_ServerHp(int client, int args)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			CheatCommand(i, "give", "health");
		}
	}
	CPrintToChatAll("%t", "Vote_HP_Pass", client);
	return Plugin_Handled;
}

public Action CommondVote(int client, int args)
{
	if (!IsClientInGame(client) || IsFakeClient(client)) return Plugin_Handled;
	if (GetClientTeam(client) == 1) 
	{
		CPrintToChat(client, "%t", "Vote_Spec_Not");
		return Plugin_Handled;
	}
	
	if (args > 0)
	{
		char sCfg[PLATFORM_MAX_PATH];
		char sPath[PLATFORM_MAX_PATH];
		char sCommand[PLATFORM_MAX_PATH];
		char sMessage[256];
		GetCmdArg(1, sCfg, sizeof(sCfg));
		BuildPath(Path_SM, sPath, sizeof(sPath), "../../cfg/%s", sCfg);
		if (FileExists(sPath))
		{
			FormatEx(sCommand, sizeof(sCommand), "exec %s", sCfg);
			strcopy(sMessage, sizeof(sMessage), sCommand);
			FindConfigName(sCommand, sMessage, sizeof(sMessage));
			if (StartVote(client, sMessage))
			{
				strcopy(g_sCfg, sizeof(g_sCfg), sCommand);
				FakeClientCommand(client, "Vote Yes");
			}
			return Plugin_Handled;
		}
	}
	
	ShowVoteMenu(client);
	
	return Plugin_Handled;
}

public Action Command_VoteKick(int client, int args)
{		
	if(IsConnectedInGame(client) && GetClientTeam(client) != 1) 
	{
		g_voteType = view_as<voteType>(kick);
		CreateVoteKickMenu(client);	
	}		
	return Plugin_Handled;
}

public Action Command_VoteSpec(int client, int args)
{		
	if(IsConnectedInGame(client) && GetClientTeam(client) != 1) 
	{
		g_voteType = view_as<voteType>(spec);
		CreateVoteSpecMenu(client);		
	}		
	return Plugin_Handled;
}

void CreateVoteKickMenu(int client)
{	
	Handle kMenu = CreateMenu(Menu_VoteHandler);		
	char name[MAX_NAME_LENGTH];
	char playerid[32];
	SetMenuTitle(kMenu, "选择踢出玩家(select players):");
	for(int i = 1;i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && client != i)
		{
			Format(playerid,sizeof(playerid),"%i",GetClientUserId(i));
			if(GetClientName(i,name,sizeof(name)))
			{
				AddMenuItem(kMenu, playerid, name);						
			}
		}		
	}
	if (GetMenuItemCount(kMenu) == 0)
	{
		CPrintToChat(client, "%t", "Vote_None_Player");
		delete kMenu;
		ShowVoteMenu(client);
	}
	else
	{
		SetMenuExitBackButton(kMenu, true);
		SetMenuExitButton(kMenu, true);
		DisplayMenu(kMenu, client, 20);	
	}
}

void CreateVoteSpecMenu(int client)
{	
	Handle sMenu = CreateMenu(Menu_VoteHandler);		
	char name[MAX_NAME_LENGTH];
	char playerid[32];
	SetMenuTitle(sMenu, "选择旁观玩家(select players):");
	for(int i = 1;i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != 1 && i != client)
		{
			Format(playerid,sizeof(playerid),"%i",GetClientUserId(i));
			if(GetClientName(i,name,sizeof(name)))
			{
				AddMenuItem(sMenu, playerid, name);						
			}
		}		
	}
	if (GetMenuItemCount(sMenu) == 0)
	{
		CPrintToChat(client, "%t", "Vote_None_Player");
		delete sMenu;
		ShowVoteMenu(client);
	}
	else
	{
		SetMenuExitBackButton(sMenu, true);
		SetMenuExitButton(sMenu, true);
		DisplayMenu(sMenu, client, 20);	
	}
}

public int Menu_VoteHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char Info[64];
		char Buffer[64];
		GetMenuItem(menu, param2, Info, sizeof(Info), _, Buffer, sizeof(Buffer));
		int player = StringToInt(Info);
		player = GetClientOfUserId(player);
		
		switch (g_voteType)
		{
			case (view_as<voteType>(kick)):
			{
				int client_ilevel = 0;
				int player_ilevel = 0;
				if (GetUserAdmin(param1) != INVALID_ADMIN_ID) client_ilevel = GetAdminImmunityLevel(GetUserAdmin(param1));
				if (GetUserAdmin(player) != INVALID_ADMIN_ID) player_ilevel = GetAdminImmunityLevel(GetUserAdmin(player));
				if (client_ilevel < player_ilevel)
				{
					CPrintToChatEx(param1, player, "%t", "Vote_level_low", player);
					delete menu;
					CreateVoteKickMenu(param1);
				}
				Format(g_sCfg, sizeof(g_sCfg), "sm_kick %s", Info);
				Format(Buffer, sizeof(Buffer), "踢出玩家： %s ", Buffer);
			}
			case (view_as<voteType>(spec)):
			{
				Format(g_sCfg, sizeof(g_sCfg), "sm_swapto 1 %s", Buffer);
				Format(Buffer, sizeof(Buffer), "强制玩家旁观： %s ", Buffer);
			}
		}
		
		if (StartVote(param1, Buffer))
		{
			if (IsConnectedInGame(param1)) FakeClientCommand(param1, "Vote Yes");
			if (IsConnectedInGame(player) && GetClientTeam(player) !=1 ) FakeClientCommand(player, "Vote No");
		}
		else
		{
			ShowVoteMenu(param1);
		}
	}
/*  	if (action == MenuAction_End)		//when Menu ends by other hud, do nothing.
	{
		delete menu;
	}  */
	if (action == MenuAction_Cancel)
	{
		ShowVoteMenu(param1);
	}
	
	return 0;
}
	

bool FindConfigName(const char[] cfg, char[] message, int maxlength)
{
	KvRewind(g_hCfgsKV);
	if (KvGotoFirstSubKey(g_hCfgsKV))
	{
		do
		{
			if (KvJumpToKey(g_hCfgsKV, cfg))
			{
				KvGetString(g_hCfgsKV, "message", message, maxlength);
				return true;
			}
		} while (KvGotoNextKey(g_hCfgsKV));
	}
	return false;
}

void ShowVoteMenu(int client)
{
	Handle hMenu = CreateMenu(VoteMenuHandler);
	SetMenuTitle(hMenu, "选择:");
	char sBuffer[64];
	KvRewind(g_hCfgsKV);
	if (KvGotoFirstSubKey(g_hCfgsKV))
	{
		do
		{
			KvGetSectionName(g_hCfgsKV, sBuffer, sizeof(sBuffer));
			AddMenuItem(hMenu, sBuffer, sBuffer);
		} while (KvGotoNextKey(g_hCfgsKV));
	}
	SetMenuExitBackButton(hMenu, true);
	SetMenuExitButton(hMenu, true);
	DisplayMenu(hMenu, client, 20);
}

public int VoteMenuHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[64];
		char sBuffer[64];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		KvRewind(g_hCfgsKV);
		if (KvJumpToKey(g_hCfgsKV, sInfo) && KvGotoFirstSubKey(g_hCfgsKV))
		{
			Handle hMenu = CreateMenu(ConfigsMenuHandler, MENU_ACTIONS_ALL);
			Format(sBuffer, sizeof(sBuffer), "选择 %s :", sInfo);
			SetMenuTitle(hMenu, sBuffer);
			do
			{
				KvGetSectionName(g_hCfgsKV, sInfo, sizeof(sInfo));
				KvGetString(g_hCfgsKV, "message", sBuffer, sizeof(sBuffer));
				AddMenuItem(hMenu, sInfo, sBuffer);
			} while (KvGotoNextKey(g_hCfgsKV));
			SetMenuExitBackButton(hMenu, true);
			SetMenuExitButton(hMenu, true);
			DisplayMenu(hMenu, param1, 20);
		}
		else
		{
			PrintToChat(param1, "No such file exists.");
			ShowVoteMenu(param1);
		}
	}
/*  	if (action == MenuAction_End)
	{
		delete menu;
	}  */
	
	return 0;
}

public int ConfigsMenuHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[64];
		char sBuffer[64];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo), _, sBuffer, sizeof(sBuffer));
		strcopy(g_sCfg, sizeof(g_sCfg), sInfo);
		
		if ( StrEqual(g_sCfg, "sm_votekick") || StrEqual(g_sCfg, "sm_votespec"))
		{
			FakeClientCommand(param1, "%s", g_sCfg);
			delete menu;
			return 0;
		}
		if ( StrEqual(g_sCfg, "slots+4"))
		{
			FakeClientCommand(param1, "sm_slots %d", GetConVarInt(FindConVar("sv_maxplayers")) + 4);
			delete menu;
			return 0;
		}
		if ( StrEqual(g_sCfg, "slots-4"))
		{
			FakeClientCommand(param1, "sm_slots %d", GetConVarInt(FindConVar("sv_maxplayers")) - 4);
			delete menu;
			return 0;
		}
		if ( StrEqual(g_sCfg, "slotsfull"))
		{
			FakeClientCommand(param1, "sm_slots %d", 25);
			delete menu;
			return 0;
		}
		if ( StrEqual(g_sCfg, "slotsplayer"))
		{
			FakeClientCommand(param1, "sm_slots %d", GetPlayerCount(false));
			delete menu;
			return 0;
		}
		if (StartVote(param1, sBuffer))
		{
			if (IsConnectedInGame(param1)) FakeClientCommand(param1, "Vote Yes");
		}
		else
		{
			ShowVoteMenu(param1);
		}
	
	}
/*   	if (action == MenuAction_End)
	{
		CloseHandle(menu);
	} */
	if (action == MenuAction_Cancel)
	{
		ShowVoteMenu(param1);
	}
	
	return 0;
}

bool StartVote(int client, const char[] cfgname)
{
	if (!IsBuiltinVoteInProgress())
	{
		int iNumPlayers;
		int[] iPlayers = new int[MaxClients];
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
			{
				continue;
			}
			if (GetClientTeam(i) == 1) continue;
			iPlayers[iNumPlayers++] = i;
		}
		
		char sBuffer[64];
		g_hVote = CreateBuiltinVote(VoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
		if (g_hVote == null)
		{
			CPrintToChat(client, "%t", "Vote_Process");
			return false;
		}
		Format(sBuffer, sizeof(sBuffer), "执行 '%s' ?", cfgname);
		SetBuiltinVoteArgument(g_hVote, sBuffer);
		SetBuiltinVoteInitiator(g_hVote, client);
		SetBuiltinVoteResultCallback(g_hVote, VoteResultHandler);
		if (!DisplayBuiltinVote(g_hVote, iPlayers, iNumPlayers, 20))
		{
			delete g_hVote;
			g_hVote = null;
			CPrintToChat(client, "%t", "Vote_Process");
			return false;
		}
		CPrintToChatAllEx(client, "%t", "Vote_Initiate", client);
		return true;
	}
	CPrintToChat(client, "%t", "Vote_Process");
	return false;
}

public void VoteActionHandler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	switch (action)
	{
		case BuiltinVoteAction_End:
		{
			g_hVote = INVALID_HANDLE;
			CloseHandle(vote);
		}
		case BuiltinVoteAction_Cancel:
		{
			DisplayBuiltinVoteFail(vote, view_as<BuiltinVoteFailReason>(param1));
		}
	}
}

public void VoteResultHandler(Handle vote, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	for (int i = 0; i < num_items; i++)
	{
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES)
		{
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] >= (num_clients * 0.6))
			{
				char sCommand[PLATFORM_MAX_PATH];
				strcopy(sCommand, sizeof(sCommand), g_sCfg);
				if (sCommand[0] == '\0')
				{
					DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Generic);
					return;
				}

				DisplayBuiltinVotePass(vote, "Loading cfg file...");
				ServerCommand("%s", sCommand);
				ServerExecute();
				if (IsWitchToggleCommand(sCommand))
				{
					CreateTimer(0.2, RestartCurrentMap, _, TIMER_FLAG_NO_MAPCHANGE);
				}
				return;
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

bool IsWitchToggleCommand(const char[] command)
{
	return StrEqual(command, "exec vote/witch_on.cfg", false)
		|| StrEqual(command, "exec vote/witch_off.cfg", false);
}

public Action RestartCurrentMap(Handle timer)
{
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	ForceChangeLevel(map, "Witch vote");
	return Plugin_Stop;
}
	
stock bool IsConnectedInGame(int client)
{
    return (client > 0 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsFakeClient(client));
}

stock int GetPlayerCount(bool InGameOnly)
{
	int BotNum = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i) && IsFakeClient(i) ) BotNum++;
		continue;
	}
	return (GetClientCount(InGameOnly) - BotNum);
}
