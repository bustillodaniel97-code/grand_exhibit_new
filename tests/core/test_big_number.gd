extends SceneTree
## test_big_number.gd — BigNumber math, overflow safety, notation table.
## Run: godot --headless --path <repo> -s tests/core/test_big_number.gd

var failures := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS ", msg)
	else:
		failures += 1
		print("  FAIL ", msg)

func _init() -> void:
	call_deferred("run")

func eq_bn(b: BigNumber, pm: float, pe: int) -> bool:
	return is_equal_approx(b.m, pm) and b.e == pe

func run() -> void:
	# Bootstrap autoloads (not instantiated under -s).
	for pair in [["event_bus","EventBus"],["data_loader","DataLoader"],["clock_guard","ClockGuard"],["analytics","Analytics"],["ad_service","AdService"],["iap_service","IAPService"],["game_state","GameState"],["save_system","SaveSystem"],["economy","Economy"]]:
		var n: Node = load("res://autoload/%s.gd" % pair[0]).new()
		n.name = pair[1]
		root.add_child(n)

	print("-- construction / normalize --")
	check(eq_bn(BigNumber.zero(), 0.0, 0), "zero()")
	check(eq_bn(BigNumber.one(), 1.0, 0), "one()")
	check(eq_bn(BigNumber.from_float(0.0), 0.0, 0), "from_float(0)")
	check(eq_bn(BigNumber.from_float(-5.0), 0.0, 0), "from_float(negative) -> zero")
	check(eq_bn(BigNumber.from_float(NAN), 0.0, 0), "from_float(NAN) -> zero")
	check(eq_bn(BigNumber.from_float(1234.5), 1.2345, 3), "from_float(1234.5)")
	check(eq_bn(BigNumber.from_float(0.05), 5.0, -2), "from_float(0.05)")
	check(eq_bn(BigNumber.from_parts(123.0, 0), 1.23, 2), "from_parts normalize up-loop")
	check(eq_bn(BigNumber.from_parts(0.007, 5), 7.0, 2), "from_parts normalize down-loop")
	var cp: BigNumber = BigNumber.from_parts(2.0, 3)
	var cp2: BigNumber = cp.copy()
	cp2.m = 9.0
	check(is_equal_approx(cp.m, 2.0), "copy() is independent")

	print("-- add / sub across exponent gaps --")
	check(eq_bn(BigNumber.from_parts(5.0, 0).add(BigNumber.from_parts(5.0, 0)), 1.0, 1), "5+5=10")
	check(eq_bn(BigNumber.zero().add(BigNumber.from_parts(3.0, 4)), 3.0, 4), "0+x=x")
	check(eq_bn(BigNumber.from_parts(3.0, 4).add(BigNumber.zero()), 3.0, 4), "x+0=x")
	var big: BigNumber = BigNumber.from_parts(1.0, 20)
	check(big.add(BigNumber.one()).eq(big), "1e20 + 1 == 1e20 (gap > 15)")
	check(big.sub(BigNumber.one()).eq(big), "1e20 - 1 == 1e20 (gap > 15)")
	var s: BigNumber = BigNumber.from_parts(1.0, 15).add(BigNumber.one())
	check(not s.lt(BigNumber.from_parts(1.0, 15)), "1e15 + 1 >= 1e15 (gap = 15 at float resolution)")
	check(BigNumber.from_parts(3.0, 0).sub(BigNumber.from_parts(5.0, 0)).is_zero(), "3-5 clamps to 0")
	check(eq_bn(BigNumber.from_parts(5.0, 3).sub(BigNumber.from_parts(2.0, 3)), 3.0, 3), "5e3-2e3=3e3")

	print("-- mul / div / scale --")
	check(eq_bn(BigNumber.from_parts(2.0, 3).mul(BigNumber.from_parts(3.0, 4)), 6.0, 7), "2e3*3e4=6e7")
	check(eq_bn(BigNumber.from_parts(6.0, 7).div(BigNumber.from_parts(3.0, 4)), 2.0, 3), "6e7/3e4=2e3")
	check(BigNumber.from_parts(6.0, 7).div(BigNumber.zero()).is_zero(), "div by zero -> zero")
	check(eq_bn(BigNumber.from_parts(2.0, 3).scale(2.5), 5.0, 3), "scale(2.5)")
	check(BigNumber.from_parts(2.0, 3).scale(0.0).is_zero(), "scale(0) -> zero")
	check(BigNumber.from_parts(2.0, 3).scale(-1.0).is_zero(), "scale(negative) -> zero")

	print("-- overflow safety (1e150+ and inf mantissa) --")
	var h: BigNumber = BigNumber.from_parts(1.0, 150).mul(BigNumber.from_parts(1.0, 150))
	check(h.e == 300 and is_equal_approx(h.m, 1.0), "1e150 * 1e150 = 1e300")
	check(BigNumber.from_parts(9.99, 400).add(BigNumber.from_parts(1.0, 10)).e == 400, "add near 1e400 no hang")
	var ov: BigNumber = BigNumber.from_parts(9.9, 100).scale(1e300)  # 9.9*1e300 -> inf mantissa
	check(not is_inf(ov.m) and not is_nan(ov.m) and ov.e >= 400, "scale to inf mantissa recovered (no hang)")
	var ov2: BigNumber = BigNumber.from_parts(INF, 5)
	check(not is_inf(ov2.m) and ov2.e > 5, "from_parts(INF) recovered")
	check(BigNumber.from_parts(9.9, 500).mul(BigNumber.from_parts(9.9, 500)).e >= 1000, "mul at 1e500 stays finite")

	print("-- cmp family --")
	check(BigNumber.from_parts(1.0, 5).cmp(BigNumber.from_parts(9.0, 4)) == 1, "cmp by exponent")
	check(BigNumber.from_parts(2.0, 5).cmp(BigNumber.from_parts(1.0, 5)) == 1, "cmp by mantissa")
	check(BigNumber.from_parts(2.0, 5).cmp(BigNumber.from_parts(2.0, 5)) == 0, "cmp equal")
	check(BigNumber.zero().lt(BigNumber.one()), "zero < one")
	check(BigNumber.from_parts(2.0, 5).gte(BigNumber.from_parts(2.0, 5)), "gte equal")

	print("-- notation table --")
	var cases: Array = [
		[0.0, 0, "0"], [9.0, 0, "9"], [9.99, 2, "999"], [1.5, 1, "15"], [1.5, 2, "150"],
		[1.23, 3, "1.23K"], [4.56, 4, "45.6K"], [1.0, 6, "1M"], [4.56, 7, "45.6M"],
		[1.0, 9, "1B"], [1.0, 12, "1T"],
		[7.89, 15, "7.89aa"], [1.0, 15, "1aa"], [1.0, 17, "100aa"], [9.99, 17, "999aa"],
		[1.0, 18, "1ab"], [1.0, 90, "1az"], [1.0, 93, "1ba"],
		[9.999, 5, "1M"],
		[5.0, 3, "5K"],
	]
	for c in cases:
		var got: String = BigNumber.from_parts(c[0], c[1]).to_notation()
		check(got == c[2], "notation %se%d -> \"%s\" (got \"%s\")" % [c[0], c[1], c[2], got])

	print("-- save / from_save tolerance --")
	var rt: BigNumber = BigNumber.from_save(BigNumber.from_parts(1.23, 45).to_save())
	check(eq_bn(rt, 1.23, 45), "to_save/from_save round-trip")
	check(BigNumber.from_save("junk").is_zero(), "from_save(string) -> zero")
	check(BigNumber.from_save(42).is_zero(), "from_save(int) -> zero")
	check(BigNumber.from_save({}).is_zero(), "from_save({}) -> zero")
	check(BigNumber.from_save({"m": -5.0, "e": 3}).is_zero(), "from_save(negative m) -> zero")
	check(BigNumber.from_save({"m": "abc", "e": 1}).is_zero(), "from_save(bad m) -> zero")
	check(eq_bn(BigNumber.from_save({"m": 25.0, "e": 1}), 2.5, 2), "from_save re-normalizes")

	print("-- to_float_approx --")
	check(is_equal_approx(BigNumber.from_parts(1.0, 5).to_float_approx(), 100000.0), "to_float 1e5")
	check(BigNumber.from_parts(9.9, 400).to_float_approx() == 1e308, "to_float clamps 1e308")
	check(BigNumber.zero().to_float_approx() == 0.0, "to_float zero")

	print("RESULT: ", "ALL PASS" if failures == 0 else "%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)
