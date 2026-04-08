class_name SupportPowers

extends Node3D

var cooldown: int = 60


## this is supposed to be overwritten by extending SupportPowers
func _get_tooltip() -> String:
	return (
		"{0} - {1}\n{2} HP, {3} DPS\n{4}: {5}"
		. format(
			[
				tr("HELICOPTER"),
				tr("HELICOPTER_DESCRIPTION"),
			]
		)
	)
