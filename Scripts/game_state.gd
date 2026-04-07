extends Node

var score_a: int = 0
var score_b: int = 0

var attacking_team: String = ""
var contest_winner: String = ""
var return_scene: String = ""
var contest_reason: String = ""
var contest_crosshair_pos: Vector2 = Vector2.ZERO

# Array of Dictionaries, one per human player, in join order.
# Each dict: { "input_id": String, "team": String, "unit_role": String }
# input_id: "kb0", "kb1", "joy0".."joy7"
var players: Array = []

# Index into players[] for the player who controlled the contest unit.
var contest_player_index: int = -1

func reset_score() -> void:
	score_a = 0
	score_b = 0

func go_to_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)

func get_players_on_team(team: String) -> Array:
	var result: Array = []
	for p in players:
		if p["team"] == team:
			result.append(p)
	return result
