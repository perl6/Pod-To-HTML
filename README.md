# Pod::To::HTML

Render Perl 6 Pod as HTML

## SYNOPSIS

From the command line:

    perl6 --doc=HTML lib/FancyModule.pm > FancyModule.html

From within Perl 6:

```perl6
#Pod Block
=pod My I<super B<awesome>> embedded C<pod>
     document!

say Pod::To::HTML.render($=pod[0]);

#Pod file
say Pod::To::HTML.render('your/file.pod'.IO,
                         header => "your-custom-header-inside-body",
                         footer => "your-custom-footer-inside-body",
                         head-fields => "tags-inside-head",
                         lang        => "document language (defaults to 'en')",
                         default-title = 'No =title was found so we use this',
                         css-url => 'https://example.com/css.css');
                         # specify css-url as empty string to disable CSS inclusion

#Pod string
my $pod = q:to/END/;
=pod
My I<super B<awesome>> embedded C<pod>
     document!
END
say Pod::To::HTML.render($pod,
                         header => "your-custom-header-inside-body",
                         footer => "your-custom-footer-inside-body",
                         head-fields => "tags-inside-head",
			             lang        => "document language (defaults to 'en')",
                         default-title => 'No =title was found so we use this');
```

## DESCRIPTION

`Pod::To::HTML` takes a Pod tree and outputs correspondingly formatted HTML.  
Generally this is done via the command line, using`perl6 --doc=HTML`, which extracts the pod from the document and feeds it to `Pod::To::HTML`.  
The other route is with the `render` method (called by `--doc=HTML`), which creates a complete HTML document from the Pod tree it is called with. Optionally, a custom header/fooder/head-fields can be provided. These can be used to link to custom css stylesheets and javascript libraries.

## DEBUGGING

You can set the `P6DOC_DEBUG` environmental variable to make the module produce some debugging information.
