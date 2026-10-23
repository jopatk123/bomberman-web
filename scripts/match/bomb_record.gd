class_name BombRecord
extends RefCounted
## Shape of one bomb in the match dictionary. Visual nodes stay outside this type.


const FUSE := 2.0
const SLIDE_INTERVAL := 0.07


static func make(x: int, y: int, owner: int, blast: int, pierce: int) -> Dictionary:
	return {
		"x": x,
		"y": y,
		"owner": owner,
		"timer": FUSE,
		"range": blast,
		"pierce": pierce,
		"solid": false,
		"slide_dx": 0,
		"slide_dy": 0,
		"slide_cd": 0.0,
	}


static func count_owned(bombs: Dictionary, peer_id: int) -> int:
	var n := 0
	for b in bombs.values():
		if int(b.owner) == peer_id:
			n += 1
	return n
