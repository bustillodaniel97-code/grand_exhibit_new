class_name BigNumber
extends RefCounted
## Arbitrary-range number for idle-game economies: value = m * 10^e.
## m kept in [1, 10) unless the value is exactly zero (m == 0, e == 0).
## Safe far past float limits (aa+ magnitudes); only mantissa uses float precision.

var m: float = 0.0
var e: int = 0

static func zero() -> BigNumber:
	return BigNumber.from_parts(0.0, 0)

static func one() -> BigNumber:
	return BigNumber.from_parts(1.0, 0)

static func from_float(v: float) -> BigNumber:
	if v <= 0.0 or is_nan(v) or is_inf(v):
		return BigNumber.zero()
	var pe: int = int(floor(log(v) / log(10.0)))
	var pm: float = v / pow(10.0, pe)
	return BigNumber.from_parts(pm, pe)

static func from_parts(pm: float, pe: int) -> BigNumber:
	var b := BigNumber.new()
	b.m = pm
	b.e = pe
	return b.normalize()

func normalize() -> BigNumber:
	if m <= 0.0 or is_nan(m):
		m = 0.0
		e = 0
		return self
	if is_inf(m):
		# Mantissa overflowed float range (e.g. scale by a huge factor).
		# Approximate inf as 1e308 and continue in log space; without this
		# guard the loops below would never terminate.
		m = 1.0
		e += 308
		push_warning("BigNumber: mantissa overflow, approximated as 1e%d" % e)
	while m >= 10.0:
		m /= 10.0
		e += 1
	while m < 1.0:
		m *= 10.0
		e -= 1
	return self

func copy() -> BigNumber:
	return BigNumber.from_parts(m, e)

func is_zero() -> bool:
	return m == 0.0

func add(o: BigNumber) -> BigNumber:
	if is_zero():
		return o.copy()
	if o.is_zero():
		return copy()
	var hi: BigNumber = self if e >= o.e else o
	var lo: BigNumber = o if e >= o.e else self
	var diff: int = hi.e - lo.e
	if diff > 15:
		return hi.copy()  # smaller term is below float significance
	var sum_m: float = hi.m + lo.m / pow(10.0, diff)
	return BigNumber.from_parts(sum_m, hi.e)

func sub(o: BigNumber) -> BigNumber:
	if o.is_zero():
		return copy()
	if cmp(o) <= 0:
		return BigNumber.zero()
	var diff: int = e - o.e
	if diff > 15:
		return copy()
	var res_m: float = m - o.m / pow(10.0, diff)
	if res_m <= 0.0:
		return BigNumber.zero()
	return BigNumber.from_parts(res_m, e)

func mul(o: BigNumber) -> BigNumber:
	if is_zero() or o.is_zero():
		return BigNumber.zero()
	return BigNumber.from_parts(m * o.m, e + o.e)

func scale(f: float) -> BigNumber:
	if is_zero() or f == 0.0 or is_nan(f):
		return BigNumber.zero()
	if f < 0.0:
		push_warning("BigNumber.scale with negative factor; clamped to zero")
		return BigNumber.zero()
	return BigNumber.from_parts(m * f, e)

func div(o: BigNumber) -> BigNumber:
	if is_zero() or o.is_zero():
		return BigNumber.zero()
	return BigNumber.from_parts(m / o.m, e - o.e)

func cmp(o: BigNumber) -> int:
	if is_zero() and o.is_zero():
		return 0
	if is_zero():
		return -1
	if o.is_zero():
		return 1
	if e != o.e:
		return 1 if e > o.e else -1
	if is_equal_approx(m, o.m):
		return 0
	return 1 if m > o.m else -1

func gte(o: BigNumber) -> bool:
	return cmp(o) >= 0

func gt(o: BigNumber) -> bool:
	return cmp(o) > 0

func lt(o: BigNumber) -> bool:
	return cmp(o) < 0

func lte(o: BigNumber) -> bool:
	return cmp(o) <= 0

func eq(o: BigNumber) -> bool:
	return cmp(o) == 0

## "999", "1.23K", "45.6M", "7.89aa"
func to_notation() -> String:
	if is_zero():
		return "0"
	if e < 3:
		var v: float = m * pow(10.0, e)
		if e == 0:
			return "%d" % int(floor(v + 0.0001))
		return _trim("%.1f" % v)
	var idx: int = int(e / 3.0) - 1  # 0=K 1=M 2=B 3=T 4=aa 5=ab ...
	var digits: float = m * pow(10.0, e % 3)
	if digits >= 999.5:
		# Roll into the next suffix instead of showing "999.9K"-style edges.
		digits /= 1000.0
		idx += 1
	var suffix: String = _suffix(idx)
	if digits >= 100.0:
		return "%d%s" % [int(digits), suffix]
	if digits >= 10.0:
		return _trim("%.1f" % digits) + suffix
	return _trim("%.2f" % digits) + suffix

static func _suffix(idx: int) -> String:
	if idx < 4:
		return ["K", "M", "B", "T"][idx]
	var n: int = idx - 4
	if n >= 26 * 26:
		return "zz"  # display-only clamp past "zz" (e ~ 2100); unreachable in practice
	return String.chr(97 + int(n / 26)) + String.chr(97 + (n % 26))

static func _trim(s: String) -> String:
	if "." in s:
		s = s.rstrip("0").rstrip(".")
	return s

func to_save() -> Dictionary:
	return {"m": m, "e": e}

static func from_save(d: Variant) -> BigNumber:
	if typeof(d) != TYPE_DICTIONARY:
		return BigNumber.zero()
	var pm: float = float(d.get("m", 0.0))
	var pe: int = int(d.get("e", 0))
	if pm <= 0.0:
		return BigNumber.zero()
	return BigNumber.from_parts(pm, pe)

func to_float_approx() -> float:
	if is_zero():
		return 0.0
	if e > 300:
		return 1e308
	return m * pow(10.0, e)
