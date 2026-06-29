extends AnimatedSprite2D


var weapons = {

	"pistola": {
		"animation":"pistola",
		"damage":25,
		"cooldown":0.3,
		"range":1200,
		"magazine":12
	},

	"mitra": {
		"animation":"mitra",
		"damage":20,
		"cooldown":0.12,
		"range":1600,
		"magazine":30
	},

	"pompa": {
		"animation":"pompa",
		"damage":12,
		"cooldown":0.8,
		"range":800,
		"pellets":8,
		"spread":0.2,
		"magazine":8
	},

	"granata": {
		"animation":"granata",
		"damage":100,
		"cooldown":1.5,
		"range":1000,
	}
}

var current_weapon := "mitra"
