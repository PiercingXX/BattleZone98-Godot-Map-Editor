Synthetic BZN fixtures for tests/gd/test_bz_bzn.gd. Not corpus, not game, not BZP.

How they were made (from the repo root):

  PYTHONPATH=backend python3
    from bzmap.formats.bzn import BznFile, GameObject
    # Hand-authored header / player / geyser / tail strings (synthmap).
    bzn = BznFile.build(HEADER, [player, geyser], TAIL)
    bzn.write("tests/gd/fixtures/bzn/untouched.bzn")
    geyser.set_position(333.125, 44.5, 555.875)
    bzn.write("tests/gd/fixtures/bzn/mutated_pos.bzn")
    clone = GameObject.from_template(TEMPLATE)  # clone_template.txt
    clone.set_position(11.5, 22.25, 33.75)
    clone.set_yaw(0.5)
    clone.set_identity(3, 4, "cloned_obj")
    clone.set_team(2)
    # cloned_object.txt = clone.render()  (CRLF, no trailing newline)

untouched.bzn / mutated_pos.bzn are CRLF, written by the Python reference.
clone_template.txt is LF; from_template() splits any conventional newline.
