extends RefCounted
## Weapon archetypes as plain data. weapon.gd reads one of these to fire, recoil and build
## its viewmodel, so a new gun is a new entry here. Numbers are tuned for feel.
##
## Fields:
##   mode            "auto" (hold) or "semi" (one shot per pull, presses are buffered)
##   rpm             rounds per minute
##   damage          body damage per round at close range
##   crit            precision (head) damage multiplier
##   mag, reload     magazine size and reload time in seconds
##   zoom            camera FOV multiplier while aiming down sights
##   ads_time        seconds to raise the sights
##   ads_z           how far in front of the eye the gun sits when aiming (metres, negative)
##   hip_spread, ads_spread   base cone half-angle in degrees
##   bloom, bloom_max         spread added per shot and its cap, in degrees
##   recoil_v        [min, max] upward kick per shot in degrees
##   recoil_h        [min, max] sideways kick; the bias keeps patterns mostly vertical
##   recoil_keep     share of the kick that stays in your aim; the rest recovers
##   kick            viewmodel punch per shot, 0 to 1
##   falloff         [start, end] in metres; damage drops to falloff_min past the end
##   model           shape of the box viewmodel

const ORDER := ["auto_rifle", "hand_cannon", "scout_rifle"]

const ARCHETYPES := {
	"auto_rifle": {
		"name": "Auto Rifle",
		"mode": "auto",
		"rpm": 600.0,
		"damage": 22.0,
		"crit": 1.5,
		"mag": 32,
		"reload": 2.1,
		"zoom": 0.72,
		"ads_time": 0.16,
		"ads_z": -0.24,
		"hip_spread": 1.2,
		"ads_spread": 0.15,
		"bloom": 0.12,
		"bloom_max": 1.6,
		"recoil_v": [0.5, 0.9],
		"recoil_h": [-0.3, 0.4],
		"recoil_keep": 0.35,
		"kick": 0.55,
		"falloff": [28.0, 48.0],
		"falloff_min": 0.6,
		"model": {
			"body": 0.34, "handguard": 0.26, "barrel": 0.16, "stock": true,
			"mag": Vector3(0.04, 0.14, 0.06), "optic": "iron",
			"metal": Color(0.42, 0.44, 0.47), "accent": Color(0.85, 0.55, 0.2),
		},
	},
	"hand_cannon": {
		"name": "Hand Cannon",
		"mode": "semi",
		"rpm": 140.0,
		"damage": 64.0,
		"crit": 2.4,  # the auto rifle's 1.5 plus 0.9: precision is the whole point
		"mag": 12,
		"reload": 2.5,
		"zoom": 0.8,
		"ads_time": 0.2,
		"ads_z": -0.36,  # held out at arm's length so the frame doesn't fill the view
		"hip_spread": 0.9,
		"ads_spread": 0.05,
		"bloom": 0.9,
		"bloom_max": 2.2,
		"recoil_v": [2.6, 3.4],
		"recoil_h": [-0.5, 0.9],
		"recoil_keep": 0.25,
		"kick": 1.0,
		"falloff": [24.0, 40.0],
		"falloff_min": 0.55,
		"model": {
			"body": 0.2, "handguard": 0.0, "barrel": 0.17, "stock": false,
			"mag": Vector3(0.0, 0.0, 0.0), "optic": "iron", "cylinder": true,
			"metal": Color(0.55, 0.5, 0.42), "accent": Color(0.75, 0.2, 0.15),
		},
	},
	"scout_rifle": {
		"name": "Scout Rifle",
		"mode": "semi",
		"rpm": 200.0,
		"damage": 46.0,
		"crit": 1.75,
		"mag": 15,
		"reload": 2.3,
		"zoom": 0.45,
		"ads_time": 0.24,
		"ads_z": -0.15,  # eye close to the scope
		"hip_spread": 1.6,
		"ads_spread": 0.02,
		"bloom": 0.35,
		"bloom_max": 1.4,
		"recoil_v": [1.0, 1.4],
		"recoil_h": [-0.25, 0.25],
		"recoil_keep": 0.3,
		"kick": 0.7,
		"falloff": [50.0, 80.0],
		"falloff_min": 0.7,
		"model": {
			"body": 0.4, "handguard": 0.3, "barrel": 0.22, "stock": true,
			"mag": Vector3(0.04, 0.1, 0.07), "optic": "scope",
			"metal": Color(0.32, 0.36, 0.34), "accent": Color(0.3, 0.75, 0.85),
		},
	},
}
