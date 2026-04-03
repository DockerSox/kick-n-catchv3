extends Node

# Persists across scene changes
var team_a_player: int = 1   # 1 = human, 0 = cpu
var team_b_player: int = 1
var score_a: int = 0
var score_b: int = 0
var attacking_team: String = ""  # "A" or "B"

# Contest Game context
var contest_winner: String = ""        # "A" or "B" — set by contest game on win
var return_scene: String = ""          # scene to return to after contest
var contest_reason: String = ""        # "kickoff", "clash", "no_unit"
var contest_crosshair_pos: Vector2 = Vector2.ZERO  # pitch position to resume from

func reset_score() -> void:
	score_a = 0
	score_b = 0

func go_to_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
