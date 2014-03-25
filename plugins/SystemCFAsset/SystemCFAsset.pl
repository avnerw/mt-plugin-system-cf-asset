package MT::Plugin::SystemCFAsset;
use strict;
use warnings;
use base qw( MT::Plugin );

my $plugin = __PACKAGE__->new(
    {   name    => 'SystemCFAsset',
        version => 0.01,
        description =>
            '<__trans phrase="You can create and use asset-relative custom fields in system scope.">',
        plugin_link =>
            'https://github.com/masiuchi/mt-plugin-system-cf-asset',

        author_name => 'masiuchi',
        author_link => 'https://github.com/masiuchi',

        registry => { callbacks => { post_init => \&_overwrite_registry, }, },
    }
);
MT->add_plugin($plugin);

sub _overwrite_registry {
    my $types = MT->registry('customfield_types') or return;

    require MT::Asset;
    my $asset_types = MT::Asset->class_labels;
    my @asset_types = sort { $asset_types->{$a} cmp $asset_types->{$b} }
        keys %$asset_types;

    for my $type (@asset_types) {
        if ( $type =~ /^asset\.(\w+)/ ) {
            $type = $1;
        }

        delete $types->{$type}{context};

        my $original = $types->{$type}{field_html_params};
        $types->{$type}{field_html_params} = sub {
            $original->(@_);
            $_[2]->{blog_id} = MT->app->blog->id if MT->app->blog;
        };
    }
}

1;
