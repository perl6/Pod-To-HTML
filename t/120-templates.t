use Test; # -*- mode: perl6 -*- 
use Test::Output;
use Pod::To::HTML;
plan 6;
my $r;

=begin pod
=TITLE The usual suspects

The seven suspects are:

=item  Happy
=item  Dopey
=item  Sleepy
=item  Bashful
=item  Sneezy
=item  Grumpy
=item  Keyser Soze
=end pod

stderr-like { $r = pod2html $=pod[0], :templates<templates> },
            /'does not contain required templates'/,
            'Complains when required templates not found';

ok $r ~~ ms[[
    '<p>' 'The seven suspects are:' '</p>'
    '<ul>'
        '<li>' '<p>' Happy '</p>' '</li>'
        '<li>' '<p>' Dopey '</p>' '</li>'
        '<li>' '<p>' Sleepy '</p>' '</li>'
        '<li>' '<p>' Bashful '</p>' '</li>'
        '<li>' '<p>' Sneezy '</p>' '</li>'
        '<li>' '<p>' Grumpy '</p>' '</li>'
        '<li>' '<p>' Keyser Soze '</p>' '</li>'
    '</ul>'
]], 'Uses default templates';

$r = pod2html $=pod[0], :templates("t/templates");
ok $r ~~ ms[[  '<meta description="This is a new template"/>' ]], 'Gets text from new template';
ok $r ~~ ms[[ "<h1 class='title'>The usual suspects</h1>" ]], 'Fills template correctly';

my $head='<meta name=viewport content="width=device-width, initial-scale=1">';
$r = pod2html $=pod[0], :templates("t/templates"), :$head ;
ok $r ~~ ms[[ $head ]], 'headers are redered as is';

class Pod::To::HTML::Dummy does Pod::To::HTML::Renderer {
    method render(%context) {
        "Rendered %context<title>";
    }
}

$r = pod2html $=pod[0], :page-renderer(Pod::To::HTML::Dummy);

is $r, 'Rendered The usual suspects', 'Custom renderer was used';