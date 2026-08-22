Synthetic BZN fixtures for tests/gd/test_bz_bzn.gd and the object/open/save
tests. Not corpus, not game, not BZP — the header, both objects and the tail
are hand-authored, and "synthmap" is not a real terrain.

These files are COMMITTED. They used to be caught by .gitignore's blanket
*.bzn ban, which meant every fresh clone and every CI runner skipped five test
files; .gitignore now carries a targeted exception for this directory. The ban
is still in force everywhere else, because it exists to keep real map content
out of a public repo (AGENTS.md rule 3) and these files contain none.

Regenerate after changing the intended content:

  godot --headless --path . -s tests/gd/fixtures/bzn/make_fixtures.gd

make_fixtures.gd holds the content as readable source. It writes:

  untouched.bzn    header + player + geyser + tail, CRLF.
                   player: seqno 0, team 1, isUser, pos 640/10/640, obj_addr 1,
                   and a physics residue block whose mass_inv is 1e+030 —
                   test_bz_bzn.gd pins that as a value the editor must carry
                   through untouched.
                   geyser: prjid eggeizr1, seqno 1, pos 100.25/12.5/200.75,
                   obj_addr 2, label synthmap1_geyser.

  mutated_pos.bzn  the same file with the geyser at 333.125/44.5/555.875.

A note on mutated_pos.bzn, because it is easy to get wrong when regenerating:
it is written from its own hand-authored text, NOT by calling set_position on
the geyser. test_bz_bzn.gd asserts that set_position(333.125, 44.5, 555.875)
reproduces this file byte for byte, so a golden produced by the routine under
test would agree with itself no matter what that routine did. The three sites
the geyser's coordinates appear in — both `pos` blocks and the transform's
`posit_*` triple — are spelled out in the generator instead. Nine lines differ
between the two files, and the test checks that count.

The earlier revision of this file described a Python recipe:

  PYTHONPATH=backend python3
  from bzmap.formats.bzn import BznFile, GameObject
  ...

That could not be followed. There is no backend/ directory in this repository
and no commit ever added one — the Python bzmap backend became in-process
GDScript under project/backend/, which is what make_fixtures.gd uses. Note the
tradeoff that came with the move: the Python fixtures were a cross-language
oracle, and these are not. What keeps the tests honest now is that the expected
values are hand-written here rather than derived from a run of the code.

clone_template.txt is LF; from_template() splits any conventional newline.
cloned_object.txt is the expected render of the clone case (CRLF, no trailing
newline) and is unchanged.
