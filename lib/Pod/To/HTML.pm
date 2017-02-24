unit class Pod::To::HTML;
use URI::Escape;

#try require Term::ANSIColor <&colored>;
#if &colored.defined {
    #&colored = -> $t, $c { $t };
#}

sub colored($text, $how) {
    $text
}

method render(
    $pod,
    Str :$header = '',
    Str :$footer = '',
    Str :head-fields($head) = '',
    :$default-title = '',
    :$lang = 'en'
    ) {
    given $pod {
        when Array {
            pod2html($pod, :$header, :$footer, :$head, :$default-title, :$lang)
        }
        when Pod::Block {
            pod2html($pod, :$header, :$footer, :$head, :$default-title, :$lang)
        }
        when IO::Path {
            use MONKEY-SEE-NO-EVAL;
            pod2html(EVAL($file.slurp ~ "\n\$=pod"), :$header, :$footer, :$head, :$default-title, :$lang);
        }
        when Str {
            use MONKEY-SEE-NO-EVAL;
            pod2html(EVAL($pod-string ~ "\n\$=pod"), :$header, :$footer, :$head, :$default-title, :$lang);
        }
        default { pod2html($pod) }
    }
}

# FIXME: this code's a horrible mess. It'd be really helpful to have a module providing a generic
# way to walk a Pod tree and invoke callbacks on each node, that would reduce the multispaghetti at
# the bottom to something much more readable.

my &url;
my $title;
my $subtitle;
my @meta;
my @indexes;
my @body;
my @footnotes;
my %crossrefs;

 sub Debug(Callable $)  { }         # Disable debug code
#sub Debug(Callable $c) { $c() }    # Enable debug code

sub escape_html(Str $str) returns Str {
    return $str unless $str ~~ /<[&<>"']>/;

    $str.trans( [ q{&},     q{<},    q{>},    q{"},      q{'}     ] =>
                [ q{&amp;}, q{&lt;}, q{&gt;}, q{&quot;}, q{&#39;} ] );
}

sub unescape_html(Str $str) returns Str {
    $str.trans( [ rx{'&amp;'}, rx{'&lt;'}, rx{'&gt;'}, rx{'&quot;'}, rx{'&#39;'} ] =>
                [ q{&},        q{<},       q{>},       q{"},         q{'}        ] );
}

sub escape_id ($id) {
    $id.trim.subst(/\s+/, '_', :g).subst('"', '&quot;', :g);
}

multi visit(Nil, |a) {
    Debug { note colored("visit called for Nil", "bold") }
}
multi visit($root, :&pre, :&post, :&assemble = -> *% { Nil }) {
    Debug { note colored("visit called for ", "bold") ~ $root.perl }
    my ($pre, $post);
    $pre = pre($root) if defined &pre;

    my @content = $root.?contents.map: {visit $_, :&pre, :&post, :&assemble};
    $post = post($root, :@content) if defined &post;

    return assemble(:$pre, :$post, :@content, :node($root));
}

class Pod::List is Pod::Block { };

sub assemble-list-items(:@content, :$node, *% ) {
    my @newcont;
    my $foundone = False;
    my $everwarn = False;

    my $atlevel = 0;
    my @pushalias;

    my sub oodwarn($got, $want) {
        unless $everwarn {
            warn "=item$got without preceding =item$want found!";
            $everwarn = True;
        }
    }

    for @content {
        when Pod::Item {
            $foundone = True;

            # here we deal with @newcont being empty (first list), or with the
            # last element not being a list (new list)
            unless +@newcont && @newcont[*-1] ~~ Pod::List {
                @newcont.push(Pod::List.new());
                if $_.level > 1 {
                    oodwarn($_.level, 1);
                }
            }

            # only bother doing the binding business if we're at a different
            # level than previous items
            if $_.level != $atlevel {
                # guaranteed to be bound to a Pod::List (see above 'unless')
                @pushalias := @newcont[*-1].contents;

                for 2..($_.level) -> $L {
                    unless +@pushalias && @pushalias[*-1] ~~ Pod::List {
                        @pushalias.push(Pod::List.new());
                        if +@pushalias == 1 { # we had to push a sublist to a list with no =items
                            oodwarn($OUTER::_.level, $L);
                        }
                    }
                    @pushalias := @pushalias[*-1].contents;
                }

                $atlevel = $_.level;
            }

            @pushalias.push($_);
        }

        default {
            @newcont.push($_);
            $atlevel = 0;
        }
    }

    return $foundone ?? $node.clone(contents => @newcont) !! $node;
}


#| Converts a Pod tree to a HTML document.
sub pod2html(
    $pod,
    :&url = -> $url { $url },
    :$head = '',
    :$header = '',
    :$footer = '',
    :$default-title,
    :$css-url = '//design.perl6.org/perl.css',
    :$lang = 'en',
    --> Str
    ) is export {
    ($title, $subtitle, @meta, @indexes, @body, @footnotes) = ();
    #| Keep count of how many footnotes we've output.
    my Int $*done-notes = 0;
    &OUTER::url = &url;

    @body.push: node2html($pod.map: { visit $_, :assemble(&assemble-list-items) });

    my $title_html = $title // $default-title // '';

    my $prelude = qq:to/END/;
        <!doctype html>
        <html lang="$lang">
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
          <link rel="stylesheet" href="$css-url">
          { do-metadata() // () }
          $head
        </head>
        <body class="pod">
        <div id="___top"></div>
        $header
        END

    return join(qq{\n},
        $prelude,
        ( $title.defined ?? "<h1 class='title'>{$title_html}</h1>"
                         !! () ),
        ( $subtitle.defined  ?? "<p class='subtitle'>{$subtitle}</p>"
                         !! () ),
        ( my $ToC := do-toc($pod) // () ),
        '<div class="pod-body', ($ToC ?? '' !! ' no-toc'), '">',@body,'</div>',
        do-footnotes(),
        $footer,
        '</body>',
        "</html>\n"
    );
}

#| Returns accumulated metadata as a string of C«<meta>» tags
sub do-metadata(--> Str) {
    return @meta.map(-> $p {
        qq[<meta name="{escape_html($p.key)}" value="{node2text($p.value)}" />]
    }).join("\n");
}

#| Turns accumulated headings into a nested-C«<ol>» table of contents
sub do-toc($pod --> Str) {
    my @levels is default(0) = 0;
    my proto sub find-headings($node, :$inside-heading){*}
    multi sub find-headings(Str $s is raw, :$inside-heading){ $inside-heading ?? $s.trim !! '' }
    multi sub find-headings(Pod::FormattingCode $node is raw where *.type eq 'C', :$inside-heading){
        my $html = $node.contents.map(*.&find-headings(:$inside-heading));
       $inside-heading ?? qq[<code class="pod-code-inline">{$html}</code>] !! ''
    }
    multi sub find-headings(Pod::Heading $node is raw, :$inside-heading){
        @levels.splice($node.level) if $node.level < +@levels;
        @levels[$node.level-1]++;
        my $level-hierarchy = @levels.join('.'); # e.g. §4.2.12
        my $text = $node.contents.map(*.&find-headings(inside-heading => True));
        my $link = escape_id(node2text($node.contents));
        qq[<tr class="toc-level-{$node.level}"><td class="toc-number">{$level-hierarchy}</td><td class="toc-text"><a href="#$link">{$text}</a></td></tr>\n];
    }
    multi sub find-headings(Positional \list, :$inside-heading){
        list.map(*.&find-headings(:$inside-heading))
    }
    multi sub find-headings(Pod::Block $node is raw, :$inside-heading){
        $node.contents.map(*.&find-headings(:$inside-heading))
    }
    multi sub find-headings(Pod::Config $node, :$inside-heading){
        ''
    }
    multi sub find-headings(Pod::Raw $node is raw, :$inside-heading){
        $node.contents.map(*.&find-headings(:$inside-heading))
    }

    my $html = find-headings($pod);
    $html.trim ??
        qq:to/EOH/
        <nav class="indexgroup">
        <table id="TOC">
        <caption><h2 id="TOC_Title">Table of Contents</h2></caption>
        {$html}
        </table>
        </nav>
        EOH
    !! ''
}

#| Flushes accumulated footnotes since last call. The idea here is that we can stick calls to this
#| before each C«</section>» tag (once we have those per-header) and have notes that are visually
#| and semantically attached to the section.
sub do-footnotes(--> Str) {
    return '' unless @footnotes;

    my Int $current-note = $*done-notes + 1;
    my $notes = @footnotes.kv.map(-> $k, $v {
                    my $num = $k + $current-note;
                    qq{<li><a href="#fn-ref-$num" id="fn-$num">[↑]</a> $v </li>\n}
                }).join;

    $*done-notes += @footnotes;
    @footnotes = ();

    return qq[<aside><ol start="$current-note">\n]
         ~ $notes
         ~ qq[</ol></aside>\n];
}

#| block level or below
proto sub node2html(|) returns Str is export {*}
multi sub node2html($node) {
    Debug { note colored("Generic node2html called for ", "bold") ~ $node.perl };
    return node2inline($node);
}
multi sub node2html(Pod::Block::Declarator $node) {
    given $node.WHEREFORE {
        when Routine {
            "<article>\n"
                ~ '<code class="pod-code-inline">'
                    ~ node2text($node.WHEREFORE.name ~ $node.WHEREFORE.signature.perl)
                ~ "</code>:\n"
                ~ node2html($node.contents)
            ~ "\n</article>\n";
        }
        default {
            Debug { note "I don't know what {$node.WHEREFORE.WHAT.perl} is. Assuming class..." };
	    "<h1>"~ node2html([$node.WHEREFORE.perl, q{: }, $node.contents])~ "</h1>";
        }
    }
}
multi sub node2html(Pod::Block::Code $node) {
    Debug { note colored("Code node2html called for ", "bold") ~ $node.gist };
    if %*POD2HTML-CALLBACKS and %*POD2HTML-CALLBACKS<code> -> &cb {
        return cb :$node, default => sub ($node) {
            return '<pre class="pod-block-code">' ~ node2inline($node.contents) ~ "</pre>\n"
        }
    }
    else  {
        return '<pre class="pod-block-code">' ~ node2inline($node.contents) ~ "</pre>\n"
    }

}
multi sub node2html(Pod::Block::Comment $node) {
    Debug { note colored("Comment node2html called for ", "bold") ~ $node.gist };
    return '';
}
multi sub node2html(Pod::Block::Named $node) {
    Debug { note colored("Named Block node2html called for ", "bold") ~ $node.gist };
    given $node.name {
        when 'config' { return '' }
        when 'nested' {
            return qq{<div class="nested">\n} ~ node2html($node.contents) ~ qq{\n</div>\n};
        }
        when 'output' { return qq[<pre class="pod-block-named-outout">\n] ~ node2inline($node.contents) ~ "</pre>\n"; }
        when 'pod'  {
            return qq[<span class="{$node.config<class>}">\n{node2html($node.contents)}</span>\n]
                if $node.config<class>;
            return node2html($node.contents);
        }
        when 'para' { return node2html($node.contents[0]); }
        when 'defn' {
            return node2html($node.contents[0]) ~ "\n"
                    ~ node2html($node.contents[1..*-1]);
        }
        when 'Image' {
            my $url;
            if $node.contents == 1 {
                my $n = $node.contents[0];
                if $n ~~ Str {
                    $url = $n;
                }
                elsif ($n ~~ Pod::Block::Para) &&  $n.contents == 1 {
                    $url = $n.contents[0] if $n.contents[0] ~~ Str;
                }
            }
            unless $url.defined {
                die "Found an Image block, but don't know how to extract the image URL :(";
            }
            return qq[<img src="$url" />];
        }
        when 'Xhtml' | 'Html' {
            unescape_html node2html $node.contents
        }
        default {
            if $node.name eq 'TITLE' {
                $title = node2text($node.contents);
                return '';
            }
            if $node.name eq 'SUBTITLE' {
                $subtitle = node2text($node.contents);
                return '';
            }
            elsif $node.name ~~ any(<VERSION DESCRIPTION AUTHOR COPYRIGHT SUMMARY>)
              and $node.contents[0] ~~ Pod::Block::Para {
                @meta.push: Pair.new(
                    key => $node.name.lc,
                    value => $node.contents
                );
            }

            return '<section>'
                ~ "<h1>{$node.name}</h1>\n"
                ~ node2html($node.contents)
                ~ "</section>\n";
        }
    }
}
multi sub node2html(Pod::Block::Para $node) {
    Debug { note colored("Para node2html called for ", "bold") ~ $node.gist };
    return '<p>' ~ node2inline($node.contents) ~ "</p>\n";
}
multi sub node2html(Pod::Block::Table $node) {
    Debug { note colored("Table node2html called for ", "bold") ~ $node.gist };
    my @r = '<table class="pod-table">';

    if $node.config<caption> -> $c {
        @r.push("<caption>{node2inline($c)}</caption>");
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
        $node.contents.map(-> $line {
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

multi sub node2html(Pod::Config $node) {
    Debug { note colored("Config node2html called for ", "bold") ~ $node.perl };
    return '';
}

# TODO: would like some way to wrap these and the following content in a <section>; this might be
# the same way we get lists working...
multi sub node2html(Pod::Heading $node) {
    Debug { note colored("Heading node2html called for ", "bold") ~ $node.gist };
    my $lvl = min($node.level, 6); #= HTML only has 6 levels of numbered headings
    my %escaped = (
        id => escape_id(node2rawtext($node.contents)),
        html => node2inline($node.contents),
    );

    %escaped<uri> = uri_escape %escaped<id>;

    @indexes.push: Pair.new(key => $lvl, value => %escaped);

    return sprintf('<h%d id="%s">', $lvl, %escaped<id>)
                ~ qq[<a class="u" href="#___top" title="go to top of document">]
                    ~ %escaped<html>
                ~ qq[</a>]
            ~ qq[</h{$lvl}>\n];
}

# FIXME
multi sub node2html(Pod::List $node) {
    return '<ul>' ~ node2html($node.contents) ~ "</ul>\n";
}
multi sub node2html(Pod::Item $node) {
    Debug { note colored("List Item node2html called for ", "bold") ~ $node.gist };
    return '<li>' ~ node2html($node.contents) ~ "</li>\n";
}
multi sub node2html(Positional $node) {
    return $node.map({ node2html($_) }).join
}
multi sub node2html(Str $node) {
    return escape_html($node);
}


#| inline level or below
multi sub node2inline($node --> Str) {
    Debug { note colored("missing a node2inline multi for ", "bold") ~ $node.gist };
    return node2text($node);
}
multi sub node2inline(Pod::Block::Para $node --> Str) {
    samewith $node.contents;
}
multi sub node2inline(Pod::FormattingCode $node --> Str) {
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
                ~ node2inline($node.contents)
                ~ q{</} ~ %basic-html{$_} ~ q{>};
        }

        # Escape
        when 'E' {
            return $node.meta.map({
                when Int { "&#$_;" }
                when Str { "&$_;"  }
            }).join;
        }

        # Note
        when 'N' {
            @footnotes.push(node2inline($node.contents));

            my $id = +@footnotes;
            return qq{<a href="#fn-$id" id="fn-ref-$id">[$id]</a>};
        }

        # Links
        when 'L' {
            my $text = node2inline($node.contents);
            my $url  = $node.meta[0] || node2text($node.contents);
            if $text ~~ /^'#'/ {
                # if we have an internal-only link, strip the # from the text.
                $text = $/.postmatch
            }
            $url = url(unescape_html($url));
            if $url ~~ /^'#'/ {
                $url = '#' ~ uri_escape( escape_id($/.postmatch) )
            }
            return qq[<a href="$url">{$text}</a>]
        }

        # zero-width comment
        when 'Z' {
            return '';
        }

        when 'D' {
            # TODO memorise these definitions (in $node.meta) and display them properly
            my $text = node2inline($node.contents);
            return qq[<defn>{$text}</defn>]
        }

        when 'X' {
            multi sub recurse-until-str(Str:D $s){ $s }
            multi sub recurse-until-str(Pod::Block $n){ $n.contents>>.&recurse-until-str().join }

            my $index-text = recurse-until-str($node).join;
            my @indices = $node.meta;
            my $index-name-attr = qq[index-entry{@indices ?? '-' !! ''}{@indices.join('-')}{$index-text ?? '-' !! ''}$index-text].subst('_', '__', :g).subst(' ', '_', :g).subst('%', '%25', :g).subst('#', '%23', :g);

            my $text = node2inline($node.contents);
            %crossrefs{$_} = $text for @indices;

            return qq[<a name="$index-name-attr"><span class="index-entry">$text\</span></a>] if $text;
            return qq[<a name="$index-name-attr"></a>];
        }

        # Stuff I haven't figured out yet
        default {
            Debug { note colored("missing handling for a formatting code of type ", "red") ~ $node.type }
            return qq{<kbd class="pod2html-todo">$node.type()&lt;}
                    ~ node2inline($node.contents)
                    ~ q{&gt;</kbd>};
        }
    }
}

multi sub node2inline(Positional $node --> Str) {
    return $node.map({ node2inline($_) }).join;
}
multi sub node2inline(Str $node --> Str) {
    return escape_html($node);
}


#| HTML-escaped text
multi sub node2text($node --> Str) {
    Debug { note colored("missing a node2text multi for ", "red") ~ $node.perl };
    return escape_html(node2rawtext($node));
}
multi sub node2text(Pod::Block::Para $node --> Str) {
    samewith $node.contents;
}
multi sub node2text(Pod::Raw $node --> Str) {
    my $t = $node.target;
    if $t && lc($t) eq 'html' {
        $node.contents.join
    }
    else {
        '';
    }
}

# FIXME: a lot of these multis are identical except the function name used...
#        there has to be a better way to write this?
multi sub node2text(Positional $node --> Str) {
    return $node.map({ node2text($_) }).join;
}
multi sub node2text(Str $node --> Str) {
    return escape_html($node);
}


#| plain, unescaped text
multi sub node2rawtext($node --> Str) {
    Debug { note colored("Generic node2rawtext called with ", "red") ~ $node.perl };
    return $node.Str;
}
multi sub node2rawtext(Pod::Block $node --> Str) {
    Debug { note colored("node2rawtext called for ", "bold") ~ $node.gist };
    samewith $node.contents;
}
multi sub node2rawtext(Positional $node --> Str) {
    return $node.map({ node2rawtext($_) }).join;
}
multi sub node2rawtext(Str $node --> Str) {
    return $node;
}

# vim: expandtab shiftwidth=4 ft=perl6
