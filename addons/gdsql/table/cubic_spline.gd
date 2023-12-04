# https://github.com/morganherlocker/cubic-spline
# 三次拟合
extends RefCounted
class_name CubicSpline

var xs = []
var ys = []
var ks = []

func _init(_xs: Array, _ys: Array):
	xs = _xs
	ys = _ys
	var _ks = []
	_ks.resize(xs.size())
	_ks.fill(0.0)
	ks = getNaturalKs(_ks)

func getNaturalKs(_ks: Array) -> Array:
	var n = xs.size() - 1
	var A = zerosMat(n + 1, n + 2)
	
	for i in range(1, n):
		A[i][i - 1] = 1 / (xs[i] - xs[i - 1])
		A[i][i] = \
			2 * \
			(1 / (xs[i] - xs[i - 1]) + 1 / (xs[i + 1] - xs[i]))
		A[i][i + 1] = 1 / (xs[i + 1] - xs[i])
		A[i][n + 1] = \
			3 * \
			((ys[i] - ys[i - 1]) / \
				((xs[i] - xs[i - 1]) * (xs[i] - xs[i - 1])) + \
				(ys[i + 1] - ys[i]) / \
					((xs[i + 1] - xs[i]) * (xs[i + 1] - xs[i])))
					
					
	A[0][0] = 2 / (xs[1] - xs[0])
	A[0][1] = 1 / (xs[1] - xs[0])
	A[0][n + 1] = \
		(3 * (ys[1] - ys[0])) / \
		((xs[1] - xs[0]) * (xs[1] - xs[0]))
		
	A[n][n - 1] = 1 / (xs[n] - xs[n - 1])
	A[n][n] = 2 / (xs[n] - xs[n - 1])
	A[n][n + 1] = \
		(3 * (ys[n] - ys[n - 1])) / \
		((xs[n] - xs[n - 1]) * (xs[n] - xs[n - 1]))
		
	return solve(A, _ks)
	
# inspired by https://stackoverflow.com/a/40850313/4417327
func getIndexBefore(target: float) -> float:
	var low = 0;
	var high = xs.size()
	var mid = 0;
	while low < high:
		mid = floor((low + high) / 2.0);
		if xs[mid] < target and mid != low:
			low = mid
		elif xs[mid] >= target and mid != high:
			high = mid
		else:
			high = low
			
	if low == xs.size() - 1:
		return xs.size() - 1
		
	return low + 1
	

func at(x: float) -> float:
	var i = getIndexBefore(x)
	var t = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
	var a = \
		ks[i - 1] * (xs[i] - xs[i - 1]) - \
		(ys[i] - ys[i - 1])
	var b = \
		-ks[i] * (xs[i] - xs[i - 1]) + \
		(ys[i] - ys[i - 1])
	var q = \
		(1 - t) * ys[i - 1] + \
		t * ys[i] + \
		t * (1 - t) * (a * (1 - t) + b * t)
	return q


func solve(A: Array[Array], _ks: Array) -> Array:
	var m = A.size()
	var h = 0
	var k = 0
	while h < m and k <= m:
		var i_max = 0
		var _max = -9223372036854775808
		for i in range(h, m):
			var v = abs(A[i][k])
			if v > _max:
				i_max = i
				_max = v

		if A[i_max][k] == 0:
			k += 1
		else:
			swapRows(A, h, i_max)
			for i in range(h+1, m):
				var f = A[i][k] / A[h][k]
				A[i][k] = 0;
				for j in range(k+1, m+1): A[i][j] -= A[h][j] * f
			h += 1
			k += 1
			
	for i in range(m-1, -1, -1):
		var v = 0
		if A[i][i]:
			v = A[i][m] / A[i][i]
		_ks[i] = v
		for j in range(i-1, -1, -1):
			A[j][m] -= A[j][i] * v
			A[j][i] = 0
	return _ks

func zerosMat(r: int, c: int) -> Array[Array]:
	var A: Array[Array] = []
	for i in r:
		var arr = []
		arr.resize(c)
		arr.fill(0.0)
		A.push_back(arr)
	return A
	

func swapRows(m: Array, k: int, l: int) -> void:
	var p = m[k]
	m[k] = m[l]
	m[l] = p
	
