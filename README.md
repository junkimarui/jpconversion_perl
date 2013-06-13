How to use
======================

1. edit conf.perl

2. make dictionary
`perl make_dic.pl`

3. make cache (optional)
`perl make_conncache.pl < sample.txt`

4. run converter
`perl ime.pl`

You can also refer the sample code in run.pl

Configuration
------------------------
Configuration written in conf.perl

* dictionary_dir:
path to directory containing dictionary0[0-9].txt
* additional_dictionary (optional):
path to additional dictionary ("additional.txt")
* connection_filename:
default: connection.txt (in Mozc dictionary)
* sqlite:
sqlite command name
* database_file:
file name to save sqlite database
* trie_file:
file name to save trie
* temporary_file:
temporary file name
* temporary_trie_file:
temporary file name 2
* connection_cache_file:
cache file for connection data
* ime_debug:
if 1 is set, debug information can be seen
* bestk:
if 1 is set, it uses viterbi algorithm. otherwise, it uses k-th nearest path algorithm.
