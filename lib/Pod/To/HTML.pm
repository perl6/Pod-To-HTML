class Pod::To::HTML;
use URI::Escape;

#try require Term::ANSIColor <&colored>;
#if &colored.defined {
    #&colored = -> $t, $c { $t };
#}

sub colored($text, $how) {
    $text
}

method render($pod) {
    pod2html($pod)
}

# FIXME: this code's a horrible mess. It'd be really helpful to have a module providing a generic
# way to walk a Pod tree and invoke callbacks on each node, that would reduce the multispaghetti at
# the bottom to something much more readable.

my &url;
my $title;
my @meta;
my @indexes;
my @body;
my @footnotes;

 sub Debug(Callable $)  { }         # Disable debug code
#sub Debug(Callable $c) { $c() }    # Enable debug code

sub escape_html(Str $str) returns Str {
    return $str unless $str ~~ /<[&<>"']>/;

    $str.trans( [ q{&},     q{<},    q{>},    q{"},      q{'}     ] =>
                [ q{&amp;}, q{&lt;}, q{&gt;}, q{&quot;}, q{&#39;} ] );
}

sub visit($root, :&pre, :&post, :&assemble = -> *%{ Nil }) {
    my ($pre, $post);
    $pre = pre($root) if defined &pre;
    my @content = $root.?content.map: {visit $_, :&pre, :&post, :&assemble};
    $post = post($root, :@content) if defined &post;
    return assemble(:$pre, :$post, :@content, :node($root));
}

class Pod::List is Pod::Block { };

sub assemble-list-items(:@content, :$node, *% ) {
    my @current;
    my @result;
    my $found;
    for @content -> $c {
        if $c ~~ Pod::Item {
            @current.push: $c;
            $found = True;
        }
        elsif @current {
            @result.push: Pod::List.new(content => @current);
            @current = ();
            @result.push: $c;
        }
        else {
            @result.push: $c;
        }
    }
    @result.push: Pod::List.new(content => @current) if @current;
    @current = ();
    return $found ?? $node.clone(content => @result) !! $node;
}


#= Converts a Pod tree to a HTML document.
sub pod2html($pod, :&url = -> $url { $url }, :$head = '', :$header = '', :$footer = '') is export returns Str {
    ($title, @meta, @indexes, @body, @footnotes) = ();
    &OUTER::url = &url;
    @body.push: node2html($pod.map: {visit $_, :assemble(&assemble-list-items)});

    my $title_html = $title // 'Pod document';

    my $prelude = qq:to/END/;
        <!doctype html>
        <html>
        <head>
          <title>{ $title_html }</title>
          <meta charset="UTF-8" />
          <style>
            /* code gets the browser-default font
             * kbd gets a slightly less common monospace font
             * samp gets the hard pixelly fonts
             */
            kbd \{ font-family: "Droid Sans Mono", "Luxi Mono", "Inconsolata", monospace }
            samp \{ font-family: "Terminus", "Courier", "Lucida Console", monospace }
            /* WHATWG HTML frowns on the use of <u> because it looks like a link,
             * so we make it not look like one.
             */
            u \{ text-decoration: none }
            .nested \{
                margin-left: 3em;
            }
            // footnote things:
            aside, u \{ opacity: 0.7 }
            a[id^="fn-"]:target \{ background: #ff0 }
          </style>
          <link rel="stylesheet" href="http://perlcabal.org/syn/perl.css">
          { do-metadata() // () }
          $head
        </head>
        <body class="pod" id="___top">
        $header
        END

    return join(qq{\n},
        $prelude,
        ( $title.defined ?? "<h1>{$title_html}</h1>"
                         !! () ),
        ( do-toc() // () ),
        @body,
        do-footnotes(),
        $footer,
        '</body>',
        "</html>\n"
    );
}

#= Returns accumulated metadata as a string of C«<meta>» tags
sub do-metadata returns Str {
    return @meta.map(-> $p {
        qq[<meta name="{escape_html($p.key)}" value="{node2text($p.value)}" />]
    }).join("\n");
}

#= Turns accumulated headings into a nested-C«<ol>» table of contents
sub do-toc returns Str {
    my $r = qq[<nav class="indexgroup">\n];

    my $indent = q{ } x 2;
    my @opened;
    for @indexes -> $p {
        my $lvl  = $p.key;
        my %head = $p.value;
        while @opened && @opened[*-1] > $lvl {
            $r ~= $indent x @opened - 1
                ~ "</ol>\n";
            @opened.pop;
        }
        my $last = @opened[*-1] // 0;
        if $last < $lvl {
            $r ~= $indent x $last
                ~ qq[<ol class="indexList indexList{$lvl}">\n];
            @opened.push($lvl);
        }
        $r ~= $indent x $lvl
            ~ qq[<li class="indexItem indexItem{$lvl}">]
            ~ qq[<a href="#{%head<uri>}">{%head<html>}</a>\n];
    }
    for ^@opened {
        $r ~= $indent x @opened - 1 - $^left
            ~ "</ol>\n";
    }

    return $r ~ '</nav>';
}

#= Keep count of how many footnotes we've output.
my Int $done-notes = 0;

#= Flushes accumulated footnotes since last call. The idea here is that we can stick calls to this
#  before each C«</section>» tag (once we have those per-header) and have notes that are visually
#  and semantically attached to the section.
sub do-footnotes returns Str {
    #state $done-notes = 0; # TODO 2011-09-07 Rakudo-nom bug

    return '' unless @footnotes;

    my Int $current-note = $done-notes + 1;
    my $notes = @footnotes.kv.map(-> $k, $v {
                    my $num = $k + $current-note;
                    qq{<li><a href="#fn-ref-$num" id="fn-$num">[↑]</a> $v </li>\n}
                }).join;

    $done-notes += @footnotes;
    @footnotes = ();

    return qq[<aside><ol start="$current-note">\n]
         ~ $notes
         ~ qq[</ol></aside>\n];
}

sub twine2text($twine) returns Str {
    Debug { note colored("twine2text called for ", "bold") ~ $twine.perl };
    return '' unless $twine.elems;
    my $r = $twine[0];
    for $twine[1..*] -> $f, $s {
        $r ~= twine2text($f.content);
        $r ~= $s;
    }
    return $r;
}

#= block level or below
multi sub node2html($node) returns Str {
    Debug { note colored("Generic node2html called for ", "bold") ~ $node.perl };
    return node2inline($node);
}

multi sub node2html(Pod::Block::Declarator $node) returns Str {
    given $node.WHEREFORE {
        when Sub {
            "<article>\n"
                ~ '<code>'
                    ~ node2text($node.WHEREFORE.name ~ $node.WHEREFORE.signature.perl)
                ~ "</code>:\n"
                ~ node2html($node.content)
            ~ "\n</article>\n";
        }
        default {
            Debug { note "I don't know what {$node.WHEREFORE.perl} is" };
            node2html([$node.WHEREFORE.perl, q{: }, $node.content]);
        }
    }
}

multi sub node2html(Pod::Block::Code $node) returns Str {
    Debug { note colored("Code node2html called for ", "bold") ~ $node.gist };
    return '<pre>' ~ node2inline($node.content) ~ "</pre>\n"
}

multi sub node2html(Pod::Block::Comment $node) returns Str {
    Debug { note colored("Comment node2html called for ", "bold") ~ $node.gist };
    return '';
}

multi sub node2html(Pod::Block::Named $node) returns Str {
    Debug { note colored("Named Block node2html called for ", "bold") ~ $node.gist };
    given $node.name {
        when 'config' { return '' }
        when 'nested' {
            return qq{<div class="nested">\n} ~ node2html($node.content) ~ qq{\n</div>\n};
        }
        when 'output' { return '<pre>\n' ~ node2inline($node.content) ~ '</pre>\n'; }
        when 'pod'  { return node2html($node.content); }
        when 'para' { return node2html($node.content[0]); }
        when 'defn' {
            return node2html($node.content[0]) ~ "\n"
                    ~ node2html($node.content[1..*-1]);
        }
        when 'Image' {
            my $url;
            if $node.content == 1 {
                my $n = $node.content[0];
                if $n ~~ Str {
                    $url = $n;
                }
                elsif ($n ~~ Pod::Block::Para) &&  $n.content == 1 {
                    $url = $n.content[0] if $n.content[0] ~~ Str;
                }
            }
            unless $url.defined {
                die "Found an Image block, but don't know how to extract the image URL :(";
            }
            return qq[<img src="$url" />];
        }
        default {
            if $node.name eq 'TITLE' {
                $title = node2text($node.content);
                return '';
            }
            elsif $node.name ~~ any(<VERSION DESCRIPTION AUTHOR COPYRIGHT SUMMARY>)
              and $node.content[0] ~~ Pod::Block::Para {
                @meta.push: Pair.new(
                    key => $node.name.lc,
                    value => $node.content
                );
            }

            return '<section>'
                ~ "<h1>{$node.name}</h1>\n"
                ~ node2html($node.content)
                ~ "</section>\n";
        }
    }
}

multi sub node2html(Pod::Block::Para $node) returns Str {
    Debug { note colored("Para node2html called for ", "bold") ~ $node.gist };
    return '<p>' ~ node2inline($node.content) ~ "</p>\n";
}

multi sub node2html(Pod::Block::Table $node) returns Str {
    Debug { note colored("Table node2html called for ", "bold") ~ $node.gist };
    my @r = '<table>';

    if $node.caption {
        @r.push("<caption>{node2inline($node.caption)}</caption>");
    }

    if $node.headers {
        @r.push(
            '<thead><tr>',
            $node.headers.map(-> $cell {
                "<th>{node2html($cell)}</th>"
            }),
            '</tr></thead>'
        );
    }

    @r.push(
        '<tbody>',
        $node.content.map(-> $line {
            '<tr>',
            $line.list.map(-> $cell {
                "<td>{node2html($cell)}</td>"
            }),
            '</tr>'
        }),
        '</tbody>',
        '</table>'
    );

    return @r.join("\n");
}

multi sub node2html(Pod::Config $node) returns Str {
    Debug { note colored("Config node2html called for ", "bold") ~ $node.perl };
    return '';
}

# TODO: would like some way to wrap these and the following content in a <section>; this might be
# the same way we get lists working...
multi sub node2html(Pod::Heading $node) returns Str {
    Debug { note colored("Heading node2html called for ", "bold") ~ $node.gist };
    my $lvl = min($node.level, 6); #= HTML only has 6 levels of numbered headings
    my %escaped = (
        uri => uri_escape(node2rawtext($node.content)),
        html => node2inline($node.content),
    );
    @indexes.push: Pair.new(key => $lvl, value => %escaped);

    return sprintf('<h%d id="%s">', $lvl, %escaped<uri>)
                ~ qq[<a class="u" href="#___top" title="go to top of document">]
                    ~ %escaped<html>
                ~ qq[</a>]
            ~ qq[</h{$lvl}>\n];
}

# FIXME
multi sub node2html(Pod::List $node) returns Str {
    return '<ul>' ~ node2html($node.content) ~ "</ul>\n";
}
multi sub node2html(Pod::Item $node) returns Str {
    Debug { note colored("List Item node2html called for ", "bold") ~ $node.gist };
    return '<li>' ~ node2html($node.content) ~ "</li>\n";
}

multi sub node2html(Positional $node) returns Str {
    return $node.map({ node2html($_) }).join
}

multi sub node2html(Str $node) returns Str {
    return escape_html($node);
}


#= inline level or below
multi sub node2inline($node) returns Str {
    Debug { note colored("missing a node2inline multi for ", "bold") ~ $node.gist };
    return node2text($node);
}

multi sub node2inline(Pod::Block::Para $node) returns Str {
    return node2inline($node.content);
}

multi sub node2inline(Pod::FormattingCode $node) returns Str {
    my %basic-html = (
        B => 'strong',  #= Basis
        C => 'code',    #= Code
        I => 'em',      #= Important
        K => 'kbd',     #= Keyboard
        R => 'var',     #= Replaceable
        T => 'samp',    #= Terminal
        U => 'u',       #= Unusual
    );

    given $node.type {
        when any(%basic-html.keys) {
            return q{<} ~ %basic-html{$_} ~ q{>}
                ~ node2inline($node.content)
                ~ q{</} ~ %basic-html{$_} ~ q{>};
        }

        #= Escape
        when 'E' {
            return $node.content.split(q{;}).map({
                # Perl 6 numbers = Unicode codepoint numbers
                when /^ \d+ $/
                    { q{&#} ~ $_ ~ q{;} }
                # Lowercase = HTML5 entity reference
                when /^ <[a..z]>+ $/
                    { q{&} ~ $_ ~ q{;} }
                # Uppercase = Unicode codepoint names
                default
                    { q{<kbd class="pod2html-todo">E&lt;} ~ node2text($_) ~ q{&gt;</kbd>} }
            }).join;
        }

        #= Note
        when 'N' {
            @footnotes.push(node2inline($node.content));

            my $id = +@footnotes;
            return qq{<a href="#fn-$id" id="fn-ref-$id">[$id]</a>};
        }

        #= Links
        when 'L' {
            my $url  = node2inline($node.content);
            my $text = $url;
            if $url ~~ /'|'/ {
                $text = $/.prematch;
                $url  = $/.postmatch;
            }
            $url = url($url);
            # TODO: URI-escape $url
            return qq[<a href="$url">{$text}</a>]
        }

        # zero-width comment
        when 'Z' {
            return '';
        }

        when 'D' {
            # TODO memorise these definitions and display them properly
            my $text = node2inline($node.content);
            if $text ~~ /'|'/ {
                $text = $/.prematch;
            }
            return qq[<defn>{$text}</defn>]
        }

        # Stuff I haven't figured out yet
        default {
            Debug { note colored("missing handling for a formatting code of type ", "red") ~ $node.type }
            return qq{<kbd class="pod2html-todo">$node.type()&lt;}
                    ~ node2inline($node.content)
                    ~ q{&gt;</kbd>};
        }
    }
}

multi sub node2inline(Positional $node) returns Str {
    return $node.map({ node2inline($_) }).join;
}

multi sub node2inline(Str $node) returns Str {
    return escape_html($node);
}


#= HTML-escaped text
multi sub node2text($node) returns Str {
    Debug { note colored("missing a node2text multi for ", "red") ~ $node.perl };
    return escape_html(node2rawtext($node));
}

multi sub node2text(Pod::Block::Para $node) returns Str {
    return node2text($node.content);
}

# FIXME: a lot of these multis are identical except the function name used...
#        there has to be a better way to write this?
multi sub node2text(Positional $node) returns Str {
    return $node.map({ node2text($_) }).join;
}

multi sub node2text(Str $node) returns Str {
    return escape_html($node);
}


#= plain, unescaped text
multi sub node2rawtext($node) returns Str {
    Debug { note colored("Generic node2rawtext called with ", "red") ~ $node.perl };
    return $node.Str;
}

multi sub node2rawtext(Pod::Block $node) returns Str {
    Debug { note colored("node2rawtext called for ", "bold") ~ $node.gist };
    return twine2text($node.content);
}

multi sub node2rawtext(Positional $node) returns Str {
    return $node.map({ node2rawtext($_) }).join;
}

multi sub node2rawtext(Str $node) returns Str {
    return $node;
}
