// ==============================================================================================================================
// >>> GLOBAL INCLUDES
// ==============================================================================================================================
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#include <emitsoundany>
#include <clientprefs>

// #define DRYRUN
#if defined DRYRUN
#else
#include <shop>
#endif

// ==============================================================================================================================
// >>> PLUGIN INFORMATION
// ==============================================================================================================================
#define PLUGIN_VERSION "1.2.2"
public Plugin myinfo =
{
	name 			= "[Shop] Slots",
	author 			= "AlexTheRegent",
	description 	= "",
	version 		= PLUGIN_VERSION,
	url 			= ""
}

// ==============================================================================================================================
// >>> DEFINES
// ==============================================================================================================================
#pragma newdecls required
#define MPS 		MAXPLAYERS+1
#define PMP 		PLATFORM_MAX_PATH
#define MTF 		MENU_TIME_FOREVER
#define CID(%0) 	GetClientOfUserId(%0)
#define UID(%0) 	GetClientUserId(%0)
#define SZF(%0) 	%0, sizeof(%0)
#define LC(%0) 		for (int %0 = 1; %0 <= MaxClients; ++%0) if ( IsClientInGame(%0) ) 

#define MAXLENGTH_BETS		256
#define MAXLENGTH_BET		8
#define MAXLENGTH_REELS		32
#define MAXLENGTH_REEL		4

// ==============================================================================================================================
// >>> CONSOLE VARIABLES
// ==============================================================================================================================
ConVar	g_cvarBets;
ConVar	g_cvarSymbols;
ConVar	g_cvarRates;
ConVar	g_cvarMultipliers;
ConVar	g_cvarSoundSpin;
ConVar	g_cvarSoundSlot;
ConVar	g_cvarLogging;
ConVar	g_cvarShowCredits;
ConVar	g_cvarCreditsPool;
ConVar	g_cvarJackpotCombination;
ConVar	g_cvarJackpotMuptiplier;
ConVar	g_cvarJackpotWinMessage;
ConVar	g_cvarJackpotAdvertisement;
ConVar	g_cvarJackpotChance;
ConVar	g_cvarJackpotLastWinner;

// ==============================================================================================================================
// >>> GLOBAL VARIABLES
// ==============================================================================================================================
KeyValues 	g_data;

Menu 		g_mainMenu;
Menu 		g_betsMenu;
Menu 		g_infoMenu;

Handle		g_timer[MPS];

float 		g_multipliers[MAXLENGTH_REELS/MAXLENGTH_REEL];

char		g_reel[MAXLENGTH_REELS/MAXLENGTH_REEL][MAXLENGTH_REEL];
char 		g_soundSpin[PMP];
char 		g_soundSlot[PMP];
char 		g_slotLine[128];
char 		g_logFile[PMP];
char 		g_dataFilePath[PMP] = "data/slots.txt";

int 		g_combination[MPS][MAXLENGTH_REELS/MAXLENGTH_REEL];
int 		g_step[MPS][MAXLENGTH_REELS/MAXLENGTH_REEL];
int 		g_reelLength;
int 		g_rates[MAXLENGTH_REELS/MAXLENGTH_REEL];
int 		g_bet[MPS];
int 		g_creditsPool;
int 		g_jackpotCombination[MAXLENGTH_REELS/MAXLENGTH_REEL];
int 		g_jackpotPool;
int 		g_currentRound;

// ==============================================================================================================================
// >>> LOCAL INCLUDES
// ==============================================================================================================================


// ==============================================================================================================================
// >>> FORWARDS
// ==============================================================================================================================
public void OnPluginStart() 
{
	LoadTranslations("slots.phrases.txt");
	
	RegConsoleCmd("sm_slots", Command_Slots);
	RegAdminCmd("sm_slots_pool", Command_SlotsPool, ADMFLAG_ROOT);
	RegAdminCmd("sm_slots_jackpot", Command_SlotsJackpot, ADMFLAG_ROOT);
	
	g_mainMenu = new Menu(Handler_MainMenu, MenuAction_DisplayItem|MenuAction_Display);
	g_mainMenu.AddItem("play", "play");
	g_mainMenu.AddItem("info", "info");
	
	if ( GetEngineVersion() == Engine_CSGO ) {
		strcopy(SZF(g_slotLine), "█  %s｜%s｜%s｜%s｜%s  █");
	}
	else {
		strcopy(SZF(g_slotLine), "█ %s｜%s｜%s｜%s｜%s █");
	}
	
	g_cvarBets = CreateConVar("sm_slots_bets", "100 200 500", "available bets, separated by space");
	g_cvarSymbols = CreateConVar("sm_slots_symbols", "☠ ☀ ✪ ❤ 〠 ♛", "symbols, separated by space");
	g_cvarRates = CreateConVar("sm_slots_rates", "1 1 1 1 1 1", "rates of symbols, separated by space");
	g_cvarMultipliers = CreateConVar("sm_slots_multipliers", "-1.0 0.1 0.2 0.3 0.4 0.5", "multipliers of symbols, separated by space");
	g_cvarSoundSpin = CreateConVar("sm_slots_sound_spin", "ui/csgo_ui_crate_item_scroll.wav", "sound of wheel spin");
	g_cvarSoundSlot = CreateConVar("sm_slots_sound_slot", "ui/item_drop1_common.wav", "sound of wheel spin stop");
	g_cvarLogging = CreateConVar("sm_slots_logging", "1", "write logs (1) or not (0)");
	g_cvarShowCredits = CreateConVar("sm_slots_show_credits", "1", "show client credits in title (1) or not (0)");
	g_cvarCreditsPool = CreateConVar("sm_slots_credits_pool", "0", "enable (1) or disable (0) credits pool");
	g_cvarJackpotCombination = CreateConVar("sm_slots_jackpot_combination", "☠ ☠ ☠ ☠ ☠", "jackpot combination (empty to disable)");
	g_cvarJackpotMuptiplier = CreateConVar("sm_slots_jackpot_multiplier", "0.1", "how much of clients bets goes to jackpot pool");
	g_cvarJackpotWinMessage = CreateConVar("sm_slots_jackpot_win_message", "1", "show message on jackpot to all players (1) or only winner (0)");
	g_cvarJackpotAdvertisement = CreateConVar("sm_slots_jackpot_advertisement", "1", "how often in round to display current jackpot value");
	g_cvarJackpotChance = CreateConVar("sm_slots_jackpot_chance", "0.01", "jackpot chance in percent. 0 to disable jackpot, -1 to let plugin handle chance");
	g_cvarJackpotLastWinner = CreateConVar("sm_slots_jackpot_last_winner", "1", "show (1) or not (0) with current jackpot value information about last jackpot winner: name/amount/date");
	AutoExecConfig();
	
	HookEvent("round_start", Ev_RoundStart);
	
	LoadData();
}

void LoadData()
{
	BuildPath(Path_SM, SZF(g_dataFilePath), g_dataFilePath);
	
	g_data = new KeyValues("slots");
	if ( !g_data.ImportFromFile(g_dataFilePath) ) {
		LogError("File '%s' not found or empty/broken", g_dataFilePath);
		return;
	}
	
	g_creditsPool = g_data.GetNum("credits_pool", 0);
	g_jackpotPool = g_data.GetNum("jackpot_pool", 0);
}

public void OnMapStart()
{
	
}

public void OnConfigsExecuted() 
{
	g_cvarSoundSpin.GetString(SZF(g_soundSpin));
	PrecacheSoundAny(g_soundSpin);
	g_cvarSoundSlot.GetString(SZF(g_soundSlot));
	PrecacheSoundAny(g_soundSlot);
	
	char buffer[256];
	FormatEx(SZF(buffer), "sound/%s", g_soundSpin);
	AddFileToDownloadsTable(buffer);
	FormatEx(SZF(buffer), "sound/%s", g_soundSlot);
	AddFileToDownloadsTable(buffer);
	
	g_betsMenu = new Menu(Handler_BetsMenu, MenuAction_DisplayItem|MenuAction_Display);
	g_betsMenu.ExitBackButton = true;
	
	char bets[MAXLENGTH_BETS], bet[MAXLENGTH_BETS/MAXLENGTH_BET][MAXLENGTH_BET];
	g_cvarBets.GetString(SZF(bets));
	int bets_count = ExplodeString(bets, " ", bet, sizeof(bet), sizeof(bet[]));
	for ( int i = 0; i < bets_count; ++i ) {
		g_betsMenu.AddItem(bet[i], "");
	}
	
	char reel[MAXLENGTH_REELS];
	g_cvarSymbols.GetString(SZF(reel));
	g_reelLength = ExplodeString(reel, " ", g_reel, sizeof(g_reel), sizeof(g_reel[]));
	
	char rates[256], rate[MAXLENGTH_REELS/MAXLENGTH_REEL][8];
	g_cvarRates.GetString(SZF(rates));
	if ( g_reelLength != ExplodeString(rates, " ", rate, sizeof(rate), sizeof(rate[])) ) {
		LogError("count sm_slots_symbols != count sm_slots_rates");
		SetFailState("count sm_slots_symbols != count sm_slots_rates");
	}
	g_rates[0] = StringToInt(rate[0]);
	for ( int i = 1; i < g_reelLength; ++i ) {
		g_rates[i] = g_rates[i-1] + StringToInt(rate[i]);
	}
	
	char mutlipliers[256], mutliplier[MAXLENGTH_REELS/MAXLENGTH_REEL][8];
	g_cvarMultipliers.GetString(SZF(mutlipliers));
	if ( g_reelLength != ExplodeString(mutlipliers, " ", mutliplier, sizeof(mutliplier), sizeof(mutliplier[])) ) {
		LogError("count sm_slots_symbols != count sm_slots_multipliers");
		SetFailState("count sm_slots_symbols != count sm_slots_multipliers");
	}
	for ( int i = 0; i < g_reelLength; ++i ) {
		g_multipliers[i] = StringToFloat(mutliplier[i]);
	}
	
	char jackpotCombination[256], combination[MAXLENGTH_REELS/MAXLENGTH_REEL][8];
	g_cvarJackpotCombination.GetString(SZF(jackpotCombination));
	if ( 5 != ExplodeString(jackpotCombination, " ", combination, sizeof(combination), sizeof(combination[])) ) {
		for ( int i = 0; i < 5; ++i ) {
			g_jackpotCombination[i] = -1;
		}
	}
	else {
		for ( int i = 0; i < 5; ++i ) {
			g_jackpotCombination[i] = GetSymbolNumber(combination[i]);
		}
	}
	
	g_infoMenu = new Menu(Handler_InfoMenu, MenuAction_Display);
	g_infoMenu.ExitBackButton = true;
	
	for ( int i = 0; i < g_reelLength; ++i ) {
		char text[128];
		FormatEx(SZF(text), "%T", "about symbol", LANG_SERVER, g_reel[i], g_multipliers[i]);
		g_infoMenu.AddItem("", text, ITEMDRAW_DISABLED);
	}
	
	if ( g_cvarLogging.BoolValue ) {
		BuildPath(Path_SM, SZF(g_logFile), "logs/shop_slots.txt");
	}
}

public void Ev_RoundStart(Event event, const char[] evName, bool silent) 
{
	if ( g_currentRound % g_cvarJackpotAdvertisement.IntValue == 0 ) {
		PrintToChatAll("%T", "advertisement jackpot", LANG_SERVER, GetJackpotPool());
		
		if ( g_cvarJackpotLastWinner.BoolValue ) {
			int lastJackpot;
			char name[64], date[64];
			GetJackpotWinner(name, lastJackpot, date);
			
			if ( name[0] != 0 ) {
				PrintToChatAll("%T", "advertisement jackpot winner", LANG_SERVER, name, lastJackpot, date);
			}
		}
	}
	g_currentRound++;
}

// ==============================================================================================================================
// >>> COMMANDS 
// ==============================================================================================================================
public Action Command_Slots(int client, int argc)
{
	g_mainMenu.Display(client, MTF);
	return Plugin_Handled;
}

public Action Command_SlotsPool(int client, int argc)
{
	if ( argc == 0 ) {
		PrintToChat(client, "%T", "current credits pool", client, GetCreditsPool());
		return Plugin_Handled;
	}
	
	char new_pool[32];
	GetCmdArg(1, SZF(new_pool));
	SetCreditsPool(StringToInt(new_pool));
	
	PrintToChat(client, "%T", "new credits pool", client, GetCreditsPool());
	return Plugin_Handled;
}

public Action Command_SlotsJackpot(int client, int argc)
{
	if ( argc == 0 ) {
		PrintToChat(client, "%T", "current jackpot pool", client, GetCreditsPool());
		return Plugin_Handled;
	}
	
	char new_pool[32];
	GetCmdArg(1, SZF(new_pool));
	SetJackpotPool(StringToInt(new_pool));
	
	PrintToChat(client, "%T", "new jackpot pool", client, GetJackpotPool());
	return Plugin_Handled;
}

// ==============================================================================================================================
// >>> HANDLERS
// ==============================================================================================================================
public int Handler_MainMenu(Menu menu, MenuAction action, int client, int slot)
{
	switch (action) {
		case MenuAction_DisplayItem: {
			char phrase[64];
			menu.GetItem(slot, "", 0, _, SZF(phrase));
			
			char text[255];
			FormatEx(SZF(text), "%T", phrase, client);
			
			return RedrawMenuItem(text);
		}
		
		case MenuAction_Display: {
			char title[255];
			if ( g_cvarShowCredits.BoolValue ) {
				#if defined DRYRUN
				FormatEx(SZF(title), "%T", "slots title credits", client, 100);
				#else
				FormatEx(SZF(title), "%T", "slots title credits", client, Shop_GetClientCredits(client));
				#endif
			}
			else {
				FormatEx(SZF(title), "%T", "slots title", client);
			}
			
			menu.SetTitle(title);
		}
		
		case MenuAction_Select: {
			char item[16];
			menu.GetItem(slot, SZF(item));
			
			if ( StrEqual(item, "play") ) {
				if ( g_cvarCreditsPool.BoolValue ) {
					PrintToChat(client, "%T", "current credits pool", client, GetCreditsPool());
				}
				
				g_betsMenu.Display(client, MTF);
			}
			else if ( StrEqual(item, "info") ) {
				g_infoMenu.Display(client, MTF);
			}
			else {
				LogError(item);
			}
		}
	}
	
	return 0;
}

public int Handler_BetsMenu(Menu menu, MenuAction action, int client, int slot)
{
	switch (action) {
		case MenuAction_DisplayItem: {
			char bet[MAXLENGTH_BET];
			menu.GetItem(slot, SZF(bet));
			
			char text[255];
			FormatEx(SZF(text), "%T", "bet", client, StringToInt(bet));
			
			return RedrawMenuItem(text);
		}
		
		case MenuAction_Display: {
			char title[255];
			if ( g_cvarShowCredits.BoolValue ) {
			#if defined DRYRUN
				FormatEx(SZF(title), "%T", "bet title credits", client, 100);
				#else
				FormatEx(SZF(title), "%T", "bet title credits", client, Shop_GetClientCredits(client));
				#endif
			}
			else {
				FormatEx(SZF(title), "%T", "bet title", client);
			}
			menu.SetTitle(title);
		}
		
		case MenuAction_Select: {
			char bet[MAXLENGTH_BET];
			menu.GetItem(slot, SZF(bet));
			g_bet[client] = StringToInt(bet);
			
			
			#if defined DRYRUN
			#else
			if ( Shop_GetClientCredits(client) < g_bet[client] ) {
				PrintToChat(client, "%T", "not enough credits", client, g_bet[client] - Shop_GetClientCredits(client));
				g_betsMenu.Display(client, MTF);
				return 0;
			}
			#endif
			
			if ( g_cvarCreditsPool.BoolValue ) {
				if ( GetCreditsPool() < g_bet[client] ) {
					PrintToChat(client, "%T", "not enough credits in pool", client, g_bet[client], g_creditsPool);
					g_betsMenu.Display(client, MTF);
					return 0;
				}
			}
			
			if ( g_cvarLogging.BoolValue ) {
				char auth[32], ip[64], name[32];
				GetClientAuthId(client, AuthId_Steam2, SZF(auth));
				GetClientIP(client, SZF(ip));
				GetClientName(client, SZF(name));
				
				LogToFile(g_logFile, "%T", "log before bet", LANG_SERVER, name, auth, ip, g_bet[client]);
			}
			
			#if defined DRYRUN
			#else
			Shop_TakeClientCredits(client, g_bet[client]);
			#endif
			
			if ( g_cvarCreditsPool.BoolValue ) {
				SetCreditsPool(GetCreditsPool() + g_bet[client]);
			}
			
			if ( g_cvarJackpotMuptiplier.FloatValue > 0.0 ) {
				SetJackpotPool(GetJackpotPool() + RoundToNearest(g_cvarJackpotMuptiplier.FloatValue * g_bet[client]));
			}
			
			if ( g_cvarJackpotChance.FloatValue > 0.0  ) {
				if ( GetRandomFloat(0.0, 100.0) <= g_cvarJackpotChance.FloatValue ) {
					for ( int i = 0; i < 5; ++i ) {
						g_combination[client][i] = g_jackpotCombination[i];
						g_step[client][i] = (i+1)*10 + GetRandomInt(1, 6);
					}
				}
				else {
					for ( int i = 0; i < 5; ++i ) {
						g_combination[client][i] = GetRandomSymbol();
						g_step[client][i] = (i+1)*10 + GetRandomInt(1, 6);
					}
					
					if ( IsCombinationJackpot(client) ) {
						g_combination[client][GetRandomInt(0, 5-1)]++;
					}
				}
			}
			else {
				for ( int i = 0; i < 5; ++i ) {
					g_combination[client][i] = GetRandomSymbol();
					// g_combination[client][i] = 0;
					g_step[client][i] = (i+1)*10 + GetRandomInt(1, 6);
				}
			}
			
			// PrintToChatAll("%s %s %s %s %s", g_reel[g_combination[client][0]], g_reel[g_combination[client][1]], g_reel[g_combination[client][2]], g_reel[g_combination[client][3]], g_reel[g_combination[client][4]]);
			g_timer[client] = CreateTimer(0.1, Timer_StartAnimation, UID(client), TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
		}
		
		case MenuAction_Cancel: {
			if ( slot == MenuCancel_ExitBack ) {
				g_mainMenu.Display(client, MTF);
			}
		}
	}
	
	return 0;
}

public int Handler_InfoMenu(Menu menu, MenuAction action, int client, int slot)
{
	switch (action) {
		case MenuAction_Display: {
			char title[255];
			FormatEx(SZF(title), "%T", "info title", client);
			menu.SetTitle(title);
		}
		
		case MenuAction_Cancel: {
			if ( slot == MenuCancel_ExitBack ) {
				g_mainMenu.Display(client, MTF);
			}
		}
	}
}

public int Handler_Animation(Menu menu, MenuAction action, int client, int slot)
{
	if ( slot == 1 ) {
		if ( g_cvarCreditsPool.BoolValue ) {
			PrintToChat(client, "%T", "current credits pool", client, GetCreditsPool());
		}
		
		g_betsMenu.Display(client, MTF);
	}
}

// ==============================================================================================================================
// >>> FUNCTIONS  
// ==============================================================================================================================
int GetRandomSymbol()
{
	int random = GetRandomInt(0, g_rates[g_reelLength-1]);
	
	int num = 0;
	while ( g_rates[num] < random ) {
		num++;
	}
	
	return num;
}

int GetSlotSymbol(int client, int slot, int offset)
{
	return (offset + g_combination[client][slot] + g_step[client][slot] + g_reelLength)%g_reelLength;
}

void DisplayPanelFromString(int client, char[][] string, int length, bool showControls)
{
	Panel panel = new Panel();
	for ( int i = 0; i < length; ++i ) {
		panel.DrawText(string[i]);
	}
	
	char text[64];
	if ( showControls ) {
		FormatEx(SZF(text), "%T", "spin again", client);
		panel.DrawItem(text);
		FormatEx(SZF(text), "%T", "exit", client);
		panel.DrawItem(text);
	}
	else {
		FormatEx(SZF(text), "%T", "spin again disabled", client);
		panel.DrawText(text);
		FormatEx(SZF(text), "%T", "exit disabled", client);
		panel.DrawText(text);
	}
	
	panel.Send(client, Handler_Animation, MTF);
	delete panel;
}

// ==============================================================================================================================
// >>> TIMERS  
// ==============================================================================================================================
public Action Timer_StartAnimation(Handle timer, any userid)
{
	int client = CID(userid);
	if ( !client ) return Plugin_Stop;
	
	char content[][64] = {
		"█░░░░░░░░░░░░░░░█", 
		"█░░░░░░░░░░░░░░░█", 
		"█░░░░░░░░░░░░░░░█", 
		"█░░░░░░░░░░░░░░░█", 
		"█░░░░░░░░░░░░░░░█", 
		"█░░░░░░░░░░░░░░░█", 
		"                 ", 
		"-----------------"
	};
	
	Format(content[1], sizeof(content[]), g_slotLine, g_reel[GetSlotSymbol(client, 0, -1)], g_reel[GetSlotSymbol(client, 1, -1)], g_reel[GetSlotSymbol(client, 2, -1)], g_reel[GetSlotSymbol(client, 3, -1)], g_reel[GetSlotSymbol(client, 4, -1)]);
	Format(content[2], sizeof(content[]), g_slotLine, g_reel[GetSlotSymbol(client, 0,  0)], g_reel[GetSlotSymbol(client, 1,  0)], g_reel[GetSlotSymbol(client, 2,  0)], g_reel[GetSlotSymbol(client, 3,  0)], g_reel[GetSlotSymbol(client, 4,  0)]);
	Format(content[3], sizeof(content[]), g_slotLine, g_reel[GetSlotSymbol(client, 0,  1)], g_reel[GetSlotSymbol(client, 1,  1)], g_reel[GetSlotSymbol(client, 2,  1)], g_reel[GetSlotSymbol(client, 3,  1)], g_reel[GetSlotSymbol(client, 4,  1)]);

	
	bool playSpinSound = true;
	for ( int i = 0; i < 5; ++i ) {
		playSpinSound &= CheckSlot(client, i);
	}
	
	if ( g_step[client][4] <= 0 ) {
		DisplayPanelFromString(client, content, 7, true);
		OnSpinEnd(client);
		return Plugin_Stop;
	}
	
	if ( g_step[client][4] == 1 ) {
		g_step[client][4]--;
	}
	
	if ( playSpinSound ) {
		EmitSoundToClientAny(client, g_soundSpin);
	}
	
	DisplayPanelFromString(client, content, 7, false);
	return Plugin_Continue;
}

void OnSpinEnd(int client)
{
	int won;
	if ( IsCombinationJackpot(client) ) {
		won = GetJackpotPool();
		SetJackpotPool(0);
		
		if ( g_cvarJackpotWinMessage.BoolValue ) {
			char name[32];
			GetClientName(client, SZF(name));
			PrintToChatAll("%T", "jackpot won all", client, name, won);
		}
		else {
			PrintToChat(client, "%T", "jackpot won", client, won);
		}
		
		char name[64], date[64];
		GetClientName(client, SZF(name));
		FormatTime(SZF(date), "%H:%M %m/%d/%y", GetTime());
		SetJackpotWinner(name, won, date);
	}
	else {
		float multiplier = 1.0;
		for ( int i = 0; i < 5; ++i ) {
			multiplier += g_multipliers[g_combination[client][i]];
		}
		
		won = RoundToNearest(g_bet[client] * multiplier);
		if ( won < 1 ) won = 0;
		if ( g_cvarLogging.BoolValue ) {
			char auth[32], ip[64], name[32];
			GetClientAuthId(client, AuthId_Steam2, SZF(auth));
			GetClientIP(client, SZF(ip));
			GetClientName(client, SZF(name));
			
			LogToFile(g_logFile, "%T", "log after bet", LANG_SERVER, name, auth, ip, g_bet[client], won);
		}
	}
	
	if ( won > 0 ) {
		#if defined DRYRUN
		#else
		Shop_GiveClientCredits(client, won);
		#endif
	}
	
	if ( g_cvarCreditsPool.BoolValue ) {
		int rem = GetCreditsPool() - won;
		if ( rem < 0 ) rem = 0;
		SetCreditsPool(rem);
	}
	
	EmitSoundToClientAny(client, g_soundSlot);
	PrintToChat(client, "%T", "won", client, won);
}

bool CheckSlot(int client, int slot)
{
	if ( g_step[client][slot] > 0 ) {
		g_step[client][slot]--;
		
		if ( g_step[client][slot] == 0 ) {
			EmitSoundToClientAny(client, g_soundSlot);
			return false;
		}
	}
	
	return true;
}

int GetSymbolNumber(const char[] symbol)
{
	for ( int i = 0; i < g_reelLength; ++i ) {
		if ( StrEqual(g_reel[i], symbol, false) ) {
			return i;
		}
	}
	return -1;
}

bool IsCombinationJackpot(int client)
{
	if ( g_cvarJackpotChance.FloatValue == 0.0 ) {
		return false;
	}
	
	for ( int i = 0; i < 5; ++i ) {
		if ( g_combination[client][i] != g_jackpotCombination[i] ) {
			return false;
		}
	}
	
	return true;
}

void SetCreditsPool(int pool)
{
	g_data.SetNum("credits_pool", pool);
	g_data.ExportToFile(g_dataFilePath);
	g_creditsPool = pool;
}

int GetCreditsPool()
{
	return g_creditsPool;
}

void SetJackpotPool(int pool)
{
	g_data.SetNum("jackpot_pool", pool);
	g_data.ExportToFile(g_dataFilePath);
	g_jackpotPool = pool;
}

int GetJackpotPool()
{
	return g_jackpotPool;
}

void SetJackpotWinner(char[] name, int pool, char[] date)
{
	g_data.SetString("last_winner_name", name);
	g_data.SetNum("last_winner_pool", pool);
	g_data.SetString("last_winner_date", date);
	g_data.ExportToFile(g_dataFilePath);
}

void GetJackpotWinner(char[] name, int& pool, char[] date)
{
	g_data.GetString("last_winner_name", name, 64, "");
	pool = g_data.GetNum("last_winner_pool", 0);
	g_data.GetString("last_winner_date", date, 64, "");
}
