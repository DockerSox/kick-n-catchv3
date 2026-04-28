extends Node
# Settings — persists user preferences to user://settings.cfg.
#
# Currently tracks:
#   tutorial_on_launch: bool — if true, game boots into tutorial; otherwise title.
#
# Future settings (audio volume, controller glyph style, etc.) can be added
# here without changing the boot flow.
 
const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "general"
 
var tutorial_on_launch: bool = true
 
func _ready() -> void:
	_load()
 
func _load() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(CONFIG_PATH)
	if err != OK:
		# First run or corrupted file — keep defaults, write fresh.
		_save()
		return
	tutorial_on_launch = cfg.get_value(SECTION, "tutorial_on_launch", true)
 
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "tutorial_on_launch", tutorial_on_launch)
	cfg.save(CONFIG_PATH)
 
func set_tutorial_on_launch(value: bool) -> void:
	tutorial_on_launch = value
	_save()
 
