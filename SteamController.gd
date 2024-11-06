extends Node

@rpc("any_peer", "reliable") func receivePacket(_data): pass
@rpc("any_peer", "reliable") func receiveJoinRequest(_this_lobby_id, _friend_id): pass
@rpc("any_peer", "reliable") func receiveLobbyChat(_this_lobby_id, _change_id, _making_change_id, _chat_state, _data): pass
@rpc("any_peer", "reliable") func receiveLobbyCreated(_connect, _this_lobby_id): pass
@rpc("any_peer", "reliable") func receiveLobbyJoined(_this_lobby_id, _permissions, _locked, _response, _data): pass
@rpc("any_peer", "reliable") func receivePersonaStateChange(_this_steam_id, _flag): pass
@rpc("any_peer", "reliable") func createLobbyRPC(): pass
@rpc("any_peer", "reliable") func appendUsername(_username): pass
@rpc("any_peer", "reliable") func joinLobbyRPC(_steam_lobby_id): pass
@rpc("any_peer", "reliable") func leaveLobbyRPC(_steam_lobby_id): pass
@rpc("any_peer", "reliable") func sendP2PPacketRPC(_steam_id_remote, _data): pass
