extends "res://tests/venue/test_operational_routes.gd"
## Diagnostic variant: persist the route report and quarter-tile map.
func _initialize() -> void:
 OS.set_environment("GRAND_EXHIBIT_CONNECTIVITY_MAP","1")
 OS.set_environment("GRAND_EXHIBIT_CONNECTIVITY_REPORT","/tmp/ge-connectivity-audit.json")
 super._initialize()
