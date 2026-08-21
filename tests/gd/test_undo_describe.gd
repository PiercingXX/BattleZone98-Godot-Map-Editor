extends RefCounted
## Command describe() labels and UndoStack.describe_command default.


func run(t) -> void:
	var height := HeightStrokeCommand.new()
	t.eq(height.describe(), "height stroke")
	height.tool = "raise"
	t.eq(height.describe(), "raise stroke")
	height.tool = "lower"
	t.eq(height.describe(), "lower stroke")
	height.tool = "flatten"
	t.eq(height.describe(), "flatten stroke")
	height.tool = "smooth"
	t.eq(height.describe(), "smooth stroke")
	height.tool = "ramp"
	t.eq(height.describe(), "ramp stroke")
	height.tool = "noise"
	t.eq(height.describe(), "noise stroke")

	t.eq(MaterialStrokeCommand.new().describe(), "paint stroke")
	var match_cmd := MaterialStrokeCommand.new()
	match_cmd.tool = "match"
	t.eq(match_cmd.describe(), "match corners")
	t.eq(CloneStrokeCommand.new().describe(), "clone stroke")

	var mask := MaskStrokeCommand.new()
	t.eq(mask.describe(), "mask stroke")
	mask.stem = "mapw"
	t.eq(mask.describe(), "mask mapw")

	var add_w := FeatureCommand.new()
	add_w.kind = FeatureCommand.Kind.ADD
	add_w.group = "water"
	t.eq(add_w.describe(), "add water")
	var rm_p := FeatureCommand.new()
	rm_p.kind = FeatureCommand.Kind.REMOVE
	rm_p.group = "plants"
	t.eq(rm_p.describe(), "remove plant")
	var ed_w := FeatureCommand.new()
	ed_w.kind = FeatureCommand.Kind.EDIT
	ed_w.group = "water"
	t.eq(ed_w.describe(), "edit water")

	t.eq(WaterCommand.new().describe(), "water level")
	var aip := AiPathCommand.new()
	aip.kind = AiPathCommand.Kind.ADD_PATH
	t.eq(aip.describe(), "add AI path")
	aip.kind = AiPathCommand.Kind.MOVE_POINT
	t.eq(aip.describe(), "move AI path point")
	t.eq(HeightmapImportCommand.new().describe(), "import heightmap")

	var place := ObjectCommand.new()
	place.kind = ObjectCommand.Kind.ADD
	place.after = {"prjid": "npscr1"}
	t.eq(place.describe(), "place npscr1")
	var delete := ObjectCommand.new()
	delete.kind = ObjectCommand.Kind.DELETE
	delete.before = {"prjid": "avapc"}
	t.eq(delete.describe(), "delete avapc")
	var edit := ObjectCommand.new()
	edit.kind = ObjectCommand.Kind.EDIT
	edit.after = {"prjid": "player"}
	t.eq(edit.describe(), "edit player")
	var batch := ObjectCommand.new()
	batch.kind = ObjectCommand.Kind.ADD
	batch.items = [{"after": {"prjid": "sbhqnp"}}]
	t.eq(batch.describe(), "place sbhqnp")
	var bare := ObjectCommand.new()
	bare.kind = ObjectCommand.Kind.ADD
	t.eq(bare.describe(), "place object")

	UndoStack.clear()
	t.eq(UndoStack.describe_command(null), "")
	t.eq(UndoStack.describe_command(place), "place npscr1")
	t.eq(UndoStack.describe_command(_Nameless.new()), "RefCounted", "default is class name")
	UndoStack.clear()


class _Nameless:
	extends RefCounted
