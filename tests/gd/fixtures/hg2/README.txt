Synthetic HG2 fixtures are built in tests/gd/test_bz_hg2.gd (not stored here).
They match files written by:

  PYTHONPATH=backend python3 -c "from bzmap.formats.hg2 import HeightMap, write_hg2; ..."

sha256 of the 1×1 and 2×2 builders is asserted against that reference so the
parse tests are checking Python-identical bytes. No game/corpus data.
