#edit conf.perl before execution
#conf.perl : config file

# create dictionary and trie
system("perl make_dic.pl");
# make cache file (optional)
system("perl make_conncache.pl < sample.txt");
# execute japanese kana conversion tool
system("perl ime.pl");
