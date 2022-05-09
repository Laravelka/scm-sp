#include <clientmod/multicolors>
#include <sourcemod>
#include <clientmod>
#include <sdktools>
#include <cstrike>
#include <console>
#include <colors>
#include <string>
#include <regex>

#undef REQUIRE_EXTENSIONS
#include <ripext>

#undef REQUIRE_PLUGIN
#include <basecomm>

#define RIP_ON()		(CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "HTTPRequest.HTTPRequest")			== FeatureStatus_Available)
#define PLUGIN_VERSION "1.5.0"
#define VK_API_VERSION "5.131"

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name        = "Social Manager",
	author      = "Laravelka (Laravelka#3092)",
	description = "send message to vk, discord and telegram chats",
	version     = PLUGIN_VERSION,
	url         = "tg.me/laravelka"
}

Menu menuChats;
ArrayList chatsArray;
int messagesDelay = 5, chatsCount, isLogging, isPrintHostName, lastMessageTime[MAXPLAYERS+1] = 0;
char vkToken[128], ServerIp[64], HostName[256], dsToken[128], tgToken[128], sSection[256], sValueID[256], sText[MAXPLAYERS+1][MAX_MESSAGE_LENGTH], MsgWasSent[128], MsgNotSent[128];
stock int onClickMenu(Menu menu, MenuAction action, int client, int params)
{
	switch (action) {
		case MenuAction_Select:{
			char chatId[30], itemTitle[520];
			menu.GetItem(params, chatId, sizeof(chatId), _, itemTitle, sizeof(itemTitle));

			if ((lastMessageTime[client]+messagesDelay) >= GetTime() && !(GetUserFlagBits(client) & ADMFLAG_ROOT)) {
				MC_PrintToChat(client, "%t", "ClientMod.Messages.Delay", messagesDelay);
				C_PrintToChat(client, "%t", "Old.Messages.Delay", messagesDelay);
			} else {
				if (strncmp(chatId, "vk_", 3, false) == 0) {
					SendToVK(chatId[3], sText[client], client);
				} else if (strncmp(chatId, "ds_", 3, false) == 0) {
					SendToDS(chatId[3], sText[client], client);
				} else if (strncmp(chatId, "tg_", 3, false) == 0) {
					SendToTG(chatId[3], sText[client], client);
				}
			}
		}
	}
}

public void OnPluginStart()
{
	Handle convarIp = FindConVar("ip");
	Handle convarHost = FindConVar("hostname");

	GetConVarString( convarIp, ServerIp, sizeof(ServerIp));
	GetConVarString( convarHost, HostName, sizeof(HostName));

	/*
	 * Фикс для AUTOMIX/CW серверов с плагином Warmix
	 * Убирает "[В ожидании: ]" из названия сервера
	 */
	char splitactiv[12][256];
	if (ExplodeString(HostName, " [В", splitactiv, 12, sizeof(HostName)) > 1)
	{
		Format(HostName, sizeof(HostName), "%s", splitactiv[0]);
	}
	CreateConVar("scm_version", PLUGIN_VERSION, "[SM] Social Manager plugin version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_CHEAT|FCVAR_DONTRECORD);
	
	RegConsoleCmd("scm_vk", SayFromVK, "send message from VK");
	RegConsoleCmd("scm_tg", SayFromTG, "send message from Telegram");
	RegConsoleCmd("scm_ds", SayFromDS, "send message from Discord");

	RegConsoleCmd("scm", SayTo, "send message to (vk, tg or ds");
	RegConsoleCmd("scm_say", SayTo, "scm alias");
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/SocialManager.ini");
	KeyValues kv = new KeyValues("SocialManager");
	
	LoadTranslations("SocialManager.phrases");
	Format(MsgWasSent, sizeof(MsgWasSent), "%t", "Messages.MsgWasSent");
	Format(MsgNotSent, sizeof(MsgNotSent), "%t", "Messages.MsgNotSent");

	if (!FileExists(sPath, false)) {
		if (kv.JumpToKey("Settings", true)) {
			kv.SetString("vkToken", "yourvktoken");
			kv.SetString("dsToken", "yourdstoken");
			kv.SetString("tgToken", "yourtgtoken");
			
			kv.SetNum("isLogging", 1);
			kv.SetNum("messagesDelay", 5);
			kv.SetNum("isPrintHostName", 0);

			kv.Rewind();
		}

		if (kv.JumpToKey("Chats", true)) {
			kv.SetString("VK", "vk_2000000001");
			kv.SetString("Discord", "ds_2000000001");
			kv.SetString("Telegram", "tg_142805811");

			kv.Rewind();
		}
		kv.ExportToFile(sPath);
	}

	if (kv.ImportFromFile(sPath)) {
		if (kv.JumpToKey("Settings", false)) {
			kv.GetString("vkToken", vkToken, sizeof(vkToken));
			kv.GetString("dsToken", dsToken, sizeof(dsToken));
			kv.GetString("tgToken", tgToken, sizeof(tgToken));
			
			isLogging       = kv.GetNum("isLogging", 1);
			messagesDelay   = kv.GetNum("messagesDelay", 5);
			isPrintHostName = kv.GetNum("isPrintHostName", 0);

			kv.Rewind();
		}

		if (kv.JumpToKey("Chats", false)) {
			kv.GotoFirstSubKey(false);
			
			menuChats = new Menu(onClickMenu);
			menuChats.SetTitle("%t", "SayTo.MenuTitle");
			chatsArray = new ArrayList(ByteCountToCells(128));

			do {
				kv.GetSectionName(sSection, sizeof(sSection));
				kv.GetString(NULL_STRING, sValueID, sizeof(sValueID));
				
				chatsArray.PushString(sValueID);
				menuChats.AddItem(sValueID, sSection);
				
				chatsCount++;
			} while (kv.GotoNextKey(false));
		}
	} else {
		SetFailState("[SCM] KeyValues Error!");
	}
	delete kv;
}

public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] szError, int iErr_max)
{
	#if defined _ripext_included_
		MarkNativeAsOptional("HTTPRequest.HTTPRequest");
		MarkNativeAsOptional("HTTPRequest.SetHeader");
		MarkNativeAsOptional("HTTPRequest.Get");
		MarkNativeAsOptional("HTTPRequest.Post");
		MarkNativeAsOptional("HTTPRequest.AppendFormParam");
		MarkNativeAsOptional("HTTPResponse.Status.get");
	#endif
		return APLRes_Success;
}

public Action SayFromDS(int client, int args)
{
	if(client == 0 && args > 0)
	{
		char sDS[512], sBuffer[2][512];
		GetCmdArgString(sDS, sizeof(sDS));
		ReplaceString(sDS, sizeof(sDS), "\"", "", false);
		ExplodeString(sDS, "&", sBuffer, sizeof(sBuffer), sizeof(sBuffer[]));

		if(strlen(sBuffer[1]) < 1) return Plugin_Handled;

		MC_PrintToChatAll("%t", "ClientMod.SayFrom.Discord", sBuffer[0], sBuffer[1]);
		C_PrintToChatAll("%t", "Old.SayFrom.Discord", sBuffer[0], sBuffer[1]);
		ReplyToCommand(client, "[SCM][Discord] %s: %s", sBuffer[0], sBuffer[1]);
	}
	return Plugin_Continue;
}

public Action SayFromVK(int client, int args)
{
	if(client == 0 && args > 0)
	{
		char sVK[512], sBuffer[2][512];
		GetCmdArgString(sVK, sizeof(sVK));
		ReplaceString(sVK, sizeof(sVK), "\"", "", false);
		ExplodeString(sVK, "&", sBuffer, sizeof(sBuffer), sizeof(sBuffer[]));

		if(strlen(sBuffer[1]) < 1) return Plugin_Handled;

		MC_PrintToChatAll("%t", "ClientMod.SayFrom.Vk", sBuffer[0], sBuffer[1]);
		C_PrintToChatAll("%t", "Old.SayFrom.Vk", sBuffer[0], sBuffer[1]);
		ReplyToCommand(client, "[SCM][Vk] %s: %s", sBuffer[0], sBuffer[1]);
	}
	return Plugin_Continue;
}

public Action SayFromTG(int client, int args)
{
	if(client == 0 && args > 0)
	{
		char sTG[512], sBuffer[2][512];
		GetCmdArgString(sTG, sizeof(sTG));
		ReplaceString(sTG, sizeof(sTG), "\"", "", false);
		ExplodeString(sTG, "&", sBuffer, sizeof(sBuffer), sizeof(sBuffer[]));

		if(strlen(sBuffer[1]) < 1) return Plugin_Handled;

		MC_PrintToChatAll("%t", "ClientMod.SayFrom.Telegram", sBuffer[0], sBuffer[1]);
		C_PrintToChatAll("%t", "Old.SayFrom.Telegram", sBuffer[0], sBuffer[1]);
		ReplyToCommand(client, "[SCM][Telegram] %s: %s", sBuffer[0], sBuffer[1]);
	}
	return Plugin_Continue;
}

public Action SayTo(int client, int args)
{
	if (client != 0 && IsClientInGame(client) && !IsFakeClient(client)) {
		if (chatsCount < 1) {
			MC_PrintToChat(client, "%t", "ClientMod.Messages.NotWorking");
			C_PrintToChat(client, "%t", "Old.Messages.NotWorking");
			LogError("%t", "Messages.BadConfig");
		} else if (client > 0 && args < 1) {
			MC_PrintToChat(client, "%t", "ClientMod.Messages.Usage");
			C_PrintToChat(client, "%t", "Old.Messages.Usage");
		} else if (BaseComm_IsClientGagged(client)) {
			MC_PrintToChat(client, "%t", "ClientMod.Messages.ChatIsGag");
			C_PrintToChat(client, "%t", "Old.Messages.ChatIsGag");
		} else {
			char playerName[MAX_NAME_LENGTH];
			GetClientName(client, playerName, sizeof(playerName));
			ReplaceString(playerName, sizeof(playerName), "\\", "", false);
			ReplaceString(playerName, sizeof(playerName), "\"", "", false);

			GetCmdArgString(sText[client], sizeof(sText[]));

			if (isPrintHostName)
				Format(sText[client], sizeof(sText[]), "(%s) %s: %s", HostName, playerName, sText[client]);
			else
				Format(sText[client], sizeof(sText[]), "%s: %s", playerName, sText[client]);

			menuChats.Display(client, 0);
		}
	} else {
		if (chatsCount < 1) {
			LogError("%t", "Messages.BadConfig");
		} else {
			GetCmdArgString(sText[client], sizeof(sText[]));
			
			if (isPrintHostName)
				Format(sText[client], sizeof(sText[]), "%s: %s", HostName, sText[client]);
			else
				Format(sText[client], sizeof(sText[]), "%s", sText[client]);

			for(int i = 0; i < chatsArray.Length; i++) {
				char chatId[30];
				chatsArray.GetString(i, chatId, sizeof(chatId));

				if (strncmp(chatId, "vk_", 3, false) == 0) {
					SendToVK(chatId[3], sText[client], client);
				} else if (strncmp(chatId, "ds_", 3, false) == 0) {
					SendToDS(chatId[3], sText[client], client);
				} else if (strncmp(chatId, "tg_", 3, false) == 0) {
					SendToTG(chatId[3], sText[client], client);
				}
			}
		}
	}
	return Plugin_Continue;
}

/**
 * send message to vk
 *
 * @param  char  chatId
 * @param  char message
 * @param  int  client
 * @return void
 *
 */
stock void SendToVK(char[] chatId, char[] message, int client)
{
	HTTPRequest httpRequest = new HTTPRequest("https://api.vk.com/method/messages.send");
	httpRequest.SetHeader("User-Agent", "SM SocialManager plugin");

	int randomId = GetRandomInt(1111111, 9999999);
	httpRequest.AppendFormParam("v", "%s", VK_API_VERSION);
	httpRequest.AppendFormParam("peer_id", "%s", chatId);
	httpRequest.AppendFormParam("message", "%s", message);
	httpRequest.AppendFormParam("random_id", "%d", randomId);
	httpRequest.AppendFormParam("access_token", "%s", vkToken);

	httpRequest.PostForm(onVkMessageSend, client);
}

/**
 * SendToVK POST callback
 *
 * @param  HTTPResponse response
 * @param  any value
 * @return void
 *
 */
stock void onVkMessageSend(HTTPResponse response, any value)
{
	if (response.Data == null) {
		LogError("[Vk] Error: Invalid JSON response");

		if (value == 0) {
			ReplyToCommand(value, "[SCM][Vk] %t", "Messages.MsgWasSent");
		} else {
			C_PrintToChat(value, "%t", "Old.Messages.MsgNotSent", MsgNotSent);
			MC_PrintToChat(value, "%t", "ClientMod.Messages.MsgNotSent", MsgNotSent);
		}
		return;
	}

	if (response.Status != HTTPStatus_OK) {
		LogError("[Vk] Invalid status response");

		if (value == 0) {
			ReplyToCommand(value, "[SCM][Vk] %t", "Messages.MsgWasSent");
		} else {
			C_PrintToChat(value, "%t", "Old.Messages.MsgNotSent", MsgNotSent);
			MC_PrintToChat(value, "%t", "ClientMod.Messages.MsgNotSent", MsgNotSent);
		}
		return;
	}
	JSONObject data = view_as<JSONObject>(response.Data);

	if (data.HasKey("error")) {
		char errorMessage[1024];
		JSONObject error = view_as<JSONObject>(data.Get("error"));
		error.GetString("error_msg", errorMessage, sizeof errorMessage);

		if (isLogging) {
			char jsonResponse[1024];
			data.ToString(jsonResponse, sizeof jsonResponse);
			LogError("[Vk] jsonResponse: %s", jsonResponse);
		}
		
		if (value == 0) {
			ReplyToCommand(value, "[SCM][Vk] Error: %s", errorMessage);
		} else {
			C_PrintToChat(value,  "%t", "Old.Messages.MsgNotSent", MsgNotSent);
			MC_PrintToChat(value, "%t", "ClientMod.Messages.MsgNotSent", MsgNotSent);
		}
		return;
	}

	if (value == 0) {
		ReplyToCommand(value, "[SCM][VK] %s", MsgWasSent);
	} else {
		lastMessageTime[value] = GetTime();
		C_PrintToChat(value, "%t", "Old.Messages.MsgWasSent", MsgWasSent);
		MC_PrintToChat(value, "%t", "ClientMod.Messages.MsgWasSent", MsgWasSent);
	}
}

/**
 * send message to discord
 *
 * @param  char  chatId
 * @param  char message
 * @param  int  client
 * @return void
 *
 */
stock void SendToDS(char[] chatId, char[] message, int client)
{
	HTTPRequest httpRequest = new HTTPRequest(dsToken);
	httpRequest.SetHeader("User-Agent", "SM SocialManager plugin");
	httpRequest.SetHeader("Content-Type", "application/json");

	JSONObject messageParams = new JSONObject();
	messageParams.SetString("content", message);

	httpRequest.Post(messageParams, onDsMessageSend, client);
}

/**
 * SendToDS POST callback
 *
 * @param  HTTPResponse response
 * @param  any value
 * @return void
 *
 */
stock void onDsMessageSend(HTTPResponse response, any value)
{
	if (response.Status != HTTPStatus_OK && response.Status != HTTPStatus_NoContent) {
		char jsonResponse[2048];
		JSONObject data = view_as<JSONObject>(response.Data);
		data.ToString(jsonResponse, sizeof jsonResponse);
	
		if (isLogging) {
			LogError("[Discord] jsonResponse: %s", jsonResponse);
		}

		if (data.HasKey("message")) {
			char message[1024];
			data.GetString("message", message, sizeof message);
			ReplyToCommand(value, "[SCM][Discord] Error: %s", message);
		}

		if (value == 0) {
			ReplyToCommand(value, "[SCM][Discord] %t", "Messages.MsgNotSent");
		} else {
			C_PrintToChat(value,  "%t", "Old.Messages.MsgNotSent", MsgNotSent);
			MC_PrintToChat(value, "%t", "ClientMod.Messages.MsgNotSent", MsgNotSent);
		}
		return;
	} else {
		if (value == 0) {
			ReplyToCommand(value, "[SCM][Discord] %s", MsgWasSent);
		} else {
			lastMessageTime[value] = GetTime();
			C_PrintToChat(value,  "%t", "Old.Messages.MsgWasSent", MsgWasSent);
			MC_PrintToChat(value, "%t", "ClientMod.Messages.MsgWasSent", MsgWasSent);
		}
	}
}

/**
 * send message to telegram
 *
 * @param  char  chatId
 * @param  char message
 * @param  int  client
 * @return void
 *
 */
stock void SendToTG(char[] chatId, char[] message, int client)
{
	HTTPRequest httpRequest = new HTTPRequest(tgToken);
	httpRequest.SetHeader("User-Agent", "SM SocialManager plugin");
	httpRequest.SetHeader("Content-Type", "application/json");

	JSONObject messageParams = new JSONObject();

	messageParams.SetString("text", message);
	messageParams.SetString("chat_id", chatId);
	messageParams.SetString("parse_mode", "HTML");
	
	httpRequest.Post(messageParams, onTgMessageSend, client);
}

/**
 * SendToTG POST callback
 *
 * @param  HTTPResponse response
 * @param  any value
 * @return void
 *
 */
stock void onTgMessageSend(HTTPResponse response, any value)
{
	if (response.Status != HTTPStatus_OK) {
		char jsonResponse[2048];
		JSONObject data = view_as<JSONObject>(response.Data);
		data.ToString(jsonResponse, sizeof jsonResponse);
		
		if (isLogging) {
			LogError("[Telegram] jsonResponse: %s", jsonResponse);
		}

		if (data.HasKey("description")) {
			char description[1024];
			data.GetString("description", description, sizeof description);
			ReplyToCommand(value, "[SCM][Telegram] Error: %s", description);
		}

		if (value == 0) {
			ReplyToCommand(value, "[SCM][Telegram] %t", "Messages.MsgNotSent");
		} else {
			C_PrintToChat(value,  "%t", "Old.Messages.MsgNotSent", MsgNotSent);
			MC_PrintToChat(value, "%t", "ClientMod.Messages.MsgNotSent", MsgNotSent);
		}
		return;
	}

	if (response.Data == null) {
		LogError("[SCM][Telegram] Invalid JSON response");
		
		if (value == 0) {
			ReplyToCommand(value, "[SCM][Telegram] %t", "Messages.MsgNotSent");
		} else {
			C_PrintToChat(value,  "%t", "Old.Messages.MsgNotSent", MsgNotSent);
			MC_PrintToChat(value, "%t", "ClientMod.Messages.MsgNotSent", MsgNotSent);
		}
		return;
	}
	
	if (value == 0) {
		ReplyToCommand(value, "[SCM][Telegram] %s", MsgWasSent);
	} else {
		lastMessageTime[value] = GetTime();
		C_PrintToChat(value,  "%t", "Old.Messages.MsgWasSent", MsgWasSent);
		MC_PrintToChat(value, "%t", "ClientMod.Messages.MsgWasSent", MsgWasSent);
	}
}
