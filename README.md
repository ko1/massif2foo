# massif2foo.rb

This script make valgrind/massif output pretty.

valgrind/massif outputs memory usages details. The final output is a set of tree which shows each allocation backtrace. It is useful to analyze details, but it is difficult to shows allocation chart and so on.

This script translate trees to lines as tab separated form. It is easy to handle especially with spread sheet applications such as Excel.
