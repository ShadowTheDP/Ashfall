extends Node
## Pooled SFX plus the generated ambient loop.
## All clips come from tools/make_sfx.py; the music bed comes from
## tools/make_music.py.

const CLIPS := [
	"swing", "hit", "crit", "roll", "jump", "land",
	"hurt", "death", "pickup", "shoot", "ui", "wave",
	"throw", "block", "dodge", "slam", "boss", "reward",
]

var streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var music: AudioStreamPlayer


func _ready() -> void:
	for name in CLIPS:
		var path := "res://assets/audio/%s.wav" % name
		if ResourceLoader.exists(path):
			streams[name] = load(path)
	for i in 16:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = -8.0
		add_child(player)
		_pool.append(player)
	_start_music()


func _start_music() -> void:
	var path := "res://assets/audio/music_loop.wav"
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStreamWAV
	if stream == null:
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * float(stream.mix_rate))
	music = AudioStreamPlayer.new()
	music.stream = stream
	music.volume_db = -19.0
	music.bus = "Master"
	add_child(music)
	music.play()


func play(name: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if not streams.has(name) or _pool.is_empty():
		return
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = streams[name]
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.96, 1.05)
	player.play()
