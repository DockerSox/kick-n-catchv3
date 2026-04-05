extends Node

var team_a_player: int = 1
var team_b_player: int = 1
var score_a: int = 0
var score_b: int = 0
var attacking_team: String = ""
var contest_winner: String = ""
var return_scene: String = ""
var contest_reason: String = ""
var contest_crosshair_pos: Vector2 = Vector2.ZERO
var p1_team: String = "A"
var p2_team: String = "B"

func reset_score() -> void:
	score_a = 0
	score_b = 0

func go_to_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
