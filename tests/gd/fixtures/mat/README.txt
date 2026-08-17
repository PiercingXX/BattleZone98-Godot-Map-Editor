Synthetic MAT fixtures are built in tests/gd/test_bz_mat.gd (not stored here).
They match files written by:

  PYTHONPATH=backend python3 -c "from bzmap.formats.mat import MaterialGrid, encode_entry, write_mat; ..."

sha256 of the 1×1 and 2×2 builders is asserted against that reference. No
game/corpus data.
