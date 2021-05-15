#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <devzones>
#include <multicolors>

#pragma newdecls required

#define ANTI_RUSH_ZONE_PREFIX "antirush_"
#define NOT_FOUND -1

ConVar g_cvEnable;
ConVar g_cvPunishment;
ConVar g_cvLastMan;
ConVar g_cvRemoveOnPlant;
ConVar g_cvRemoveTime;
ConVar g_cvNotifyMode;
ConVar g_cvMessages;
ConVar g_cvMissing;

bool g_bEnable = true;
bool g_bAntiRush = true;
bool g_bLastMan = true;
bool g_bRemoveOnPlant = true;
bool g_bMessages = true;
bool g_bMissing = false;

int g_iPunishment = 0;
int g_iNotifyMode = 1;

float g_fRemoveTime = 15.0;

Handle g_pTimer = null;

public Plugin myinfo = 
{
	name = 			"Anti-Rush Reborn",
	author = 		"kRatoss",
	description = 	"Provies In-Game bariers to prevent players from rushing",
	version = 		"1.0"
};

public void OnPluginStart()
{
	g_cvEnable 			= CreateConVar("sm_csgo_antirush_enable", "1", "Is the plugin enabled?\n1 = Yes\n0 = No");
	g_cvPunishment 		= CreateConVar("sm_csgo_antirush_punishment", "0", "How to punish players that goes into the anti-rush bariers?\n0 = Bounce Back(Default)\n1 = Slay");
	g_cvLastMan 		= CreateConVar("sm_csgo_antirush_rush_last_man", "1", "If there is only 1 player left alive in a team, disable anti-rushing? (Allow players to push)\n1 = Enabled\n2 = Disabled");
	g_cvRemoveOnPlant	= CreateConVar("sm_csgo_antirush_remove_on_plant", "1", "Remove the bariers when the bomb is planted?\n1 = Yes\n0 = No");
	g_cvRemoveTime 		= CreateConVar("sm_csgo_antirush_remove_time", "15", "Lifespan of the barriers in seconds");
	g_cvNotifyMode 		= CreateConVar("sm_csgo_antirush_notify_mode", "1", "How to notify when a player enters the barier?\n0 = Disabled\n1 = Only the player\n2 = Everybody\n3 = Admins Only");
	g_cvMessages		= CreateConVar("sm_csgo_antirush_messages", "1", "Prin messages about antirush?\n1 = Enabled\n0 = Disabled");
	g_cvMissing 		= CreateConVar("sm_csgo_antirush_missing", "0", "Automatically search for missing zones on each map?\n1 = Yes\n0 = No");
	
	HookConVarChange(g_cvEnable, CVarHook_OnChange);
	HookConVarChange(g_cvPunishment, CVarHook_OnChange);
	HookConVarChange(g_cvLastMan, CVarHook_OnChange);
	HookConVarChange(g_cvRemoveOnPlant, CVarHook_OnChange);
	HookConVarChange(g_cvRemoveTime, CVarHook_OnChange);
	HookConVarChange(g_cvNotifyMode, CVarHook_OnChange);
	HookConVarChange(g_cvMessages, CVarHook_OnChange);
	
	AutoExecConfig(true, "antirush_reborn");
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("bomb_planted", Event_BombPlanted);
	
	LoadTranslations("antirush_csgo.phrases");
	
	RegConsoleCmd("sm_debug", Command_Debug);
}

public Action Command_Debug(int client, int args)
{
	if(g_bAntiRush)
	{
		return Plugin_Handled;
	}
	
	return Plugin_Handled;
}

public void OnMapStart()
{
	g_pTimer = null;
	g_bAntiRush = true;
	
	CreateTimer(5.0, Timer_CheckForZones, _, TIMER_FLAG_NO_MAPCHANGE);
}

void CVarHook_OnChange(ConVar cvCvar, const char[] sOldValue, const char[] sNewValue)
{
	// "sm_csgo_antirush_enable"
	if(cvCvar == g_cvEnable)
	{
		// Update the variable based on the new value
		g_bEnable = view_as<bool>(StringToInt(sNewValue));
	}
	// "sm_csgo_antirush_punishment"
	else if(cvCvar == g_cvPunishment)
	{
		int iValue = view_as<int>(StringToInt(sNewValue));
		switch(iValue)
		{
			case 0:g_iPunishment = 0;
			case 1:g_iPunishment = 1;
			default:
			{
				// In case they set "sm_csgo_antirush_punishment" to some weird value like -1 or 3
				LogMessage("Warning: \"sm_csgo_antirush_punishment\" is above maximum value (\"1\"). Setting it to \"0\"..");
				g_iPunishment = 0;
			}
		}
	}
	
	// "sm_csgo_antirush_rush_last_man"
	else if(cvCvar == g_cvLastMan)
	{
		g_bLastMan = view_as<bool>(StringToInt(sNewValue));
	}
	// "sm_csgo_antirush_remove_on_plant"
	else if(cvCvar == g_cvRemoveOnPlant)
	{
		g_bRemoveOnPlant = view_as<bool>(StringToInt(sNewValue));
	}
	// "sm_csgo_antirush_remove_time"
	else if(cvCvar == g_cvRemoveTime)
	{
		g_fRemoveTime = view_as<float>(StringToFloat(sNewValue));
	}
	// "sm_csgo_antirush_notify_mode"
	else if(cvCvar == g_cvNotifyMode)
	{
		g_iNotifyMode = view_as<int>(StringToInt(sNewValue));
		if(g_iNotifyMode < 0 || g_iNotifyMode > 3)
		{
			// In case they set "sm_csgo_antirush_notify_mode" to some weird value like -1 or over 3
			LogMessage("Warning: \"sm_csgo_antirush_notify_mode\" is above maximum value (\"3\"). Setting it to \"1\"..");
			g_iNotifyMode = 1;
		}
	}
	// "sm_csgo_antirush_messages"
	else if(cvCvar == g_cvMessages)
	{
		g_bMessages = view_as<bool>(StringToInt(sNewValue));
	}
	// "sm_csgo_antirush_missing"
	else if(cvCvar == g_cvMissing)
	{
		g_bMissing = view_as<bool>(StringToInt(sNewValue));
	}
}

public void OnConfigsExecuted()
{
	static char sValue[12];
	static ConVar cvCvar;
	
	// "sm_csgo_antirush_enable"
	if((cvCvar = FindConVar("sm_csgo_antirush_enable")) != null)
	{
		// Update the variable based on the new value
		cvCvar.GetString(sValue, sizeof(sValue));
		g_bEnable = view_as<bool>(StringToInt(sValue));
	}
	// "sm_csgo_antirush_punishment"
	if((cvCvar = FindConVar("sm_csgo_antirush_punishment")) != null)
	{
		cvCvar.GetString(sValue, sizeof(sValue));
		int iValue = view_as<int>(StringToInt(sValue));
		switch(iValue)
		{
			case 0:g_iPunishment = 0;
			case 1:g_iPunishment = 1;
			default:
			{
				// In case they set "sm_csgo_antirush_punishment" to some weird value like -1 or 3
				LogMessage("Warning: \"sm_csgo_antirush_punishment\" is above maximum value (\"1\"). Setting it to \"0\"..");
				g_iPunishment = 0;
			}
		}
	}
	// "sm_csgo_antirush_rush_last_man"
	if((cvCvar = FindConVar("sm_csgo_antirush_rush_last_man")) != null)
	{
		cvCvar.GetString(sValue, sizeof(sValue));
		g_bLastMan = view_as<bool>(StringToInt(sValue));
	}
	// "sm_csgo_antirush_remove_on_plant"
	if((cvCvar = FindConVar("sm_csgo_antirush_remove_on_plant")) != null)
	{
		cvCvar.GetString(sValue, sizeof(sValue));
		g_bRemoveOnPlant = view_as<bool>(StringToInt(sValue));
	}
	// "sm_csgo_antirush_remove_time"
	if((cvCvar = FindConVar("sm_csgo_antirush_remove_time")) != null)
	{
		cvCvar.GetString(sValue, sizeof(sValue));
		g_fRemoveTime = view_as<float>(StringToFloat(sValue));
	}
	// "sm_csgo_antirush_notify_mode"
	if((cvCvar = FindConVar("sm_csgo_antirush_notify_mode")) != null)
	{
		cvCvar.GetString(sValue, sizeof(sValue));
		g_iNotifyMode = view_as<int>(StringToInt(sValue));
		if(g_iNotifyMode < 0 || g_iNotifyMode > 3)
		{
			// In case they set "sm_csgo_antirush_notify_mode" to some weird value like -1 or over 3
			LogMessage("Warning: \"sm_csgo_antirush_notify_mode\" is above maximum value (\"3\"). Setting it to \"1\"..");
			g_iNotifyMode = 1;
		}
	}
	// "sm_csgo_antirush_messages"
	if((cvCvar = FindConVar("sm_csgo_antirush_messages")) != null)
	{
		cvCvar.GetString(sValue, sizeof(sValue));
		g_bMessages = view_as<bool>(StringToInt(sValue));
	}
	// "sm_csgo_antirush_missing"	
	if((cvCvar = FindConVar("sm_csgo_antirush_messages")) != null)
	{
		cvCvar.GetString(sValue, sizeof(sValue));
		g_bMissing = view_as<bool>(StringToInt(sValue));
	}
	// Free the memory
	// (?) Not actually needed
	//delete cvCvar;
}

public Action Timer_CheckForZones(Handle pTimer)
{
	if(g_bMissing)
	{
		static char sMap[PLATFORM_MAX_PATH], sPath[PLATFORM_MAX_PATH], sZoneName[PLATFORM_MAX_PATH];
		static File hFile;
		static KeyValues hKv;
		static int iZonesCount;
		
		GetCurrentMap(sMap, sizeof(sMap));
		StringToLowerCase(sMap);
		
		BuildPath(Path_SM, sPath, sizeof(sPath), "configs/dev_zones/%s.zones.txt", sMap);
		hFile = OpenFile(sPath, "r"); // Open the config file for reading!
		
		if(hFile == null)
		{
			BuildPath(Path_SM, sPath, sizeof(sPath), "configs/dev_zones/workshop/%s.zones.txt", sMap);
			hFile = OpenFile(sPath, "r"); // Open the config file for reading!
			
			if(hFile == null)
			{
				SetFailState("There are no anti-rush zones for map \"%s\" ( missing config \"%s\").", sMap, sPath);
			}
			else
			{
				hKv = new KeyValues("Zones");
				hKv.ImportFromFile(sPath);
				
				if(hKv.GotoFirstSubKey())
				{
					iZonesCount = 0;
					do 
					{
						hKv.GetString("name", sZoneName, sizeof(sZoneName));
						
						if(StrContains(sZoneName, ANTI_RUSH_ZONE_PREFIX, false) != NOT_FOUND)
						{
							iZonesCount++;
						}
					}
					while (hKv.GotoNextKey());
					
					LogMessage("Loaded \"%i\" zones from \"%s\".", iZonesCount, sPath);
					if(iZonesCount == 0)
					{
						//SetFailState("There are no anti-rush zones for map \"%s\" ( 0 zones with \"%s\" in their names found )", sMap, ANTI_RUSH_ZONE_PREFIX);
					}
				}
				else
				{
					SetFailState("There are no anti-rush zones for map \"%s\" ( wrong configuration )", sMap);
				}
			}
		}
	}
}

public void Event_RoundStart(Event pEvent, const char[] sName, bool bDontBroadcast)
{
	if(!IsWarmupPeriod())
	{
		if(g_bEnable)
		{
			if(g_bMessages)
			{
				for (int iClient = 1; iClient <= MaxClients; iClient++)
				{
					if(IsClientInGame(iClient))
					{
						CPrintToChat(iClient, "%T", "AnnounceAntiRush", iClient, RoundFloat(g_fRemoveTime));
					}
				}		
			}
			
			g_bAntiRush = true;
			
			static ConVar cvFreezeTime; 
			cvFreezeTime = FindConVar("mp_freezetime");
			
			delete g_pTimer;
			g_pTimer = CreateTimer(g_fRemoveTime + cvFreezeTime.FloatValue, Timer_RemoveAntiRush, _, TIMER_FLAG_NO_MAPCHANGE);
			g_pTimer = null;
			
			delete cvFreezeTime;
		}
	}
}

public void Event_BombPlanted(Event pEvent, const char[] sName, bool bDontBroadcast)
{
	if(g_bEnable)
	{
		if(g_bRemoveOnPlant && g_bAntiRush)
		{
			if(g_bMessages)
			{
				CPrintToChatAll("%T", "BombPlant", LANG_SERVER);	
			}
			g_bAntiRush = false;
		}
	}
}

public void Event_PlayerDeath(Event pEvent, const char[] sName, bool bDontBroadcast)
{
	if(!IsWarmupPeriod())
	{
		// Make sure the plugin is enabled before performing any action!
		if(g_bEnable && g_bLastMan)
		{
			static int iVictim, iTeam, iAlivePlayers;
			iVictim = GetClientOfUserId(pEvent.GetInt("userid"));
			
			// Make sure is a client
			if(iVictim >= 1 && iVictim <= MaxClients)
			{
				if(IsClientInGame(iVictim))
				{
					iTeam = GetClientTeam(iVictim);
					iAlivePlayers = 0;
					
					static int iClient;
					for (iClient = 1; iClient <= MaxClients; iClient++)
					{
						if(IsClientInGame(iClient) && GetClientTeam(iClient) == iTeam && IsPlayerAlive(iClient))
						{
							// Count alive players in team
							iAlivePlayers++;
						}
					}
					
					// If there is only 1 person left alive in a team and rushing is not allowed yet
					if(iAlivePlayers == 1 && g_bAntiRush)
					{
						if(g_bMessages)
						{
							CPrintToChatAll("%T", "LastManStanding", LANG_SERVER);
						}
						g_bAntiRush = false;
					}
				}		
			}
		}
	}
}

public Action Timer_RemoveAntiRush(Handle pTimer)
{
	if(!IsWarmupPeriod())
	{
		if(g_bAntiRush)
		{
			if(g_bMessages)
			{
				CPrintToChatAll("%T", "NotifyAllowRush", LANG_SERVER);
			}
			g_bAntiRush = false;	
		}
	}
}

public void Zone_OnClientEntry(int iClient, const char[] sZone)
{
	if(!IsWarmupPeriod())
	{
		static char sPlayerName[32];
		
		// Check if the plugin is enabled before doing any action
		if(g_bEnable && g_bAntiRush)
		{
			// Make sure the client is valid.
			if(iClient > 0 && iClient <= MaxClients && IsClientInGame(iClient) && IsPlayerAlive(iClient))
			{
				// Check if the zone is part of our plugin and not added by another plugin.
				if(StrContains(sZone, ANTI_RUSH_ZONE_PREFIX, false) != NOT_FOUND)
				{
					// Expected Name: antirush_ct_longdoors, antirush_tr_longdoors, antirush_both_longdoors
					static int iTeam = CS_TEAM_NONE;
					if(StrContains(sZone, "ct", false) != NOT_FOUND)
						iTeam = CS_TEAM_CT;
					else if(StrContains(sZone, "tr", false) != NOT_FOUND)
						iTeam = CS_TEAM_T;
					else if(StrContains(sZone, "both", false) != NOT_FOUND)
						iTeam = CS_TEAM_NONE;
					
					// If the zone doesn't depend on the team or the client is in the team that is not allowed to rush. Block him from entering the zone!
					if(iTeam == CS_TEAM_NONE || GetClientTeam(iClient) == iTeam)
					{
						switch(g_iPunishment)
						{
							// Bounce back
							case 0: 
							{
								// Get the position of the zone
								static float fZonePosition[3];
								Zone_GetZonePosition(sZone, false, fZonePosition);
								
								// Get the position of the player
								static float fPlayerPosition[3];
								GetClientAbsOrigin(iClient, fPlayerPosition);
								
								// Credits: Franc1sco
								// ---------------------------------------------------------------------------------------
								// Create vector from the given starting and ending points.
								static float fVector[3];
								MakeVectorFromPoints(fZonePosition, fPlayerPosition, fVector);
								
								// Normalize the vector (equal magnitude at varying distances).
								NormalizeVector(fVector, fVector);
								
								// Apply the magnitude by scaling the vector (multiplying each of its components).
								ScaleVector(fVector, 350.0);
								// ---------------------------------------------------------------------------------------
								
								// Always set the velocity to at least 300 units
								if(fVector[1] > 0.0 && fVector[1] < 300.0)
									fVector[1] = 300.0;
									
								if(fVector[0] > 0.0 && fVector[0] < 300.0)
									fVector[0] = 300.0;	
									
								// Invert the z velocity so we don't bounce the player UP.
								if(fVector[2] > 0.0)
									fVector[2] *= -1.0;
								
								TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, fVector);
								
								if(g_bMessages)
								{
									switch(g_iNotifyMode)
									{
										// Notify the player
										case 1: 
										{
											CPrintToChat(iClient, "%T", "NotifyPlayer", iClient); 
										}
										// Notify everybody
										case 2:
										{
											GetClientName(iClient, sPlayerName, sizeof(sPlayerName));
											CPrintToChatAll("%T", "NotifyServer", LANG_SERVER, sPlayerName);
										}
										// Notify admins
										case 3:
										{
											GetClientName(iClient, sPlayerName, sizeof(sPlayerName));
											for (int iAdmin = 1; iAdmin <= MaxClients; iAdmin++)
											{
												if(IsClientInGame(iAdmin) && GetUserFlagBits(iAdmin))
												{
													CPrintToChat(iAdmin, "%T", "NotifyServer", LANG_SERVER, sPlayerName);
												}
											}
										}
									}							
								}
							}	
							// Slay
							case 1:
							{
								ForcePlayerSuicide(iClient);
								
								if(g_bMessages)
								{
									switch(g_iNotifyMode)
									{
										// Notify the player
										case 1: 
										{
											CPrintToChat(iClient, "%T", "NotifySlay", iClient);
										}
										// Notify everybody
										case 2:
										{
											GetClientName(iClient, sPlayerName, sizeof(sPlayerName));
											CPrintToChatAll("%T", "NotifyServerSlay", LANG_SERVER, sPlayerName);
										}
										// Notify admins
										case 3:
										{
											GetClientName(iClient, sPlayerName, sizeof(sPlayerName));
											for (int iAdmin = 1; iAdmin <= MaxClients; iAdmin++)
											{
												if(IsClientInGame(iAdmin) && GetUserFlagBits(iAdmin))
												{
													CPrintToChat(iAdmin, "%T", "NotifyServerSlay", LANG_SERVER, sPlayerName);
												}
											}
										}
									}							
								}
							}
						}
					}
				}		
			}
		}
	}
}

stock bool IsWarmupPeriod()
{
	return view_as<bool>(GameRules_GetProp("m_bWarmupPeriod"));
}

// https://github.com/Franc1sco/DevZones/blob/master/DevZones%20(CORE%20PLUGIN)/scripting/devzones.sp#L1437-L1456
/**
 * Converts the given string to lower case
 *
 * @param szString     Input string for conversion and also the output
 * @return             void
 */
stock void StringToLowerCase(char[] szInput) 
{
    int iIterator = 0;

    while (szInput[iIterator] != EOS) 
    {
        if (!IsCharLower(szInput[iIterator])) szInput[iIterator] = CharToLower(szInput[iIterator]);
        else szInput[iIterator] = szInput[iIterator];

        iIterator++;
    }

    szInput[iIterator + 1] = EOS;
}