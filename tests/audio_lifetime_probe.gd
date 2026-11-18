extends Node
## Bounded lifetime measurement, not proof of zero leaks at engine shutdown.
var _fails := 0
func _ready() -> void:
	if not Profile.require_test_profile(): return
	await get_tree().process_frame
	var player_id := Sfx.music.get_instance_id()
	var stream_id := Sfx.music.stream.get_instance_id()
	var stream_refs := Sfx.music.stream.get_reference_count()
	var playback_refs := Sfx.music.get_stream_playback().get_reference_count()
	var settled_refs: Dictionary = {}
	_check(Sfx.get_child_count() == 17 and Sfx._pool.size() == 16 and Sfx.streams.size() == Sfx.CLIPS.size(), "fixed initial audio ownership")
	for cycle in 5:
		$Main.enter_hub()
		_check($Main.start_node("ash_gate"), "enter test biome")
		for clip in Sfx.CLIPS: Sfx.play(clip, -60)
		$Main._on_exit_chosen("hanging_gallery")
		await get_tree().create_timer(1.8).timeout
		_check(Game.run_phase == "passage", "normal transition completes")
		var refs := {}
		for clip in Sfx.CLIPS: refs[clip] = Sfx.streams[clip].get_reference_count()
		if cycle == 0: settled_refs = refs
		_check(refs == settled_refs, "effect resource references do not accumulate after playback")
		_check(Sfx.get_child_count() == 17 and Sfx.music.get_instance_id() == player_id and Sfx.music.stream.get_instance_id() == stream_id, "Hub/biome/Passage never add or replace music resources")
		_check(Sfx.music.stream.get_reference_count() == stream_refs and Sfx.music.get_stream_playback().get_reference_count() == playback_refs and Sfx.music.playing, "music refs/playback remain stable and playing")
		print("AUDIO cycle=", cycle + 1, " players=", Sfx.get_child_count(), " stream_refs=", Sfx.music.stream.get_reference_count(), " playback_refs=", Sfx.music.get_stream_playback().get_reference_count())
	$Main.enter_hub()
	await get_tree().process_frame
	print("AUDIO LIFETIME %s (5 Hub/biome/Passage cycles; exit warning tracked separately)" % ("OK" if _fails == 0 else "FAILED"))
	get_tree().quit(0 if _fails == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_fails += 1
		push_error("AUDIO LIFETIME FAIL: " + message)
