Dependency
======================
You need marisa-trie perl binding.
https://code.google.com/p/marisa-trie/

And you also need mozc dictionary (dictionary_oss).
After you downloaded it, you should specify the directory in `conf.perl`.
https://github.com/niw/mozc/tree/master/src/data/dictionary_oss

How to use
======================

1. edit conf.perl

2. make dictionary
`perl make_dic.pl`

3. make cache (optional)
`perl make_conncache.pl < sample.txt`

4. make romaji table (optional)
`perl make_romaji.pl`

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
* from_romaji:
 if 1 is set, this program takes alphabet (Roma-ji) input. default escaping character is $.
`sample input: korehanihongohenkantsu-rudesu.$Alphabet$moutsukotogadekimasu.`
* romaji_file:
 romaji conversion table file (romaji.txt in the directory)
* romaji_trie:
 it saves trie for input alphabet (Roma-ji).
