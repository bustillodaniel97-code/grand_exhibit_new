extends Node
## Original adaptive score for Grand Exhibit.
##
## A deterministic sequencer generates the music at runtime: a memorable
## five-note museum motif, four rotating chord routes, bass, mallet ostinato,
## soft drums and a long counter-line. Bar-level variations are selected from a
## 32-bar form, so the score develops for several minutes before its large form
## returns. Venue order changes mode, tempo and timbre while preserving the tune.

const MIX_RATE := 22050.0
const BUFFER_S := 1.0
const STEPS_PER_BEAT := 4
const BARS_IN_FORM := 32

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _voices: Array[Dictionary] = []
var _sample_clock: int = 0
var _next_step_sample: int = 0
var _step: int = 0
var _tempo: float = 94.0
var _root: int = 50
var _mode: Array[int] = [0, 2, 4, 7, 9] # bright pentatonic
var _venue_key: String = ""
var _enabled: bool = true

func _ready() -> void:
	name = "AdaptiveMusic"
	process_mode = Node.PROCESS_MODE_ALWAYS
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = BUFFER_S
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = -13.0
	add_child(_player)
	_apply_venue(GameState.current_venue)
	_enabled = bool(GameState.settings.get("music", true))
	if _enabled:
		_player.play()
		_playback = _player.get_stream_playback()
	if EventBus.has_signal("prestige_performed"):
		EventBus.prestige_performed.connect(func(_from: String, to: String) -> void:
			_apply_venue(to))

func _process(_delta: float) -> void:
	var want: bool = bool(GameState.settings.get("music", true))
	if want != _enabled:
		_enabled = want
		if want:
			_player.play()
			_playback = _player.get_stream_playback()
		else:
			_player.stop()
	if not _enabled or _playback == null:
		return
	var frames: int = _playback.get_frames_available()
	for _i in frames:
		if _sample_clock >= _next_step_sample:
			_trigger_step(_step)
			_step += 1
			_next_step_sample += _samples_per_step()
		_playback.push_frame(_mix_frame())
		_sample_clock += 1

func _apply_venue(venue_id: String) -> void:
	if venue_id == _venue_key:
		return
	_venue_key = venue_id
	var order: int = maxi(1, int(DataLoader.get_venue(venue_id).get("order", 1)))
	var tempos := [92.0, 98.0, 88.0, 104.0, 86.0, 100.0]
	var roots := [50, 53, 48, 52, 55, 49]
	_tempo = tempos[(order - 1) % tempos.size()]
	_root = roots[(order - 1) % roots.size()]
	_mode.assign([0, 2, 4, 7, 9] if order not in [3, 6] else [0, 2, 3, 7, 9])
	_voices.clear()
	_step = 0
	_sample_clock = 0
	_next_step_sample = 0

func _samples_per_step() -> int:
	return maxi(1, int(round(MIX_RATE * 60.0 / _tempo / float(STEPS_PER_BEAT))))

func _trigger_step(step_index: int) -> void:
	var beat16: int = step_index % 16
	var bar: int = (step_index / 16) % BARS_IN_FORM
	var phrase: int = bar / 4
	var chord_route: Array[int] = [
		0, 3, 4, 1, 0, 4, 3, 1,
		0, 2, 3, 4, 0, 3, 1, 4,
		0, 3, 4, 1, 2, 4, 0, 3,
		0, 4, 3, 1, 2, 3, 4, 0,
	]
	var degree: int = chord_route[bar]
	var chord_root: int = _scale_note(degree, 0)

	# Warm pad attacks once per bar; alternate inversions stop the harmony from
	# sounding pasted even when the melody returns.
	if beat16 == 0:
		var inversion: int = (bar + phrase) % 3
		for tone in 3:
			var note: int = _scale_note(degree + tone * 2, 12)
			if tone < inversion:
				note += 12
			_note(note, 0.055, 3.4, "pad", -0.35 + tone * 0.35)

	# Bass answers on beats one and three with occasional approach notes.
	if beat16 in [0, 8]:
		_note(chord_root - 12, 0.16, 0.55, "bass", -0.12)
	elif beat16 == 14 and bar % 4 == 3:
		_note(_scale_note(chord_route[(bar + 1) % BARS_IN_FORM], -12) - 1,
			0.09, 0.20, "bass", -0.12)

	# The identity: 0–2–4–2–7. It is reharmonised, displaced, answered and
	# occasionally rested, rather than replayed verbatim every bar.
	var motif := [0, -1, 1, -1, 2, -1, 1, 4, -1, 2, -1, 1, 0, -1, -1, -1]
	var m: int = motif[(beat16 + (bar % 4) * 2) % motif.size()]
	var rest_bar: bool = bar in [7, 15, 23]
	if m >= 0 and not rest_bar:
		var octave: int = 12 + (12 if phrase in [3, 6] and beat16 >= 8 else 0)
		var ornament: int = 1 if (bar * 7 + beat16) % 13 == 0 else 0
		_note(_scale_note(degree + m + ornament, octave), 0.11, 0.34,
			"mallet", 0.18)

	# A slow counter-melody only in the second half of each eight-bar section.
	if bar % 8 >= 4 and beat16 in [2, 10]:
		var counter_degree: int = degree + (4 if beat16 == 2 else 3)
		_note(_scale_note(counter_degree, 24), 0.045, 1.1, "flute", 0.42)

	# Brushed pulse: kick anchors, hats breathe, a soft click marks beat three.
	if beat16 in [0, 8]:
		_drum("kick", 0.15 if beat16 == 0 else 0.10, 0.24)
	if beat16 in [2, 6, 10, 14] and bar not in [7, 15, 23, 31]:
		_drum("hat", 0.035, 0.08)
	if beat16 == 8:
		_drum("click", 0.055, 0.12)

func _scale_note(degree: int, octave_offset: int) -> int:
	var size: int = _mode.size()
	var oct: int = floori(float(degree) / float(size))
	var idx: int = posmod(degree, size)
	return _root + _mode[idx] + oct * 12 + octave_offset

func _note(midi: int, amp: float, duration_s: float, kind: String, pan: float) -> void:
	_voices.append({"freq": 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0),
		"amp": amp, "age": 0.0, "dur": duration_s, "phase": 0.0,
		"kind": kind, "pan": pan})

func _drum(kind: String, amp: float, duration_s: float) -> void:
	_voices.append({"freq": 90.0, "amp": amp, "age": 0.0, "dur": duration_s,
		"phase": 0.0, "kind": kind, "pan": 0.0})

func _mix_frame() -> Vector2:
	var left: float = 0.0
	var right: float = 0.0
	var dead: Array[int] = []
	for i in _voices.size():
		var v: Dictionary = _voices[i]
		var age: float = float(v["age"])
		var dur: float = float(v["dur"])
		if age >= dur:
			dead.append(i)
			continue
		var phase: float = float(v["phase"])
		var freq: float = float(v["freq"])
		var kind: String = str(v["kind"])
		var env: float = _envelope(age, dur, kind)
		var sample: float = _osc(kind, phase, age, freq) * float(v["amp"]) * env
		var pan: float = clampf(float(v["pan"]), -0.8, 0.8)
		left += sample * sqrt(0.5 * (1.0 - pan))
		right += sample * sqrt(0.5 * (1.0 + pan))
		v["phase"] = fmod(phase + TAU * freq / MIX_RATE, TAU)
		v["age"] = age + 1.0 / MIX_RATE
	for i in range(dead.size() - 1, -1, -1):
		_voices.remove_at(dead[i])
	return Vector2(tanh(left * 0.85), tanh(right * 0.85))

func _envelope(age: float, dur: float, kind: String) -> float:
	var attack: float = 0.20 if kind == "pad" else 0.012
	var release: float = 0.65 if kind == "pad" else minf(0.18, dur * 0.45)
	var a: float = clampf(age / attack, 0.0, 1.0)
	var r: float = clampf((dur - age) / release, 0.0, 1.0)
	return a * r * exp(-age * (0.25 if kind == "pad" else 1.1))

func _osc(kind: String, phase: float, age: float, freq: float) -> float:
	match kind:
		"pad":
			return sin(phase) * 0.62 + sin(phase * 0.501) * 0.20 + sin(phase * 2.003) * 0.10
		"bass":
			return sin(phase) * 0.72 + (2.0 / PI) * asin(sin(phase)) * 0.18
		"mallet":
			return sin(phase) * 0.68 + sin(phase * 2.01) * 0.22 + sin(phase * 3.99) * 0.10
		"flute":
			return sin(phase) * 0.82 + sin(phase * 2.0) * 0.10
		"kick":
			return sin(phase * maxf(0.35, 1.0 - age * 5.0))
		"hat":
			return sin(phase * 17.17 + age * MIX_RATE * 1.73) * 0.55 \
				+ sin(phase * 29.31) * 0.45
		"click":
			return sin(phase * 7.0) * (1.0 if fmod(age * 260.0, 2.0) < 1.0 else -1.0)
	return sin(phase)
