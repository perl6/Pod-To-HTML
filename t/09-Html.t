use Test;
use Pod::To::HTML;
plan 1;
my $r;

=begin Html

This should be <b>raw</b> HTML
That isn't
changed.

=end Html

$r = node2html $=pod[0];
nok $r ~~ / '<p>' /, 'no paragraphs should be inserted into Html blocks';
