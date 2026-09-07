Task for the coding agent (the same words are given on the command line):

Add a `--ignore-punctuation` flag to the tally CLI so that words are counted with leading and
trailing punctuation stripped (so "hello," and "hello" count as the same word). Keep the default
behaviour unchanged. Add a test for the new flag in test_tally.py and make sure `python -m pytest -q`
passes. Commit nothing; just leave the working tree changed.
