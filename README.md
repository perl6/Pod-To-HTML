# TITLE

Pod::To::HTML

Render Pod6 as HTML

[![Build Status](https://travis-ci.org/perl6/Pod-To-HTML.svg?branch=master)](https://travis-ci.org/perl6/Pod-To-HTML)

# SYNOPSIS

From the command line:

    perl6 --doc=HTML lib/FancyModule.pm > FancyModule.html

From within Perl 6:

```perl6

=pod My I<super B<awesome>> embedded C<pod>
     document!

say Pod::To::HTML.render($=pod[0]);

```

# DESCRIPTION

`Pod::To::HTML` takes a Pod tree and outputs correspondingly formatted HTML. Generally this is via `perl6 --doc=HTML`, which extracts the pod from the document and feeds it to `Pod::To::HTML`. The other route is with the render method (called by `--doc=HTML`), which creates a complete HTML document from the Pod tree it is called with.
