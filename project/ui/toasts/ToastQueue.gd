extends RefCounted
class_name ToastQueue
## Bounded toast list. Newest last; overflow drops the oldest.

const MAX_VISIBLE := 4
const LIFETIME_S := 3.5
const FADE_S := 0.4

var _next_id: int = 1
var items: Array = []


func push(text: String, level: String, now_s: float) -> Dictionary:
	var item := {
		"id": _next_id,
		"text": text,
		"level": LogRouter.infer_level(text, level),
		"born_s": now_s,
	}
	_next_id += 1
	items.append(item)
	while items.size() > MAX_VISIBLE:
		items.remove_at(0)
	return item


func dismiss(id: int) -> bool:
	for i in items.size():
		if int(items[i].get("id", 0)) == id:
			items.remove_at(i)
			return true
	return false


func expire(now_s: float) -> Array:
	var gone: Array = []
	var kept: Array = []
	for item in items:
		var born := float(item.get("born_s", now_s))
		if now_s - born >= LIFETIME_S:
			gone.append(item)
		else:
			kept.append(item)
	items = kept
	return gone


func alpha_at(item: Dictionary, now_s: float) -> float:
	var born := float(item.get("born_s", now_s))
	var remain := LIFETIME_S - (now_s - born)
	if remain >= FADE_S:
		return 1.0
	if remain <= 0.0:
		return 0.0
	return clampf(remain / FADE_S, 0.0, 1.0)
